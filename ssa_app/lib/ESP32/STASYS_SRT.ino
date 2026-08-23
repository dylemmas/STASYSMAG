/*
 * ESP32 Wearable Movement Sensor - FreeRTOS with Challenge-Response Security
 * * Tujuan: Mengimplementasikan sistem otentikasi challenge-response
 * untuk memastikan hanya aplikasi resmi yang dapat terhubung.
 */

#include "BluetoothSerial.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>
#include "mbedtls/sha256.h"

// --- KUNCI RAHASIA ---
// JANGAN PERNAH MENGIRIM KUNCI INI. Kunci ini harus sama persis dengan yang ada di aplikasi.
const char* SECRET_KEY = "12ebaf10h12fa9123z21sti";

// --- Konfigurasi Bluetooth ---
BluetoothSerial SerialBT;
const char* deviceName = "STASYS V1 (002)";

// --- Variabel Global ---
Adafruit_MPU6050 mpu;
bool isAuthenticated = false; // Status otentikasi

void handleAuthentication() {
  isAuthenticated = false;
  Serial.println("--> [AUTH] Waiting for challenge from app...");

  String challenge = "";
  unsigned long startTime = millis();

  // Tunggu challenge dari aplikasi (dengan timeout 5 detik)
  while (millis() - startTime < 5000) {
    if (SerialBT.available()) {
      challenge = SerialBT.readStringUntil('\n');
      challenge.trim();
      break;
    }
  }

  if (challenge.length() == 0) {
    Serial.println("--> [AUTH] Challenge timeout. Disconnecting.");
    SerialBT.disconnect();
    return;
  }

  Serial.println("Challenge received. Calculating response...");
  Serial.println(challenge);

  // Gabungkan challenge dengan secret key
  String toHash = challenge + String(SECRET_KEY);
  Serial.print("--> [AUTH] String to hash: ");
  Serial.println(toHash);

  // Hitung HMAC-SHA256 (untuk kesederhanaan, kita gunakan SHA256 standar di sini)
  byte hashResult[32];
  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  mbedtls_sha256_starts(&ctx, 0); // 0 for SHA-256
  mbedtls_sha256_update(&ctx, (const unsigned char*)toHash.c_str(), toHash.length());
  mbedtls_sha256_finish(&ctx, hashResult);
  mbedtls_sha256_free(&ctx);

  // Konversi hash ke string heksadesimal
  char hexHash[65];
  for (int i = 0; i < 32; i++) {
    sprintf(hexHash + (i * 2), "%02x", hashResult[i]);
  }
  hexHash[64] = 0;

  Serial.print("--> [AUTH] Calculated response (HEX): ");
  Serial.println(hexHash);

  // Kirim response kembali ke aplikasi
  Serial.println("--> [AUTH] Sending response to app...");
  SerialBT.println(hexHash);
  Serial.println("Response sent.");

  // Tunggu konfirmasi dari aplikasi bahwa otentikasi berhasil.
  Serial.println("--> [AUTH] Waiting for authentication confirmation from app...");
  String confirmation = "";
  startTime = millis();
  while (millis() - startTime < 5000) { // Timeout 5 detik untuk konfirmasi
      if (SerialBT.available()) {
          confirmation = SerialBT.readStringUntil('\n');
          confirmation.trim();
          break;
      }
  }

  if (confirmation == "AUTH_SUCCESS") {
      Serial.println("--> [AUTH] Confirmation received. Authentication successful!");
      isAuthenticated = true;
  } else {
      Serial.print("--> [AUTH] Confirmation failed or timed out. Received: ");
      Serial.println(confirmation);
      SerialBT.disconnect();
      isAuthenticated = false;
  }
}
//   // Beri sedikit waktu agar aplikasi bisa memverifikasi
//   delay(100);

//   // Idealnya, aplikasi akan mengirim konfirmasi. Untuk saat ini, kita anggap berhasil.
//   isAuthenticated = true;
// }

// --- Definisi Tugas (Task) FreeRTOS ---
void sensorTask(void *parameter) {
  for (;;) {
    if (SerialBT.connected()) {
      // Jika baru terhubung, lakukan otentikasi dulu
      if (!isAuthenticated) {
        handleAuthentication();
      }

      // Hanya kirim data jika sudah terotentikasi
      if (isAuthenticated) {
        sensors_event_t a, g, temp;
        mpu.getEvent(&a, &g, &temp);

        String data_packet = "";
        data_packet += String(a.acceleration.x, 4) + ",";
        data_packet += String(a.acceleration.y, 4) + ",";
        data_packet += String(a.acceleration.z, 4) + ",";
        data_packet += String(g.gyro.x, 4) + ",";
        data_packet += String(g.gyro.y, 4) + ",";
        data_packet += String(g.gyro.z, 4);

        SerialBT.println(data_packet);
        vTaskDelay(50 / portTICK_PERIOD_MS);
      }
    } else {
      isAuthenticated = false; // Reset status saat koneksi terputus
      vTaskDelay(500 / portTICK_PERIOD_MS);
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(10);

  SerialBT.begin(deviceName);
  Serial.printf("Bluetooth device '%s' is ready to pair.\n", deviceName);

  if (!mpu.begin()) {
    Serial.println("Error: Failed to find MPU6050 chip. Check wiring.");
    while (1) { delay(10); }
  }
  Serial.println("MPU-6050 Sensor Found!");
  mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
  mpu.setGyroRange(MPU6050_RANGE_250_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  xTaskCreate(sensorTask, "Sensor & BT Task", 4096, NULL, 1, NULL);
}

void loop() {
  // Dibiarkan kosong, FreeRTOS menangani semuanya.
}
