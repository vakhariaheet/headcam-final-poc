#pragma once
#include <stddef.h>
#include <stdint.h>
#define pdPASS 1
#define portMAX_DELAY 0xffffffffu
#define tskIDLE_PRIORITY 0
#define taskENTER_CRITICAL() ((void)0)
#define taskEXIT_CRITICAL() ((void)0)
int xTaskCreate(void (*fn)(void *), const char *, unsigned, void *, unsigned, void *);
