import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Solo Thirai Player');
    await windowManager.setMinimumSize(const Size(480, 320));
  }

  // Windows: "Open with Solo Thirai Player" / drag file onto the .exe passes the path here.
  final initial = args.where((a) => !a.startsWith('-')).toList();
  runApp(ThiraiApp(initialPath: initial.isNotEmpty ? initial.first : null));
}

class ThiraiApp extends StatelessWidget {
  const ThiraiApp({super.key, this.initialPath});
  final String? initialPath;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFB300);
    return MaterialApp(
      title: 'Solo Thirai Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          primary: accent,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
      ),
      home: HomeScreen(initialPath: initialPath),
    );
  }
}
