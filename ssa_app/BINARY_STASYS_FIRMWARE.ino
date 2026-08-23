#include "BluetoothSerial.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>
#include "mbedtls/sha256.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"

#define BATTERY_PIN 39
#define VOLTAGE_DIVIDER_RATIO 2.0
#define BATTERY_MAX_VOLTAGE 4.2
#define BATTERY_MIN_VOLTAGE 3.0

const char* SECRET_KEY = "12ebaf10h12fa9123z21sti";
const char* deviceName = "STASYS V1 (01)";

BluetoothSerial SerialBT;
Adafruit_MPU6050 mpu;

volatile bool isAuthenticated = false;
volatile int batteryPercentage = 0;

// --- BINARY PACKET STRUCTURE ---
// __attribute__((packed)) ensures no extra padding bytes are added
struct __attribute__((packed)) DataPacket {
  uint8_t header[2]; // 0xAA, 0xBB (Sync bytes)
  float ax;
  float ay;
  float az;
  float gx;
  float gy;
  float gz;
  uint8_t battery;
  uint8_t checksum;  // Simple XOR checksum
};

float readBatteryVoltage() {
  long sum = 0;
  for(int i=0; i<16; i++) sum += analogRead(BATTERY_PIN);
  float rawValue = sum / 16.0;
  return (rawValue / 4095.0) * 3.3 * VOLTAGE_DIVIDER_RATIO;
}

int calculateBatteryPercentage(float voltage) {
  if (voltage >= BATTERY_MAX_VOLTAGE) return 100;
  if (voltage <= BATTERY_MIN_VOLTAGE) return 0;
  float percentage = ((voltage - BATTERY_MIN_VOLTAGE) / (BATTERY_MAX_VOLTAGE - BATTERY_MIN_VOLTAGE)) * 100.0;
  return constrain((int)percentage, 0, 100);
}

void handleAuthentication() {
  isAuthenticated = false;
  // Flush buffer
  while (SerialBT.available()) SerialBT.read();

  String challenge = "";
  unsigned long startTime = millis();
  SerialBT.setTimeout(500);

  while (millis() - startTime < 5000) {
    if (SerialBT.available()) {
      challenge = SerialBT.readStringUntil('\n');
      challenge.trim();
      if (challenge.length() > 0) break;
    }
    vTaskDelay(10 / portTICK_PERIOD_MS);
  }

  if (challenge.length() == 0) {
    SerialBT.disconnect();
    return;
  }

  String toHash = challenge + String(SECRET_KEY);
  byte hashResult[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  mbedtls_sha256_starts(&ctx, 0);
  mbedtls_sha256_update(&ctx, (const unsigned char*)toHash.c_str(), toHash.length());
  mbedtls_sha256_finish(&ctx, hashResult);
  mbedtls_sha256_free(&ctx);

  char hexHash[65];
  for (int i = 0; i < 32; i++) sprintf(hexHash + (i * 2), "%02x", hashResult[i]);

  // Auth response is still TEXT for simplicity
  SerialBT.println(hexHash);
  delay(200);
  isAuthenticated = true;
}

void batteryMonitorTask(void *parameter) {
  for (;;) {
    float batteryVoltage = readBatteryVoltage();
    batteryPercentage = calculateBatteryPercentage(batteryVoltage);
    vTaskDelay(5000 / portTICK_PERIOD_MS);
  }
}

void sensorTask(void *parameter) {
  for (;;) {
    if (SerialBT.connected()) {
      if (!isAuthenticated) {
        handleAuthentication();
      }

      if (isAuthenticated) {
        sensors_event_t a, g, temp;
        mpu.getEvent(&a, &g, &temp);

        // Prepare Binary Packet
        DataPacket pkt;
        pkt.header[0] = 0xAA;
        pkt.header[1] = 0xBB;
        pkt.ax = a.acceleration.x;
        pkt.ay = a.acceleration.y;
        pkt.az = a.acceleration.z;
        pkt.gx = g.gyro.x;
        pkt.gy = g.gyro.y;
        pkt.gz = g.gyro.z;
        pkt.battery = (uint8_t)batteryPercentage;

        // Calculate Checksum (XOR of data bytes)
        // We cast the struct to a byte array to loop through it
        uint8_t* ptr = (uint8_t*)&pkt;
        pkt.checksum = 0;
        // Checksum from byte 2 (after header) to end-1 (before checksum)
        for(int i=2; i<sizeof(DataPacket)-1; i++) {
          pkt.checksum ^= ptr[i];
        }

        // Send raw bytes
        SerialBT.write((const uint8_t*)&pkt, sizeof(DataPacket));

        // 20Hz update
        vTaskDelay(20 / portTICK_PERIOD_MS);
      } else {
        vTaskDelay(1000 / portTICK_PERIOD_MS);
      }
    } else {
      isAuthenticated = false;
      vTaskDelay(500 / portTICK_PERIOD_MS);
    }
  }
}

void setup() {
  setCpuFrequencyMhz(80);
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  SerialBT.begin(deviceName);
  esp_bredr_tx_power_set(ESP_PWR_LVL_N0, ESP_PWR_LVL_P3);

  Wire.begin();
  if (!mpu.begin()) while (1) delay(100);

  mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
  mpu.setGyroRange(MPU6050_RANGE_250_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  xTaskCreate(sensorTask, "SensorTask", 4096, NULL, 1, NULL);
  xTaskCreate(batteryMonitorTask, "BatMonitor", 2048, NULL, 1, NULL);
}

void loop() {
  vTaskDelay(1000 / portTICK_PERIOD_MS);
}
