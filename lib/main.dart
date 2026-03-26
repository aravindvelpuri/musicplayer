import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/splash_screen.dart';

class AppConfig {
  static String version = '1.0.0';
  static String buildNumber = '1';

  static Future<void> init() async {
    final packageInfo = await PackageInfo.fromPlatform();
    version = packageInfo.version;
    buildNumber = packageInfo.buildNumber;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B5EA7),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F5FA),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
