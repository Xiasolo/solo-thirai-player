import 'package:shared_preferences/shared_preferences.dart';

/// Subtitle look & position. x/y are alignment values: -1 = left/top, 0 = centre, 1 = right/bottom.
class SubStyle {
  double x = 0;
  double y = 0.88;
  double fontSize = 24;
  int color = 0xFFFFFFFF;
  double bgOpacity = 0;
  bool outline = true;

  static Future<SubStyle> load() async {
    final p = await SharedPreferences.getInstance();
    return SubStyle()
      ..x = p.getDouble('sub.x') ?? 0
      ..y = p.getDouble('sub.y') ?? 0.88
      ..fontSize = p.getDouble('sub.size') ?? 24
      ..color = p.getInt('sub.color') ?? 0xFFFFFFFF
      ..bgOpacity = p.getDouble('sub.bg') ?? 0
      ..outline = p.getBool('sub.outline') ?? true;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('sub.x', x);
    await p.setDouble('sub.y', y);
    await p.setDouble('sub.size', fontSize);
    await p.setInt('sub.color', color);
    await p.setDouble('sub.bg', bgOpacity);
    await p.setBool('sub.outline', outline);
  }
}
