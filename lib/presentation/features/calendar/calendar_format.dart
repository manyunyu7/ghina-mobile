import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../../domain/entities/entities.dart';

/// `Sepanjang hari`, `09.00–10.30`, `09.00` (no end), multi-day spans get
/// their dates (`5 Okt – 7 Okt`).
String eventTimeLabel(CalendarEvent e) {
  final end = e.endAt;
  if (e.allDay) {
    if (end == null || isSameDay(end, e.startAt)) return 'Sepanjang hari';
    return 'Sepanjang hari · ${Fmt.dateShortWeekday(e.startAt)} – '
        '${Fmt.dateShortWeekday(end)}';
  }
  if (end == null) return Fmt.time(e.startAt);
  if (isSameDay(end, e.startAt) ||
      (end.hour == 0 &&
          end.minute == 0 &&
          isSameDay(end, addDays(e.startAt, 1)))) {
    return '${Fmt.time(e.startAt)}–${Fmt.time(end)}';
  }
  return '${Fmt.dateShortWeekday(e.startAt)} ${Fmt.time(e.startAt)} – '
      '${Fmt.dateShortWeekday(end)} ${Fmt.time(end)}';
}

/// Short Indonesian weekday headers, Monday first.
const weekdayInitials = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// `Hari ini · Kam, 1 Okt` for nearby days, else `Kamis, 1 Oktober 2026`.
String dayTitle(DateTime day, DateTime today) {
  final rel = Fmt.relativeDay(day, now: today);
  const near = {'Hari ini', 'Besok', 'Kemarin'};
  return near.contains(rel)
      ? '$rel · ${Fmt.dateShortWeekday(day)}'
      : Fmt.dateFull(day);
}
