#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "esp_spp_api.h"
#include "esp_bt_device.h"
#include "esp_mac.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "app_protocol.h"
#include "sensor_hal.h"
#include <cmath>
#include <cstdio>
#include <cstring>

static const char *TAG = "stasys";
static EventGroupHandle_t app_events;
static staysys_hal_t sensors;
static volatile uint8_t battery_percentage;
static portMUX_TYPE spp_lock = portMUX_INITIALIZER_UNLOCKED;
static uint32_t spp_handle;
static bool spp_congested;
static char auth_rx[STASYS_MAX_CHALLENGE_LEN + 1];
static size_t auth_rx_len;

#define BT_CONNECTED BIT0
#define BT_AUTHENTICATED BIT1

static void spp_callback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param)
{
    switch (event) {
    case ESP_SPP_INIT_EVT:
        esp_spp_start_srv(ESP_SPP_SEC_NONE, ESP_SPP_ROLE_SLAVE, 0, "STASYS");
        break;
    case ESP_SPP_SRV_OPEN_EVT:
        spp_handle = param->srv_open.handle;
        spp_congested = false;
        auth_rx_len = 0;
        xEventGroupSetBits(app_events, BT_CONNECTED);
        esp_spp_write(spp_handle, 7, (uint8_t *)"READY\n");
        break;
    case ESP_SPP_DATA_IND_EVT:
        for (uint16_t i = 0; i < param->data_ind.len; ++i) {
            uint8_t byte = param->data_ind.data[i];
            if (auth_rx_len >= STASYS_MAX_CHALLENGE_LEN) {
                auth_rx_len = 0;
                xEventGroupClearBits(app_events, BT_AUTHENTICATED);
                continue;
            }
            if (byte == '\n') {
                while (auth_rx_len > 0 && (auth_rx[auth_rx_len - 1] == '\r' ||
                       auth_rx[auth_rx_len - 1] == ' ' || auth_rx[auth_rx_len - 1] == '\t')) {
                    --auth_rx_len;
                }
                size_t start = 0;
                while (start < auth_rx_len && (auth_rx[start] == ' ' || auth_rx[start] == '\t')) ++start;
                if (auth_rx_len > start) {
                    char digest[65];
                    if (staysys_auth_digest(&auth_rx[start], auth_rx_len - start, digest) == 0) {
                        esp_spp_write(spp_handle, sizeof(digest) - 1, (uint8_t *)digest);
                        esp_spp_write(spp_handle, 1, (uint8_t *)"\n");
                        xEventGroupSetBits(app_events, BT_AUTHENTICATED);
                    }
                }
                auth_rx_len = 0;
            } else if (byte != '\r') {
                auth_rx[auth_rx_len++] = (char)byte;
            }
        }
        break;
    case ESP_SPP_CONG_EVT:
        spp_congested = param->cong.cong;
        break;
    case ESP_SPP_CLOSE_EVT:
        xEventGroupClearBits(app_events, BT_CONNECTED | BT_AUTHENTICATED);
        spp_handle = 0;
        spp_congested = false;
        auth_rx_len = 0;
        break;
    default:
        break;
    }
}

static void bt_init(void)
{
    esp_bt_controller_config_t config = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&config));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_CLASSIC_BT));
    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());
    ESP_ERROR_CHECK(esp_spp_register_callback(spp_callback));
    esp_spp_cfg_t spp_cfg = {
        .mode = ESP_SPP_MODE_CB,
        .enable_l2cap_ertm = false,
        .tx_buffer_size = 0,
    };
    ESP_ERROR_CHECK(esp_spp_enhanced_init(&spp_cfg));

    uint64_t mac = 0;
    esp_read_mac((uint8_t *)&mac, ESP_MAC_BT);
    char name[24];
    snprintf(name, sizeof(name), "STASYS-%04X", (uint16_t)(mac >> 32));
    ESP_ERROR_CHECK(esp_bt_dev_set_device_name(name));
    ESP_ERROR_CHECK(esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_GENERAL_DISCOVERABLE));
}

