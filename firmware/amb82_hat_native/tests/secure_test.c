// Host tests for the ownership key schedule and sealed commands, running the
// firmware's hat_crypto.c and hat_secure.c against the SDK's own mbedTLS
// sources. With --vectors, prints fixed-seed values the app's Dart tests
// check, so both implementations are proven to agree.
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mbedtls/ecdh.h"
#include "hat_secure.h"

// Deterministic RNG: a counter, so --vectors output is reproducible.
static uint8_t rng_counter;
bool hat_random_bytes(uint8_t *out, size_t len) {
    for (size_t i = 0; i < len; i++) out[i] = (uint8_t)(rng_counter++ * 37 + 11);
    return true;
}
static int test_rng(void *ctx, unsigned char *out, size_t len) {
    (void)ctx;
    return hat_random_bytes(out, len) ? 0 : -1;
}

static void hex(const char *label, const uint8_t *bytes, size_t len) {
    printf("%s=", label);
    for (size_t i = 0; i < len; i++) printf("%02x", bytes[i]);
    printf("\n");
}

// The app side of a claim: a P-256 key pair and the owner key it derives.
typedef struct {
    mbedtls_ecp_group group;
    mbedtls_mpi secret;
    mbedtls_ecp_point point;
    uint8_t public_key[HAT_P256_PUBLIC_KEY_LEN];
} app_key;

static void app_key_init(app_key *key) {
    mbedtls_ecp_group_init(&key->group);
    mbedtls_mpi_init(&key->secret);
    mbedtls_ecp_point_init(&key->point);
    size_t written;
    assert(mbedtls_ecp_group_load(&key->group, MBEDTLS_ECP_DP_SECP256R1) == 0);
    assert(mbedtls_ecdh_gen_public(&key->group, &key->secret, &key->point, test_rng, NULL) == 0);
    assert(mbedtls_ecp_point_write_binary(&key->group, &key->point, MBEDTLS_ECP_PF_UNCOMPRESSED, &written,
                                          key->public_key, sizeof(key->public_key)) == 0);
}

static void app_owner_key(app_key *key, const uint8_t hat_public[HAT_P256_PUBLIC_KEY_LEN], uint8_t out[32]) {
    mbedtls_ecp_point hat_point;
    mbedtls_mpi shared;
    mbedtls_ecp_point_init(&hat_point);
    mbedtls_mpi_init(&shared);
    uint8_t z[32], publics[2 * HAT_P256_PUBLIC_KEY_LEN];
    assert(mbedtls_ecp_point_read_binary(&key->group, &hat_point, hat_public, HAT_P256_PUBLIC_KEY_LEN) == 0);
    assert(mbedtls_ecdh_compute_shared(&key->group, &shared, &hat_point, &key->secret, test_rng, NULL) == 0);
    assert(mbedtls_mpi_write_binary(&shared, z, sizeof(z)) == 0);
    memcpy(publics, key->public_key, HAT_P256_PUBLIC_KEY_LEN);
    memcpy(publics + HAT_P256_PUBLIC_KEY_LEN, hat_public, HAT_P256_PUBLIC_KEY_LEN);
    const char salt[] = "umpirehat-claim-v1";
    assert(hat_hkdf_sha256((const uint8_t *)salt, strlen(salt), z, sizeof(z), publics, sizeof(publics), out));
    mbedtls_mpi_free(&shared);
    mbedtls_ecp_point_free(&hat_point);
}

static size_t seal(const uint8_t key[32], const char *command, const uint8_t iv[12], const char *json, char *out,
                   size_t cap) {
    uint8_t sealed[400];
    size_t len = strlen(json);
    memcpy(sealed, iv, 12);
    assert(hat_aes_gcm_encrypt(key, iv, (const uint8_t *)command, strlen(command), (const uint8_t *)json, len,
                               sealed + 12, sealed + 12 + len));
    return hat_base64_encode(sealed, 12 + len + 16, out, cap);
}

static void test_base64(void) {
    const struct { const char *raw, *encoded; } cases[] = {
        {"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"}, {"foob", "Zm9vYg=="}, {"fooba", "Zm9vYmE="},
        {"foobar", "Zm9vYmFy"},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        char out[16];
        uint8_t back[16];
        size_t n = strlen(cases[i].raw);
        if (n) {
            assert(hat_base64_encode((const uint8_t *)cases[i].raw, n, out, sizeof(out)) == strlen(cases[i].encoded));
            assert(strcmp(out, cases[i].encoded) == 0);
            assert(hat_base64_decode(cases[i].encoded, back, sizeof(back)) == n);
            assert(memcmp(back, cases[i].raw, n) == 0);
        }
    }
    uint8_t back[16];
    assert(hat_base64_decode("Zm9", back, sizeof(back)) == 0);     // bad length
    assert(hat_base64_decode("Zm!v", back, sizeof(back)) == 0);    // bad character
    assert(hat_base64_decode("Zg==Zm9v", back, sizeof(back)) == 0); // padding mid-string
    assert(hat_base64_decode("Zm9vYmFy", back, 5) == 0);           // overflow
    char small[4];
    assert(hat_base64_encode((const uint8_t *)"foo", 3, small, sizeof(small)) == 0); // no room for NUL
}

