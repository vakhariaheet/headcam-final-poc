#include <string.h>

#include "hat_secure.h"

#define HAT_SECURE_SEALED_MAX 384 // decoded bytes; commands are < 512 bytes of JSON

static const char hat_claim_salt[] = "umpirehat-claim-v1";
static const char hat_session_salt[] = "umpirehat-session-v1";
static const char hat_base64_alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

size_t hat_base64_encode(const uint8_t *in, size_t len, char *out, size_t out_cap)
{
	size_t needed = 4 * ((len + 2) / 3);
	if (needed + 1 > out_cap) return 0;
	size_t o = 0;
	for (size_t i = 0; i < len; i += 3) {
		uint32_t block = (uint32_t)in[i] << 16;
		if (i + 1 < len) block |= (uint32_t)in[i + 1] << 8;
		if (i + 2 < len) block |= in[i + 2];
		out[o++] = hat_base64_alphabet[block >> 18 & 0x3F];
		out[o++] = hat_base64_alphabet[block >> 12 & 0x3F];
		out[o++] = i + 1 < len ? hat_base64_alphabet[block >> 6 & 0x3F] : '=';
		out[o++] = i + 2 < len ? hat_base64_alphabet[block & 0x3F] : '=';
	}
	out[o] = '\0';
	return o;
}

static int hat_base64_value(char c)
{
	const char *p = c ? strchr(hat_base64_alphabet, c) : NULL;
	return p ? (int)(p - hat_base64_alphabet) : -1;
}

size_t hat_base64_decode(const char *in, uint8_t *out, size_t out_cap)
{
	size_t len = strlen(in);
	if (len == 0 || len % 4 != 0) return 0;
	size_t o = 0;
	for (size_t i = 0; i < len; i += 4) {
		bool last = i + 4 == len;
		int pad = (in[i + 3] == '=') + (in[i + 2] == '=');
		if (pad && !last) return 0;
		if (in[i + 2] == '=' && in[i + 3] != '=') return 0;
		uint32_t block = 0;
		for (int k = 0; k < 4 - pad; k++) {
			int v = hat_base64_value(in[i + k]);
			if (v < 0) return 0;
			block |= (uint32_t)v << (18 - 6 * k);
		}
		if (o + 3 - pad > out_cap) return 0;
		out[o++] = (uint8_t)(block >> 16);
		if (pad < 2) out[o++] = (uint8_t)(block >> 8);
		if (pad < 1) out[o++] = (uint8_t)block;
	}
	return o;
}

bool hat_hkdf_sha256(const uint8_t *salt, size_t salt_len, const uint8_t *ikm, size_t ikm_len, const uint8_t *info,
					 size_t info_len, uint8_t out[HAT_SECURE_KEY_LEN])
{
	uint8_t prk[32];
	uint8_t expand_input[256];
	if (info_len + 1 > sizeof(expand_input)) return false;
	memcpy(expand_input, info, info_len);
	expand_input[info_len] = 0x01; // T(1) = HMAC(PRK, info || 0x01)
	bool ok = hat_hmac_sha256(salt, salt_len, ikm, ikm_len, prk) &&
			  hat_hmac_sha256(prk, sizeof(prk), expand_input, info_len + 1, out);
	memset(prk, 0, sizeof(prk));
	return ok;
}

bool hat_secure_claim(const char *app_public_b64, char *hat_public_b64, size_t hat_public_b64_cap,
					  uint8_t owner_key[HAT_SECURE_KEY_LEN])
{
	uint8_t publics[2 * HAT_P256_PUBLIC_KEY_LEN]; // app_public || hat_public
	uint8_t shared[HAT_P256_SHARED_LEN];
	uint8_t *app_public = publics;
	uint8_t *hat_public = publics + HAT_P256_PUBLIC_KEY_LEN;
	if (!app_public_b64 ||
		hat_base64_decode(app_public_b64, app_public, HAT_P256_PUBLIC_KEY_LEN) != HAT_P256_PUBLIC_KEY_LEN) {
		return false;
	}
	bool ok = hat_ecdh_p256(app_public, hat_public, shared) &&
			  hat_hkdf_sha256((const uint8_t *)hat_claim_salt, strlen(hat_claim_salt), shared, sizeof(shared), publics,
							  sizeof(publics), owner_key) &&
			  hat_base64_encode(hat_public, HAT_P256_PUBLIC_KEY_LEN, hat_public_b64, hat_public_b64_cap) > 0;
	memset(shared, 0, sizeof(shared));
	if (!ok) memset(owner_key, 0, HAT_SECURE_KEY_LEN);
	return ok;
}

bool hat_secure_session_key(const uint8_t owner_key[HAT_SECURE_KEY_LEN], const uint8_t *nonce, size_t nonce_len,
							uint8_t session_key[HAT_SECURE_KEY_LEN])
{
	return hat_hkdf_sha256((const uint8_t *)hat_session_salt, strlen(hat_session_salt), owner_key, HAT_SECURE_KEY_LEN,
						   nonce, nonce_len, session_key);
}

bool hat_secure_open(const uint8_t session_key[HAT_SECURE_KEY_LEN], const char *command, const char *sealed_b64,
					 char *plaintext, size_t plaintext_cap)
{
	uint8_t sealed[HAT_SECURE_SEALED_MAX];
	size_t sealed_len = sealed_b64 ? hat_base64_decode(sealed_b64, sealed, sizeof(sealed)) : 0;
	if (sealed_len < HAT_GCM_IV_LEN + HAT_GCM_TAG_LEN) return false;
	size_t text_len = sealed_len - HAT_GCM_IV_LEN - HAT_GCM_TAG_LEN;
	if (text_len + 1 > plaintext_cap) return false;
	bool ok = hat_aes_gcm_decrypt(session_key, sealed, (const uint8_t *)command, strlen(command),
								  sealed + HAT_GCM_IV_LEN, text_len, sealed + HAT_GCM_IV_LEN + text_len,
								  (uint8_t *)plaintext);
	plaintext[ok ? text_len : 0] = '\0';
	// A JSON payload never contains NUL; reject one that would truncate.
	return ok && strlen(plaintext) == text_len;
}
