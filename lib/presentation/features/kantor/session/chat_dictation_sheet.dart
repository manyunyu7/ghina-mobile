import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import '../../notes/widgets/dictation_bar.dart' show showDictationUnavailable;
import '../../notes/widgets/mic_permission.dart' show waitForAppResume;

/// How the dictation pop-up was closed.
enum DictationSheetAction {
  /// Batal: the words are dropped.
  cancel,

  /// Selesai: the words go into the chat field (not sent).
  done,

  /// Kirim: the words go into the chat field and are sent right away.
  send,
}

typedef DictationSheetResult = ({DictationSheetAction action, String text});

/// The Kantor chat's "Dikte" pop-up. null = dismissed some other way (swipe):
/// the caller then stops dictation and asks before dropping the words.
Future<DictationSheetResult?> showChatDictationSheet(BuildContext context) {
  final g = context.ghina;
  return showModalBottomSheet<DictationSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // tabletop / two panels: a readable column, not a 1200dp wide strip
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: g.surface,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const ChatDictationSheet(),
  );
}

enum _Stage {
  /// Availability / permission check.
  checking,

  /// Mic not allowed yet: short explanation + "Izinkan mikrofon".
  explain,

  /// The system prompt is up.
  asking,

  /// Denied once: message + "Coba lagi".
  denied,

  /// Blocked ("jangan tanya lagi"): "Buka pengaturan app".
  blocked,

  /// In the system settings; checked again when the app is back.
  settings,

  /// The recognizer runs (or ran) — the controller's phase tells the rest.
  running,
}

/// Mic indicator following the voice level, status line, mm:ss, the live
/// transcript (committed + fading partial, scrolls along), and Batal /
/// Selesai / Kirim. The mic permission flow happens inside it.
class ChatDictationSheet extends ConsumerStatefulWidget {
  const ChatDictationSheet({super.key});

  /// "Menyambung…" only when a restart takes this long (they're ~30 ms
  /// normally: no flashing label).
  static const reconnectLabelAfter = Duration(milliseconds: 700);

  /// No voice / new words this long → "Jeda — lanjut bicara".
  static const pauseLabelAfter = Duration(seconds: 4);

  @override
  ConsumerState<ChatDictationSheet> createState() => _ChatDictationSheetState();
}

class _ChatDictationSheetState extends ConsumerState<ChatDictationSheet> {
  static const _fallback = 'Kamu tetap bisa mengetik pesannya, ya.';

  _Stage _stage = _Stage.checking;
  bool _stillBlocked = false;
  bool _closing = false;
  bool _reconnecting = false;
  Timer? _reconnectTimer;

  /// Dictation time ([DictationState.elapsed]) of the last voice / words.
  Duration _lastVoice = Duration.zero;
  final _scroll = ScrollController();
  ({Future<bool> future, void Function() cancel})? _back;

