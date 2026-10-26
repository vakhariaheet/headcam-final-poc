#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "hat_crypto.h"

// Ownership protocol v1 key schedule and sealed command payloads, built on
// hat_crypto.h. Mirrored by the app's hat_ownership_protocol.dart.
//
//   claim:   owner_key   = HKDF-SHA256(salt "umpirehat-claim-v1",
//                                      ikm  ECDH-P256 shared X,
//                                      info app_public || hat_public)
//   session: session_key = HKDF-SHA256(salt "umpirehat-session-v1",
//                                      ikm  owner_key, info nonce)
//   sealed:  base64(iv[12] || AES-256-GCM(session_key, iv, aad = command
//            name, JSON params) || tag[16])
//
// The owner key never crosses the air: both sides derive it.

#define HAT_SECURE_KEY_LEN 32

// HKDF-SHA256 (RFC 5869) producing exactly one 32-byte block.
bool hat_hkdf_sha256(const uint8_t *salt, size_t salt_len, const uint8_t *ikm, size_t ikm_len, const uint8_t *info,
					 size_t info_len, uint8_t out[HAT_SECURE_KEY_LEN]);

// Answers a CLAIM: decodes the app's base64 P-256 public key, runs ECDH, and
// derives the owner key. Writes this side's public key as base64.
bool hat_secure_claim(const char *app_public_b64, char *hat_public_b64, size_t hat_public_b64_cap,
					  uint8_t owner_key[HAT_SECURE_KEY_LEN]);

bool hat_secure_session_key(const uint8_t owner_key[HAT_SECURE_KEY_LEN], const uint8_t *nonce, size_t nonce_len,
							uint8_t session_key[HAT_SECURE_KEY_LEN]);

// Opens a sealed payload into a NUL-terminated string. False on bad base64,
// size, or authentication failure (wrong key, wrong command, tampering).
bool hat_secure_open(const uint8_t session_key[HAT_SECURE_KEY_LEN], const char *command, const char *sealed_b64,
					 char *plaintext, size_t plaintext_cap);

// Standard base64 with padding. Return bytes written, or 0 on error/overflow.
size_t hat_base64_encode(const uint8_t *in, size_t len, char *out, size_t out_cap);
size_t hat_base64_decode(const char *in, uint8_t *out, size_t out_cap);
