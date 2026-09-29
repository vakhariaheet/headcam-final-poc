#pragma once
#include "FreeRTOS.h"
typedef struct host_queue *QueueHandle_t;
QueueHandle_t xQueueCreate(unsigned, size_t);
void vQueueDelete(QueueHandle_t);
int xQueueSend(QueueHandle_t, const void *, unsigned);
int xQueueReceive(QueueHandle_t, void *, unsigned);
