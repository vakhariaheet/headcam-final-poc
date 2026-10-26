// Host tests for the pairing window, ownership sessions, and owner keys.
// Uses CommonCrypto for real HMAC-SHA256 so the firmware check matches the
// app's computation, not just a stub.
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CommonCrypto/CommonHMAC.h>
#include "../src/mmfv2_video_example/hat_pairing.c"
#include "../src/mmfv2_video_example/hat_owner.c"
#include "../src/mmfv2_video_example/hat_secure.c"

static uint8_t flash[1024];
static bool fail_save;
uint32_t ftl_save(void *data, uint16_t offset, uint16_t size) {
    assert(offset % 4 == 0 && size % 4 == 0 && offset + size <= sizeof(flash));
    if (fail_save) return 1;
    memcpy(flash + offset, data, size); return 0;
}
uint32_t ftl_load(void *data, uint16_t offset, uint16_t size) {
    memcpy(data, flash + offset, size); return 0;
}
bool hat_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t msg_len, uint8_t out[32]) {
    CCHmac(kCCHmacAlgSHA256, key, key_len, msg, msg_len, out); return true;
}
// ECDH and GCM are covered by secure_test.c against real mbedTLS.
bool hat_ecdh_p256(const uint8_t peer[65], uint8_t own[65], uint8_t shared[32]) {
    (void)peer; (void)own; (void)shared; abort();
}
bool hat_aes_gcm_decrypt(const uint8_t key[32], const uint8_t iv[12], const uint8_t *aad, size_t aad_len,
                         const uint8_t *ct, size_t len, const uint8_t tag[16], uint8_t *out) {
    (void)key; (void)iv; (void)aad; (void)aad_len; (void)ct; (void)len; (void)tag; (void)out; abort();
}

static void new_key(uint8_t key[HAT_OWNER_KEY_LEN]) { arc4random_buf(key, HAT_OWNER_KEY_LEN); }

static void test_pairing_window(void) {
    hat_pairing_init(false, 0); // no owner: open at boot
    assert(hat_pairing_is_open());
    uint32_t generation = hat_pairing_generation();
    assert(hat_pairing_tick(HAT_PAIRING_WINDOW_MS - 1) == HAT_NO_CONNECTION && hat_pairing_is_open());
    hat_pairing_tick(HAT_PAIRING_WINDOW_MS);
    assert(!hat_pairing_is_open() && hat_pairing_generation() == generation + 1);

    hat_pairing_open(1000000);
    hat_pairing_open(1000000 + HAT_PAIRING_WINDOW_MS - 5); // reopening restarts the window
    hat_pairing_tick(1000000 + HAT_PAIRING_WINDOW_MS + 10);
    assert(hat_pairing_is_open());
    hat_pairing_close(2000000);
    assert(!hat_pairing_is_open());

    hat_pairing_init(true, 0); // owner exists: closed at boot
    assert(!hat_pairing_is_open());
}

static void test_auth_timeout(void) {
    hat_pairing_init(true, 0);
    hat_session_connected(3, 100);
    assert(hat_pairing_tick(100 + HAT_AUTH_TIMEOUT_MS - 1) == HAT_NO_CONNECTION);
    assert(hat_pairing_tick(100 + HAT_AUTH_TIMEOUT_MS) == 3);
    assert(hat_pairing_tick(100 + HAT_AUTH_TIMEOUT_MS + 1) == HAT_NO_CONNECTION); // reported once
    hat_session_disconnected(3);

    // Authenticated links are never timed out.
    hat_session_connected(4, 0);
    uint8_t session[HAT_OWNER_KEY_LEN], copied[HAT_OWNER_KEY_LEN];
    new_key(session);
    assert(!hat_session_key(4, copied)); // no key before authentication
    hat_session_authenticate(4, session);
    assert(hat_session_key(4, copied) && memcmp(copied, session, sizeof(session)) == 0);
    assert(!hat_session_key(9, copied)); // only for the authenticated link
    assert(hat_pairing_tick(10 * HAT_AUTH_TIMEOUT_MS) == HAT_NO_CONNECTION);
    hat_session_disconnected(4);
    assert(!hat_session_authenticated(4)); // authentication ends with the link
    assert(!hat_session_key(4, copied));
    hat_session_connected(4, 0); // a new link on the same id starts unauthenticated
    assert(!hat_session_authenticated(4) && !hat_session_key(4, copied));
    hat_session_disconnected(4);

    // While pairing is open an unauthenticated link may stay to claim; the
    // deadline starts when the window closes.
    hat_pairing_open(0);
    hat_session_connected(5, 0);
    assert(hat_pairing_tick(5 * HAT_AUTH_TIMEOUT_MS) == HAT_NO_CONNECTION);
    hat_pairing_close(200000);
    assert(hat_pairing_tick(200000 + HAT_AUTH_TIMEOUT_MS - 1) == HAT_NO_CONNECTION);
    assert(hat_pairing_tick(200000 + HAT_AUTH_TIMEOUT_MS) == 5);
    hat_session_disconnected(5);
}

