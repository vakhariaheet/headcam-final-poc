#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "hat_ota_image.h"

// Over-the-air update, started by the owner's sealed UPDATE_FW command. The
// hat downloads the image over its current Wi-Fi network and verifies the
// owner-supplied SHA-256 before the new slot becomes bootable
// (hat_ota_image.h), then reboots into it. Progress and the outcome go to
// the owner's app as {"event":"ota",...} notifications.

// Checks preconditions and starts the download task. Returns NULL once
// started, or a reason: busy, no_wifi, streaming, unsupported_flash, bad_url,
// bad_size, out_of_memory.
const char *hat_ota_start(const char *url, uint32_t size, const uint8_t sha256[HAT_OTA_SHA256_LEN],
						  const char *version);
// True from a successful start until the task fails (success reboots).
bool hat_ota_in_progress(void);
