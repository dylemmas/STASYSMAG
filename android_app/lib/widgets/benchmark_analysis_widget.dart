// ============================================
// File: widgets/benchmark_analysis_widget.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/session_logger.dart';
import '../models/data_models.dart';
import 'dart:math';

class ShotDetection {
  final double time;
  final double stabilityScore;
  final double magnitude;

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
  State<BenchmarkAnalysisWidget> createState() => _BenchmarkAnalysisWidgetState();
}

class _BenchmarkAnalysisWidgetState extends State<BenchmarkAnalysisWidget> {
  List<ShotDetection> _detectedShots = [];
  bool _isAnalyzing = false;
  double _gyroThreshold = 3.0;
  double _minShotInterval = 1.0;

  @override
  void initState() {
    super.initState();
    _analyzeShots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isAnalyzing
          ? _buildAnalyzingView()
          : Column(
              children: [
                _buildControlPanel(),
                _buildStatsCards(),
                Expanded(
                  child: _buildShotsList(),
                ),
              ],
            ),
    );
  }

  Widget _buildAnalyzingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Analyzing shots...'),
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
              'STASYS Benchmark Analysis',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gyro Threshold: ${_gyroThreshold.toStringAsFixed(1)}°/s'),
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
                      Text('Min Shot Interval: ${_minShotInterval.toStringAsFixed(1)}s'),
                      Slider(
                        value: _minShotInterval,
                        min: 0.5,
                        max: 3.0,
                        divisions: 10,
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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _analyzeShots,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-analyze'),
                ),
                ElevatedButton.icon(
                  onPressed: _showDetailedChart,
                  icon: const Icon(Icons.analytics),
                  label: const Text('Detailed Chart'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    if (_detectedShots.isEmpty) {
      return const SizedBox.shrink();
    }

    double avgScore = _detectedShots.map((s) => s.stabilityScore).reduce((a, b) => a + b) / _detectedShots.length;
    double totalTime = _detectedShots.isNotEmpty ? _detectedShots.last.time : 0.0;

    List<double> shotTimes = [];
    if (_detectedShots.isNotEmpty) {
      shotTimes.add(_detectedShots.first.time); // Time to first shot
      for (int i = 1; i < _detectedShots.length; i++) {
        shotTimes.add(_detectedShots[i].time - _detectedShots[i-1].time); // Inter-shot intervals
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildStatCard('Average Score', avgScore.toStringAsFixed(1), Icons.star, Colors.orange)),
                Expanded(child: _buildStatCard('Total Time', '${totalTime.toStringAsFixed(2)}s', Icons.timer, Colors.blue)),
                Expanded(child: _buildStatCard('Shots Detected', '${_detectedShots.length}', Icons.my_location, Colors.green)),
              ],
            ),
            if (shotTimes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Recording Duration', '${widget.session.duration.toStringAsFixed(2)}s', Icons.play_circle, Colors.purple)),
                  Expanded(child: _buildStatCard('Avg Shot Interval', '${(shotTimes.skip(1).isEmpty ? 0.0 : shotTimes.skip(1).reduce((a, b) => a + b) / shotTimes.skip(1).length).toStringAsFixed(2)}s', Icons.schedule, Colors.teal)),
                  Expanded(child: _buildStatCard('Time to 1st Shot', '${shotTimes.first.toStringAsFixed(2)}s', Icons.speed, Colors.red)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildShotsList() {
    if (_detectedShots.isEmpty) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No shots detected',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'Try adjusting the detection parameters',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Fixed header
          Container(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Shot Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.grey[100],
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Shot #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('Time (s)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('Magnitude', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          // Expanded ListView to prevent overflow
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: _detectedShots.length,
              itemBuilder: (context, index) {
                final shot = _detectedShots[index];
                final shotTime = index == 0
                    ? shot.time // Time to first shot
                    : shot.time - _detectedShots[index - 1].time; // Inter-shot interval

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                    color: index.isEven ? Colors.white : Colors.grey[50],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getScoreColor(shot.stabilityScore),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            shot.stabilityScore.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          shotTime.toStringAsFixed(2),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          shot.magnitude.toStringAsFixed(2),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  void _analyzeShots() {
    setState(() {
      _isAnalyzing = true;
    });

    // Simulate analysis delay
    Future.delayed(const Duration(milliseconds: 500), () {
      List<ShotDetection> shots = [];

      // Calculate gyro magnitude for each data point
      List<double> gyroMagnitudes = [];
      List<double> times = [];

      for (int i = 0; i < widget.session.gyroX.length; i++) {
        double magnitude = sqrt(
          pow(widget.session.gyroX[i].y, 2) +
          pow(widget.session.gyroY[i].y, 2) +
          pow(widget.session.gyroZ[i].y, 2)
        );
        gyroMagnitudes.add(magnitude);
        times.add(widget.session.gyroX[i].x);
      }

      // Simple peak detection
      for (int i = 1; i < gyroMagnitudes.length - 1; i++) {
        if (gyroMagnitudes[i] > _gyroThreshold &&
            gyroMagnitudes[i] > gyroMagnitudes[i-1] &&
            gyroMagnitudes[i] > gyroMagnitudes[i+1]) {

          // Check minimum interval
          bool validInterval = true;
          if (shots.isNotEmpty) {
            double lastShotTime = shots.last.time;
            if (times[i] - lastShotTime < _minShotInterval) {
              validInterval = false;
            }
          }

          if (validInterval) {
            // Calculate stability score for this shot (simple implementation)
            double stabilityScore = _calculateStabilityScore(i, gyroMagnitudes);

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

  double _calculateStabilityScore(int peakIndex, List<double> magnitudes) {
    // Simple stability calculation based on variance around the peak
    int windowSize = 10;
    int start = max(0, peakIndex - windowSize);
    int end = min(magnitudes.length, peakIndex + windowSize + 1);

    List<double> window = magnitudes.sublist(start, end);
    double mean = window.reduce((a, b) => a + b) / window.length;
    double variance = window.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / window.length;

    // Convert to 0-100 score (lower variance = higher score)
    double score = max(0, 100 - (variance * 10));
    return min(100, score);
  }

  void _showDetailedChart() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Detailed Analysis Chart',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _buildDetailedChart(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedChart() {
    // Calculate gyro magnitude for plotting
    List<DataPoint> magnitudeData = [];
    for (int i = 0; i < widget.session.gyroX.length; i++) {
      double magnitude = sqrt(
        pow(widget.session.gyroX[i].y, 2) +
        pow(widget.session.gyroY[i].y, 2) +
        pow(widget.session.gyroZ[i].y, 2)
      );
      magnitudeData.add(DataPoint(widget.session.gyroX[i].x, magnitude));
    }

    return SfCartesianChart(
      primaryXAxis: NumericAxis(
        title: AxisTitle(text: 'Time (seconds)'),
      ),
      primaryYAxis: NumericAxis(
        title: AxisTitle(text: 'Magnitude (°/s)'),
      ),
      series: <CartesianSeries>[
        LineSeries<DataPoint, double>(
          dataSource: magnitudeData,
          xValueMapper: (DataPoint point, _) => point.x,
          yValueMapper: (DataPoint point, _) => point.y,
          name: 'Gyro Magnitude',
          color: Colors.blue,
        ),
      ],
      annotations: _detectedShots.map((shot) => CartesianChartAnnotation(
        widget: Icon(Icons.my_location, color: Colors.red, size: 16),
        coordinateUnit: CoordinateUnit.point,
        x: shot.time,
        y: shot.magnitude,
      )).toList(),
    );
  }
}
