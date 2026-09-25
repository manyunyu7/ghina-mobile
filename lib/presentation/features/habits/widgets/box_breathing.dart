import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/design_system.dart';

/// One phase of box breathing (4 s each).
enum BreathPhase {
  inhale('Tarik napas'),
  holdIn('Tahan'),
  exhale('Buang pelan'),
  holdOut('Tahan');

  const BreathPhase(this.label);
  final String label;
}

/// Seconds per phase (box breathing 4-4-4-4).
const breathPhaseSeconds = 4;

/// Phase at [elapsed] into a cycle.
BreathPhase breathPhaseAt(Duration elapsed) {
  final i = (elapsed.inMilliseconds ~/ (breathPhaseSeconds * 1000)) % 4;
  return BreathPhase.values[i];
}

/// Circle size factor (0.55–1) at [t] ∈ [0, 1) of a 16-s cycle.
double breathScaleAt(double t) {
  const lo = 0.55, hi = 1.0;
  final q = (t * 4) % 4;
  final f = q - q.floor();
  final eased = 0.5 - math.cos(f * math.pi) / 2;
  return switch (q.floor()) {
    0 => lo + (hi - lo) * eased,
    1 => hi,
    2 => hi - (hi - lo) * eased,
    _ => lo,
  };
}

/// The breathing tree: an expanding / shrinking circle with Ghina breathing
/// inside, the phase label and its countdown. Haptic tick on each phase.
class BoxBreathing extends StatefulWidget {
  const BoxBreathing({
    super.key,
    this.size = 260,
    this.color = GhinaColors.blue,
    this.running = true,
  });

  final double size;
  final ChunkySwatch color;
  final bool running;

  @override
  State<BoxBreathing> createState() => _BoxBreathingState();
}

class _BoxBreathingState extends State<BoxBreathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: breathPhaseSeconds * 4),
  );
  BreathPhase? _phase;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    if (widget.running) _c.repeat();
  }

  @override
  void didUpdateWidget(BoxBreathing old) {
    super.didUpdateWidget(old);
    if (widget.running && !_c.isAnimating) _c.repeat();
    if (!widget.running && _c.isAnimating) _c.stop();
  }

  void _onTick() {
    final p = breathPhaseAt(_c.duration! * _c.value);
    if (p != _phase) {
      _phase = p;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = widget.color;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final scale = breathScaleAt(t);
        final elapsed = _c.duration! * t;
        final phase = breathPhaseAt(elapsed);
        final inPhase = elapsed.inMilliseconds % (breathPhaseSeconds * 1000);
        final left = breathPhaseSeconds - inPhase ~/ 1000;
        final s = widget.size;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: s,
              height: s,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer guide ring.
                  Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sw.base.withValues(alpha: 0.25),
                        width: 3,
                      ),
                    ),
                  ),
                  Container(
                    width: s * scale,
                    height: s * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sw.base.withValues(alpha: g.isDark ? 0.28 : 0.18),
                    ),
                  ),
                  Container(
                    width: s * scale * 0.78,
                    height: s * scale * 0.78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sw.base.withValues(alpha: g.isDark ? 0.4 : 0.28),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8 + 0.2 * scale,
                    child: MascotView(
                      mood: MascotMood.happy,
                      size: s * 0.42,
                      animate: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              phase.label,
              key: const ValueKey('breath-phase'),
              style: GhinaType.h1.copyWith(color: g.textPrimary),
            ),
            Text('$left', style: GhinaType.h2.w(900).copyWith(color: sw.base)),
          ],
        );
      },
    );
  }
}
