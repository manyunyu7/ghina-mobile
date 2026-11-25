import 'package:flutter/widgets.dart';

/// Hasil satu pembaruan IME: hapus [backspaces] grafem dari belakang, lalu
/// ketik [insert]. [resetTo] ≠ null berarti buffer TextField tersembunyi
/// perlu dikembalikan ke nilai itu (setelah event saat ini selesai).
@immutable
class ImeEdit {
  const ImeEdit({this.backspaces = 0, this.insert = '', this.resetTo});
  final int backspaces;
  final String insert;
  final TextEditingValue? resetTo;

  bool get isEmpty => backspaces == 0 && insert.isEmpty;

  @override
  String toString() =>
      'ImeEdit(-$backspaces, +"$insert"'
      '${resetTo != null ? ', reset' : ''})';
}

/// Melacak isi TextField tersembunyi dan menurunkan perubahan yang SUDAH
/// dikomit oleh IME (Gboard, dikte suara, IME CJK) supaya dikirim ke Mac
/// tepat sekali.
///
/// Aturan:
///  * Teks di wilayah `composing` belum dikirim, KECUALI bagian awalnya yang
///    sudah pernah terkirim (Gboard sering "membuka ulang" kata yang sudah
///    diketik sebagai composing saat backspace — itu tidak boleh menghapus
///    lalu mengetik ulang kata tersebut).
///  * Perbedaan dihitung per grafem (emoji = 1 backspace).
///  * Buffer diawali [sentinel] supaya backspace di field "kosong" tetap
///    menghasilkan perubahan yang bisa dideteksi.
class ImeTextTracker {
  ImeTextTracker({this.maxBuffer = 64});

  /// Dua zero-width space: tak terlihat, tidak memicu kapitalisasi otomatis.
  static const String sentinel = '​​';

  static const TextEditingValue initialValue = TextEditingValue(
    text: sentinel,
    selection: TextSelection.collapsed(offset: sentinel.length),
  );

  final int maxBuffer;

  /// Teks yang dianggap sudah ada di Mac (termasuk sentinel).
  String _sent = sentinel;
  String get sent => _sent;

  void resetBaseline() => _sent = sentinel;

  ImeEdit update(TextEditingValue value) {
    final text = value.text;
    final composing = value.composing;
    String target;
    final hasComposing =
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;
    if (hasComposing) {
      final before = text.substring(0, composing.start);
      final comp = text.substring(composing.start, composing.end);
      final after = text.substring(composing.end);
      final sentTail = composing.start <= _sent.length
          ? _sent.substring(composing.start)
          : '';
      // Composing lebih pendek dari yang sudah terkirim (backspace di dalam
      // kata yang dibuka ulang) → hapus kelebihannya sekarang. Selain itu
      // tahan apa yang sudah terkirim; perbedaan diselesaikan saat komit.
      final keep = _isGraphemePrefix(comp, sentTail) ? comp : sentTail;
      target = before + keep + after;
    } else {
      target = text;
    }

    final edit = _diff(_sent, target);
    _sent = target;

    TextEditingValue? reset;
    if (!hasComposing &&
        (!text.startsWith(sentinel) ||
            text.characters.length > maxBuffer ||
            text.endsWith('\n'))) {
      reset = initialValue;
      _sent = sentinel;
    }
    return ImeEdit(
      backspaces: edit.backspaces,
      insert: edit.insert,
      resetTo: reset,
    );
  }

  /// [a] adalah awalan [b] (per grafem).
  static bool _isGraphemePrefix(String a, String b) {
    if (!b.startsWith(a)) return false;
    return a.characters.length <= b.characters.length &&
        b.characters.take(a.characters.length).join() == a;
  }

  static ImeEdit _diff(String from, String to) {
    if (from == to) return const ImeEdit();
    final a = from.characters.toList();
    final b = to.characters.toList();
    final n = a.length < b.length ? a.length : b.length;
    var p = 0;
    while (p < n && a[p] == b[p]) {
      p++;
    }
    return ImeEdit(backspaces: a.length - p, insert: b.skip(p).join());
  }
}
