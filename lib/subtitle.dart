import 'dart:convert';
import 'dart:typed_data';

class SubtitleCue {
  SubtitleCue(this.start, this.end, this.text);
  final Duration start;
  final Duration end;
  final String text;
}

/// Decodes subtitle bytes: UTF-8 (with/without BOM), UTF-16 LE/BE, else Latin-1.
String decodeSubtitleBytes(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return _utf16(b.sublist(2), little: true);
  }
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    return _utf16(b.sublist(2), little: false);
  }
  try {
    var s = utf8.decode(b);
    if (s.startsWith('﻿')) s = s.substring(1);
    return s;
  } on FormatException {
    return latin1.decode(b);
  }
}

String _utf16(Uint8List b, {required bool little}) {
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add(little ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]));
  }
  return String.fromCharCodes(units);
}

final _timeLine = RegExp(
    r'((?:\d+:)?\d{1,2}:\d{1,2}[,.]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{1,2}[,.]\d{1,3})');
final _tags = RegExp(r'<[^>]*>|\{\\[^}]*\}');

Duration _parseTime(String t) {
  final parts = t.split(RegExp(r'[:,.]'));
  final msRaw = parts.removeLast();
  final ms = int.parse(msRaw.padRight(3, '0').substring(0, 3));
  final sec = int.parse(parts.removeLast());
  final min = int.parse(parts.removeLast());
  final hour = parts.isNotEmpty ? int.parse(parts.removeLast()) : 0;
  return Duration(hours: hour, minutes: min, seconds: sec, milliseconds: ms);
}

/// Parses SRT and WebVTT text into cues.
List<SubtitleCue> parseSubtitles(String raw) {
  final s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cues = <SubtitleCue>[];
  for (final block in s.split(RegExp(r'\n[ \t]*\n'))) {
    final lines = block.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = _timeLine.firstMatch(lines[i]);
      if (m == null) continue;
      try {
        final text = lines
            .sublist(i + 1)
            .join('\n')
            .replaceAll(_tags, '')
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .trim();
        if (text.isNotEmpty) {
          cues.add(SubtitleCue(_parseTime(m.group(1)!), _parseTime(m.group(2)!), text));
        }
      } catch (_) {}
      break;
    }
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// Text of all cues active at [t] (overlapping cues are stacked).
String cueTextAt(List<SubtitleCue> cues, Duration t) {
  if (cues.isEmpty) return '';
  // binary search: last cue whose start <= t
  var lo = 0, hi = cues.length - 1, idx = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].start <= t) {
      idx = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (idx < 0) return '';
  final out = <String>[];
  for (var i = idx; i >= 0 && i > idx - 8; i--) {
    final c = cues[i];
    if (c.start <= t && t < c.end) out.insert(0, c.text);
  }
  return out.join('\n');
}
