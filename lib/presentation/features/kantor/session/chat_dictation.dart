import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/platform/platform_state.dart';
import '../../notes/markdown_edit.dart' show insertAtCursor;
import '../../notes/widgets/dictation_bar.dart' show showDictationUnavailable;
import '../../notes/widgets/mic_permission.dart';

/// Speech into the chat field ("Dikte", `id-ID`): words land in the field as
/// they are recognised, editable before sending. Same flow as the Killa
/// composer, driven by the shared `dictationControllerProvider`; the owner
/// widget forwards `ref.listen(dictationControllerProvider, d.onChange)`.
class ChatDictation {
  ChatDictation({required this.ref, required this.context, required this.text});

  final WidgetRef ref;
  final BuildContext Function() context;
  final TextEditingController text;

  /// Length of the transcript already put into [text].
  int _inserted = 0;
  bool _ownsDictation = false;
  bool _disposed = false;
  void Function()? _cancelOwned;

  void dispose() {
    _disposed = true;
    _ownsDictation = false;
    _cancelOwned?.call();
    _cancelOwned = null;
  }

  bool get active => ref.read(dictationControllerProvider).isActive;

  void onChange(DictationState? prev, DictationState next) {
    if (_disposed || !_ownsDictation) return;
    final committed = next.committed;
    if (committed.length > _inserted) {
      final delta = committed.substring(_inserted);
      _inserted = committed.length;
      final v = text.value;
      final at = v.selection.isValid
          ? v
          : v.copyWith(
              selection: TextSelection.collapsed(offset: v.text.length),
            );
      text.value = insertAtCursor(at, delta);
    } else if (committed.length < _inserted) {
      _inserted = committed.length;
    }
    if (prev?.phase != DictationPhase.error &&
        next.phase == DictationPhase.error &&
        next.error?.kind != SpeechErrorKind.permission) {
      showErrorToast(context(), _error(next.error?.kind));
    }
  }

  String _error(SpeechErrorKind? k) => switch (k) {
    SpeechErrorKind.network =>
      'Dikte butuh paket suara offline. Ketik dulu pesannya, ya',
    SpeechErrorKind.languageUnavailable =>
      'Bahasa Indonesia belum tersedia untuk dikte di HP ini',
    SpeechErrorKind.busy =>
      'Mikrofon lagi dipakai aplikasi lain. Coba lagi sebentar, ya',
    SpeechErrorKind.audio => 'Mikrofon bermasalah. Coba lagi, ya',
    _ => 'Dikte berhenti. Coba lagi, yuk',
  };

  Future<void> toggle() async => active ? stop() : start();

  Future<void> start() async {
    if (_disposed || active) return;
    final c = ref.read(dictationControllerProvider.notifier);
    final avail = await ref
        .read(speechTranscriberProvider)
        .availability(locale: ref.read(speechLocaleProvider));
    if (_disposed) return;
    final ctx = context();
    if (_disposed || !ctx.mounted) return;
    const fallback = 'Kamu tetap bisa mengetik pesannya, ya.';
    if (!avail.canDictate(
      allowNetwork: ref.read(dictationAllowsNetworkProvider),
    )) {
      await showDictationUnavailable(ctx, ref, avail, fallback: fallback);
      return;
    }
    if (!await ensureMicReady(ctx, ref, MicPurpose.dictate)) return;
    if (_disposed || !ctx.mounted) return;
    c.clear();
    _inserted = 0;
    _ownsDictation = true;
    _cancelOwned = () {
      c.cancel();
    };
    final ok = await c.start();
    if (_disposed || ok || !ctx.mounted) return;
    final s = ref.read(dictationControllerProvider);
    if (s.phase == DictationPhase.unavailable && s.availability != null) {
      await showDictationUnavailable(
        ctx,
        ref,
        s.availability!,
        fallback: fallback,
      );
    } else if (s.error?.kind == SpeechErrorKind.permission) {
      if (s.permission == MicPermissionStatus.permanentlyDenied) {
        await showMicSettingsGuide(ctx, ref);
      } else {
        showErrorToast(ctx, 'Izin mikrofon dibutuhkan untuk dikte');
      }
    } else if (s.phase == DictationPhase.error) {
      showErrorToast(ctx, _error(s.error?.kind));
    }
  }

  /// Stops listening; the final words still land in the field.
  Future<void> stop() async {
    final c = ref.read(dictationControllerProvider.notifier);
    await c.stop();
    c.clear();
    _inserted = 0;
    _ownsDictation = false;
    _cancelOwned = null;
  }

  Future<void> cancel() async {
    final c = ref.read(dictationControllerProvider.notifier);
    await c.cancel();
    c.clear();
    _inserted = 0;
    _ownsDictation = false;
    _cancelOwned = null;
  }
}
