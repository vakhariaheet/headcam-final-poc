#pragma once
#include <stddef.h>
#include <stdint.h>
#define pdPASS 1
#define portMAX_DELAY UINT32_MAX
#define tskIDLE_PRIORITY 0
#define pdMS_TO_TICKS(n) (n)
int xTaskCreate(void (*fn)(void *), const char *, unsigned, void *, unsigned, void *);
void vTaskDelay(unsigned milliseconds);
