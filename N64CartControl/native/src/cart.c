
#include "msvc_compat.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libusb.h>

#include "cart.h"
#include "romfs.h"

#define CART_VID 0x1209
#define CART_PID 0x6800

#define EP_OUT 0x01
#define EP_IN  0x82

#define USB_TIMEOUT_MS 5000
#define PIPE_RETRY_MAX 50
#define CHUNK 64

#define CART_INFO      0x2345
#define CART_READ_SEC  0x2346
#define CART_READ_SEC_CONT 0x2347
#define CART_WRITE_SEC 0x2348
#define CART_ERASE_SEC 0x234A
#define FLASH_SPI_MODE 0x234C
#define FLASH_QUAD_MODE 0x234D
#define BOOTLOADER_MODE 0x234E
#define CART_REBOOT    0x234F

#define ACK_NOERROR 0x5432

#pragma pack(push, 1)
typedef struct {
    uint16_t type;
    uint32_t offset;
} req_header;

typedef struct {
    uint16_t type;
    cart_info_t info;
} ack_header;
#pragma pack(pop)

typedef char cart_assert_req_header[(sizeof(req_header) == 6) ? 1 : -1];
typedef char cart_assert_ack_header[(sizeof(ack_header) == 14) ? 1 : -1];
typedef char cart_assert_romfs_entry[(sizeof(romfs_entry) == 64) ? 1 : -1];
typedef char cart_assert_romfs_attr[(sizeof(attr_by_names) == 2) ? 1 : -1];

static libusb_context *ctx;
static libusb_device_handle *handle;
static bool iface_claimed;

static cart_info_t info;
static bool spi_mode;
static uint16_t *flash_map;
static uint8_t *flash_list;
static uint8_t *io_buffer;

static void set_err(char *err, const char *fmt, ...)
{
    if (!err) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, CART_ERR_LEN, fmt, ap);
    va_end(ap);
}

static int bulk(unsigned char endpoint, void *data, int length, int *transferred)
{
    if (!handle) {
        return LIBUSB_ERROR_NO_DEVICE;
    }

    int ret;
    int attempt = 0;
    do {
        ret = libusb_bulk_transfer(handle, endpoint, (unsigned char *)data, length, transferred, USB_TIMEOUT_MS);
        if (ret == LIBUSB_ERROR_PIPE) {
            libusb_clear_halt(handle, endpoint);
        }
        attempt++;
    } while (ret == LIBUSB_ERROR_PIPE && attempt < PIPE_RETRY_MAX);
    return ret;
}

static bool bulk_exact(unsigned char endpoint, void *data, int length, const char *what, char *err)
{
    int actual = 0;
    int ret = bulk(endpoint, data, length, &actual);
    if (ret != 0 || actual != length) {
        set_err(err, "%s failed (%s, %d/%d bytes)", what, libusb_error_name(ret), actual, length);
        return false;
    }
    return true;
}

static bool send_cmd(uint16_t type, ack_header *ack_out, char *err)
{
    req_header req;
    req.type = type;
    req.offset = 0;

    if (!bulk_exact(EP_OUT, &req, sizeof(req), "Command request", err)) {
        return false;
    }

    ack_header ack;
    if (!bulk_exact(EP_IN, &ack, sizeof(ack), "Command reply", err)) {
        return false;
    }

    if (ack.type != ACK_NOERROR) {
        set_err(err, "Cart rejected command 0x%04X (status 0x%04X)", type, ack.type);
        return false;
    }

    if (ack_out) {
        *ack_out = ack;
    }
    return true;
}

bool romfs_flash_sector_erase(uint32_t offset)
{
    req_header req;
    req.type = CART_ERASE_SEC;
    req.offset = offset;

    if (!bulk_exact(EP_OUT, &req, sizeof(req), "Erase request", NULL)) {
        return false;
    }

    ack_header ack;
    if (!bulk_exact(EP_IN, &ack, sizeof(ack), "Erase reply", NULL)) {
        return false;
    }

    return ack.type == ACK_NOERROR;
}

bool romfs_flash_sector_write(uint32_t offset, uint8_t *buffer)
{
    req_header req;
    req.type = CART_WRITE_SEC;
    req.offset = offset;

    if (!bulk_exact(EP_OUT, &req, sizeof(req), "Write request", NULL)) {
        return false;
    }

    ack_header ack;
    if (!bulk_exact(EP_IN, &ack, sizeof(ack), "Write reply", NULL)) {
        return false;
    }
    if (ack.type != ACK_NOERROR) {
        return false;
    }

    for (uint32_t i = 0; i < ROMFS_FLASH_SECTOR; i += CHUNK) {
        uint8_t tmp[CHUNK];
        memcpy(tmp, &buffer[i], sizeof(tmp));

        if (!bulk_exact(EP_OUT, tmp, sizeof(tmp), "Write data", NULL)) {
            return false;
        }
        if (!bulk_exact(EP_IN, &ack, sizeof(ack), "Write data reply", NULL)) {
            return false;
        }
        if (ack.type != ACK_NOERROR) {
            return false;
        }
    }

    return true;
}

