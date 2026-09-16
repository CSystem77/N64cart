#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CART_ERR_LEN 256

typedef struct {
    uint32_t start;
    uint32_t size;
    uint32_t vers;
} cart_info_t;

#ifdef __cplusplus
extern "C" {
#endif

bool cart_connect(char *err);
void cart_disconnect(void);
bool cart_connected(void);
const cart_info_t *cart_info(void);

bool cart_session_begin(char *err);
bool cart_session_end(char *err);

uint8_t *cart_io_buffer(void);

bool cart_reboot(char *err);
bool cart_bootloader(char *err);

#ifdef __cplusplus
}
#endif
