import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'chat_look.dart';

/// Draws the wallpaper patterns without any image file. The photo wallpaper is
/// not drawn here (see [ChatWallpaper]).
class ChatWallPainter extends CustomPainter {
  const ChatWallPainter({
    required this.wall,
    required this.bg,
    required this.ink,
    required this.alt,
    required this.dark,
  });

  final ChatWall wall;
  final Color bg;
  final Color ink;
  final Color alt;
  final bool dark;

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    switch (wall) {
      case ChatWall.polos:
      case ChatWall.foto:
        canvas.drawRect(rect, Paint()..color = bg);
      case ChatWall.titik:
        canvas.drawRect(rect, Paint()..color = bg);
        final dot = Paint()..color = ink.withValues(alpha: 0.16);
        for (var y = 0.0; y < size.height; y += 18) {
          for (var x = 0.0; x < size.width; x += 18) {
            canvas.drawCircle(Offset(x + 9, y + 9), 1.1, dot);
          }
        }
      case ChatWall.kertas:
        final warm = dark ? const Color(0xFF3A3220) : const Color(0xFFFFF1C9);
        canvas.drawRect(rect, Paint()..color = _mix(bg, warm, 0.55));
        final line = Paint()
          ..color = const Color(0xFF2F6FEB).withValues(alpha: 0.16)
          ..strokeWidth = 1;
        for (var y = 27.5; y < size.height; y += 28) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case ChatWall.doodle:
        canvas.drawRect(rect, Paint()..color = _mix(bg, alt, 0.7));
        _tile(canvas, size, 120, _doodleTile);
      case ChatWall.rel:
        canvas.drawRect(rect, Paint()..color = _mix(bg, alt, 0.6));
        _tile(canvas, size, 60, _railTile);
      case ChatWall.laut:
        _gradient(
          canvas,
          rect,
          [
            _mix(bg, const Color(0xFF7FB8FF), 0.45),
            _mix(bg, const Color(0xFFB6F0E4), 0.40),
          ],
          const [0, 1],
        );
      case ChatWall.senja:
        _gradient(
          canvas,
          rect,
          [
            _mix(bg, const Color(0xFFFFC38A), 0.50),
            _mix(bg, const Color(0xFFF27A9B), 0.42),
            _mix(bg, const Color(0xFF7A5BB0), 0.40),
          ],
          const [0, 0.6, 1],
          begin: const Alignment(0.26, -1),
          end: const Alignment(-0.26, 1),
        );
      case ChatWall.malam:
        _gradient(
          canvas,
          rect,
          const [Color(0xFF0B1530), Color(0xFF1B1440)],
          const [0, 1],
        );
        _tile(canvas, size, 200, _starTile, h: 180);
    }
    canvas.restore();
  }

  void _gradient(
    Canvas canvas,
    Rect rect,
    List<Color> colors,
    List<double> stops, {
    Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter,
  }) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
          stops: stops,
        ).createShader(rect),
    );
  }

  void _tile(
    Canvas canvas,
    Size size,
    double w,
    void Function(Canvas) draw, {
    double? h,
  }) {
    final th = h ?? w;
    for (var y = 0.0; y < size.height; y += th) {
      for (var x = 0.0; x < size.width; x += w) {
        canvas.save();
        canvas.translate(x, y);
        draw(canvas);
        canvas.restore();
      }
    }
  }

  static const _line = Color(0xFF8A8F98);

  void _doodleTile(Canvas c) {
    final p = Paint()
      ..color = _line.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // desk
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 14, 26, 16),
        const Radius.circular(4),
      ),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(16, 30)
        ..relativeLineTo(0, 4)
        ..moveTo(34, 30)
        ..relativeLineTo(0, 4)
        ..moveTo(12, 22)
        ..relativeLineTo(26, 0),
      p,
    );
    // star
    c.drawPath(
      Path()
        ..moveTo(80, 18)
        ..relativeLineTo(3, 6)
        ..relativeLineTo(6, 1)
        ..relativeLineTo(-4.5, 4)
        ..relativeLineTo(1, 6)
        ..relativeLineTo(-5.5, -3)
        ..relativeLineTo(-5.5, 3)
        ..relativeLineTo(1, -6)
        ..relativeLineTo(-4.5, -4)
        ..relativeLineTo(6, -1)
        ..close(),
      p,
    );
    // cup
    const r6 = Radius.circular(6);
    c.drawPath(
      Path()
        ..moveTo(20, 78)
        ..relativeLineTo(18, 0)
        ..relativeLineTo(0, 14)
        ..relativeArcToPoint(const Offset(-6, 6), radius: r6)
        ..relativeLineTo(-6, 0)
        ..relativeArcToPoint(const Offset(-6, -6), radius: r6)
        ..close()
        ..moveTo(38, 82)
        ..relativeLineTo(4, 0)
        ..relativeArcToPoint(
          const Offset(0, 6),
          radius: const Radius.circular(3),
        )
        ..relativeLineTo(-4, 0),
      p,
    );
    // monitor
    c.drawPath(
      Path()
        ..moveTo(76, 74)
        ..relativeLineTo(22, 0)
        ..relativeLineTo(0, 16)
        ..relativeLineTo(-22, 0)
        ..close()
        ..moveTo(76, 80)
        ..relativeLineTo(22, 0)
        ..moveTo(84, 90)
        ..relativeLineTo(0, 6)
        ..moveTo(80, 96)
        ..relativeLineTo(14, 0),
      p,
    );
    c.drawCircle(const Offset(60, 56), 3, p);
    c.drawPath(
      Path()
        ..moveTo(98, 52)
        ..relativeQuadraticBezierTo(6, 6, 0, 12),
      p,
    );
  }

  void _railTile(Canvas c) {
    final sleeper = Paint()
      ..color = _line.withValues(alpha: 0.16)
      ..strokeWidth = 5;
    for (final x in const [8.0, 26.0, 44.0]) {
      c.drawLine(Offset(x, 16), Offset(x, 44), sleeper);
    }
    final rail = Paint()
      ..color = _line.withValues(alpha: 0.26)
      ..strokeWidth = 2.5;
    c.drawLine(const Offset(0, 22), const Offset(60, 22), rail);
    c.drawLine(const Offset(0, 38), const Offset(60, 38), rail);
  }

  void _starTile(Canvas c) {
    void star(double x, double y, double r, Color col) =>
        c.drawCircle(Offset(x, y), r, Paint()..color = col);
    star(20, 30, 1.5, Colors.white);
    star(90, 80, 1, Colors.white);
    star(150, 20, 1.5, const Color(0xFFFDE68A));
    star(60, 140, 1, Colors.white);
    star(170, 120, 1, const Color(0xFFC7D2FE));
  }

  @override
  bool shouldRepaint(ChatWallPainter old) =>
      old.wall != wall ||
      old.bg != bg ||
      old.ink != ink ||
      old.alt != alt ||
      old.dark != dark;
}