static void sensor_task(void *)
{
        int16_t last_mpu[6] = {0};
        int16_t last_mag[3] = {0};
        bool have_mpu = false;
    float previous[3] = {0};
    while (true) {
        EventBits_t bits = xEventGroupWaitBits(app_events, BT_AUTHENTICATED,
                                                pdFALSE, pdTRUE, pdMS_TO_TICKS(100));
        if (!(bits & BT_AUTHENTICATED)) continue;
        int64_t deadline = esp_timer_get_time() + STASYS_PACKET_PERIOD_US;
        have_mpu = false;

        float peak[3] = {0};
        float max_jerk = -1.0f;
        long gyro_sum[3] = {0};
        uint16_t max_piezo = 0;
        for (int i = 0; i < STASYS_OVERSAMPLE_LOOPS; ++i) {
            if (staysys_mpu_read(&sensors, last_mpu) != ESP_OK) {
                esp_rom_delay_us(STASYS_SENSOR_DELAY_US);
                continue;
            }
            have_mpu = true;
            int piezo = 0;
            if (staysys_piezo_read(&sensors, &piezo) == ESP_OK && piezo > max_piezo) {
                max_piezo = (uint16_t)piezo;
            }
            float current[3] = {
                last_mpu[0] / 8192.0f * 9.81f,
                last_mpu[1] / 8192.0f * 9.81f,
                last_mpu[2] / 8192.0f * 9.81f,
            };
            float jerk = fabsf(current[0] - previous[0]) +
                         fabsf(current[1] - previous[1]) +
                         fabsf(current[2] - previous[2]);
            if (jerk > max_jerk) {
                max_jerk = jerk;
                memcpy(peak, current, sizeof(peak));
            }
            previous[0] = current[0]; previous[1] = current[1]; previous[2] = current[2];
            gyro_sum[0] += last_mpu[3]; gyro_sum[1] += last_mpu[4]; gyro_sum[2] += last_mpu[5];
            esp_rom_delay_us(STASYS_SENSOR_DELAY_US);
        }
        if (!have_mpu) continue;
        if (sensors.qmc_present) (void)staysys_qmc_read(&sensors, last_mag);
        staysys_packet_payload_t payload = {
            .ax = peak[0], .ay = peak[1], .az = peak[2],
            .gx = (gyro_sum[0] / (float)STASYS_OVERSAMPLE_LOOPS) / 65.5f * 0.0174533f,
            .gy = (gyro_sum[1] / (float)STASYS_OVERSAMPLE_LOOPS) / 65.5f * 0.0174533f,
            .gz = (gyro_sum[2] / (float)STASYS_OVERSAMPLE_LOOPS) / 65.5f * 0.0174533f,
            .mag_x = last_mag[0], .mag_y = last_mag[1], .mag_z = last_mag[2],
            .piezo = max_piezo, .battery = battery_percentage,
        };
        uint8_t packet[STASYS_PACKET_SIZE];
        staysys_packet_serialize(&payload, packet);
        if (!spp_congested && (xEventGroupGetBits(app_events) & BT_CONNECTED)) {
            portENTER_CRITICAL(&spp_lock);
            uint32_t handle = spp_handle;
            bool can_send = !spp_congested && handle != 0;
            if (can_send) esp_spp_write(handle, sizeof(packet), packet);
            portEXIT_CRITICAL(&spp_lock);
        }
        int64_t remaining = deadline - esp_timer_get_time();
        if (remaining > 0) esp_rom_delay_us((uint32_t)remaining);
    }
}

static void battery_task(void *)
{
    while (true) {
        int sum = 0;
        int successful = 0;
        for (int i = 0; i < 16; ++i) {
            int raw = 0;
            if (staysys_battery_read(&sensors, &raw) == ESP_OK) {
                sum += raw;
                ++successful;
            }
        }
        if (successful > 0) {
            float voltage = (sum / (float)successful) / 4095.0f * 3.3f * STASYS_VOLTAGE_DIVIDER_RATIO;
            battery_percentage = (uint8_t)staysys_battery_percentage(voltage);
        }
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

extern "C" void app_main(void)
{
    esp_err_t nvs = nvs_flash_init();
    if (nvs == ESP_ERR_NVS_NO_FREE_PAGES || nvs == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs);
    app_events = xEventGroupCreate();
    if (app_events == NULL) abort();
    ESP_ERROR_CHECK(staysys_sensors_init(&sensors));
    bt_init();
    xTaskCreatePinnedToCore(sensor_task, "sensor", 6144, NULL, 1, NULL, 1);
    xTaskCreatePinnedToCore(battery_task, "battery", 3072, NULL, 1, NULL, 0);
    ESP_LOGI(TAG, "native ESP-IDF firmware started");
}
