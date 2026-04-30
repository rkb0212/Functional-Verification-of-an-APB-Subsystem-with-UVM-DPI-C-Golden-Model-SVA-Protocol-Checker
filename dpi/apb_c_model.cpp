#include "apb_c_model.h"
#include <stdint.h>
#include <string.h>

// ------------------------------------------------------------
// Address map
// ------------------------------------------------------------

static const uint32_t GPIO_BASE  = 0x00000000;
static const uint32_t GPIO_END   = 0x000000FF;

static const uint32_t TIMER_BASE = 0x00000100;
static const uint32_t TIMER_END  = 0x000001FF;

static const uint32_t MEM_BASE   = 0x00000200;
static const uint32_t MEM_END    = 0x000002FF;

// GPIO offsets
static const uint32_t GPIO_DATA_OFFSET   = 0x00;
static const uint32_t GPIO_DIR_OFFSET    = 0x04;
static const uint32_t GPIO_SET_OFFSET    = 0x08;
static const uint32_t GPIO_CLEAR_OFFSET  = 0x0C;
static const uint32_t GPIO_STATUS_OFFSET = 0x10;

// TIMER offsets
static const uint32_t TIMER_CTRL_OFFSET   = 0x00;
static const uint32_t TIMER_LOAD_OFFSET   = 0x04;
static const uint32_t TIMER_COUNT_OFFSET  = 0x08;
static const uint32_t TIMER_STATUS_OFFSET = 0x0C;
static const uint32_t TIMER_CLEAR_OFFSET  = 0x10;

// ------------------------------------------------------------
// Internal model state
// ------------------------------------------------------------

static uint32_t gpio_data_model;
static uint32_t gpio_dir_model;
static uint32_t gpio_status_model;

static uint32_t timer_ctrl_model;
static uint32_t timer_load_model;
static uint32_t timer_count_model;
static uint32_t timer_status_model;

// static uint32_t mem_model[256];
static uint32_t mem_model[64];   // 256 bytes ÷ 4 = 64 words

// ------------------------------------------------------------
// Helper functions
// ------------------------------------------------------------

static uint32_t apply_wstrb(
    uint32_t old_data,
    uint32_t new_data,
    uint8_t  strb
) {
    uint32_t result = old_data;

    for (int i = 0; i < 4; i++) {
        if ((strb >> i) & 0x1) {
            uint32_t mask = 0xFFu << (i * 8);
            result = (result & ~mask) | (new_data & mask);
        }
    }

    return result;
}

static int is_gpio_addr(uint32_t addr) {
    return (addr >= GPIO_BASE && addr <= GPIO_END);
}

static int is_timer_addr(uint32_t addr) {
    return (addr >= TIMER_BASE && addr <= TIMER_END);
}

static int is_mem_addr(uint32_t addr) {
    return (addr >= MEM_BASE && addr <= MEM_END);
}

static int is_valid_gpio_offset(uint32_t offset) {
    switch (offset) {
        case GPIO_DATA_OFFSET:
        case GPIO_DIR_OFFSET:
        case GPIO_SET_OFFSET:
        case GPIO_CLEAR_OFFSET:
        case GPIO_STATUS_OFFSET:
            return 1;
        default:
            return 0;
    }
}

static int is_valid_timer_offset(uint32_t offset) {
    switch (offset) {
        case TIMER_CTRL_OFFSET:
        case TIMER_LOAD_OFFSET:
        case TIMER_COUNT_OFFSET:
        case TIMER_STATUS_OFFSET:
        case TIMER_CLEAR_OFFSET:
            return 1;
        default:
            return 0;
    }
}

static int is_valid_mem_addr(uint32_t addr) {
    uint32_t local_addr;

    if (!is_mem_addr(addr)) {
        return 0;
    }

    local_addr = addr - MEM_BASE;

    if ((local_addr & 0x3) != 0) {
        return 0;
    }

    // if ((local_addr >> 2) >= 256) {
    //     return 0;
    // }
    if ((local_addr >> 2) >= 64)  { return 0; } 

    return 1;
}

// ------------------------------------------------------------
// Public DPI functions
// ------------------------------------------------------------

void apb_c_reset() {
    gpio_data_model   = 0;
    gpio_dir_model    = 0;
    gpio_status_model = 0;

    timer_ctrl_model   = 0;
    timer_load_model   = 10;
    timer_count_model  = 0;
    timer_status_model = 0;

    memset(mem_model, 0, sizeof(mem_model));
}

