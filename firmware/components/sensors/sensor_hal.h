#pragma once

#include <stdint.h>
#include "system_config.h"

#ifdef __cplusplus
extern "C" {
#endif

int staysys_sensors_init(staysys_hal_t *hal);
int staysys_mpu_read(staysys_hal_t *hal, int16_t raw[6]);
int staysys_qmc_read(staysys_hal_t *hal, int16_t raw[3]);
int staysys_piezo_read(staysys_hal_t *hal, int *raw);
int staysys_battery_read(staysys_hal_t *hal, int *raw);
int staysys_battery_percentage(float voltage);

#ifdef __cplusplus
}
#endif
