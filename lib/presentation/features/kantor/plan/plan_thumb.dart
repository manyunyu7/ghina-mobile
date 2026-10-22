import 'package:flutter/material.dart';

/// A small flat picture of an office plan: the template gallery thumbnails
/// (the daemon's SVG, which is only `<rect>`s) and the preview of a plan
/// before it exists. No SVG package needed.
class KantorPlanThumb extends StatelessWidget {
  const KantorPlanThumb({super.key, required this.rects, required this.size});

  /// Parses the `thumb` string of `GET /api/templates`; empty when absent.
  factory KantorPlanThumb.svg(String? svg) {
    final rects = <PlanRect>[];
    var w = 0.0, h = 0.0;
    if (svg != null) {
      final vb = RegExp(r'viewBox="0 0 ([\d.]+) ([\d.]+)"').firstMatch(svg);
      w = double.tryParse(vb?.group(1) ?? '') ?? 0;
      h = double.tryParse(vb?.group(2) ?? '') ?? 0;
      for (final m in RegExp(r'<rect ([^>]*?)/>').allMatches(svg)) {
        final a = {
          for (final x in RegExp(r'([\w-]+)="([^"]*)"').allMatches(m.group(1)!))
            x.group(1)!: x.group(2)!,
        };
        double n(String k) => double.tryParse(a[k] ?? '') ?? 0;
        final c = _hex(a['fill']);
        if (c == null) continue;
        rects.add(
          PlanRect(
            n('x'),
            n('y'),
            a.containsKey('width') ? n('width') : w,
            a.containsKey('height') ? n('height') : h,
            c.withValues(alpha: double.tryParse(a['opacity'] ?? '') ?? 1),
          ),
        );
      }
    }
    return KantorPlanThumb(rects: rects, size: Size(w, h));
  }

  /// Rooms of a plan from `template/preview` or `wizard/preview`
  /// (`{w, h, rooms: [{x, y, w, h, floor, kind}]}`), drawn like the daemon's
  /// own thumbnail: corridor, wall, floor.
  factory KantorPlanThumb.plan(Map<String, dynamic> plan) {
    final rects = <PlanRect>[];
    for (final raw in plan['rooms'] as List? ?? const []) {
      final r = raw as Map;
      if (r['kind'] == 'zone') continue;
      final x = (r['x'] as num).toDouble(), y = (r['y'] as num).toDouble();
      final w = (r['w'] as num).toDouble(), h = (r['h'] as num).toDouble();
      rects.add(PlanRect(x, y, w, h, const Color(0xFF2A2430)));
      rects.add(PlanRect(x + 1, y + 1, w - 2, h - 2, _floor['${r['floor']}']));
    }
    return KantorPlanThumb(
      rects: rects,
      size: Size(
        (plan['w'] as num?)?.toDouble() ?? 0,
        (plan['h'] as num?)?.toDouble() ?? 0,
      ),
    );
  }

  final List<PlanRect> rects;
  final Size size;

  @override
  Widget build(BuildContext context) {
    if (size.isEmpty) return const SizedBox.shrink();
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: CustomPaint(painter: _PlanPainter(rects, size)),
    );
  }
}

class PlanRect {
  const PlanRect(this.x, this.y, this.w, this.h, this.color);
  final double x, y, w, h;
  final Color color;
}

Color? _hex(String? s) {
  if (s == null || !s.startsWith('#') || s.length < 7) return null;
  final v = int.tryParse(s.substring(1, 7), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

const _fallbackFloor = Color(0xFF98AF9F);
const _floorHex = {
  'wood': 0xFF98AF9F,
  'teal': 0xFF98AF9F,
  'carpet': 0xFF98AF9F,
  'teal2': 0xFF9AAFB0,
  'carpetGreen': 0xFFA3B596,
  'wood2': 0xFFB98F62,
  'marble': 0xFFE3DFD6,
  'tile': 0xFFE6E8EA,
  'metal': 0xFF5A616E,
  'plum': 0xFF9B8CAE,
  'frozen': 0xFFBFC1C6,
  'musholla': 0xFF5C9672,
  'grass': 0xFF6BAE57,
  'gymMat': 0xFF47546A,
  'lounge': 0xFFB89C8C,
};
final _floor = _FloorMap();

class _FloorMap {
  Color operator [](String k) =>
      _floorHex[k] == null ? _fallbackFloor : Color(_floorHex[k]!);
}

class _PlanPainter extends CustomPainter {
  _PlanPainter(this.rects, this.src);
  final List<PlanRect> rects;
  final Size src;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / src.width;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF9DB3A6),
    );
    for (final r in rects) {
      canvas.drawRect(
        Rect.fromLTWH(r.x * k, r.y * k, r.w * k, r.h * k),
        Paint()..color = r.color,
      );
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.rects != rects || old.src != src;
}