uint8_t apb_c_slverr(
    uint32_t addr,
    uint8_t  is_write
) {
    uint32_t offset;

    if (is_gpio_addr(addr)) {
        offset = addr & 0xFF;

        if (!is_valid_gpio_offset(offset)) {
            return 1;
        }

        if (is_write && offset == GPIO_STATUS_OFFSET) {
            return 1;
        }

        return 0;
    }

    if (is_timer_addr(addr)) {
        offset = addr & 0xFF;

        if (!is_valid_timer_offset(offset)) {
            return 1;
        }

        if (is_write && offset == TIMER_STATUS_OFFSET) {
            return 1;
        }

        return 0;
    }

    if (is_mem_addr(addr)) {
        if (!is_valid_mem_addr(addr)) {
            return 1;
        }

        return 0;
    }

    return 1;
}

void apb_c_write(
    uint32_t addr,
    uint32_t data,
    uint8_t  strb
) {
    uint32_t offset;
    uint32_t local_addr;
    uint32_t index;

    if (apb_c_slverr(addr, 1)) {
        return;
    }

    if (is_gpio_addr(addr)) {
        offset = addr & 0xFF;

        switch (offset) {
            case GPIO_DATA_OFFSET:
                gpio_data_model = apply_wstrb(gpio_data_model, data, strb) & 0xFF;
                break;

            case GPIO_DIR_OFFSET:
                gpio_dir_model = apply_wstrb(gpio_dir_model, data, strb) & 0xFF;
                break;

            case GPIO_SET_OFFSET:
                gpio_data_model =
                    gpio_data_model | (apply_wstrb(0, data, strb) & 0xFF);
                break;

            case GPIO_CLEAR_OFFSET:
                gpio_data_model = 
                (gpio_data_model & ~apply_wstrb(0, data, strb)) & 0xFF;

                break;

            default:
                break;
        }

        return;
    }

    if (is_timer_addr(addr)) {
        offset = addr & 0xFF;

        switch (offset) {
            case TIMER_CTRL_OFFSET:
                timer_ctrl_model = apply_wstrb(timer_ctrl_model, data, strb);
                break;

            case TIMER_LOAD_OFFSET:
                timer_load_model = apply_wstrb(timer_load_model, data, strb);
                break;

            case TIMER_COUNT_OFFSET:
                timer_count_model = apply_wstrb(timer_count_model, data, strb);
                break;

            case TIMER_CLEAR_OFFSET:
                if (strb & 0x1) {
                    if (data & 0x1) {
                        timer_status_model &= ~0x1u;
                    }

                    if (data & 0x2) {
                        timer_status_model &= ~0x2u;
                    }
                }
                break;

            default:
                break;
        }

        return;
    }

    if (is_mem_addr(addr)) {
        local_addr = addr - MEM_BASE;
        index = local_addr >> 2;

        mem_model[index] = apply_wstrb(mem_model[index], data, strb);
        return;
    }
}

uint32_t apb_c_read(
    uint32_t addr
) {
    uint32_t offset;
    uint32_t local_addr;
    uint32_t index;

    if (apb_c_slverr(addr, 0)) {
        return 0;
    }

    if (is_gpio_addr(addr)) {
        offset = addr & 0xFF;

        switch (offset) {
            case GPIO_DATA_OFFSET:
                return gpio_data_model & 0xFF;

            case GPIO_DIR_OFFSET:
                return gpio_dir_model & 0xFF;

            case GPIO_SET_OFFSET:
                return 0;

            case GPIO_CLEAR_OFFSET:
                return 0;

            case GPIO_STATUS_OFFSET:
                return gpio_status_model & 0xFF;

            default:
                return 0;
        }
    }

    if (is_timer_addr(addr)) {
        offset = addr & 0xFF;

        switch (offset) {
            case TIMER_CTRL_OFFSET:
                return timer_ctrl_model;

            case TIMER_LOAD_OFFSET:
                return timer_load_model;

            case TIMER_COUNT_OFFSET:
                return timer_count_model;

            case TIMER_STATUS_OFFSET:
                return timer_status_model;

            case TIMER_CLEAR_OFFSET:
                return 0;

            default:
                return 0;
        }
    }

    if (is_mem_addr(addr)) {
        local_addr = addr - MEM_BASE;
        index = local_addr >> 2;

        return mem_model[index];
    }

    return 0;
}