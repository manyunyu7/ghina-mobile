import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_format.dart';
import 'dream_metric_logic.dart';

String _unavailableText(MetricUnavailable u) => switch (u) {
  MetricUnavailable.noData => 'Belum ada data untuk dihitung',
  MetricUnavailable.missingRef => 'Sumber metrik tidak ditemukan',
  MetricUnavailable.wrongKind => 'Sumber metrik tidak cocok',
};

ChunkySwatch _trackColor(MetricTrack t) => switch (t) {
  MetricTrack.onTrack => GhinaColors.green,
  MetricTrack.offTrack => GhinaColors.red,
  MetricTrack.unknown => GhinaColors.gray,
};

/// The metrics section: one card per metric. [online] is the server detail
/// when it loaded, null while loading or when the call failed.
class DreamMetricsSection extends StatelessWidget {
  const DreamMetricsSection({
    super.key,
    required this.dreamId,
    required this.metrics,
    required this.online,
    required this.loading,
  });

  final String dreamId;
  final List<DreamMetric> metrics;
  final DreamDetail? online;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final readings = {
      for (final v in online?.metrics ?? const <DreamMetricView>[])
        v.metric.id: v.reading,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Metrik',
          padding: EdgeInsets.only(top: 4, bottom: 8),
        ),
        for (final m in metrics)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DreamMetricCard(
              key: ValueKey('metric-${m.id}'),
              metric: m,
              reading: readings[m.id],
              loading: loading,
            ),
          ),
      ],
    );
  }
}

class DreamMetricCard extends ConsumerStatefulWidget {
  const DreamMetricCard({
    super.key,
    required this.metric,
    required this.reading,
    required this.loading,
  });

  final DreamMetric metric;

  /// Null when there is no computed reading (offline, loading, failed).
  final DreamMetricReading? reading;
  final bool loading;

  @override
  ConsumerState<DreamMetricCard> createState() => _DreamMetricCardState();
}

class _DreamMetricCardState extends ConsumerState<DreamMetricCard> {
  final _input = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final m = widget.metric;
    final parsed = parseManualValue(_input.text);
    if (!parsed.ok) {
      setState(() => _error = parsed.error);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final value = parsed.value!;
    final online = await ref.read(recordDreamManualValueOnlineProvider)(
      dreamId: m.dreamId,
      metricId: m.id,
      value: value,
      at: null,
    );
    if (!mounted) return;
    switch (online) {
      case Ok():
        ref.invalidate(dreamOnlineDetailProvider(m.dreamId));
        _done('Nilai ${m.label} dicatat');
      case Err(:final failure) when failure is NetworkFailure:
        final local = await ref.read(recordDreamManualValueProvider)(
          metricId: m.id,
          value: value,
          at: ref.read(clockProvider).now(),
        );
        if (!mounted) return;
        switch (local) {
          case Ok():
            _done('Lagi offline, nilainya disimpan dulu dan disinkron nanti');
          case Err(:final failure):
            setState(() => _saving = false);
            showFailureToast(context, failure);
        }
      case Err(:final failure):
        setState(() => _saving = false);
        showFailureToast(context, failure);
    }
  }

  void _done(String message) {
    _input.clear();
    setState(() => _saving = false);
    showOkToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = widget.metric;
    final r = widget.reading;
    final mode = metricValueMode(hasOnlineReading: r != null, source: m.source);
    final target = dreamMetricValueText(m, m.targetValue);

    int? pct;
    String valueLine;
    switch (mode) {
      case MetricValueMode.computed:
        pct = r!.progressPct;
        valueLine = r.currentValue == null
            ? 'Belum ada nilai → $target'
            : '${dreamMetricValueText(m, r.currentValue!)} → $target';
      case MetricValueMode.storedManual:
        pct = metricProgressPct(
          start: m.startValue,
          target: m.targetValue,
          direction: m.effectiveDirection,
          current: m.manualValue,
        );
        valueLine = m.manualValue == null
            ? 'Belum ada nilai → $target'
            : '${dreamMetricValueText(m, m.manualValue!)} → $target';
      case MetricValueMode.targetOnly:
        valueLine = 'Target $target';
    }

    final track = mode == MetricValueMode.computed
        ? metricTrackOf(r!.onTrack)
        : null;
    final startText = m.startDate == null ? '' : formatTarget(m.startDate);
    final targetText = m.targetDate == null ? '' : formatTarget(m.targetDate);
    final projected = r?.projectedDate == null
        ? ''
        : formatTarget(r!.projectedDate);

    return ChunkyCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.label, style: GhinaType.h3.copyWith(color: g.textPrimary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChunkyPill(
                label: m.source.label,
                color: GhinaColors.blue,
                soft: true,
                uppercase: false,
              ),
              if (track != null)
                ChunkyPill(
                  key: ValueKey('metric-badge-${m.id}'),
                  label: metricTrackLabel(track),
                  color: _trackColor(track),
                  soft: true,
                  uppercase: false,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            valueLine,
            key: ValueKey('metric-value-${m.id}'),
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
          if (mode != MetricValueMode.targetOnly) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChunkyProgressBar(
                    value: ((pct ?? 0) / 100).clamp(0.0, 1.0),
                    height: 8,
                    color: GhinaColors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dreamPercentText(pct),
                  key: ValueKey('metric-pct-${m.id}'),
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ],
          if (mode == MetricValueMode.computed && r!.unavailable != null) ...[
            const SizedBox(height: 6),
            Text(
              _unavailableText(r.unavailable!),
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
          if (startText.isNotEmpty ||
              targetText.isNotEmpty ||
              projected.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (startText.isNotEmpty) _Caption('Mulai $startText'),
                if (targetText.isNotEmpty) _Caption('Target $targetText'),
                if (projected.isNotEmpty) _Caption('Proyeksi $projected'),
              ],
            ),
          ],
          if (metricNeedsInternetNote(mode, loading: widget.loading)) ...[
            const SizedBox(height: 8),
            Text(
              'Butuh internet untuk nilai terhitung',
              key: ValueKey('metric-note-${m.id}'),
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
          if (m.source.isManual) ...[
            const SizedBox(height: 12),
            ChunkyTextField(
              key: ValueKey('metric-input-${m.id}'),
              controller: _input,
              label: 'Nilai terbaru',
              hint: 'Contoh 72,5',
              errorText: _error,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\- ]')),
              ],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _record(),
            ),
            const SizedBox(height: 10),
            ChunkyButton(
              key: ValueKey('metric-save-${m.id}'),
              label: 'Catat nilai',
              icon: Icons.add_chart_rounded,
              size: ChunkyButtonSize.medium,
              loading: _saving,
              onPressed: _saving ? null : _record,
            ),
          ],
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
  );
}
