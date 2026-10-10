import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/dreams/dream_metric_logic.dart';

void main() {
  group('metricTrackOf', () {
    test('true is on track, false is off track', () {
      expect(metricTrackOf(true), MetricTrack.onTrack);
      expect(metricTrackOf(false), MetricTrack.offTrack);
    });

    test('null is unknown, never on track', () {
      expect(metricTrackOf(null), MetricTrack.unknown);
      expect(metricTrackOf(null), isNot(MetricTrack.onTrack));
      expect(metricTrackLabel(metricTrackOf(null)), 'Belum bisa dinilai');
    });

    test('labels', () {
      expect(metricTrackLabel(MetricTrack.onTrack), 'Di jalur');
      expect(metricTrackLabel(MetricTrack.offTrack), 'Meleset');
    });
  });

  group('metricValueMode', () {
    test('computed when the online reading exists', () {
      for (final s in MetricSource.values) {
        expect(
          metricValueMode(hasOnlineReading: true, source: s),
          MetricValueMode.computed,
        );
      }
    });

    test('offline: manual shows the stored reading, others the target', () {
      expect(
        metricValueMode(hasOnlineReading: false, source: MetricSource.manual),
        MetricValueMode.storedManual,
      );
      expect(
        metricValueMode(hasOnlineReading: false, source: MetricSource.weight),
        MetricValueMode.targetOnly,
      );
    });

    test('note only for target-only, and not while loading', () {
      expect(
        metricNeedsInternetNote(MetricValueMode.targetOnly, loading: false),
        isTrue,
      );
      expect(
        metricNeedsInternetNote(MetricValueMode.targetOnly, loading: true),
        isFalse,
      );
      expect(
        metricNeedsInternetNote(MetricValueMode.storedManual, loading: false),
        isFalse,
      );
      expect(
        metricNeedsInternetNote(MetricValueMode.computed, loading: false),
        isFalse,
      );
    });
  });

  group('parseManualValue', () {
    test('accepts integers, comma and dot decimals, negatives', () {
      expect(parseManualValue('72').value, 72);
      expect(parseManualValue(' 72,5 ').value, 72.5);
      expect(parseManualValue('72.5').value, 72.5);
      expect(parseManualValue('-3').value, -3);
      expect(parseManualValue('72').ok, isTrue);
    });

    test('rejects empty, null, text and non-finite', () {
      for (final s in [
        null,
        '',
        '   ',
        'abc',
        '7x',
        '1,2,3',
        'NaN',
        'Infinity',
      ]) {
        final r = parseManualValue(s);
        expect(r.ok, isFalse, reason: '$s');
        expect(r.error, isNotNull, reason: '$s');
      }
    });
  });
}
