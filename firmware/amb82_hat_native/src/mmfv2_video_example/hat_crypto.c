// mbedTLS-backed primitives for the ownership protocol. Free of SDK headers
// so host tests can compile this exact file against a host mbedTLS build.

#include <string.h>

#include "mbedtls/ecdh.h"
#include "mbedtls/gcm.h"
#include "mbedtls/md.h"

#include "hat_crypto.h"

bool hat_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t msg_len, uint8_t out[32])
{
	const mbedtls_md_info_t *sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
	return sha256 && mbedtls_md_hmac(sha256, key, key_len, msg, msg_len, out) == 0;
}

static int hat_crypto_rng(void *context, unsigned char *out, size_t len)
{
	(void)context;
	return hat_random_bytes(out, len) ? 0 : -1;
}

bool hat_ecdh_p256(const uint8_t peer_public[HAT_P256_PUBLIC_KEY_LEN], uint8_t own_public[HAT_P256_PUBLIC_KEY_LEN],
				   uint8_t shared[HAT_P256_SHARED_LEN])
{
	mbedtls_ecp_group group;
	mbedtls_mpi own_secret, shared_x;
	mbedtls_ecp_point own_point, peer_point;
	mbedtls_ecp_group_init(&group);
	mbedtls_mpi_init(&own_secret);
	mbedtls_mpi_init(&shared_x);
	mbedtls_ecp_point_init(&own_point);
	mbedtls_ecp_point_init(&peer_point);

	size_t written = 0;
	bool ok = mbedtls_ecp_group_load(&group, MBEDTLS_ECP_DP_SECP256R1) == 0 &&
			  mbedtls_ecp_point_read_binary(&group, &peer_point, peer_public, HAT_P256_PUBLIC_KEY_LEN) == 0 &&
			  mbedtls_ecp_check_pubkey(&group, &peer_point) == 0 &&
			  mbedtls_ecdh_gen_public(&group, &own_secret, &own_point, hat_crypto_rng, NULL) == 0 &&
			  mbedtls_ecdh_compute_shared(&group, &shared_x, &peer_point, &own_secret, hat_crypto_rng, NULL) == 0 &&
			  mbedtls_mpi_write_binary(&shared_x, shared, HAT_P256_SHARED_LEN) == 0 &&
			  mbedtls_ecp_point_write_binary(&group, &own_point, MBEDTLS_ECP_PF_UNCOMPRESSED, &written, own_public,
											 HAT_P256_PUBLIC_KEY_LEN) == 0 &&
			  written == HAT_P256_PUBLIC_KEY_LEN;

	mbedtls_ecp_point_free(&peer_point);
	mbedtls_ecp_point_free(&own_point);
	mbedtls_mpi_free(&shared_x);
	mbedtls_mpi_free(&own_secret);
	mbedtls_ecp_group_free(&group);
	if (!ok) memset(shared, 0, HAT_P256_SHARED_LEN);
	return ok;
}

bool hat_aes_gcm_decrypt(const uint8_t key[32], const uint8_t iv[HAT_GCM_IV_LEN], const uint8_t *aad, size_t aad_len,
						 const uint8_t *ciphertext, size_t len, const uint8_t tag[HAT_GCM_TAG_LEN], uint8_t *out)
{
	mbedtls_gcm_context gcm;
	mbedtls_gcm_init(&gcm);
	bool ok = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, key, 256) == 0 &&
			  mbedtls_gcm_auth_decrypt(&gcm, len, iv, HAT_GCM_IV_LEN, aad, aad_len, tag, HAT_GCM_TAG_LEN, ciphertext,
									   out) == 0;
	mbedtls_gcm_free(&gcm);
	if (!ok) memset(out, 0, len);
	return ok;
}

bool hat_aes_gcm_encrypt(const uint8_t key[32], const uint8_t iv[HAT_GCM_IV_LEN], const uint8_t *aad, size_t aad_len,
						 const uint8_t *plaintext, size_t len, uint8_t *out, uint8_t tag[HAT_GCM_TAG_LEN])
{
	mbedtls_gcm_context gcm;
	mbedtls_gcm_init(&gcm);
	bool ok = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, key, 256) == 0 &&
			  mbedtls_gcm_crypt_and_tag(&gcm, MBEDTLS_GCM_ENCRYPT, len, iv, HAT_GCM_IV_LEN, aad, aad_len, plaintext,
										out, HAT_GCM_TAG_LEN, tag) == 0;
	mbedtls_gcm_free(&gcm);
	return ok;
}
