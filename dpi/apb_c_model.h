#ifndef APB_C_MODEL_H
#define APB_C_MODEL_H

#include <stdint.h>
#include "svdpi.h"

#ifdef __cplusplus
extern "C" {
#endif

void apb_c_reset(void);

void apb_c_write(
    uint32_t addr,
    uint32_t data,
    uint8_t  strb
);

uint32_t apb_c_read(
    uint32_t addr
);

uint8_t apb_c_slverr(
    uint32_t addr,
    uint8_t  is_write
);

#ifdef __cplusplus
}
#endif

#endif