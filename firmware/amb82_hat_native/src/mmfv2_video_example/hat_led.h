#pragma once
#include <stdbool.h>

// AMB82-mini onboard LEDs (blue PF_9, green PE_6). A custom RGB LED replaces
// only this driver; hat_led_pattern.c decides what to show.
void hat_led_init(void);
void hat_led_render(bool blue_on, bool green_on);
