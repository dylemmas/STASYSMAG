import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/data_models.dart';

class InteractiveChart extends StatefulWidget {
  final List<DataPoint> gyroXData;
  final List<DataPoint> gyroYData;
  final List<DataPoint> gyroZData;

  const InteractiveChart({
    super.key,
    required this.gyroXData,
    required this.gyroYData,
    required this.gyroZData,
  });

  @override
  State<InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<InteractiveChart> {
  late ZoomPanBehavior _zoomPanBehavior;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true, // Mengaktifkan zoom dengan cubitan
      enablePanning: true, // Mengaktifkan geser/panning
      enableMouseWheelZooming: true, // Mengaktifkan zoom dengan roda mouse
      zoomMode: ZoomMode.x, // Zoom hanya pada sumbu X (waktu)
    );
  }

  @override
  Widget build(BuildContext context) {
    return SfCartesianChart(
      primaryXAxis: const NumericAxis(
        title: AxisTitle(text: 'Waktu (detik)'),
        edgeLabelPlacement: EdgeLabelPlacement.shift,
      ),
      primaryYAxis: const NumericAxis(
        title: AxisTitle(text: 'Nilai Giroskop (rad/s)'),
      ),
      tooltipBehavior: TooltipBehavior(enable: true),
      legend: const Legend(isVisible: true, position: LegendPosition.top),
      zoomPanBehavior: _zoomPanBehavior,
      series: <CartesianSeries>[
        LineSeries<DataPoint, double>(
          dataSource: widget.gyroXData,
          xValueMapper: (DataPoint data, _) => data.x,
          yValueMapper: (DataPoint data, _) => data.y,
          name: 'Samping',
          color: Colors.red,
        ),
        LineSeries<DataPoint, double>(
          dataSource: widget.gyroYData,
          xValueMapper: (DataPoint data, _) => data.x,
          yValueMapper: (DataPoint data, _) => data.y,
          name: 'Vertikal',
          color: Colors.green,
        ),
        LineSeries<DataPoint, double>(
          dataSource: widget.gyroZData,
          xValueMapper: (DataPoint data, _) => data.x,
          yValueMapper: (DataPoint data, _) => data.y,
          name: 'Depan/Belakang',
          color: Colors.blue,
        ),
      ],
    );
  }
}