static void test_claim_and_challenge(void) {
    memset(flash, 0xff, sizeof(flash));
    hat_owner_load();
    assert(!hat_owner_exists());

    // Claim in pairing mode: derived key persisted and window closed. The
    // claiming link is not yet authenticated; it must answer a challenge.
    hat_pairing_init(false, 0);
    hat_session_connected(1, 0);
    uint8_t key[HAT_OWNER_KEY_LEN];
    new_key(key);
    assert(hat_owner_save(key));
    hat_session_claimed(10);
    assert(hat_owner_exists() && !hat_session_authenticated(1) && !hat_pairing_is_open());
    hat_session_disconnected(1);

    // The key survives a reboot.
    hat_owner_load();
    assert(hat_owner_exists());

    // Challenge-response with the right key succeeds exactly once per nonce.
    hat_session_connected(2, 0);
    uint8_t nonce[HAT_AUTH_NONCE_LEN], taken[HAT_AUTH_NONCE_LEN], mac[HAT_AUTH_MAC_LEN];
    assert(!hat_session_take_nonce(2, taken)); // no challenge issued yet
    arc4random_buf(nonce, sizeof(nonce));
    assert(hat_session_set_nonce(2, nonce));
    assert(!hat_session_set_nonce(7, nonce)); // not the active link
    CCHmac(kCCHmacAlgSHA256, key, sizeof(key), nonce, sizeof(nonce), mac);
    assert(hat_session_take_nonce(2, taken) && memcmp(taken, nonce, sizeof(nonce)) == 0);
    assert(hat_owner_verify(taken, mac));
    assert(!hat_session_take_nonce(2, taken)); // single use

    // The session key is HKDF(owner key, nonce): fresh per challenge.
    uint8_t session[HAT_OWNER_KEY_LEN], expected[HAT_OWNER_KEY_LEN];
    assert(hat_owner_session_key(taken, session));
    assert(hat_secure_session_key(key, taken, sizeof(taken), expected));
    assert(memcmp(session, expected, sizeof(session)) == 0);
    uint8_t other_nonce[HAT_AUTH_NONCE_LEN];
    arc4random_buf(other_nonce, sizeof(other_nonce));
    assert(hat_owner_session_key(other_nonce, expected) && memcmp(session, expected, sizeof(session)) != 0);

    // Wrong key, tampered MAC, or wrong nonce all fail.
    uint8_t other_key[HAT_OWNER_KEY_LEN];
    arc4random_buf(other_key, sizeof(other_key));
    CCHmac(kCCHmacAlgSHA256, other_key, sizeof(other_key), nonce, sizeof(nonce), mac);
    assert(!hat_owner_verify(nonce, mac));
    CCHmac(kCCHmacAlgSHA256, key, sizeof(key), nonce, sizeof(nonce), mac);
    mac[31] ^= 1;
    assert(!hat_owner_verify(nonce, mac));
    mac[31] ^= 1;
    nonce[0] ^= 1;
    assert(!hat_owner_verify(nonce, mac));
    hat_session_disconnected(2);

    // A new claim replaces the owner: the old key stops working.
    uint8_t replacement[HAT_OWNER_KEY_LEN];
    new_key(replacement);
    assert(hat_owner_save(replacement));
    nonce[0] ^= 1;
    assert(!hat_owner_verify(nonce, mac));

    // A failed flash write leaves the current owner untouched.
    fail_save = true;
    assert(!hat_owner_save(key));
    fail_save = false;
    CCHmac(kCCHmacAlgSHA256, replacement, sizeof(replacement), nonce, sizeof(nonce), mac);
    assert(hat_owner_verify(nonce, mac));
    hat_owner_load();
    assert(hat_owner_verify(nonce, mac));

    // Factory reset forgets the owner, in memory and across reboot.
    assert(hat_owner_clear() && !hat_owner_exists() && !hat_owner_verify(nonce, mac));
    assert(!hat_owner_session_key(nonce, session));
    hat_owner_load();
    assert(!hat_owner_exists());
}

int main(void) {
    test_pairing_window();
    test_auth_timeout();
    test_claim_and_challenge();
    puts("Pairing and owner tests passed");
    return 0;
}
