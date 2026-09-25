/// Labels, colors and copy of the Kebiasaan screens (`docs/habits.md`). Pure
/// helpers — the same wording as the web (`src/app/(dashboard)/habits`).
library;

import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';

/// Emoji grid of the form (web `EMOJIS`).
const habitEmojis = [
  '💪', '🏃', '🚶', '🧘', '🏋️', '🚴', '🏊', '⚽', '📖', '📚', '✍️', '🧠', //
  '💧', '🥗', '🍎', '🥦', '😴', '🌅', '🙏', '🕌', '📿', '🎸', '🎨', '💻',
  '🧹', '🪴', '💰', '📵', '🚭', '🍺', '🎰', '🍬', '☕', '🎮', '📱', '🌙',
  '🔥', '🌱', '⭐', '❤️',
];

/// Color choices of the form (web `COLORS`).
const habitColors = [
  '#58CC02',
  '#1CB0F6',
  '#CE82FF',
  '#FF9600',
  '#FF4B4B',
  '#FFC800',
  '#2B70C9',
  '#00CD9C',
  '#FF86D0',
  '#64748B',
];

const weekdaysShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const weekdaysLong = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// The habit's color as a chunky swatch.
ChunkySwatch habitSwatch(Habit h) => CategoryColors.swatch(h.color);

/// `1.5` → `1,5`, `8.0` → `8`.
String fmtHabitNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst('.', ',');
}

/// `45 mnt`, `1 j 30 mnt`, `2 jam`.
String formatMinutes(num min) {
  final m = min.round();
  if (m < 60) return '$m mnt';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h jam' : '$h j $r mnt';
}

/// `Centang`, `8 gelas`, `30 mnt`.
String targetLabel(HabitTarget t) => switch (t.type) {
  HabitTargetType.check => 'Centang',
  HabitTargetType.count =>
    '${fmtHabitNum(t.goal)} ${t.unit ?? defaultCountUnit}',
  HabitTargetType.duration => formatMinutes(t.goal),
};

/// `Setiap hari`, `Hari kerja`, `Akhir pekan`, `Sen, Rab`, `3× per minggu`.
String scheduleLabel(HabitSchedule s) {
  if (s.isPerWeek) return '${s.times}× per minggu';
  if (s.isWeekdays) {
    final j = s.days.join(',');
    if (s.days.length == 7) return 'Setiap hari';
    if (j == '1,2,3,4,5') return 'Hari kerja';
    if (j == '6,7') return 'Akhir pekan';
    return s.days.map((d) => weekdaysShort[d - 1]).join(', ');
  }
  return 'Setiap hari';
}

/// Today's progress: `3/8 gelas`, `15/30 mnt`, `Selesai` / `Belum`.
String progressLabel(HabitTarget t, double? progress) {
  final v = progress ?? 0;
  return switch (t.type) {
    HabitTargetType.count =>
      '${fmtHabitNum(v)}/${fmtHabitNum(t.goal)} ${t.unit ?? defaultCountUnit}',
    HabitTargetType.duration => '${fmtHabitNum(v)}/${fmtHabitNum(t.goal)} mnt',
    HabitTargetType.check => v > 0 ? 'Selesai' : 'Belum',
  };
}

/// `Hari ini`, `Kemarin`, `Sen, 21 Sep` (+ year when not [today]'s).
String habitDayLabel(String key, String today) {
  if (key == today) return 'Hari ini';
  if (key == dateKey(addDays(parseDateKey(today), -1))) return 'Kemarin';
  final d = parseDateKey(key);
  final base =
      '${weekdaysShort[d.weekday - 1]}, ${d.day} ${_monthsShort[d.month - 1]}';
  return key.substring(0, 4) == today.substring(0, 4)
      ? base
      : '$base ${d.year}';
}

/// `21 September 2026`.
String habitLongDate(String key) {
  final d = parseDateKey(key);
  return '${d.day} ${_monthsLong[d.month - 1]} ${d.year}';
}

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];
const _monthsLong = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', //
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// The streak line of a card: `Hari bersih ke-12`, `🔥 5 hari beruntun`.
String streakHeadline(HabitStreak s) => s.kind == HabitKind.quit
    ? 'Hari bersih ke-${s.current}'
    : '${s.current} ${s.unit.label} beruntun';

/// Next milestone above the current streak (build: null past 100).
int? nextMilestoneOf(HabitStreak s) => nextHabitMilestone(s.kind, s.current);