  DictationController get _c => ref.read(dictationControllerProvider.notifier);
  MicrophonePermission get _perm => ref.read(microphonePermissionProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_begin());
    });
  }

  @override
  void dispose() {
    _back?.cancel();
    _reconnectTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool _usable(MicPermissionStatus s) =>
      s.isGranted || s == MicPermissionStatus.unsupported;

  void _go(_Stage s) {
    if (mounted) setState(() => _stage = s);
  }

  Future<void> _begin() async {
    if (ref.read(dictationControllerProvider).isActive) {
      _go(_Stage.running);
      return;
    }
    final avail = await ref
        .read(speechTranscriberProvider)
        .availability(locale: ref.read(speechLocaleProvider));
    if (!mounted) return;
    if (!avail.canDictate(
      allowNetwork: ref.read(dictationAllowsNetworkProvider),
    )) {
      // The voice pack sheet: download, or "Pakai online dulu".
      final go = await showDictationUnavailable(
        context,
        ref,
        avail,
        fallback: _fallback,
      );
      if (!mounted) return;
      if (!go) return _close(DictationSheetAction.cancel);
    }
    final s = await _perm.status();
    if (!mounted) return;
    if (_usable(s)) return _listen();
    _go(
      s == MicPermissionStatus.permanentlyDenied
          ? _Stage.blocked
          : _Stage.explain,
    );
  }

  /// One system prompt per tap ("Izinkan mikrofon" / "Coba lagi").
  Future<void> _ask() async {
    _go(_Stage.asking);
    final s = await _perm.request();
    if (!mounted) return;
    if (_usable(s)) return _listen();
    _go(
      s == MicPermissionStatus.permanentlyDenied
          ? _Stage.blocked
          : _Stage.denied,
    );
  }

  /// "Buka pengaturan app"; back in the app the mic is checked again and
  /// dictation starts by itself when it's allowed now.
  Future<void> _openSettings() async {
    _back?.cancel();
    final back = _back = waitForAppResume();
    _go(_Stage.settings);
    final ok = await _perm.openAppSettings();
    if (!ok) {
      back.cancel();
      if (!mounted) return;
      _go(_Stage.blocked);
      showToastBadge(
        context,
        message: 'Buka Pengaturan HP › Aplikasi › app ini › Mikrofon, ya',
        icon: Icons.settings_rounded,
        color: GhinaColors.blue,
      );
      return;
    }
    if (!await back.future || !mounted) return;
    final s = await _perm.status();
    if (!mounted) return;
    if (_usable(s)) return _listen();
    setState(() {
      _stillBlocked = true;
      _stage = _Stage.blocked;
    });
  }

  Future<void> _listen() async {
    _lastVoice = Duration.zero; // start() resets the timer
    _go(_Stage.running);
    final ok = await _c.start();
    if (ok || !mounted || _closing) return;
    final s = ref.read(dictationControllerProvider);
    if (s.phase == DictationPhase.unavailable && s.availability != null) {
      final go = await showDictationUnavailable(
        context,
        ref,
        s.availability!,
        fallback: _fallback,
      );
      if (!mounted) return;
      if (go) return _listen();
      return _close(DictationSheetAction.cancel);
    }
    if (s.error?.kind == SpeechErrorKind.permission) {
      _go(
        s.permission == MicPermissionStatus.permanentlyDenied
            ? _Stage.blocked
            : _Stage.denied,
      );
    }
    // Other errors show in the sheet (phase error) with "Coba lagi".
  }

  /// Selesai / Kirim: waits for the last words, then hands them over.
  Future<void> _finish(DictationSheetAction action) async {
    if (_closing) return;
    setState(() => _closing = true);
    final s = ref.read(dictationControllerProvider);
    final text = s.isActive ? await _c.stop() : s.text;
    if (!mounted) return;
    _c.clear();
    Navigator.of(context).pop((action: action, text: text));
  }

  Future<void> _close(DictationSheetAction action) async {
    if (_closing) return;
    _closing = true;
    await _c.cancel();
    if (!mounted) return;
    _c.clear();
    Navigator.of(context).pop((action: action, text: ''));
  }

  /// Back / tap outside: Batal, after a short question when there are words.
  Future<void> _confirmCancel() async {
    if (_closing) return;
    if (ref.read(dictationControllerProvider).text.trim().isEmpty) {
      return _close(DictationSheetAction.cancel);
    }
    final drop = await showChunkyConfirm(
      context,
      title: 'Buang teks dikte?',
      message: 'Kata yang sudah dikenali tidak masuk ke kotak ketik.',
      confirmLabel: 'Buang',
      cancelLabel: 'Lanjut dikte',
      destructive: true,
    );
    if (drop && mounted) await _close(DictationSheetAction.cancel);
  }

  void _onDictation(DictationState? prev, DictationState next) {
    if (next.level >= DictationController.voiceLevel ||
        next.text != prev?.text ||
        next.elapsed < _lastVoice) {
      _lastVoice = next.elapsed;
    }
    if (next.phase == DictationPhase.restarting) {
      _reconnectTimer ??= Timer(ChatDictationSheet.reconnectLabelAfter, () {
        if (mounted) setState(() => _reconnecting = true);
      });
    } else {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnecting = false;
    }
    if (next.text != prev?.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dictationControllerProvider, _onDictation);
    final d = ref.watch(dictationControllerProvider);
    final g = context.ghina;
    final running = _stage == _Stage.running;
    final busy = _closing || d.phase == DictationPhase.stopping;
    final hasText = d.text.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmCancel());
      },
      child: LayoutBuilder(
        builder: (context, box) {
          // ±45–60% of the (sub)screen; tabletop halves get a little more.
          final maxH = box.maxHeight.isFinite
              ? box.maxHeight
              : MediaQuery.sizeOf(context).height;
          final hi = maxH * 0.9;
          final h = (maxH * 0.55).clamp(math.min(300.0, hi), hi).toDouble();
          final compact = h < 380;
          return SizedBox(
            key: const ValueKey('dict-sheet'),
            height: h,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                compact ? 8 : 12,
                20,
                compact ? 10 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: g.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  Row(
                    children: [
                      _MicPulse(
                        level: running && d.isActive ? d.level : 0,
                        on: running && d.isActive,
                        size: compact ? 52 : 72,
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: _statusLine(d, g)),
                      if (running && (d.isActive || d.elapsed > Duration.zero))
                        Text(
                          formatDictationElapsed(d.elapsed),
                          key: const ValueKey('dict-time'),
                          style: GhinaType.bodyS
                              .w(800)
                              .copyWith(color: g.textSecondary),
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 14),
                  Expanded(child: running ? _transcript(d, g) : _permit(g)),
                  SizedBox(height: compact ? 8 : 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChunkyButton(
                          key: const ValueKey('dict-cancel'),
                          label: 'Batal',
                          size: ChunkyButtonSize.medium,
                          variant: ChunkyButtonVariant.ghost,
                          onPressed: _closing
                              ? null
                              : () => _close(DictationSheetAction.cancel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChunkyButton(
                          key: const ValueKey('dict-done'),
                          label: 'Selesai',
                          size: ChunkyButtonSize.medium,
                          variant: ChunkyButtonVariant.outline,
                          onPressed: running && hasText && !busy
                              ? () => _finish(DictationSheetAction.done)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChunkyButton(
                          key: const ValueKey('dict-send'),
                          label: 'Kirim',
                          icon: Icons.send_rounded,
                          size: ChunkyButtonSize.medium,
                          onPressed: running && hasText && !busy
                              ? () => _finish(DictationSheetAction.send)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusLine(DictationState d, GhinaTokens g) {
    String text;
    VoidCallback? tap;
    switch (_stage) {
      case _Stage.checking:
        text = 'Menyiapkan dikte…';
      case _Stage.explain:
        text = 'Izinkan mikrofon dulu';
      case _Stage.asking:
        text = 'Meminta izin mikrofon…';
      case _Stage.denied:
        text = 'Mikrofon belum diizinkan';
      case _Stage.blocked:
        text = 'Mikrofon masih diblokir';
      case _Stage.settings:
        text = 'Menunggu dari Pengaturan…';
      case _Stage.running:
        if (_closing || d.phase == DictationPhase.stopping) {
          text = 'Menyelesaikan…';
        } else if (d.phase == DictationPhase.starting) {
          text = 'Menyiapkan mikrofon…';
        } else if (d.phase == DictationPhase.error) {
          text = d.error?.kind.message ?? 'Dikte berhenti';
        } else if (!d.isActive) {
          text = 'Dikte berhenti';
        } else if (d.stopIn != null) {
          text = 'Masih mendengarkan? Ketuk untuk lanjut (${d.stopIn} dtk)';
          tap = _c.keepListening;
        } else if (d.phase == DictationPhase.restarting && _reconnecting) {
          text = 'Menyambung…';
        } else if (d.elapsed - _lastVoice >=
            ChatDictationSheet.pauseLabelAfter) {
          text = 'Jeda — lanjut bicara';
        } else {
          text = 'Mendengarkan…';
        }
    }
    final label = Text(
      text,
      key: const ValueKey('dict-status'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GhinaType.bodyL.w(800).copyWith(color: g.textPrimary),
    );
    return tap == null ? label : GestureDetector(onTap: tap, child: label);
  }

  Widget _transcript(DictationState d, GhinaTokens g) {
    final stopped =
        !d.isActive && !_closing && d.phase != DictationPhase.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: g.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                child: d.text.isEmpty
                    ? Text(
                        'Ngomong aja, teksnya muncul di sini…',
                        style: GhinaType.bodyL.copyWith(color: g.textMuted),
                      )
                    : Text.rich(
                        key: const ValueKey('dict-text'),
                        TextSpan(
                          style: GhinaType.bodyL.copyWith(
                            color: g.textPrimary,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(text: d.committed),
                            if (d.partial.isNotEmpty)
                              TextSpan(
                                text:
                                    '${d.committed.isEmpty ? '' : ' '}'
                                    '${d.partial}',
                                style: TextStyle(color: g.textMuted),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (stopped) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('dict-again'),
            label: d.phase == DictationPhase.error
                ? 'Coba lagi'
                : 'Lanjut dikte',
            icon: Icons.mic_rounded,
            size: ChunkyButtonSize.small,
            variant: ChunkyButtonVariant.secondary,
            onPressed: _listen,
          ),
        ],
      ],
    );
  }

  /// Permission steps inside the pop-up (no separate dialogs).
  Widget _permit(GhinaTokens g) {
    final (String message, Widget? action) = switch (_stage) {
      _Stage.explain => (
        'Mikrofon dipakai buat mengubah ucapanmu jadi teks; pengenalan suara '
            'jalan di perangkat. Setelah kamu izinkan, dikte langsung mulai.',
        ChunkyButton(
          key: const ValueKey('mic-allow'),
          label: 'Izinkan mikrofon',
          icon: Icons.mic_rounded,
          size: ChunkyButtonSize.medium,
          onPressed: _ask,
        ),
      ),
      _Stage.denied => (
        'Tanpa mikrofon dikte tidak bisa jalan. Ketuk "Coba lagi", lalu '
            'pilih Izinkan. Kamu tetap bisa mengetik.',
        ChunkyButton(
          key: const ValueKey('mic-retry'),
          label: 'Coba lagi',
          icon: Icons.mic_rounded,
          size: ChunkyButtonSize.medium,
          onPressed: _ask,
        ),
      ),
      _Stage.blocked => (
        '${_stillBlocked ? 'Mikrofon masih belum diizinkan. ' : ''}'
            'Buka pengaturan app ini › Izin › Mikrofon, lalu pilih Izinkan. '
            'Setelah kembali ke sini, langsung dicek lagi.',
        ChunkyButton(
          key: const ValueKey('mic-settings'),
          label: 'Buka pengaturan app',
          icon: Icons.settings_rounded,
          size: ChunkyButtonSize.medium,
          onPressed: _openSettings,
        ),
      ),
      _Stage.settings => (
        'Izinkan Mikrofon di Pengaturan, lalu kembali ke sini — dikte '
            'langsung mulai.',
        null,
      ),
      _Stage.asking => ('Pilih "Izinkan" di jendela izin.', null),
      _ => ('', null),
    };
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.isNotEmpty)
            Text(
              message,
              key: const ValueKey('dict-permit'),
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }
}

/// Big mic with a ring that swells with the voice level.
class _MicPulse extends StatelessWidget {
  const _MicPulse({required this.level, required this.on, required this.size});

  final double level;
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    final blue = GhinaColors.blue;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedScale(
            scale: on ? 0.75 + 0.25 * level.clamp(0.0, 1.0) : 0.7,
            duration: const Duration(milliseconds: 120),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: blue.base.withValues(alpha: on ? 0.22 : 0.1),
              ),
            ),
          ),
          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? blue.base : blue.base.withValues(alpha: 0.5),
            ),
            child: Icon(
              Icons.mic_rounded,
              color: Colors.white,
              size: size * 0.34,
            ),
          ),
        ],
      ),
    );
  }
}
