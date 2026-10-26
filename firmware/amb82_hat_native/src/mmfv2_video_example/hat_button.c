#include "gpio_api.h"

#include "hat_button.h"

#define HAT_BUTTON_PIN PF_10
// Realtek's Arduino button example triggers on a rising edge, implying the
// button reads high when pressed. Flip if the board shows the inverse.
#define HAT_BUTTON_PRESSED_LEVEL 1

static gpio_t hat_button_gpio;

void hat_button_init(void)
{
	gpio_init(&hat_button_gpio, HAT_BUTTON_PIN);
	gpio_dir(&hat_button_gpio, PIN_INPUT);
	gpio_mode(&hat_button_gpio, PullNone); // the board provides the bias
}

bool hat_button_pressed(void)
{
	return gpio_read(&hat_button_gpio) == HAT_BUTTON_PRESSED_LEVEL;
}
