/// Labels of the People screens (Indonesian). Pure helpers.
library;

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';

/// "Ibu" / the summary / the organization — the one-line context of a person.
String? personSubtitle(Person p) {
  for (final s in [p.relation, p.organization, p.summary]) {
    if (s != null && s.trim().isNotEmpty) return s.trim();
  }
  return null;
}

/// `5 Mei 1990` / `5 Mei` / `Mei 1990` / `1990` — null when nothing is known.
String? personBirthdayText(Person p) =>
    formatBirthday(year: p.birthYear, month: p.birthMonth, day: p.birthDay);

/// One line for an upcoming entry: `Besok · 35 tahun` (birthday: the age
/// turned, only when the birth year is known).
String upcomingDetail(UpcomingEvent e) {
  final when = daysUntilLabel(e.daysUntil);
  final years = e.yearsSince;
  if (years == null || years < 0) return when;
  return e.kind == EventKind.birthday
      ? '$when · $years tahun'
      : '$when · tahun ke-$years';
}

/// `🎂 Budi Contoh` for birthdays, `💍 Hari jadi · Budi Contoh` for the rest.
String upcomingTitle(UpcomingEvent e) => e.kind == EventKind.birthday
    ? '${e.kind.emoji} ${e.name}'
    : '${e.kind.emoji} ${e.label} · ${e.name}';

/// Title of a calendar overlay entry.
String occurrenceTitle(EventOccurrence o) => o.kind == EventKind.birthday
    ? '${o.kind.emoji} ${o.name}'
    : '${o.kind.emoji} ${o.label} · ${o.name}';

/// Subtitle of a calendar overlay entry (`Ulang tahun ke-35`).
String occurrenceSubtitle(EventOccurrence o) {
  final years = o.yearsSince;
  if (o.kind == EventKind.birthday) {
    return years == null || years < 0 ? 'Ulang tahun' : 'Ulang tahun ke-$years';
  }
  return years == null || years < 0
      ? o.kind.label
      : '${o.kind.label} · tahun ke-$years';
}

/// `5 Mei` / `5 Mei 2010` of an important date.
String personDateText(PersonDate d) => formatDayMonth(d.month, d.day, d.year);

/// The label of an important-date kind.
String dateKindLabel(PersonDateKind k) => k.eventKind.label;
