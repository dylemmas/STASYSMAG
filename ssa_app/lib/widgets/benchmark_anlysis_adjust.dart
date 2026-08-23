// ===========================================
// File: widgets/benchmark_analysis_widget.dart
// (DIMODIFIKASI DENGAN IDE 2 & 3)
// ===========================================

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/session_logger.dart'; // Asumsi path ini benar
import '../models/data_models.dart';     // Asumsi path ini benar
import 'dart:math';

class ShotDetection {
  final double time;
  final double stabilityScore;
  final double magnitude; // Ini tetap Gyro magnitude untuk referensi

  ShotDetection({
    required this.time,
    required this.stabilityScore,
    required this.magnitude,
  });
}

class BenchmarkAnalysisWidget extends StatefulWidget {
  final SessionLog session;

  const BenchmarkAnalysisWidget({super.key, required this.session});

  @override
  State<BenchmarkAnalysisWidget> createState() =>
      _BenchmarkAnalysisWidgetState();
}

class _BenchmarkAnalysisWidgetState extends State<BenchmarkAnalysisWidget> {
  List<ShotDetection> _detectedShots = [];
  bool _isAnalyzing = false;

  // --- PARAMETER UNTUK DI-TUNING (BAGIAN 1) ---

  // <-- ADJUST/TUNING (Threshold Deteksi Gyro)
  double _gyroThreshold = 3.0; // Nilai awal

  // <-- ADJUST/TUNING (Threshold Deteksi Accel)
  double _accelThreshold = 5.0; // Nilai awal (BARU)

  // <-- ADJUST/TUNING (Jarak antar tembakan)
  double _minShotInterval = 1.0;

  // ------------------------------------------

