/*
 * ESP32 Wearable Movement Sensor - Bluetooth Serial Version
 * * Tujuan: Kode ini membuat perangkat Bluetooth bernama "ShooterSensor"
 * dan mengirimkan data sensor MPU-6050 melalui koneksi serial Bluetooth.
 */

#include "BluetoothSerial.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>

// --- Konfigurasi Bluetooth ---
BluetoothSerial SerialBT;
const char*deviceName = "ShooterSensor";

// --- Variabel Global ---
Adafruit_MPU6050 mpu;

void setup() {
  Serial.begin(115200); // Untuk debugging via USB
  delay(10);

  // Mulai koneksi Bluetooth Serial
  SerialBT.begin(deviceName);
  Serial.printf("Bluetooth device '%s' is ready to pair.\n", deviceName);

  // Inisialisasi MPU-6050
  if (!mpu.begin()) {
    Serial.println("Error: Failed to find MPU6050 chip. Check wiring.");
    while (1) { delay(10); }
  }
  Serial.println("MPU-6050 Sensor Found!");
  mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
  mpu.setGyroRange(MPU6050_RANGE_250_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
}

void loop() {
  // Hanya kirim data jika ada perangkat yang terhubung
  if (SerialBT.connected()) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    // Buat paket data yang dipisahkan koma
    String data_packet = "gyro:";
    data_packet += String(g.gyro.x, 4);
    data_packet += ",";
    data_packet += String(g.gyro.y, 4);
    data_packet += ",";
    data_packet += String(g.gyro.z, 4);

    // Kirim paket data melalui Bluetooth
    SerialBT.println(data_packet);
  } else {
    // Beri jeda jika tidak ada koneksi untuk menghemat daya
    delay(500);
  }

  // Kontrol laju data saat terhubung
  delay(50);
}
