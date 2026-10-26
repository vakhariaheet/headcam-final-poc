#include "gpio_api.h"

#include "hat_led.h"

#define HAT_LED_BLUE_PIN PF_9
#define HAT_LED_GREEN_PIN PE_6
#define HAT_LED_ACTIVE_LEVEL 1 // Arduino's AMB82-mini variant lights these on HIGH

static gpio_t hat_led_blue;
static gpio_t hat_led_green;

static void hat_led_init_pin(gpio_t *gpio, PinName pin)
{
	gpio_init(gpio, pin);
	gpio_dir(gpio, PIN_OUTPUT);
	gpio_mode(gpio, PullNone);
	gpio_write(gpio, !HAT_LED_ACTIVE_LEVEL);
}

void hat_led_init(void)
{
	hat_led_init_pin(&hat_led_blue, HAT_LED_BLUE_PIN);
	hat_led_init_pin(&hat_led_green, HAT_LED_GREEN_PIN);
}

void hat_led_render(bool blue_on, bool green_on)
{
	gpio_write(&hat_led_blue, blue_on ? HAT_LED_ACTIVE_LEVEL : !HAT_LED_ACTIVE_LEVEL);
	gpio_write(&hat_led_green, green_on ? HAT_LED_ACTIVE_LEVEL : !HAT_LED_ACTIVE_LEVEL);
}
