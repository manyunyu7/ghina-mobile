import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import '../../notes/markdown_edit.dart' show insertAtCursor;
import 'chat_dictation_sheet.dart';

/// Speech into the chat field ("Dikte", `id-ID`) through a pop-up
/// ([showChatDictationSheet]): the live transcript shows there (permission
/// steps too); Selesai puts ALL of it into the field at the cursor, Kirim
/// also sends, Batal drops it. The field is only ever added to, never
/// replaced. Driven by the shared `dictationControllerProvider`.
class ChatDictation {
  ChatDictation({
    required this.ref,
    required this.context,
    required this.text,
    this.onSend,
  });

  final WidgetRef ref;
  final BuildContext Function() context;
  final TextEditingController text;

  /// Kirim in the pop-up: sends what's in the field (words just inserted).
  final Future<void> Function()? onSend;

  bool _open = false;
  bool _disposed = false;
  void Function()? _cancelOwned;

  void dispose() {
    _disposed = true;
    _cancelOwned?.call();
    _cancelOwned = null;
  }

  bool get active => _open || ref.read(dictationControllerProvider).isActive;

  void _log(String event, String detail) {
    try {
      ref.read(dictationLogProvider).record(event, detail);
    } catch (_) {}
  }

  static int _words(String s) {
    final t = s.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  /// Adds [words] at the cursor (end when the field has no cursor).
  void _insert(String words, String how) {
    if (_disposed || words.trim().isEmpty) return;
    final v = text.value;
    final at = v.selection.isValid
        ? v
        : v.copyWith(selection: TextSelection.collapsed(offset: v.text.length));
    text.value = insertAtCursor(at, words);
    _log(
      'kotak ketik',
      '$how · ${_words(words)} kata masuk · kotak ${_words(text.text)} kata',
    );
  }

  Future<void> toggle() => open();

  /// Opens the dictation pop-up and handles how it was closed.
  Future<void> open() async {
    if (_disposed || _open) return;
    final ctx = context();
    if (!ctx.mounted) return;
    final c = ref.read(dictationControllerProvider.notifier);
    if (!ref.read(dictationControllerProvider).isActive) c.clear();
    _open = true;
    _cancelOwned = () {
      c.cancel();
    };
    DictationSheetResult? r;
    try {
      r = await showChatDictationSheet(ctx);
    } finally {
      _open = false;
    }
    if (_disposed) return;
    if (r == null) {
      // Swiped away: stop listening, and only drop the words when the owner
      // says so.
      final s = ref.read(dictationControllerProvider);
      final words = s.isActive ? await c.stop() : s.text;
      c.clear();
      _cancelOwned = null;
      final ctx2 = context();
      if (_disposed || words.trim().isEmpty || !ctx2.mounted) return;
      final drop = await showChunkyConfirm(
        ctx2,
        title: 'Buang teks dikte?',
        message: '${_words(words)} kata belum masuk ke kotak ketik.',
        confirmLabel: 'Buang',
        cancelLabel: 'Masukkan ke kotak ketik',
        destructive: true,
      );
      if (drop) {
        _log('kotak ketik', 'buang · ${_words(words)} kata');
      } else {
        _insert(words, 'tutup');
      }
      return;
    }
    _cancelOwned = null;
    switch (r.action) {
      case DictationSheetAction.cancel:
        _log('kotak ketik', 'batal');
      case DictationSheetAction.done:
        _insert(r.text, 'selesai');
      case DictationSheetAction.send:
        _insert(r.text, 'kirim');
        await onSend?.call();
    }
  }

  /// Ends a dictation that is still running (sending mid-dictation): the
  /// words still land in the field.
  Future<void> stop() async {
    final c = ref.read(dictationControllerProvider.notifier);
    if (!ref.read(dictationControllerProvider).isActive) return;
    final words = await c.stop();
    c.clear();
    _insert(words, 'stop');
  }

  Future<void> cancel() async {
    final c = ref.read(dictationControllerProvider.notifier);
    await c.cancel();
    c.clear();
  }
}
