import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import 'speech_model_sheet.dart';

export 'speech_model_sheet.dart'
    show DictationOfflineTile, showSpeechModelSheet;

/// Live "Dikte" panel docked above the editor / chat composer: mic level,
/// "Mendengarkan…" with the running time (mm:ss), the live partial text
/// (greyed — final text lands in the field as you speak), the silence
/// warning ("Masih mendengarkan?"), the best-effort offline hint, Selesai /
/// Batal.
class DictationBar extends ConsumerWidget {
  const DictationBar({super.key, required this.onStop, required this.onCancel});

  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final d = ref.watch(dictationControllerProvider);
    // Listening and the short restarts in between read the same: the label
    // must not blink at every recognizer session.
    final status = switch (d.phase) {
      DictationPhase.starting => 'Menyiapkan mikrofon…',
      DictationPhase.stopping => 'Merapikan teks…',
      _ => 'Mendengarkan…',
    };
    final bestEffort = d.availability?.offline == OfflineSpeechSupport.unknown;
    final warning = d.stopIn;
    return Container(
      key: const ValueKey('dictation-bar'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: GhinaColors.blue.tint(g.brightness),
        borderRadius: GhinaRadii.rLg,
        border: Border.all(
          color: GhinaColors.blue.tintBorder(g.brightness),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _MicLevel(level: d.level),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // One Text (not a Row): never overflows in a narrow
                    // composer (Fold cover screen).
                    Text.rich(
                      TextSpan(
                        text: status,
                        style: GhinaType.bodyS
                            .w(900)
                            .copyWith(color: GhinaColors.blue.base),
                        children: [
                          TextSpan(
                            text: '  ${formatDictationElapsed(d.elapsed)}',
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      key: const ValueKey('dictation-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Always one line tall: the bar doesn't jump when the
                    // live text comes and goes between utterances.
                    Text(
                      d.partial.isEmpty ? 'ngomong aja…' : d.partial,
                      key: d.partial.isEmpty
                          ? const ValueKey('dictation-idle-line')
                          : const ValueKey('dictation-partial'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.body.copyWith(
                        color: d.partial.isEmpty
                            ? g.textMuted.withValues(alpha: 0.6)
                            : g.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('dictation-cancel'),
                onPressed: onCancel,
                child: const Text('Batal'),
              ),
              const SizedBox(width: 4),
              ChunkyButton(
                key: const ValueKey('dictation-stop'),
                label: 'Selesai',
                size: ChunkyButtonSize.small,
                color: GhinaColors.blue,
                expand: false,
                onPressed: d.phase == DictationPhase.stopping ? null : onStop,
              ),
            ],
          ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            _SilenceWarning(
              secondsLeft: warning,
              onKeep: ref
                  .read(dictationControllerProvider.notifier)
                  .keepListening,
            ),
          ],
          if (bestEffort && d.hint != null) ...[
            const SizedBox(height: 6),
            Text(
              d.hint!,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Masih mendengarkan? Dikte berhenti dalam 10 dtk" + Lanjutkan. The whole
/// strip is tappable; speaking dismisses it too.
class _SilenceWarning extends StatelessWidget {
  const _SilenceWarning({required this.secondsLeft, required this.onKeep});

  final int secondsLeft;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Material(
      key: const ValueKey('dictation-silence-warning'),
      color: GhinaColors.orange.tint(g.brightness),
      borderRadius: GhinaRadii.rMd,
      child: InkWell(
        borderRadius: GhinaRadii.rMd,
        onTap: onKeep,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                Icons.hourglass_bottom_rounded,
                size: 18,
                color: GhinaColors.orange.base,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Masih mendengarkan? Dikte berhenti dalam $secondsLeft dtk',
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              TextButton(
                key: const ValueKey('dictation-keep'),
                onPressed: onKeep,
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicLevel extends StatelessWidget {
  const _MicLevel({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final v = level.clamp(0.0, 1.0);
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28 + 12 * v,
            height: 28 + 12 * v,
            decoration: BoxDecoration(
              color: GhinaColors.blue.base.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GhinaColors.blue.base,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Explains why "Dikte" can't start here (offline pack missing, no speech
/// service…) in the speech-pack sheet: in-app download with progress, "Pakai
/// online dulu", settings fallback. [fallback] names what still works
/// instead (default: the Notes voice recorder). Returns true when dictation
/// may start now (pack ready, or online allowed).
Future<bool> showDictationUnavailable(
  BuildContext context,
  WidgetRef ref,
  SpeechAvailability availability, {
  String fallback = 'Tenang, "Rekam suara" tetap bisa dipakai kapan saja.',
}) => showSpeechModelSheet(context, fallback: fallback);
