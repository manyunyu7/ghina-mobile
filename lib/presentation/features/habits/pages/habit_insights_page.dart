import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../lock/habit_lock_gate.dart';
import '../widgets/habit_analysis_widgets.dart';

/// "Analisis" of one habit from the server (`/insights`). **Online-only**: the
/// result lives in this widget's state only, nothing is stored or cached.
class HabitInsightsPage extends StatelessWidget {
  const HabitInsightsPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) =>
      HabitLockGate(child: _InsightsView(id: id));
}

const _ranges = [30, 90, 365];

class _InsightsView extends ConsumerStatefulWidget {
  const _InsightsView({required this.id});

  final String id;

  @override
  ConsumerState<_InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends ConsumerState<_InsightsView> {
  int _days = 90;
  bool _loading = true;
  HabitAnalysis? _data;
  Failure? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ref.read(fetchHabitAnalysisProvider)(
      widget.id,
      days: _days,
    );
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      switch (r) {
        case Ok(:final value):
          _data = value;
        case Err(:final failure):
          _data = null;
          _error = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(watchAllHabitsProvider).value;
    final name = habits?.where((h) => h.id == widget.id).firstOrNull?.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          name == null ? 'Analisis' : 'Analisis · $name',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading && _data == null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              0,
            ),
            child: _rangePicker(),
          ),
          const Expanded(child: LoadingListView(tiles: 3, hero: true)),
        ],
      );
    }
    final err = _error;
    if (err != null) {
      final offline = err is NetworkFailure;
      return ScrollableFill(
        child: ErrorRetry(
          title: offline ? 'Analisis butuh internet' : 'Ups, gagal memuat',
          message: offline
              ? 'Hubungkan ke internet dulu, ya. Analisisnya dihitung di server dan nggak disimpan di HP.'
              : err.message,
          onRetry: _load,
        ),
      );
    }
    final a = _data!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      children: [
        _rangePicker(),
        GhinaSpace.gapMd,
        if (_loading) const LinearProgressIndicator(),
        if (a.isEmpty)
          const EmptyState(
            key: ValueKey('analysis-empty'),
            title: 'Belum ada yang dianalisis',
            message:
                'Catat beberapa hari dulu, nanti pola dan pemicunya muncul di sini.',
            mood: MascotMood.thinking,
            compact: true,
          )
        else ...[
          AnalysisSummary(analysis: a),
          AnalysisRuns(analysis: a),
          AnalysisPerMonth(analysis: a),
          AnalysisTriggers(analysis: a),
          AnalysisDistributions(analysis: a),
          AnalysisRiskWindows(analysis: a),
          AnalysisDimensions(analysis: a),
          AnalysisEvents(analysis: a),
        ],
      ],
    );
  }

  Widget _rangePicker() => ChunkySegmented<int>(
    segments: [
      for (final d in _ranges) ChunkySegment(value: d, label: '$d hari'),
    ],
    value: _days,
    onChanged: (d) {
      if (d == _days) return;
      setState(() => _days = d);
      _load();
    },
    height: 42,
  );
}
