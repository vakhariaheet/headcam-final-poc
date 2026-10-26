#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define HAT_P256_PUBLIC_KEY_LEN 65 // uncompressed SEC1 point: 0x04 || X || Y
#define HAT_P256_SHARED_LEN 32
#define HAT_GCM_IV_LEN 12
#define HAT_GCM_TAG_LEN 16

// Platform seam. hat_random.c (SDK RNG) and hat_crypto.c (mbedTLS) implement
// these on the board; host tests compile hat_crypto.c against host mbedTLS.
bool hat_random_bytes(uint8_t *out, size_t len);
bool hat_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t msg_len, uint8_t out[32]);

// Ephemeral P-256 ECDH against peer_public. Validates the peer point, then
// writes this side's public key and the shared X coordinate.
bool hat_ecdh_p256(const uint8_t peer_public[HAT_P256_PUBLIC_KEY_LEN], uint8_t own_public[HAT_P256_PUBLIC_KEY_LEN],
				   uint8_t shared[HAT_P256_SHARED_LEN]);

// AES-256-GCM. Decryption fails (and zeroes out) when the tag does not verify.
bool hat_aes_gcm_decrypt(const uint8_t key[32], const uint8_t iv[HAT_GCM_IV_LEN], const uint8_t *aad, size_t aad_len,
						 const uint8_t *ciphertext, size_t len, const uint8_t tag[HAT_GCM_TAG_LEN], uint8_t *out);
bool hat_aes_gcm_encrypt(const uint8_t key[32], const uint8_t iv[HAT_GCM_IV_LEN], const uint8_t *aad, size_t aad_len,
						 const uint8_t *plaintext, size_t len, uint8_t *out, uint8_t tag[HAT_GCM_TAG_LEN]);
