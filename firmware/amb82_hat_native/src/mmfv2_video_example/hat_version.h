#pragma once

// Reported to the owner's app by INFO and compared against the backend's
// firmware releases. Bump it for every release you publish: the bootloader
// itself only compares build timestamps, so this is for people.
#define HAT_FIRMWARE_VERSION "0.2.0"
#define HAT_HARDWARE_MODEL "AMB82_MINI_V1"
