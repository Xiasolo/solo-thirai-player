import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart' show nativeChannel, baseName;
import 'settings.dart';
import 'subtitle.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.source, required this.title});
  final String source;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;
  final focusNode = FocusNode();
  final _subs = <StreamSubscription>[];
  SharedPreferences? prefs;

  // playback state
  final position = ValueNotifier<Duration>(Duration.zero);
  Duration duration = Duration.zero;
  bool playing = false;
  bool buffering = true;
  double volume = 100;
  double lastVolume = 100;
  double rate = 1.0;
  BoxFit fit = BoxFit.contain;
  bool hwdec = true;
  bool fullscreen = false;
  bool landscape = false;
  bool orientationDecided = false;
  int? vw, vh;
  bool resumed = false;
  int lastSavedSec = -1;
  double? seekDrag;

  // subtitles
  SubStyle style = SubStyle();
  List<SubtitleCue> cues = [];
  List<String> mpvSubText = const [];
  String? externalSubName;
  int subDelayMs = 0;
  final subText = ValueNotifier<String>('');
  final subKey = GlobalKey();
  bool draggingSub = false;

  // UI
  bool controlsVisible = true;
  Timer? hideTimer;
  String? osd;
  Timer? osdTimer;
  Offset? doubleTapPos;

  // decoder fallback: hardware -> hardware(copy) -> software
  // Windows: copy-back hardware decoding works with 8/10-bit, HEVC, AV1, 4K, HDR.
  final List<String> hwModes =
      Platform.isWindows ? const ['auto-copy', 'no'] : const ['auto-safe', 'no'];
  int hwIndex = 0;
  bool firstFrame = false;
  bool fallingBack = false;
  String? fatalError;
  Timer? stuckTimer;

  NativePlayer? get native => player.platform is NativePlayer ? player.platform as NativePlayer : null;

  @override
  void initState() {
    super.initState();
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Solo Thirai Player',
        bufferSize: 64 * 1024 * 1024, // smooth 4K / high bitrate
      ),
    );
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: hwModes.first,
      ),
    );
    controller.waitUntilFirstFrameRendered.then((_) {
      if (mounted) setState(() => firstFrame = true);
    });
    _init();
  }

  Future<void> _init() async {
    prefs = await SharedPreferences.getInstance();
    style = await SubStyle.load();

    final np = native;
    if (np != null) {
      await np.setProperty('volume-max', '150');
      await np.setProperty('sub-auto', 'no'); // we load same-name subtitles ourselves
      await np.setProperty('cache', 'yes');
      await np.setProperty('hwdec-codecs', 'all');
      await np.setProperty('framedrop', 'vo');
    }

    _subs.addAll([
      player.stream.playing.listen((v) {
        setState(() => playing = v);
        _scheduleHide();
      }),
      player.stream.position.listen((v) {
        position.value = v;
        _refreshSubText();
        _saveResume(v);
      }),
      player.stream.duration.listen((v) {
        setState(() => duration = v);
        _maybeResume();
      }),
      player.stream.buffering.listen((v) => setState(() => buffering = v)),
      player.stream.volume.listen((v) => volume = v),
      player.stream.rate.listen((v) => rate = v),
      player.stream.subtitle.listen((v) {
        mpvSubText = v;
        _refreshSubText();
      }),
      player.stream.tracks.listen((_) => setState(() {})),
      player.stream.width.listen((v) {
        vw = v;
        _autoOrientation();
      }),
      player.stream.height.listen((v) {
        vh = v;
        _autoOrientation();
      }),
      player.stream.completed.listen((c) {
        if (c) prefs?.remove('resume:${widget.source}');
      }),
      player.stream.error.listen((e) {
        if (vw == null || vw == 0) {
          _fallback('Error: $e');
        } else {
          _showOsd('Error: $e');
        }
      }),
    ]);

    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (Platform.isWindows) {
      windowManager.setTitle('${widget.title} - Solo Thirai Player');
    }

    await native?.setProperty('hwdec', hwModes[hwIndex]);
    await _openMedia();
    await _autoLoadSubtitle();
    _scheduleHide();
  }

  // ---------- open + decoder fallback (4K / HEVC / 10-bit safety) ----------
  Future<void> _openMedia() async {
    if (mounted) setState(() => fatalError = null);
    vw = null;
    stuckTimer?.cancel();
    final wait = widget.source.contains('://') ? 25 : 10;
    stuckTimer = Timer(Duration(seconds: wait), _checkStuck);
    try {
      await player.open(Media(widget.source));
    } catch (e) {
      _fallback('Open failed: $e');
    }
  }

  void _checkStuck() {
    if (!mounted || fatalError != null) return;
    final hasVideoTrack =
        player.state.tracks.video.any((t) => t.id != 'auto' && t.id != 'no');
    final noPicture = vw == null || vw == 0 || (!firstFrame && hwIndex == 0);
    final notMoving = player.state.playing && position.value < const Duration(milliseconds: 300);
    if ((hasVideoTrack && noPicture) || notMoving || duration == Duration.zero) {
      _fallback('Video load aagala (decoder: ${hwModes[hwIndex]})');
    }
  }

  Future<void> _fallback(String reason) async {
    if (fallingBack || !mounted) return;
    fallingBack = true;
    try {
      if (hwIndex < hwModes.length - 1) {
        hwIndex++;
        await native?.setProperty('hwdec', hwModes[hwIndex]);
        setState(() => hwdec = hwModes[hwIndex] != 'no');
        _showOsd(hwModes[hwIndex] == 'no'
            ? 'Software decoding-la try pannren...'
            : 'Vera decoder-la try pannren...');
        await _openMedia();
      } else {
        stuckTimer?.cancel();
        setState(() => fatalError = reason);
      }
    } finally {
      fallingBack = false;
    }
  }

  Future<void> _retryFromStart() async {
    hwIndex = 0;
    await native?.setProperty('hwdec', hwModes[0]);
    setState(() => hwdec = true);
    await _openMedia();
  }

  // ---------- resume ----------
  Future<void> _maybeResume() async {
    if (resumed || duration == Duration.zero) return;
    resumed = true;
    final saved = prefs?.getInt('resume:${widget.source}') ?? 0;
    if (saved > 10000 && saved < duration.inMilliseconds - 15000) {
      await player.seek(Duration(milliseconds: saved));
      _showOsd('Resumed from ${_fmt(Duration(milliseconds: saved))}');
    }
  }

  void _saveResume(Duration p) {
    final sec = p.inSeconds;
    if (sec % 5 == 0 && sec != lastSavedSec && sec > 0) {
      lastSavedSec = sec;
      prefs?.setInt('resume:${widget.source}', p.inMilliseconds);
    }
  }

  // ---------- orientation / fullscreen ----------
  void _autoOrientation() {
    if (!Platform.isAndroid || orientationDecided || vw == null || vh == null || vw == 0) return;
    orientationDecided = true;
    landscape = vw! >= vh!;
    _applyOrientation();
  }

  void _applyOrientation() {
    SystemChrome.setPreferredOrientations(landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
    setState(() {});
  }

  Future<void> _toggleFullscreen() async {
    if (Platform.isWindows) {
      fullscreen = !fullscreen;
      await windowManager.setFullScreen(fullscreen);
      setState(() {});
    } else if (Platform.isAndroid) {
      landscape = !landscape;
      _applyOrientation();
    }
  }

  // ---------- subtitles ----------
  void _refreshSubText() {
    String t;
    if (cues.isNotEmpty) {
      t = cueTextAt(cues, position.value - Duration(milliseconds: subDelayMs));
    } else {
      t = mpvSubText.where((s) => s.trim().isNotEmpty).join('\n').trim();
    }
    if (t != subText.value) subText.value = t;
  }

  Future<void> _autoLoadSubtitle() async {
    if (!Platform.isWindows) return;
    final src = widget.source;
    final dot = src.lastIndexOf('.');
    if (dot <= 0) return;
    final base = src.substring(0, dot);
    for (final ext in ['srt', 'vtt', 'ass', 'ssa']) {
      final f = File('$base.$ext');
      if (await f.exists()) {
        await _loadSubtitleBytes(baseName(f.path), await f.readAsBytes());
        return;
      }
    }
  }

  Future<void> _pickSubtitle() async {
    try {
      if (Platform.isAndroid) {
        final r = await nativeChannel.invokeMethod<Map>('pickSubtitle');
        if (r == null) return;
        await _loadSubtitleBytes(r['name'] as String? ?? 'subtitle.srt', r['bytes'] as Uint8List);
      } else {
        final r = await FilePicker.platform.pickFiles(
          dialogTitle: 'Load subtitle',
          type: FileType.custom,
          allowedExtensions: ['srt', 'vtt', 'ass', 'ssa', 'txt'],
        );
        final path = r?.files.single.path;
        if (path == null) return;
        await _loadSubtitleBytes(baseName(path), await File(path).readAsBytes());
      }
    } catch (e) {
      _showOsd('Subtitle load failed: $e');
    }
    focusNode.requestFocus();
  }

  Future<void> _loadSubtitleBytes(String name, Uint8List bytes) async {
    final text = decodeSubtitleBytes(bytes);
    final ext = name.toLowerCase().split('.').last;
    if (ext != 'ass' && ext != 'ssa') {
      final parsed = parseSubtitles(text);
      if (parsed.isNotEmpty) {
        await player.setSubtitleTrack(SubtitleTrack.no());
        setState(() {
          cues = parsed;
          externalSubName = name;
        });
        _refreshSubText();
        _showOsd('Subtitle: $name');
        return;
      }
    }
    // ASS/SSA and anything else: let the mpv engine parse it, we still draw it.
    setState(() {
      cues = [];
      externalSubName = name;
    });
    await player.setSubtitleTrack(SubtitleTrack.data(text, title: name));
    _showOsd('Subtitle: $name');
  }

  void _setSubDelay(int ms) {
    setState(() => subDelayMs = ms);
    native?.setProperty('sub-delay', (ms / 1000).toStringAsFixed(3));
    _refreshSubText();
    _showOsd('Subtitle delay: ${ms > 0 ? '+' : ''}$ms ms');
  }

  // ---------- helpers ----------
  void _seekBy(Duration d) {
    var t = position.value + d;
    if (t < Duration.zero) t = Duration.zero;
    if (duration > Duration.zero && t > duration) t = duration;
    player.seek(t);
    _showOsd('${d.isNegative ? '⏪' : '⏩'}  ${_fmt(t)}');
  }

  void _setVolume(double v) {
    v = v.clamp(0, 150).toDouble();
    player.setVolume(v);
    setState(() => volume = v);
    _showOsd('Volume ${v.round()}%');
  }

  void _toggleMute() {
    if (volume > 0) {
      lastVolume = volume;
      _setVolume(0);
    } else {
      _setVolume(lastVolume == 0 ? 100 : lastVolume);
    }
  }

  void _showOsd(String text) {
    osdTimer?.cancel();
    setState(() => osd = text);
    osdTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => osd = null);
    });
  }

  void _poke() {
    if (!controlsVisible) setState(() => controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && playing && !draggingSub && seekDrag == null) {
        setState(() => controlsVisible = false);
      }
    });
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
      player.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -10));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume(volume + 5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume(volume - 5);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.enter) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape) {
      if (fullscreen) {
        _toggleFullscreen();
      } else {
        Navigator.maybePop(context);
      }
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyG) {
      _setSubDelay(subDelayMs - 100);
    } else if (k == LogicalKeyboardKey.keyH) {
      _setSubDelay(subDelayMs + 100);
    } else if (k == LogicalKeyboardKey.keyS) {
      _subtitleSheet();
    } else {
      return KeyEventResult.ignored;
    }
    _poke();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    prefs?.setInt('resume:${widget.source}', position.value.inMilliseconds);
    hideTimer?.cancel();
    osdTimer?.cancel();
    stuckTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (Platform.isWindows) {
      if (fullscreen) windowManager.setFullScreen(false);
      windowManager.setTitle('Solo Thirai Player');
    }
    player.dispose();
    focusNode.dispose();
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: controlsVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _poke(),
          child: LayoutBuilder(builder: (context, box) {
            return Stack(children: [
              Positioned.fill(
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: fit,
                  fill: Colors.black,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (Platform.isWindows) {
                      player.playOrPause();
                      _poke();
                    } else {
                      setState(() => controlsVisible = !controlsVisible);
                      if (controlsVisible) _scheduleHide();
                    }
                  },
                  onDoubleTapDown: (d) => doubleTapPos = d.localPosition,
                  onDoubleTap: () {
                    if (Platform.isWindows) {
                      _toggleFullscreen();
                      return;
                    }
                    final x = doubleTapPos?.dx ?? box.maxWidth / 2;
                    if (x < box.maxWidth / 3) {
                      _seekBy(const Duration(seconds: -10));
                    } else if (x > box.maxWidth * 2 / 3) {
                      _seekBy(const Duration(seconds: 10));
                    } else {
                      player.playOrPause();
                    }
                  },
                ),
              ),
              if (buffering)
                const Center(child: CircularProgressIndicator(strokeWidth: 3)),
              Positioned.fill(child: _subtitleLayer(box)),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: AnimatedOpacity(
                    opacity: controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: _controls(box),
                  ),
                ),
              ),
              if (fatalError != null) Positioned.fill(child: _errorView()),
              if (osd != null)
                Positioned(
                  top: 70,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(osd!, style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text('Indha video play aagala',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SelectableText(
            '${widget.title}\n\n$fatalError\n\nPath: ${widget.source}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7)),
          ),
          const SizedBox(height: 20),
          Wrap(spacing: 12, children: [
            FilledButton.icon(
              onPressed: _retryFromStart,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _subtitleLayer(BoxConstraints box) {
    return ValueListenableBuilder<String>(
      valueListenable: subText,
      builder: (context, text, _) {
        if (text.isEmpty) return const SizedBox.shrink();
        final scale = (math.min(box.maxHeight, box.maxWidth * 9 / 16) / 450).clamp(0.6, 3.0);
        final fs = style.fontSize * scale;
        return Align(
          alignment: Alignment(style.x, style.y),
          child: GestureDetector(
            onPanStart: (_) {
              setState(() => draggingSub = true);
              hideTimer?.cancel();
            },
            onPanUpdate: (d) {
              final sz = subKey.currentContext?.size ?? Size.zero;
              final hx = math.max(1.0, (box.maxWidth - sz.width) / 2);
              final hy = math.max(1.0, (box.maxHeight - sz.height) / 2);
              setState(() {
                style.x = (style.x + d.delta.dx / hx).clamp(-1.0, 1.0);
                style.y = (style.y + d.delta.dy / hy).clamp(-1.0, 1.0);
                // snap to centre lines
                if (style.x.abs() < 0.03) style.x = 0;
                if (style.y.abs() < 0.03) style.y = 0;
              });
            },
            onPanEnd: (_) {
              setState(() => draggingSub = false);
              style.save();
              _scheduleHide();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.03, vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.9),
                child: _subtitleBox(text, fs),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _subtitleBox(String text, double fs) {
    final base = TextStyle(fontSize: fs, height: 1.25, fontWeight: FontWeight.w600);
    return Container(
      key: subKey,
      padding: EdgeInsets.symmetric(horizontal: fs * 0.4, vertical: fs * 0.15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(style.bgOpacity),
        borderRadius: BorderRadius.circular(6),
        border: draggingSub ? Border.all(color: Colors.white54, width: 1.5) : null,
      ),
      child: Stack(children: [
        if (style.outline)
          Text(
            text,
            textAlign: TextAlign.center,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(2.0, fs / 7)
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.black,
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            color: Color(style.color),
            shadows: style.outline ? null : const [Shadow(blurRadius: 6, color: Colors.black)],
          ),
        ),
      ]),
    );
  }

  Widget _controls(BoxConstraints box) {
    final compact = box.maxWidth < 560;
    return Column(children: [
      // top bar
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        child: SafeArea(
          bottom: false,
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
            Expanded(
              child: Text(widget.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            ),
            IconButton(tooltip: 'Subtitles (S)', icon: const Icon(Icons.subtitles_outlined), onPressed: _subtitleSheet),
            IconButton(tooltip: 'Audio track', icon: const Icon(Icons.audiotrack_outlined), onPressed: _audioSheet),
            IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune), onPressed: _settingsSheet),
          ]),
        ),
      ),
      // centre buttons
      Expanded(
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _roundBtn(Icons.replay_10, 44, () => _seekBy(const Duration(seconds: -10))),
            SizedBox(width: compact ? 24 : 40),
            _roundBtn(playing ? Icons.pause : Icons.play_arrow, 64, () {
              player.playOrPause();
              _poke();
            }),
            SizedBox(width: compact ? 24 : 40),
            _roundBtn(Icons.forward_10, 44, () => _seekBy(const Duration(seconds: 10))),
          ]),
        ),
      ),
      // bottom bar
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ValueListenableBuilder<Duration>(
              valueListenable: position,
              builder: (context, pos, _) {
                final maxMs = math.max(1, duration.inMilliseconds).toDouble();
                final value = (seekDrag ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
                return Row(children: [
                  Text(_fmt(Duration(milliseconds: value.round())), style: const TextStyle(fontSize: 13)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: value,
                        max: maxMs,
                        onChangeStart: (v) => setState(() => seekDrag = v),
                        onChanged: (v) => setState(() => seekDrag = v),
                        onChangeEnd: (v) {
                          player.seek(Duration(milliseconds: v.round()));
                          setState(() => seekDrag = null);
                          _scheduleHide();
                        },
                      ),
                    ),
                  ),
                  Text(_fmt(duration), style: const TextStyle(fontSize: 13)),
                ]);
              },
            ),
            Row(children: [
              IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => player.playOrPause(),
              ),
              IconButton(
                icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
                onPressed: _toggleMute,
              ),
              if (!compact)
                SizedBox(
                  width: 130,
                  child: Slider(
                    value: volume.clamp(0, 150).toDouble(),
                    max: 150,
                    onChanged: (v) => _setVolume(v),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: _settingsSheet,
                child: Text('${rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate}x'),
              ),
              IconButton(
                tooltip: 'Aspect',
                icon: const Icon(Icons.aspect_ratio),
                onPressed: _cycleFit,
              ),
              IconButton(
                tooltip: 'Fullscreen (F)',
                icon: Icon(Platform.isAndroid
                    ? Icons.screen_rotation
                    : (fullscreen ? Icons.fullscreen_exit : Icons.fullscreen)),
                onPressed: _toggleFullscreen,
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _roundBtn(IconData icon, double size, VoidCallback onTap) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, size: size)),
      ),
    );
  }

  void _cycleFit() {
    const order = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
    const names = ['Fit', 'Zoom / Crop', 'Stretch'];
    final i = (order.indexOf(fit) + 1) % order.length;
    setState(() => fit = order[i]);
    _showOsd('Aspect: ${names[i]}');
  }

  // ---------- sheets ----------
  Future<void> _sheet(Widget Function(BuildContext, StateSetter) builder) async {
    hideTimer?.cancel();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black12,
      backgroundColor: const Color(0xEE17171A),
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: builder(c, (fn) {
              setSheet(fn);
              setState(() {});
            }),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    _scheduleHide();
  }

  String _trackLabel(String id, String? title, String? lang) {
    if (id == 'auto') return 'Auto';
    if (id == 'no') return 'Off';
    final parts = [title, lang].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  void _audioSheet() {
    _sheet((c, set) {
      final tracks = player.state.tracks.audio;
      final current = player.state.track.audio;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SheetTitle('Audio track'),
        ...tracks.map((t) => ListTile(
              dense: true,
              leading: Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(_trackLabel(t.id, t.title, t.language)),
              onTap: () {
                player.setAudioTrack(t);
                Navigator.pop(c);
              },
            )),
      ]);
    });
  }

  void _settingsSheet() {
    _sheet((c, set) {
      const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SheetTitle('Playback speed'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in speeds)
            ChoiceChip(
              label: Text('${s}x'),
              selected: rate == s,
              onSelected: (_) => set(() {
                rate = s;
                player.setRate(s);
              }),
            ),
        ]),
        const SizedBox(height: 16),
        const _SheetTitle('Aspect'),
        Wrap(spacing: 8, children: [
          for (final e in {BoxFit.contain: 'Fit', BoxFit.cover: 'Zoom / Crop', BoxFit.fill: 'Stretch'}.entries)
            ChoiceChip(label: Text(e.value), selected: fit == e.key, onSelected: (_) => set(() => fit = e.key)),
        ]),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hardware decoding'),
          subtitle: const Text('ON = smooth 4K / HEVC. Video glitch aana OFF pannunga.'),
          value: hwdec,
          onChanged: (v) => set(() {
            hwdec = v;
            hwIndex = v ? 0 : hwModes.length - 1;
            native?.setProperty('hwdec', hwModes[hwIndex]);
          }),
        ),
        const SizedBox(height: 8),
        Text('Shortcuts: Space play/pause · ←/→ 10s · ↑/↓ volume · F fullscreen · M mute · '
            'S subtitles · G/H subtitle delay',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
      ]);
    });
  }

  void _subtitleSheet() {
    _sheet((c, set) {
      final embedded = player.state.tracks.subtitle;
      final current = player.state.track.subtitle;
      const colors = [0xFFFFFFFF, 0xFFFFEB3B, 0xFF80DEEA, 0xFFA5D6A7, 0xFFFFAB91];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SheetTitle('Subtitles'),
        FilledButton.icon(
          onPressed: () async {
            Navigator.pop(c);
            await _pickSubtitle();
          },
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Load subtitle file (SRT / VTT / ASS)'),
        ),
        if (externalSubName != null)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.radio_button_checked),
            title: Text(externalSubName!, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => set(() {
                cues = [];
                externalSubName = null;
                player.setSubtitleTrack(SubtitleTrack.no());
                _refreshSubText();
              }),
            ),
          ),
        if (embedded.where((t) => t.id != 'auto').length > 1) ...[
          const SizedBox(height: 8),
          Text('Embedded tracks', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ...embedded.where((t) => t.id != 'auto').map((t) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(externalSubName == null && t == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(_trackLabel(t.id, t.title, t.language)),
                onTap: () => set(() {
                  cues = [];
                  externalSubName = null;
                  player.setSubtitleTrack(t);
                }),
              )),
        ],
        const Divider(height: 28),
        const _SheetTitle('Position'),
        Text('Tip: video mela subtitle-ah finger / mouse-la drag panni enga venalum vaikkalam.',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final e in {'Top': -0.9, 'Centre': 0.0, 'Bottom': 0.88}.entries)
            ActionChip(
              label: Text(e.key),
              onPressed: () => set(() {
                style.x = 0;
                style.y = e.value;
                style.save();
              }),
            ),
        ]),
        _slider('Left ↔ Right', style.x, -1, 1, (v) => set(() => style.x = v)),
        _slider('Top ↕ Bottom', style.y, -1, 1, (v) => set(() => style.y = v)),
        const Divider(height: 28),
        const _SheetTitle('Style'),
        _slider('Size', style.fontSize, 12, 64, (v) => set(() => style.fontSize = v)),
        _slider('Background', style.bgOpacity, 0, 1, (v) => set(() => style.bgOpacity = v)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Outline'),
          value: style.outline,
          onChanged: (v) => set(() {
            style.outline = v;
            style.save();
          }),
        ),
        Wrap(spacing: 10, children: [
          for (final col in colors)
            GestureDetector(
              onTap: () => set(() {
                style.color = col;
                style.save();
              }),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: style.color == col ? Colors.white : Colors.white24,
                child: CircleAvatar(radius: 12, backgroundColor: Color(col)),
              ),
            ),
        ]),
        const Divider(height: 28),
        const _SheetTitle('Sync (delay)'),
        Row(children: [
          IconButton.filledTonal(
              icon: const Icon(Icons.remove), onPressed: () => set(() => _setSubDelay(subDelayMs - 100))),
          Expanded(
            child: Text('${subDelayMs > 0 ? '+' : ''}$subDelayMs ms',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ),
          IconButton.filledTonal(
              icon: const Icon(Icons.add), onPressed: () => set(() => _setSubDelay(subDelayMs + 100))),
          TextButton(onPressed: () => set(() => _setSubDelay(0)), child: const Text('Reset')),
        ]),
        Text('Subtitle munnadi vandha  +  ·  late-ah vandha  −',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
      ]);
    });
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: (_) => style.save(),
        ),
      ),
    ]);
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      );
}
