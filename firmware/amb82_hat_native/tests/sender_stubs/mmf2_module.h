#pragma once
#include <stdint.h>
#define MM_TYPE_VSINK 0x41
#define MM_TYPE_NONE 0
typedef struct {
    void *(*create)(void *);
    int (*handle)(void *, void *, void *);
    uint32_t module_type, output_type;
    const char *name;
} mm_module_t;
typedef struct { uintptr_t data_addr; uint32_t size, timestamp; } mm_queue_item_t;
