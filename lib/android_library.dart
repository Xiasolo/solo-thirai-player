import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'home_screen.dart' show nativeChannel;

/// MX Player style library for Android: every video on the device, grouped by folder.

class VideoItem {
  VideoItem(Map m)
      : id = (m['id'] as num).toInt(),
        uri = m['uri'] as String,
        name = (m['name'] as String?) ?? 'Video',
        folder = (m['folder'] as String?) ?? 'Others',
        size = ((m['size'] as num?) ?? 0).toInt(),
        durationMs = ((m['duration'] as num?) ?? 0).toInt(),
        date = ((m['date'] as num?) ?? 0).toInt(),
        width = ((m['width'] as num?) ?? 0).toInt(),
        height = ((m['height'] as num?) ?? 0).toInt();

  final int id;
  final String uri;
  final String name;
  final String folder;
  final int size;
  final int durationMs;
  final int date;
  final int width;
  final int height;

  String get sizeText {
    if (size <= 0) return '';
    const gb = 1024 * 1024 * 1024, mb = 1024 * 1024;
    return size >= gb ? '${(size / gb).toStringAsFixed(2)} GB' : '${(size / mb).toStringAsFixed(0)} MB';
  }

  String get qualityText {
    final s = minInt(width, height);
    if (s >= 2000) return '4K';
    if (s >= 1400) return '2K';
    if (s >= 1000) return '1080p';
    if (s >= 700) return '720p';
    if (s >= 470) return '480p';
    if (s > 0) return '${s}p';
    return '';
  }

  String get durationText {
    if (durationMs <= 0) return '';
    final d = Duration(milliseconds: durationMs);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

int minInt(int a, int b) => a < b ? a : b;

typedef PlayCallback = void Function(String uri, String name);

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.onPlay,
    required this.onOpenFile,
    required this.onOpenUrl,
  });
  final PlayCallback onPlay;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenUrl;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool loading = true;
  bool granted = false;
  List<VideoItem> all = [];
  Map<String, List<VideoItem>> folders = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      granted = await nativeChannel.invokeMethod<bool>('requestPermission') ?? false;
      if (granted) {
        final list = await nativeChannel.invokeMethod<List>('queryVideos') ?? [];
        all = list.map((m) => VideoItem(m as Map)).toList();
        final map = <String, List<VideoItem>>{};
        for (final v in all) {
          map.putIfAbsent(v.folder, () => []).add(v);
        }
        final keys = map.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        folders = {for (final k in keys) k: map[k]!};
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  void _openFolder(String title, List<VideoItem> items) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FolderScreen(title: title, items: items, onPlay: widget.onPlay),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('திரை  Solo Thirai', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: all.isEmpty
                ? null
                : () => showSearch(context: context, delegate: _VideoSearch(all, widget.onPlay)),
          ),
          IconButton(tooltip: 'Open file', icon: const Icon(Icons.folder_open), onPressed: widget.onOpenFile),
          IconButton(tooltip: 'Open URL', icon: const Icon(Icons.link), onPressed: widget.onOpenUrl),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : !granted
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.video_library_outlined, size: 72, color: cs.primary),
                      const SizedBox(height: 16),
                      const Text('Phone-la irukura videos-ah kaatta permission venum',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Allow')),
                      TextButton(onPressed: widget.onOpenFile, child: const Text('Illa, file-ah select pannren')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: all.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 160),
                          Center(child: Text('Videos edhuvum kidaikkala')),
                        ])
                      : ListView(children: [
                          _folderTile(Icons.video_library, 'All videos', all, cs),
                          const Divider(height: 1),
                          for (final e in folders.entries) _folderTile(Icons.folder, e.key, e.value, cs),
                        ]),
                ),
    );
  }

  Widget _folderTile(IconData icon, String name, List<VideoItem> items, ColorScheme cs) {
    return ListTile(
      leading: Icon(icon, size: 40, color: cs.primary),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${items.length} videos'),
      onTap: () => _openFolder(name, items),
    );
  }
}

class FolderScreen extends StatelessWidget {
  const FolderScreen({super.key, required this.title, required this.items, required this.onPlay});
  final String title;
  final List<VideoItem> items;
  final PlayCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => VideoTile(item: items[i], onPlay: onPlay),
      ),
    );
  }
}

class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.item, required this.onPlay});
  final VideoItem item;
  final PlayCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final info = [item.qualityText, item.sizeText].where((s) => s.isNotEmpty).join('  ·  ');
    return InkWell(
      onTap: () => onPlay(item.uri, item.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 128,
              height: 72,
              child: Stack(fit: StackFit.expand, children: [
                VideoThumb(id: item.id),
                if (item.durationText.isNotEmpty)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      color: Colors.black87,
                      child: Text(item.durationText, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(info, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class VideoThumb extends StatefulWidget {
  const VideoThumb({super.key, required this.id});
  final int id;
  static final _cache = <int, Future<Uint8List?>>{};

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  late Future<Uint8List?> future;

  @override
  void initState() {
    super.initState();
    future = VideoThumb._cache.putIfAbsent(
      widget.id,
      () => nativeChannel
          .invokeMethod<Uint8List>('thumbnail', {'id': widget.id})
          .catchError((_) => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (_, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: const Color(0xFF222226),
            child: const Icon(Icons.movie_outlined, color: Colors.white38),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

class _VideoSearch extends SearchDelegate<void> {
  _VideoSearch(this.all, this.onPlay);
  final List<VideoItem> all;
  final PlayCallback onPlay;

  @override
  List<Widget> buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  Widget _results() {
    final q = query.toLowerCase();
    final list = q.isEmpty ? all : all.where((v) => v.name.toLowerCase().contains(q)).toList();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) => VideoTile(item: list[i], onPlay: onPlay),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();
}