/// A small swatch of a wallpaper, for the settings sheet.
class ChatWallSwatch extends StatelessWidget {
  const ChatWallSwatch({
    super.key,
    required this.wall,
    this.photo,
    this.width = 56,
    this.height = 40,
  });

  final ChatWall wall;
  final String? photo;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: GhinaRadii.rSm,
      child: SizedBox(
        width: width,
        height: height,
        child: ChatWallpaper(wall: wall, photo: photo, child: const SizedBox()),
      ),
    );
  }
}

/// The wallpaper behind the whole chat (list and bottom bar).
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({
    super.key,
    required this.wall,
    required this.child,
    this.photo,
  });

  final ChatWall wall;
  final String? photo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (wall == ChatWall.polos) return child;
    final g = context.ghina;
    final dark = g.brightness == Brightness.dark;
    final file = wall == ChatWall.foto && photo != null ? File(photo!) : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: ChatWallPainter(
              wall: wall,
              bg: wall == ChatWall.foto ? g.surfaceAlt : g.background,
              ink: g.textPrimary,
              alt: g.surfaceAlt,
              dark: dark,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (file != null)
          Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (wall == ChatWall.foto)
          ColoredBox(color: g.background.withValues(alpha: 0.30)),
        child,
      ],
    );
  }
}

/// Paints one pixel sprite, scaled to fit [size] and bottom-aligned.
class SpritePainter extends CustomPainter {
  const SpritePainter(this.sprite);
  final PixelSprite sprite;