bool romfs_flash_sector_read(uint32_t offset, uint8_t *buffer, uint32_t need)
{
    req_header req;
    req.type = CART_READ_SEC;
    req.offset = offset;

    if (!bulk_exact(EP_OUT, &req, sizeof(req), "Read request", NULL)) {
        return false;
    }

    uint32_t pos = 0;
    while (need > 0) {
        uint8_t tmp[CHUNK];
        if (!bulk_exact(EP_IN, tmp, sizeof(tmp), "Read reply", NULL)) {
            return false;
        }

        uint32_t copy = (need > CHUNK) ? CHUNK : need;
        memcpy(&buffer[pos], tmp, copy);
        pos += copy;
        need -= copy;

        if (need == 0) {
            break;
        }

        req.type = CART_READ_SEC_CONT;
        req.offset = pos;
        if (!bulk_exact(EP_OUT, &req, sizeof(req), "Read continue request", NULL)) {
            return false;
        }
    }

    return true;
}

bool cart_connect(char *err)
{
    if (handle) {
        return true;
    }

    int ret = libusb_init(&ctx);
    if (ret < 0) {
        ctx = NULL;
        set_err(err, "Cannot initialise libusb (%s)", libusb_error_name(ret));
        return false;
    }
    libusb_set_option(ctx, LIBUSB_OPTION_LOG_LEVEL, LIBUSB_LOG_LEVEL_ERROR);

    handle = libusb_open_device_with_vid_pid(ctx, CART_VID, CART_PID);
    if (!handle) {
        set_err(err, "No n64cart found (expected USB %04X:%04X)", CART_VID, CART_PID);
        cart_disconnect();
        return false;
    }

    if (libusb_kernel_driver_active(handle, 0) == 1) {
        libusb_detach_kernel_driver(handle, 0);
    }

    ret = libusb_claim_interface(handle, 0);
    if (ret != 0) {
        set_err(err, "Cannot claim the cart interface (%s)", libusb_error_name(ret));
        cart_disconnect();
        return false;
    }
    iface_claimed = true;

    ack_header ack;
    if (!send_cmd(CART_INFO, &ack, err)) {
        cart_disconnect();
        return false;
    }
    info = ack.info;

    uint32_t map_size = 0;
    uint32_t list_size = 0;
    romfs_get_buffers_sizes(info.size, &map_size, &list_size);

    flash_map = malloc(map_size);
    flash_list = malloc(list_size);
    io_buffer = malloc(ROMFS_FLASH_SECTOR);
    if (!flash_map || !flash_list || !io_buffer) {
        set_err(err, "Out of memory for the romfs tables");
        cart_disconnect();
        return false;
    }

    return true;
}

void cart_disconnect(void)
{
    if (handle && spi_mode) {
        cart_session_end(NULL);
    }
    if (handle && iface_claimed) {
        libusb_release_interface(handle, 0);
        iface_claimed = false;
    }
    if (handle) {
        libusb_close(handle);
        handle = NULL;
    }
    if (ctx) {
        libusb_exit(ctx);
        ctx = NULL;
    }

    free(flash_map);
    free(flash_list);
    free(io_buffer);
    flash_map = NULL;
    flash_list = NULL;
    io_buffer = NULL;
    spi_mode = false;
    memset(&info, 0, sizeof(info));
}

bool cart_connected(void)
{
    return handle != NULL;
}

const cart_info_t *cart_info(void)
{
    return &info;
}

bool cart_session_begin(char *err)
{
    if (!handle) {
        set_err(err, "Cart is not connected");
        return false;
    }
    if (spi_mode) {
        return true;
    }

    if (!send_cmd(FLASH_SPI_MODE, NULL, err)) {
        return false;
    }
    spi_mode = true;

    if (!romfs_start(info.start, info.size, flash_map, flash_list)) {
        set_err(err, "Cannot mount the cart filesystem");
        cart_session_end(NULL);
        return false;
    }
    return true;
}

bool cart_session_end(char *err)
{
    if (!handle || !spi_mode) {
        return true;
    }
    if (!send_cmd(FLASH_QUAD_MODE, NULL, err)) {
        return false;
    }
    spi_mode = false;
    return true;
}

uint8_t *cart_io_buffer(void)
{
    return io_buffer;
}

static bool cart_leave_cmd(uint16_t type, char *err)
{
    if (!handle) {
        set_err(err, "Cart is not connected");
        return false;
    }
    if (!send_cmd(type, NULL, err)) {
        return false;
    }

    cart_disconnect();
    return true;
}

bool cart_reboot(char *err)
{
    return cart_leave_cmd(CART_REBOOT, err);
}

bool cart_bootloader(char *err)
{
    return cart_leave_cmd(BOOTLOADER_MODE, err);
}
