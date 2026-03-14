import 'package:flutter/material.dart';

import 'services/log_service.dart';
import 'services/settings_service.dart';
import 'ui/home_page.dart';

final _log = LogService();
final _settings = SettingsService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([_log.init(), _settings.load()]);
  runApp(DViewerApp(log: _log, settings: _settings));
}

class DViewerApp extends StatelessWidget {
  final LogService log;
  final SettingsService settings;

  const DViewerApp({super.key, required this.log, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umao VDownloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei UI',
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: HomePage(log: log, settings: settings),
    );
  }
}