static void test_hkdf_rfc5869(void) {
    // RFC 5869 test case 1, first 32 bytes of OKM.
    uint8_t ikm[22], salt[13], info[10], okm[32];
    memset(ikm, 0x0b, sizeof(ikm));
    for (int i = 0; i < 13; i++) salt[i] = (uint8_t)i;
    for (int i = 0; i < 10; i++) info[i] = (uint8_t)(0xf0 + i);
    assert(hat_hkdf_sha256(salt, sizeof(salt), ikm, sizeof(ikm), info, sizeof(info), okm));
    const uint8_t expected[32] = {0x3c, 0xb2, 0x5f, 0x25, 0xfa, 0xac, 0xd5, 0x7a, 0x90, 0x43, 0x4f,
                                  0x64, 0xd0, 0x36, 0x2f, 0x2a, 0x2d, 0x2d, 0x0a, 0x90, 0xcf, 0x1a,
                                  0x5a, 0x4c, 0x5d, 0xb0, 0x2d, 0x56, 0xec, 0xc4, 0xc5, 0xbf};
    assert(memcmp(okm, expected, sizeof(okm)) == 0);
}

int main(int argc, char **argv) {
    bool vectors = argc > 1 && strcmp(argv[1], "--vectors") == 0;
    test_base64();
    test_hkdf_rfc5869();

    // Claim: both sides derive the same owner key; it never appears on the wire.
    app_key app;
    app_key_init(&app);
    char app_public_b64[96], hat_public_b64[96];
    assert(hat_base64_encode(app.public_key, sizeof(app.public_key), app_public_b64, sizeof(app_public_b64)));
    uint8_t hat_owner[32], app_owner[32], hat_public[HAT_P256_PUBLIC_KEY_LEN];
    assert(hat_secure_claim(app_public_b64, hat_public_b64, sizeof(hat_public_b64), hat_owner));
    assert(hat_base64_decode(hat_public_b64, hat_public, sizeof(hat_public)) == sizeof(hat_public));
    app_owner_key(&app, hat_public, app_owner);
    assert(memcmp(hat_owner, app_owner, 32) == 0);

    // Malformed or off-curve app keys are refused.
    uint8_t bad[HAT_P256_PUBLIC_KEY_LEN];
    memcpy(bad, app.public_key, sizeof(bad));
    bad[64] ^= 1; // no longer on the curve
    char bad_b64[96];
    hat_base64_encode(bad, sizeof(bad), bad_b64, sizeof(bad_b64));
    uint8_t ignored[32];
    assert(!hat_secure_claim(bad_b64, hat_public_b64, sizeof(hat_public_b64), ignored));
    assert(!hat_secure_claim("Zm9v", hat_public_b64, sizeof(hat_public_b64), ignored));

    // Session key and sealed SET_STA round trip.
    const uint8_t nonce[16] = {0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5, 0x96, 0x87,
                               0x78, 0x69, 0x5a, 0x4b, 0x3c, 0x2d, 0x1e, 0x0f};
    uint8_t session[32];
    assert(hat_secure_session_key(hat_owner, nonce, sizeof(nonce), session));
    const uint8_t iv[12] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
    const char *params = "{\"ssid\":\"test-network\",\"pass\":\"test-password\"}";
    char sealed[600], opened[512];
    assert(seal(session, "SET_STA", iv, params, sealed, sizeof(sealed)));
    assert(hat_secure_open(session, "SET_STA", sealed, opened, sizeof(opened)));
    assert(strcmp(opened, params) == 0);

    // Wrong command (AAD), wrong key, tampering, or truncation all fail.
    assert(!hat_secure_open(session, "START_STREAM", sealed, opened, sizeof(opened)));
    uint8_t other[32];
    memcpy(other, session, 32);
    other[0] ^= 1;
    assert(!hat_secure_open(other, "SET_STA", sealed, opened, sizeof(opened)));
    char tampered[600];
    strcpy(tampered, sealed);
    tampered[20] = tampered[20] == 'A' ? 'B' : 'A';
    assert(!hat_secure_open(session, "SET_STA", tampered, opened, sizeof(opened)));
    assert(!hat_secure_open(session, "SET_STA", "AAAA", opened, sizeof(opened)));
    assert(!hat_secure_open(session, "SET_STA", sealed, opened, 8)); // no room

    if (vectors) {
        // For mobile/test/hat_ownership_test.dart.
        uint8_t app_secret[32];
        assert(mbedtls_mpi_write_binary(&app.secret, app_secret, sizeof(app_secret)) == 0);
        hex("app_private", app_secret, sizeof(app_secret));
        hex("app_public", app.public_key, sizeof(app.public_key));
        hex("hat_public", hat_public, sizeof(hat_public));
        hex("owner_key", hat_owner, 32);
        hex("nonce", nonce, sizeof(nonce));
        hex("session_key", session, 32);
        printf("sealed_set_sta=%s\n", sealed);
    }
    puts("Secure channel tests passed");
    return 0;
}
