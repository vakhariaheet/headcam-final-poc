// Minimal mbedTLS 2.28 configuration for host tests of hat_crypto.c: the
// modules the firmware uses, with portable C instead of the SDK's hardware
// ALT implementations. Selected with -DMBEDTLS_CONFIG_FILE.
#pragma once

#define MBEDTLS_AES_C
#define MBEDTLS_BIGNUM_C
#define MBEDTLS_CIPHER_C
#define MBEDTLS_ECDH_C
#define MBEDTLS_ECP_C
#define MBEDTLS_ECP_DP_SECP256R1_ENABLED
#define MBEDTLS_ECP_NIST_OPTIM
#define MBEDTLS_ECP_NO_INTERNAL_RNG // hat_crypto.c always passes its own RNG
#define MBEDTLS_GCM_C
#define MBEDTLS_MD_C
#define MBEDTLS_SHA256_C

#include "mbedtls/check_config.h"