/// Ring progress toward the next milestone (1 when there is none), measured
/// from the previous milestone so the ring always moves visibly.
double milestoneFraction(HabitStreak s) {
  final next = nextMilestoneOf(s);
  if (next == null) return 1;
  final list = s.kind == HabitKind.quit
      ? quitMilestonesReached(s.current)
      : [
          for (final m in buildMilestones)
            if (m <= s.current) m,
        ];
  final prev = list.isEmpty ? 0 : list.last;
  final span = next - prev;
  return span <= 0 ? 0 : ((s.current - prev) / span).clamp(0, 1).toDouble();
}

/// `3 hari lagi menuju 7 hari 🌱`.
String nextMilestoneLine(HabitStreak s) {
  final next = nextMilestoneOf(s);
  if (next == null) return 'Semua target streak tercapai 🏆';
  final left = next - s.current;
  return '$left ${s.unit.label} lagi menuju $next ${s.unit.label}';
}

/// The no-shame line of the relapse sheet *before* logging — [cleanDays] is
/// the clean run the relapse ends.
String relapseSheetMessage(int cleanDays) => cleanDays > 0
    ? 'Kamu sempat bersih $cleanDays hari — itu nyata, dan nggak hilang. '
          'Catat dengan jujur, lalu mulai lagi 🌱'
    : 'Nggak apa-apa. Mencatat dengan jujur itu langkah berani. '
          'Pelan-pelan, kita mulai lagi 🌱';

/// Title of the relapse "done" view (server `previousStreak`).
String relapseDoneTitle(int previousStreak) => previousStreak > 0
    ? 'Kamu sempat bersih $previousStreak hari — itu nyata.'
    : 'Tercatat. Terima kasih sudah jujur.';

const relapseDoneBody =
    'Satu hari berat nggak menghapus usahamu. Hari bersih barumu dimulai '
    'besok — pelan-pelan saja.';

/// Copy of the "Libur hari ini" limit (use case message).
const skipLimitMessage = 'Maksimal 2 hari libur dalam 7 hari';

/// `Libur hari ini` hint: how many rest days are left this week.
String skipsLeftLabel(HabitToday t) => t.canSkip
    ? 'Sisa jatah libur: ${t.skipsLeft}'
    : 'Jatah libur minggu ini habis';

/// Celebration title of a streak milestone.
String milestoneTitle(HabitKind kind, int m, HabitStreakUnit unit) =>
    kind == HabitKind.quit
    ? '$m hari bersih! 🌳'
    : '$m ${unit.label} beruntun! 🔥';

/// Celebration subtitle; [masked] (outside the Habits screen) hides a private
/// habit's name.
String milestoneSubtitle(Habit h, int m, {bool masked = false}) {
  final name = masked && h.isPrivate ? 'kebiasaan pribadimu' : h.name;
  return h.isQuit
      ? 'Kamu sudah $m hari lepas dari $name. Bangga banget sama kamu!'
      : 'Kamu konsisten menjalani $name. Terus pertahankan, ya!';
}

/// Color of a heatmap cell.
Color heatmapColor(BuildContext context, HabitDayCell c, ChunkySwatch sw) {
  final g = context.ghina;
  final empty = g.isDark ? g.surfaceAlt : GhinaColors.polar;
  return switch (c.state) {
    HabitDayState.met || HabitDayState.clean => sw.base,
    HabitDayState.partial => Color.lerp(
      empty,
      sw.base,
      0.25 + c.fraction * 0.5,
    )!,
    HabitDayState.missed =>
      g.isDark ? const Color(0xFF3A2A2E) : const Color(0xFFFFE1E1),
    HabitDayState.relapse => GhinaColors.red.base,
    HabitDayState.skip => GhinaColors.yellow.base.withValues(alpha: 0.45),
    HabitDayState.pending =>
      c.fraction > 0
          ? Color.lerp(empty, sw.base, 0.25 + c.fraction * 0.5)!
          : empty,
    HabitDayState.off ||
    HabitDayState.before ||
    HabitDayState.future => empty.withValues(alpha: 0.5),
  };
}

/// Friendly label of a heatmap state (legend / semantics).
String heatmapStateLabel(HabitDayState s) => switch (s) {
  HabitDayState.met => 'Tercapai',
  HabitDayState.partial => 'Sebagian',
  HabitDayState.missed => 'Terlewat',
  HabitDayState.skip => 'Libur',
  HabitDayState.pending => 'Hari ini',
  HabitDayState.off => 'Bukan jadwal',
  HabitDayState.clean => 'Bersih',
  HabitDayState.relapse => 'Kambuh',
  HabitDayState.before => 'Belum mulai',
  HabitDayState.future => 'Nanti',
};

/// `Kebiasaan` form hint of the kind.
String kindHint(HabitKind k) => k == HabitKind.build
    ? 'Rutinitas baik yang mau kamu bangun: olahraga, baca, minum air…'
    : 'Kebiasaan yang mau kamu tinggalkan: rokok, begadang, scroll medsos…';