  @override
  void paint(Canvas canvas, Size size) {
    final k = (size.width / sprite.width) < (size.height / sprite.height)
        ? size.width / sprite.width
        : size.height / sprite.height;
    final dx = (size.width - sprite.width * k) / 2;
    final dy = size.height - sprite.height * k;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < sprite.height; y++) {
      final row = sprite.rows[y];
      for (var x = 0; x < row.length; x++) {
        final col = sprite.palette[row[x]];
        if (col == null) continue;
        paint.color = col;
        canvas.drawRect(
          Rect.fromLTWH(dx + x * k, dy + y * k, k + 0.4, k + 0.4),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SpritePainter old) => old.sprite != sprite;
}

/// The mascot, drawn at the size the web uses above a message (27 x 21).
class ChatPeekSprite extends StatelessWidget {
  const ChatPeekSprite(
    this.peek, {
    super.key,
    this.width = 27,
    this.height = 21,
  });

  final ChatPeek peek;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = peek.sprite;
    if (s == null) return SizedBox(width: width, height: height);
    return CustomPaint(size: Size(width, height), painter: SpritePainter(s));
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter({required this.mine, this.color});
  final bool mine;
  final Color? color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (mine) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color ?? Colors.grey);
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.mine != mine || old.color != color;
}

/// A message bubble in the chosen shape and color. [mine] bubbles use the
/// owner's color; the others use the surface color. With a peek mascot set,
/// the owner's bubble gets the pixel mascot sitting on its top edge (the
/// caller leaves 16 px above it).
class ThemedBubble extends StatelessWidget {
  const ThemedBubble({
    super.key,
    required this.shape,
    required this.mine,
    required this.me,
    required this.padding,
    required this.child,
    this.peek = ChatPeek.none,
  });

  final ChatBubbleShape shape;
  final bool mine;
  final ChatMeColor me;
  final ChatPeek peek;
  final EdgeInsetsGeometry padding;
  final Widget child;

  static const _lg = Radius.circular(GhinaRadii.lg);
  static const _tail = Radius.circular(4);

  BorderRadius get _radius => switch (shape) {
    ChatBubbleShape.kantor => BorderRadius.only(
      topLeft: _lg,
      topRight: _lg,
      bottomLeft: mine ? _lg : _tail,
      bottomRight: mine ? _tail : _lg,
    ),
    ChatBubbleShape.bulat => BorderRadius.circular(22),
    ChatBubbleShape.ekor => BorderRadius.only(
      topLeft: Radius.circular(mine ? 10 : 0),
      topRight: Radius.circular(mine ? 0 : 10),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    ),
    ChatBubbleShape.kotak => BorderRadius.circular(4),
    ChatBubbleShape.pixel => BorderRadius.zero,
    ChatBubbleShape.awan => BorderRadius.circular(18),
  };

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final ai = g.surface;
    final fill = mine ? me.fill : ai;
    final grad = mine ? me.gradient : null;

    Border? border;
    List<BoxShadow>? shadows;
    switch (shape) {
      case ChatBubbleShape.kantor:
      case ChatBubbleShape.bulat:
      case ChatBubbleShape.kotak:
        border = mine ? null : Border.all(color: g.border, width: 2);
      case ChatBubbleShape.ekor:
        shadows = mine
            ? null
            : const [
                BoxShadow(
                  color: Color(0x29000000),
                  offset: Offset(0, 1),
                  blurRadius: 1.5,
                ),
              ];
      case ChatBubbleShape.pixel:
        final ring = mine ? g.textPrimary.withValues(alpha: 0.35) : g.border;
        shadows = [
          BoxShadow(color: ring, spreadRadius: 3),
          if (!mine)
            const BoxShadow(color: Color(0x1F000000), offset: Offset(0, 6)),
        ];
      case ChatBubbleShape.awan:
        shadows = const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 4),
            blurRadius: 14,
          ),
        ];
    }

    final stripe = shape == ChatBubbleShape.kotak && !mine;
    final body = stripe
        ? Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: g.accent.base),
              ),
              Padding(padding: const EdgeInsets.only(left: 4), child: child),
            ],
          )
        : child;

    Widget bubble = Container(
      padding: padding,
      clipBehavior: stripe ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: fill,
        gradient: grad,
        borderRadius: _radius,
        border: border,
        boxShadow: shadows,
      ),
      child: body,
    );

    final tail = shape == ChatBubbleShape.ekor;
    final peeking = mine && peek != ChatPeek.none;
    if (tail || peeking) {
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          if (tail)
            Positioned(
              top: 0,
              right: mine ? -9 : null,
              left: mine ? null : -9,
              width: 10,
              height: 12,
              child: CustomPaint(
                painter: _TailPainter(
                  mine: mine,
                  color: mine ? (me.fill ?? me.from) : ai,
                ),
              ),
            ),
          if (peeking)
            Positioned(
              right: 12,
              top: -19,
              width: 27,
              height: 21,
              child: IgnorePointer(child: ChatPeekSprite(peek)),
            ),
        ],
      );
    }
    // the pixel border reaches 3 px outside the box
    return shape == ChatBubbleShape.pixel
        ? Padding(padding: const EdgeInsets.all(3), child: bubble)
        : bubble;
  }
}
