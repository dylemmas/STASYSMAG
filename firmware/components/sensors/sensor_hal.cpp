#include "sensor_hal.h"

#include <math.h>
#include "esp_err.h"

static int read_register(i2c_master_dev_handle_t device, uint8_t reg,
                         uint8_t *data, size_t length)
{
    return i2c_master_transmit_receive(device, &reg, 1, data, length, 20);
}

static int write_register(i2c_master_dev_handle_t device, uint8_t reg, uint8_t value)
{
    uint8_t data[] = {reg, value};
    return i2c_master_transmit(device, data, sizeof(data), 20);
}

int staysys_sensors_init(staysys_hal_t *hal)
{
    if (hal == NULL) return ESP_ERR_INVALID_ARG;

    i2c_master_bus_config_t bus_config = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = STASYS_I2C_SDA,
        .scl_io_num = STASYS_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags = {.enable_internal_pullup = true},
    };
    esp_err_t err = i2c_new_master_bus(&bus_config, &hal->bus);
    if (err != ESP_OK) return err;

    i2c_device_config_t mpu_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = STASYS_MPU_ADDR,
        .scl_speed_hz = 400000,
    };
    err = i2c_master_bus_add_device(hal->bus, &mpu_config, &hal->mpu);
    if (err != ESP_OK) return err;

    i2c_device_config_t qmc_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = STASYS_QMC_ADDR,
        .scl_speed_hz = 400000,
    };
    err = i2c_master_bus_add_device(hal->bus, &qmc_config, &hal->qmc);
    if (err != ESP_OK) return err;

    if (write_register(hal->mpu, 0x6b, 0x00) != ESP_OK ||
        write_register(hal->mpu, 0x1c, 0x08) != ESP_OK ||
        write_register(hal->mpu, 0x1b, 0x08) != ESP_OK ||
        write_register(hal->mpu, 0x1a, 0x00) != ESP_OK) {
        return ESP_FAIL;
    }

    uint8_t chip_id = 0;
    hal->qmc_present = read_register(hal->qmc, 0x00, &chip_id, 1) == ESP_OK &&
                        chip_id == 0x80;
    if (hal->qmc_present) {
        if (write_register(hal->qmc, 0x0b, 0x00) != ESP_OK ||
            write_register(hal->qmc, 0x0a, 0x0c) != ESP_OK) {
            hal->qmc_present = false;
        }
    }
    adc_oneshot_unit_init_cfg_t adc_config = {
        .unit_id = ADC_UNIT_1,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    if (adc_oneshot_new_unit(&adc_config, &hal->adc1) != ESP_OK) return ESP_FAIL;
    hal->battery_channel = ADC_CHANNEL_3;
    hal->piezo_channel = ADC_CHANNEL_7;
    adc_oneshot_chan_cfg_t channel_config = {
        .atten = ADC_ATTEN_DB_11,
        .bitwidth = ADC_BITWIDTH_12,
    };
    if (adc_oneshot_config_channel(hal->adc1, hal->battery_channel, &channel_config) != ESP_OK ||
        adc_oneshot_config_channel(hal->adc1, hal->piezo_channel, &channel_config) != ESP_OK) {
        return ESP_FAIL;
    }

    return ESP_OK;
}

int staysys_mpu_read(staysys_hal_t *hal, int16_t raw[6])
{
    if (hal == NULL || raw == NULL) return ESP_ERR_INVALID_ARG;
    uint8_t data[14];
    if (read_register(hal->mpu, 0x3b, data, sizeof(data)) != ESP_OK) return ESP_FAIL;
    for (int i = 0; i < 3; ++i) {
        raw[i] = (int16_t)((data[i * 2] << 8) | data[i * 2 + 1]);
    }
    for (int i = 0; i < 3; ++i) {
        raw[i + 3] = (int16_t)((data[8 + i * 2] << 8) | data[9 + i * 2]);
    }
    return ESP_OK;
}

int staysys_qmc_read(staysys_hal_t *hal, int16_t raw[3])
{
    if (hal == NULL || raw == NULL || !hal->qmc_present) return ESP_FAIL;
    uint8_t data[6];
    if (read_register(hal->qmc, 0x01, data, sizeof(data)) != ESP_OK) return ESP_FAIL;
    for (int i = 0; i < 3; ++i) {
        raw[i] = (int16_t)((data[i * 2 + 1] << 8) | data[i * 2]);
    }
    return ESP_OK;
}

int staysys_piezo_read(staysys_hal_t *hal, int *raw)
{
    if (hal == NULL || raw == NULL) return ESP_ERR_INVALID_ARG;
    return adc_oneshot_read(hal->adc1, hal->piezo_channel, raw);
}

int staysys_battery_read(staysys_hal_t *hal, int *raw)
{
    if (hal == NULL || raw == NULL) return ESP_ERR_INVALID_ARG;
    return adc_oneshot_read(hal->adc1, hal->battery_channel, raw);
}

int staysys_battery_percentage(float voltage)
{
    if (voltage >= STASYS_BATTERY_MAX_VOLTAGE) return 100;
    if (voltage <= STASYS_BATTERY_MIN_VOLTAGE) return 0;
    return (int)(((voltage - STASYS_BATTERY_MIN_VOLTAGE) /
                  (STASYS_BATTERY_MAX_VOLTAGE - STASYS_BATTERY_MIN_VOLTAGE)) * 100.0f);
}
