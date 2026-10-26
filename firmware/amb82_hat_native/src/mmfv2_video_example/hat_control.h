#pragma once

// Loads ownership, opens pairing mode when unowned, and starts the task that
// polls the button, expires pairing/authentication windows, and renders the
// status LEDs. Call once from app_example(), after FTL initialization.
void hat_control_start(void);
