import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sensor_data_provider.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/session_logger.dart';
import 'providers/ota_provider.dart';
import 'services/firmware_service.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => SessionLogger()),
        Provider(create: (_) => FirmwareService()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SessionLogger, SessionProvider>(
          create: (context) => SessionProvider(
            logger: Provider.of<SessionLogger>(context, listen: false),
          ),
          update: (context, logger, previous) => SessionProvider(logger: logger),
        ),
        ChangeNotifierProxyProvider2<SettingsProvider, SessionLogger, SensorDataProvider>(
          create: (context) => SensorDataProvider(
            settings: Provider.of<SettingsProvider>(context, listen: false),
            logger: Provider.of<SessionLogger>(context, listen: false),
          ),
          update: (context, settings, logger, previous) {
            if (previous == null) return SensorDataProvider(settings: settings, logger: logger);
            previous.updateDependencies(settings: settings, logger: logger);
            return previous;
          },
        ),
        ChangeNotifierProxyProvider<SensorDataProvider, BluetoothProvider>(
          create: (context) => BluetoothProvider(
            sensorDataProvider: Provider.of<SensorDataProvider>(context, listen: false),
          )..initializeBluetooth(),
          update: (context, sensorData, previousBluetoothProvider) {
            previousBluetoothProvider!.sensorDataProvider = sensorData;
            return previousBluetoothProvider;
          },
        ),
        ChangeNotifierProxyProvider2<BluetoothProvider, FirmwareService, OtaProvider>(
          create: (context) => OtaProvider(
            btProvider: Provider.of<BluetoothProvider>(context, listen: false),
            firmwareService: Provider.of<FirmwareService>(context, listen: false),
          ),
          update: (context, btProvider, firmwareService, previous) {
            return previous ??
                OtaProvider(
                  btProvider: btProvider,
                  firmwareService: firmwareService,
                );
          },
        ),
      ],
      child: MaterialApp.router(
        title: 'STASYS App',
        debugShowCheckedModeBanner: false,
        theme: StsysTheme.darkTheme,
        routerConfig: router,
      ),
    );
  }
}