  @override
  void initState() {
    super.initState();
    // Validasi data sensor
    if (widget.session.accelX.isEmpty || widget.session.gyroX.isEmpty) {
      // Tampilkan error atau state kosong jika data tidak ada
      //print("Error: Data sensor (gyro/accel) kosong!");
    } else {
      _analyzeShots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isAnalyzing
          ? _buildAnalyzingView()
          : Column(
              children: [
                _buildControlPanel(), // Panel kontrol sekarang di atas
                Expanded(
                  child: _detectedShots.isEmpty
                      ? _buildEmptyView()
                      : _buildResultsView(),
                ),
              ],
            ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analisis Tembakan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),

            // --- Row 1: Gyro Threshold & Min Interval ---
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gyro Threshold: ${_gyroThreshold.toStringAsFixed(1)} °/s'),
                      Slider(
                        value: _gyroThreshold,
                        min: 1.0,
                        max: 10.0,
                        divisions: 18,
                        onChanged: (value) {
                          setState(() {
                            _gyroThreshold = value;
                          });
                        },
                        onChangeEnd: (value) => _analyzeShots(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Min Interval: ${_minShotInterval.toStringAsFixed(1)} s'),
                      Slider(
                        value: _minShotInterval,
                        min: 0.2,
                        max: 3.0,
                        divisions: 14,
                        onChanged: (value) {
                          setState(() {
                            _minShotInterval = value;
                          });
                        },
                        onChangeEnd: (value) => _analyzeShots(),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // --- Row 2: Accel Threshold (BARU) ---
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accel Threshold: ${_accelThreshold.toStringAsFixed(1)} m/s²'),
                      Slider(
                        value: _accelThreshold,
                        min: 1.0,
                        max: 20.0, // Accel punya rentang lebih besar
                        divisions: 19,
                        onChanged: (value) {
                          setState(() {
                            _accelThreshold = value;
                          });
                        },
                        onChangeEnd: (value) => _analyzeShots(),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            // --- Row 3: Tombol ---
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _showDetailedChart,
                  child: const Text('Lihat Grafik Detail'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _analyzeShots,
                  child: const Text('Ulangi Analisis'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- FUNGSI UTAMA ANALISIS (DIMODIFIKASI DENGAN IDE 2) ---
  void _analyzeShots() {
    // Validasi ulang untuk memastikan data ada
    if (widget.session.gyroX.isEmpty || widget.session.accelX.isEmpty) {
      //print("Analisis dibatalkan: Data sensor tidak lengkap.");
      setState(() {
        _isAnalyzing = false;
        _detectedShots = [];
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      List<ShotDetection> shots = [];

      // Hitung magnitude untuk gyro dan accel
      List<double> gyroMagnitudes = [];
      List<double> accelMagnitudes = []; // <-- BARU
      List<double> times = [];

      // Asumsi: gyroX dan accelX memiliki panjang yang sama
      int dataLength = min(widget.session.gyroX.length, widget.session.accelX.length);

      for (int i = 0; i < dataLength; i++) {
        // Gyro Magnitude
        double gyroMag = sqrt(
          pow(widget.session.gyroX[i].y, 2) +
          pow(widget.session.gyroY[i].y, 2) +
          pow(widget.session.gyroZ[i].y, 2)
        );
        gyroMagnitudes.add(gyroMag);
        times.add(widget.session.gyroX[i].x); // Asumsi waktu sama

        // --- BARU ---
        // Accel Magnitude (pastikan nama field accelX,Y,Z benar)
        double accelMag = sqrt(
          pow(widget.session.accelX[i].y, 2) +
          pow(widget.session.accelY[i].y, 2) +
          pow(widget.session.accelZ[i].y, 2)
        );
        accelMagnitudes.add(accelMag);
        // --- END BARU ---
      }

      // Deteksi Puncak Sederhana
      for (int i = 1; i < gyroMagnitudes.length - 1; i++) {

        // --- MODIFIKASI KONDISI DETEKSI (IDE 2) ---
        // 1. Cek apakah ini puncak Gyro
        bool isGyroPeak = gyroMagnitudes[i] > _gyroThreshold &&
                          gyroMagnitudes[i] > gyroMagnitudes[i-1] &&
                          gyroMagnitudes[i] > gyroMagnitudes[i+1];

        // 2. Cek apakah Accel juga di atas threshold
        bool isAccelPeak = accelMagnitudes[i] > _accelThreshold;

        // 3. Tembakan valid HANYA JIKA KEDUANYA true
        if (isGyroPeak && isAccelPeak) {

          // 4. Cek interval minimum (logika tidak berubah)
          bool validInterval = true;
          if (shots.isNotEmpty) {
            double lastShotTime = shots.last.time;
            if (times[i] - lastShotTime < _minShotInterval) {
              validInterval = false;
            }
          }

          if (validInterval) {
            // --- PANGGILAN FUNGSI SKOR BARU (IDE 3) ---
            double stabilityScore = _calculateStabilityScore(
              i, // Indeks puncak
              times,
              gyroMagnitudes,
              accelMagnitudes // Kirim data accel juga
            );

            shots.add(ShotDetection(
              time: times[i],
              stabilityScore: stabilityScore,
              magnitude: gyroMagnitudes[i],
            ));
          }
        }
      }

      setState(() {
        _detectedShots = shots;
        _isAnalyzing = false;
      });
    });
  }


  // --- FUNGSI BARU (HELPER UNTUK IDE 3) ---
  /// Menghitung Standar Deviasi dari sebuah list angka.
  /// Ini mengukur seberapa "goyang" atau "menyebar" data tersebut.
  /// Nilai rendah = stabil. Nilai tinggi = goyang.
  double _calculateStandardDeviation(List<double> data) {
    if (data.length < 2) return 0.0; // Tidak bisa dihitung jika data terlalu sedikit

    double mean = data.reduce((a, b) => a + b) / data.length;
    double variance = data.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / (data.length - 1); // Use n-1 for sample std dev
    return sqrt(variance);
  }


  // --- FUNGSI SKOR BARU (IMPLEMENTASI IDE 3) ---
  /// Menghitung skor stabilitas berdasarkan data SESAAT SEBELUM tembakan.
  double _calculateStabilityScore(
    int peakIndex,
    List<double> times,
    List<double> gyroMagnitudes,
    List<double> accelMagnitudes
  ) {
    // --- PARAMETER UNTUK DI-TUNING (BAGIAN 2) ---

    // <-- ADJUST/TUNING (Durasi analisis pra-tembakan dalam detik)
    const double preShotWindowDuration = 1.0; // Analisis 1.0 detik data SEBELUM puncak

    // ------------------------------------------

    double peakTime = times[peakIndex];
    double startTime = peakTime - preShotWindowDuration;

    // Temukan indeks data tempat kita mulai menganalisis
    int startIndex = peakIndex;
    while (startIndex > 0 && times[startIndex - 1] > startTime) {
      startIndex--;
    }

    // Jika tembakan terjadi terlalu cepat (kurang dari 1 dtk data),
    // kita tidak bisa menghitung skor
    if (startIndex == peakIndex) {
      return 0.0; // Skor 0 karena tidak ada data pra-tembakan
    }

    // Ambil data "pra-tembakan" (sebelum puncak)
    List<double> gyroPreShot = gyroMagnitudes.sublist(startIndex, peakIndex);
    List<double> accelPreShot = accelMagnitudes.sublist(startIndex, peakIndex);

    // Hitung "goyangan" (shakiness) menggunakan Standar Deviasi
    double gyroStdDev = _calculateStandardDeviation(gyroPreShot);
    double accelStdDev = _calculateStandardDeviation(accelPreShot);

    // --- (OPSIONAL) DEBUG PRINT UNTUK TUNING ---
    // Aktifkan ini untuk melihat nilai mentah di debug console
    // print("--- Shot @ ${peakTime.toStringAsFixed(2)}s ---");
    // print("Gyro StdDev (Goyangan Rotasi): ${gyroStdDev.toStringAsFixed(3)}");
    // print("Accel StdDev (Goyangan Linear): ${accelStdDev.toStringAsFixed(3)}");
    // --- END DEBUG ---


    // --- PARAMETER UNTUK DI-TUNING (BAGIAN 3) ---
    // Ini adalah bagian "seni" nya. Sesuaikan angka "pengali" ini
    // untuk mengubah seberapa besar "goyangan" (StdDev) mengurangi skor 100.

    // <-- ADJUST/TUNING (Pengali Penalti Gyro)
    const double gyroPenaltyScaler = 10.0;

    // <-- ADJUST/TUNING (Pengali Penalti Accel)
    const double accelPenaltyScaler = 5.0;

    // ------------------------------------------

    double gyroPenalty = gyroStdDev * gyroPenaltyScaler;
    double accelPenalty = accelStdDev * accelPenaltyScaler;

    double totalPenalty = gyroPenalty + accelPenalty;

    // Skor adalah 100 dikurangi total penalti
    double score = 100.0 - totalPenalty;

    // Pastikan skor tidak di bawah 0 atau di atas 100
    return max(0, min(100, score));
  }


  // --- Sisa Widget (Tidak Berubah) ---

  Widget _buildAnalyzingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Menganalisis data...'),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Text('Tidak ada tembakan terdeteksi. Coba sesuaikan threshold.'),
    );
  }

  Widget _buildResultsView() {
    // Hitung rata-rata skor
    double averageScore = _detectedShots.isNotEmpty
        ? _detectedShots.map((s) => s.stabilityScore).reduce((a, b) => a + b) /
            _detectedShots.length
        : 0.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('Tembakan Terdeteksi', style: Theme.of(context).textTheme.labelLarge),
                      Text(
                        _detectedShots.length.toString(),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text('Rata-rata Skor', style: Theme.of(context).textTheme.labelLarge),
                      Text(
                        averageScore.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: averageScore > 85 ? Colors.green : (averageScore > 70 ? Colors.orange : Colors.red)
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _detectedShots.length,
            itemBuilder: (context, index) {
              final shot = _detectedShots[index];
              Color scoreColor = shot.stabilityScore > 85
                  ? Colors.green
                  : (shot.stabilityScore > 70 ? Colors.orange : Colors.red);

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scoreColor,
                  child: Text(
                    shot.stabilityScore.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text('Skor Stabilitas: ${shot.stabilityScore.toStringAsFixed(1)}'),
                subtitle: Text('Terdeteksi @ ${shot.time.toStringAsFixed(2)} detik (Mag: ${shot.magnitude.toStringAsFixed(1)})'),
                trailing: Text('#${index + 1}'),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDetailedChart() {
    // Hitung magnitude GYRO (untuk grafik)
    List<DataPoint> gyroMagnitudeData = [];
    // Hitung magnitude ACCEL (untuk grafik)
    List<DataPoint> accelMagnitudeData = [];

    int dataLength = min(widget.session.gyroX.length, widget.session.accelX.length);

    for (int i = 0; i < dataLength; i++) {
      double gyroMag = sqrt(
        pow(widget.session.gyroX[i].y, 2) +
        pow(widget.session.gyroY[i].y, 2) +
        pow(widget.session.gyroZ[i].y, 2)
      );
      gyroMagnitudeData.add(DataPoint(widget.session.gyroX[i].x, gyroMag));

      double accelMag = sqrt(
        pow(widget.session.accelX[i].y, 2) +
        pow(widget.session.accelY[i].y, 2) +
        pow(widget.session.accelZ[i].y, 2)
      );
      accelMagnitudeData.add(DataPoint(widget.session.accelX[i].x, accelMag));
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Grafik Magnitude Sensor', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              SizedBox(
                height: 400, // Tentukan tinggi agar tidak overflow
                width: MediaQuery.of(context).size.width * 0.9, // Tentukan lebar
                child: _buildDetailedChart(gyroMagnitudeData, accelMagnitudeData), // Kirim kedua data
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedChart(List<DataPoint> gyroData, List<DataPoint> accelData) {
    return SfCartesianChart(
      primaryXAxis: NumericAxis(
        title: AxisTitle(text: 'Time (seconds)'),
      ),
      primaryYAxis: NumericAxis(
        title: AxisTitle(text: 'Magnitude'),
        // Anda mungkin perlu axis berbeda jika skala terlalu jauh
      ),
      legend: Legend(isVisible: true, position: LegendPosition.bottom),
      series: <CartesianSeries>[
        // Grafik Gyro
        LineSeries<DataPoint, double>(
          dataSource: gyroData,
          xValueMapper: (DataPoint point, _) => point.x,
          yValueMapper: (DataPoint point, _) => point.y,
          name: 'Gyro (°/s)',
          color: Colors.blue,
        ),
        // Grafik Accel (BARU)
        LineSeries<DataPoint, double>(
          dataSource: accelData,
          xValueMapper: (DataPoint point, _) => point.x,
          yValueMapper: (DataPoint point, _) => point.y,
          name: 'Accel (m/s²)',
          color: Colors.red,
        ),
      ],
      annotations: [
        // Tambahkan garis horizontal untuk threshold
        CartesianChartAnnotation(
          widget: Container(color: const Color.fromRGBO(0, 0, 255, 0.3), height: 1), // Garis Gyro
          coordinateUnit: CoordinateUnit.point,
          region: AnnotationRegion.chart,
          x:0,
          y: _gyroThreshold,
        ),
        CartesianChartAnnotation(
          widget: Container(color: const Color.fromRGBO(255, 0, 0, 0.3), height: 1), // Garis Accel
          coordinateUnit: CoordinateUnit.point,
          region: AnnotationRegion.chart,
          x:0,
          y: _accelThreshold,
        ),
      ],
    );
  }
}

// Model DataPoint tidak berubah dari kode Anda
// (Asumsi ada di data_models.dart, tapi saya sertakan di sini
// jika ternyata belum ada)
/*
class DataPoint {
  final double x; // time
  final double y; // value
  DataPoint(this.x, this.y);
}
*/
