import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// Running stopwatches of duration habits: habit id → start time. In memory
/// for this app session (shared by the Habits list and the home card).
final habitTimersProvider =
    NotifierProvider<HabitTimersController, Map<String, DateTime>>(
      HabitTimersController.new,
    );

class HabitTimersController extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => const {};

  DateTime get _now => ref.read(clockProvider).now();

  bool isRunning(String habitId) => state.containsKey(habitId);

  void start(String habitId) {
    if (state.containsKey(habitId)) return;
    state = {...state, habitId: _now};
  }

  /// Stops the stopwatch and returns the elapsed time (null when it wasn't
  /// running).
  Duration? stop(String habitId) {
    final started = state[habitId];
    if (started == null) return null;
    state = {...state}..remove(habitId);
    final d = _now.difference(started);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Whole minutes a stopwatch run logs (rounded; < 30 s → 0).
int timerMinutes(Duration d) => (d.inSeconds / 60).round();

/// `12:05` / `1:02:05`.
String formatElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Rebuilds every second while [running], showing the elapsed time.
class ElapsedTicker extends ConsumerStatefulWidget {
  const ElapsedTicker({
    super.key,
    required this.startedAt,
    required this.builder,
  });

  final DateTime startedAt;
  final Widget Function(BuildContext context, Duration elapsed) builder;

  @override
  ConsumerState<ElapsedTicker> createState() => _ElapsedTickerState();
}

class _ElapsedTickerState extends ConsumerState<ElapsedTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.read(clockProvider).now().difference(widget.startedAt);
    return widget.builder(context, d.isNegative ? Duration.zero : d);
  }
}
