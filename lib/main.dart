import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart';
import 'win_args.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Solo Thirai Player');
    await windowManager.setMinimumSize(const Size(480, 320));
  }

  // Windows: double-click / "Open with Solo Thirai Player" passes the file path.
  runApp(ThiraiApp(initialPath: _startupFile(args)));
}

String? _startupFile(List<String> args) {
  final all = <String>[...args];
  if (Platform.isWindows) all.addAll(windowsCommandLineArgs());
  final candidates = all
      .map((a) => a.trim().replaceAll('"', ''))
      .where((a) => a.isNotEmpty && !a.startsWith('-') && !a.toLowerCase().endsWith('.exe'))
      .toList();
  for (final c in candidates) {
    if (c.contains('://') || File(c).existsSync()) return c;
  }
  return candidates.isNotEmpty ? candidates.first : null;
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
