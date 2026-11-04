import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_screen.dart';

/// Android native bridge (file picker without copying big files, "Open with" intents).
const nativeChannel = MethodChannel('thirai/native');

const videoExtensions = [
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', 'ts',
  'm2ts', 'mts', '3gp', '3g2', 'vob', 'ogv', 'rm', 'rmvb', 'asf', 'divx', 'f4v',
  'hevc', 'h264', 'h265', 'y4m', 'mxf', 'dv', 'mp3', 'flac', 'm4a', 'aac', 'wav',
  'opus', 'ogg', 'mka',
];

String baseName(String p) {
  final decoded = Uri.decodeFull(p);
  final parts = decoded.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? p : parts.last;
}

class RecentItem {
  RecentItem(this.uri, this.name);
  final String uri;
  final String name;
  Map<String, String> toJson() => {'uri': uri, 'name': name};
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialPath});
  final String? initialPath;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RecentItem> recent = [];
  bool dragOver = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleStartup());
  }

  Future<void> _handleStartup() async {
    if (widget.initialPath != null) {
      _play(widget.initialPath!, baseName(widget.initialPath!));
    }
    if (Platform.isAndroid) {
      nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'openUri') {
          final m = Map<String, dynamic>.from(call.arguments as Map);
          _play(m['uri'] as String, m['name'] as String? ?? 'Video');
        }
      });
      try {
        final r = await nativeChannel.invokeMethod<Map>('getInitialUri');
        if (r != null) _play(r['uri'] as String, r['name'] as String? ?? 'Video');
      } catch (_) {}
    }
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('recent') ?? [];
    setState(() {
      recent = list.map((s) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return RecentItem(m['uri'] as String, m['name'] as String);
      }).toList();
    });
  }

  Future<void> _saveRecent() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('recent', recent.map((r) => jsonEncode(r.toJson())).toList());
  }

  Future<void> _play(String uri, String name) async {
    recent.removeWhere((r) => r.uri == uri);
    recent.insert(0, RecentItem(uri, name));
    if (recent.length > 15) recent = recent.sublist(0, 15);
    await _saveRecent();
    if (!mounted) return;
    setState(() {});
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    await nav.push(MaterialPageRoute(builder: (_) => PlayerScreen(source: uri, title: name)));
    _loadRecent();
  }

  Future<void> _openFile() async {
    if (Platform.isAndroid) {
      final r = await nativeChannel.invokeMethod<Map>('pickVideo');
      if (r != null) _play(r['uri'] as String, r['name'] as String? ?? 'Video');
      return;
    }
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open video',
      type: FileType.any, // every format visible (4K, Blu-ray .m2ts, .mov, .ts ...)
    );
    final path = r?.files.single.path;
    if (path != null) _play(path, baseName(path));
  }

  Future<void> _openUrl() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Network stream / URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://... (mp4, m3u8, rtsp...)'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Play')),
        ],
      ),
    );
    if (url != null && url.trim().isNotEmpty) _play(url.trim(), baseName(url.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Icon(Icons.play_circle_fill_rounded, size: 84, color: cs.primary),
              const SizedBox(height: 8),
              const Text('திரை',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
              Text('Solo Thirai Player',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.6), letterSpacing: 2)),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.folder_open),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Open Video', style: TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openUrl,
                icon: const Icon(Icons.link),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Open URL / Stream'),
                ),
              ),
              if (Platform.isWindows) ...[
                const SizedBox(height: 16),
                Text('or drag & drop a video file here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.45))),
              ],
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 32),
                Row(children: [
                  const Text('Recent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => recent.clear());
                      _saveRecent();
                    },
                    child: const Text('Clear'),
                  ),
                ]),
                ...recent.map((r) => ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _play(r.uri, r.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() => recent.remove(r));
                          _saveRecent();
                        },
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );

    if (Platform.isWindows) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => dragOver = true),
        onDragExited: (_) => setState(() => dragOver = false),
        onDragDone: (d) {
          setState(() => dragOver = false);
          if (d.files.isNotEmpty) _play(d.files.first.path, d.files.first.name);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: dragOver ? cs.primary : Colors.transparent, width: 3),
          ),
          child: body,
        ),
      );
    }
    return Scaffold(body: body);
  }
}
