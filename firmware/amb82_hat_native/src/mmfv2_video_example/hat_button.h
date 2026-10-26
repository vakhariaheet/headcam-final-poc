#pragma once
#include <stdbool.h>

// The physical control's raw level. Today the AMB82-mini onboard button
// (PF_10); a custom button or capacitive pad replaces only this driver,
// since gesture timing lives in hat_press.c.
void hat_button_init(void);
bool hat_button_pressed(void);
