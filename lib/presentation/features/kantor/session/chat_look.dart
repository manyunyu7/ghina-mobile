import 'package:flutter/material.dart';

/// Chat look in the style of WA / TikTok, ported from the web Kantor
/// (`web/js/view-prefs.js`): wallpaper, bubble shape, color of your own
/// messages and a pixel mascot above them.

/// Chat wallpaper. [photo] is the owner's own picture from the gallery.
enum ChatWall {
  polos('Polos'),
  titik('Titik'),
  kertas('Kertas'),
  doodle('Doodle kantor'),
  rel('Rel kereta'),
  laut('Laut'),
  senja('Senja'),
  malam('Malam'),
  foto('Fotomu');

  const ChatWall(this.label);
  final String label;
}

enum ChatBubbleShape {
  kantor('Kantor'),
  bulat('Bulat'),
  ekor('Berekor'),
  kotak('Kotak'),
  pixel('Pixel'),
  awan('Awan');

  const ChatBubbleShape(this.label);
  final String label;

  /// Corner radius of the message field and buttons that follow the bubble.
  double get fieldRadius => switch (this) {
    ChatBubbleShape.kantor => 12,
    ChatBubbleShape.bulat => 22,
    ChatBubbleShape.ekor => 10,
    ChatBubbleShape.kotak => 4,
    ChatBubbleShape.pixel => 0,
    ChatBubbleShape.awan => 18,
  };
}

/// Color of the owner's own messages (and of Kirim and the focused field).
enum ChatMeColor {
  hijau('Hijau', Color(0xFF58CC02), Color(0xFF0B2A00)),
  biru('Biru', Color(0xFF2F6FEB), Color(0xFFFFFFFF)),
  ungu('Ungu', Color(0xFF7C4DFF), Color(0xFFFFFFFF)),
  oranye('Oranye', Color(0xFFF28C28), Color(0xFF1D1200)),
  pink('Pink', Color(0xFFE84393), Color(0xFFFFFFFF)),
  gelap('Gelap', Color(0xFF2B2F36), Color(0xFFFFFFFF)),
  gradasi(
    'Gradasi',
    Color(0xFFA347E0),
    Color(0xFFFFFFFF),
    from: Color(0xFF7C4DFF),
    to: Color(0xFFE84393),
  );

  const ChatMeColor(this.label, this.solid, this.ink, {this.from, this.to});
  final String label;

  /// One color for things that cannot be a gradient (field border, button edge).
  final Color solid;

  /// Text color on top of the bubble.
  final Color ink;
  final Color? from;
  final Color? to;

  bool get isGradient => from != null && to != null;

  /// Gradient 135deg like the web (top-left to bottom-right).
  Gradient? get gradient => isGradient
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [from!, to!],
        )
      : null;

  /// Solid fill of the bubble (null for the gradient).
  Color? get fill => isGradient ? null : solid;
}

/// Pixel mascot above the owner's message.
enum ChatPeek {
  none('Tanpa'),
  kucing('Kucing'),
  kodok('Kodok'),
  kereta('Kereta'),
  hantu('Hantu');

  const ChatPeek(this.label);
  final String label;

  PixelSprite? get sprite => _sprites[this];
}

/// A hand-made pixel picture: one letter per pixel, '.' is empty.
@immutable
class PixelSprite {
  const PixelSprite(this.rows, this.palette);
  final List<String> rows;
  final Map<String, Color> palette;

  int get width => rows.first.length;
  int get height => rows.length;
}

const _sprites = <ChatPeek, PixelSprite>{
  ChatPeek.kucing: PixelSprite(
    [
      '.k.....k.',
      'kok...kok',
      'koooooook',
      'koeoooeok',
      'kooopoook',
      '.kkkkkkk.',
    ],
    {
      'k': Color(0xFF3B2414),
      'o': Color(0xFFF4A259),
      'e': Color(0xFF1B1B1B),
      'p': Color(0xFFFF8FA3),
    },
  ),
  ChatPeek.kodok: PixelSprite(
    [
      '.ww...ww.',
      'wew...wew',
      'ggggggggg',
      'ggggggggg',
      'grrrrrrrg',
      '.ggggggg.',
    ],
    {
      'w': Color(0xFFFFFFFF),
      'e': Color(0xFF111111),
      'g': Color(0xFF5CC85A),
      'r': Color(0xFF2F7D32),
    },
  ),
  ChatPeek.kereta: PixelSprite(
    [
      '..rrrrr..',
      '.rbbbbbr.',
      '.rbbbbbr.',
      '.rrrrrrr.',
      '.ryrrryr.',
      '.rrrrrrr.',
      '..k...k..',
    ],
    {
      'r': Color(0xFFD94F3D),
      'b': Color(0xFF9AD1FF),
      'y': Color(0xFFFFD84D),
      'k': Color(0xFF333333),
    },
  ),
  ChatPeek.hantu: PixelSprite(
    [
      '...ooooo...',
      '..owwwwwo..',
      '.owwewewwo.',
      '.owwwwwwwo.',
      '.owwwwwwwo.',
      '.owowowowo.',
      '..o.o.o.o..',
    ],
    {'w': Color(0xFFEEF2FF), 'e': Color(0xFF3B3B58), 'o': Color(0xFF7C83A8)},
  ),
};
