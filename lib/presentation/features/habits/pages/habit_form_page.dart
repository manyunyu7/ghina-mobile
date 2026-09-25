import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/habit_reminder_permission.dart';
import '../habit_format.dart';
import '../lock/habit_lock_gate.dart';
import '../widgets/habit_cards.dart';

/// Create / edit a habit: name, emoji, color, kind, schedule, target,
/// reminders, private, why and start date.
class HabitFormPage extends StatelessWidget {
  const HabitFormPage({super.key, this.id});

  /// Null = new habit.
  final String? id;

  @override
  Widget build(BuildContext context) =>
      HabitLockGate(child: _HabitForm(id: id));
}

class _HabitForm extends ConsumerStatefulWidget {
  const _HabitForm({this.id});

  final String? id;

  @override
  ConsumerState<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends ConsumerState<_HabitForm> {
  final _name = TextEditingController();
  final _why = TextEditingController();
  final _goal = TextEditingController();
  final _unit = TextEditingController();
  final _customEmoji = TextEditingController();
  final Map<String, String> _errors = {};

  HabitKind _kind = HabitKind.build;
  String? _emoji = '💪';
  String _color = defaultHabitColor;
  HabitScheduleType _scheduleType = HabitScheduleType.daily;
  Set<int> _days = {1, 2, 3, 4, 5};
  int _times = 3;
  HabitTargetType _targetType = HabitTargetType.check;
  List<String> _reminders = [];
  bool _private = false;
  late DateTime _start;
  bool _saving = false;
  bool _loaded = false;
  Habit? _editing;

  bool get _isEdit => widget.id != null;

  @override
  void initState() {
    super.initState();
    _start = startOfDay(ref.read(clockProvider).now());
    if (!_isEdit) _loaded = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _why.dispose();
    _goal.dispose();
    _unit.dispose();
    _customEmoji.dispose();
    super.dispose();
  }

  void _fill(Habit h) {
    _editing = h;
    _loaded = true;
    _name.text = h.name;
    _why.text = h.why ?? '';
    _kind = h.kind;
    _emoji = h.emoji;
    if (h.emoji != null && !habitEmojis.contains(h.emoji)) {
      _customEmoji.text = h.emoji!;
    }
    _color = h.color;
    _scheduleType = h.schedule.type;
    if (h.schedule.isWeekdays) _days = {...h.schedule.days};
    if (h.schedule.isPerWeek) _times = h.schedule.times ?? 3;
    _targetType = h.target.type;
    if (!h.target.isCheck) _goal.text = fmtHabitNum(h.target.goal);
    if (h.target.isCount) _unit.text = h.target.unit ?? '';
    _reminders = [...h.reminders];
    _private = h.isPrivate;
    _start = parseDateKey(h.startDate);
  }

  void _setKind(HabitKind k) {
    setState(() {
      _kind = k;
      if (!_isEdit && (_emoji == '💪' || _emoji == '🚭')) {
        _emoji = k == HabitKind.quit ? '🚭' : '💪';
      }
      _errors.clear();
    });
  }

  HabitSchedule _schedule() => switch (_scheduleType) {
    HabitScheduleType.daily => HabitSchedule.daily,
    HabitScheduleType.weekdays => HabitSchedule.weekdays(_days.toList()),
    HabitScheduleType.perWeek => HabitSchedule.perWeek(_times),
  };

  HabitTarget? _target() {
    switch (_targetType) {
      case HabitTargetType.check:
        return HabitTarget.check;
      case HabitTargetType.count:
        final g = double.tryParse(_goal.text.trim().replaceAll(',', '.'));
        if (g == null || g <= 0) return null;
        return HabitTarget.count(g, unit: _unit.text);
      case HabitTargetType.duration:
        final g = int.tryParse(_goal.text.trim());
        if (g == null || g <= 0) return null;
        return HabitTarget.duration(g.toDouble());
    }
  }

  Future<void> _addReminder() async {
    if (_reminders.length >= habitRemindersMax) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Ingatkan jam berapa?',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    final hm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (_reminders.contains(hm)) return;
    setState(() => _reminders = [..._reminders, hm]..sort());
    await ensureHabitReminderPermission(context, ref);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final target = _kind == HabitKind.quit ? HabitTarget.check : _target();
    setState(() {
      _errors.clear();
      if (name.isEmpty) _errors['name'] = 'Kasih nama kebiasaannya dulu, ya';
      if (target == null) {
        _errors['target'] = _targetType == HabitTargetType.duration
            ? 'Isi berapa menit per hari'
            : 'Isi targetnya (lebih dari 0)';
      }
      if (_kind == HabitKind.build &&
          _scheduleType == HabitScheduleType.weekdays &&
          _days.isEmpty) {
        _errors['schedule'] = 'Pilih minimal satu hari';
      }
    });
    if (_errors.isNotEmpty || target == null) return;
    setState(() => _saving = true);
    if (_reminders.isNotEmpty) {
      await ensureHabitReminderPermission(context, ref);
    }
    if (!mounted) return;
    final input = HabitInput(
      name: name,
      emoji: _emoji,
      color: _color,
      kind: _kind,
      schedule: _kind == HabitKind.quit ? HabitSchedule.daily : _schedule(),
      target: target,
      reminders: _reminders,
      isPrivate: _private,
      why: _why.text.trim().isEmpty ? null : _why.text.trim(),
      startDate: _start,
    );
    final rewards = _isEdit ? null : await RewardTracker.startLoaded(ref);
    final r = _isEdit
        ? await ref.read(updateHabitProvider)(widget.id!, input)
        : await ref.read(createHabitProvider)(input);
    if (!mounted) {
      rewards?.cancel();
      return;
    }
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        HapticFeedback.mediumImpact();
        if (rewards != null) {
          // A new quit habit may unlock "Teman Streak" right away.
          await rewards.finish(
            context,
            xpToast: (xp) => 'Kebiasaan baru! +$xp XP',
            doneToast: 'Kebiasaan baru siap! 🌱',
          );
        } else {
          showOkToast(context, 'Tersimpan 👍');
        }
        if (!mounted) return;
        if (_isEdit) {
          popOr(context, '/habits/${value.id}');
        } else {
          context.pushReplacement('/habits/${value.id}');
        }
      case Err(:final failure):
        rewards?.cancel();
        if (failure is ValidationFailure && failure.field != null) {
          setState(() => _errors[failure.field!] = failure.message);
        } else {
          showFailureToast(context, failure);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_loaded) {
      final habit = ref.watch(watchAllHabitsProvider);
      final h = habit.value?.where((x) => x.id == widget.id).firstOrNull;
      if (h != null) {
        _fill(h);
      } else {
        return Scaffold(
          appBar: AppBar(title: const Text('Ubah kebiasaan')),
          body: habit.hasValue
              ? const EmptyState(
                  title: 'Kebiasaan nggak ditemukan',
                  message: 'Mungkin sudah dihapus.',
                )
              : const LoadingListView(tiles: 5, hero: false),
        );
      }
    }
    final g = context.ghina;
    final quit = _kind == HabitKind.quit;
    final today = startOfDay(ref.read(clockProvider).now());
    final preview = Habit(
      id: 'preview',
      name: _name.text.trim().isEmpty ? 'Kebiasaan baru' : _name.text.trim(),
      emoji: _emoji,
      color: _color,
      kind: _kind,
      startDate: dateKey(_start),
      createdAt: today,
      updatedAt: today,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah kebiasaan' : 'Kebiasaan baru'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  GhinaSpace.md,
                  GhinaSpace.page,
                  GhinaSpace.xl,
                ),
                children: [
                  ChunkySegmented<HabitKind>(
                    segments: const [
                      ChunkySegment(
                        value: HabitKind.build,
                        label: 'Membangun',
                        icon: Icons.eco_rounded,
                        color: GhinaColors.green,
                      ),
                      ChunkySegment(
                        value: HabitKind.quit,
                        label: 'Berhenti',
                        icon: Icons.do_not_disturb_rounded,
                        color: GhinaColors.purple,
                      ),
                    ],
                    value: _kind,
                    onChanged: _setKind,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    kindHint(_kind),
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                  if (_isEdit && _editing != null && _editing!.kind != _kind)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Riwayatnya tetap disimpan, tapi dihitung dengan aturan jenis baru.',
                        style: GhinaType.caption
                            .w(800)
                            .copyWith(color: GhinaColors.orange.base),
                      ),
                    ),
                  GhinaSpace.gapLg,
                  Row(
                    children: [
                      HabitAvatar(habit: preview, size: 56),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ChunkyTextField(
                          key: const ValueKey('habit-name'),
                          controller: _name,
                          label: 'Nama',
                          hint: quit ? 'Misal: Rokok' : 'Misal: Minum air',
                          maxLength: habitNameMax,
                          errorText: _errors['name'],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  GhinaSpace.gapMd,
                  FieldLabel('Emoji', error: _errors.containsKey('emoji')),
                  _EmojiGrid(
                    selected: _emoji,
                    color: CategoryColors.swatch(_color),
                    onChanged: (e) => setState(() {
                      _emoji = e;
                      _customEmoji.clear();
                    }),
                  ),
                  GhinaSpace.gapSm,
                  Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: ChunkyTextField(
                          controller: _customEmoji,
                          hint: 'Emoji lain…',
                          maxLength: 8,
                          onChanged: (v) {
                            final chars = v.trim().characters;
                            setState(
                              () => _emoji = chars.isEmpty
                                  ? null
                                  : chars.take(2).toString(),
                            );
                          },
                        ),
                      ),
                      const Spacer(),
                      if (_emoji != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _emoji = null;
                            _customEmoji.clear();
                          }),
                          child: const Text('Tanpa emoji'),
                        ),
                    ],
                  ),
                  if (_errors['emoji'] case final e?) _ErrorText(e),
                  GhinaSpace.gapMd,
                  const FieldLabel('Warna'),
                  ChunkyColorPicker(
                    selected: _color,
                    palette: habitColors,
                    size: 40,
                    onChanged: (c) => setState(() => _color = c),
                  ),
                  if (!quit) ...[
                    GhinaSpace.gapXl,
                    const FieldLabel('Jadwal'),
                    ChunkyChoiceChips<HabitScheduleType>(
                      options: const [
                        ChunkyChoice(
                          value: HabitScheduleType.daily,
                          label: 'Setiap hari',
                        ),
                        ChunkyChoice(
                          value: HabitScheduleType.weekdays,
                          label: 'Hari tertentu',
                        ),
                        ChunkyChoice(
                          value: HabitScheduleType.perWeek,
                          label: 'X kali seminggu',
                        ),
                      ],
                      selected: {_scheduleType},
                      onChanged: (s) => setState(() => _scheduleType = s.first),
                    ),
                    if (_scheduleType == HabitScheduleType.weekdays) ...[
                      GhinaSpace.gapMd,
                      _WeekdayPicker(
                        selected: _days,
                        onChanged: (d) => setState(() => _days = d),
                      ),
                    ],
                    if (_scheduleType == HabitScheduleType.perWeek) ...[
                      GhinaSpace.gapMd,
                      _Stepper(
                        value: _times,
                        min: 1,
                        max: 7,
                        label: '$_times× per minggu',
                        onChanged: (v) => setState(() => _times = v),
                      ),
                    ],
                    if (_errors['schedule'] case final e?) _ErrorText(e),
                    GhinaSpace.gapXl,
                    const FieldLabel('Target harian'),
                    ChunkySegmented<HabitTargetType>(
                      segments: const [
                        ChunkySegment(
                          value: HabitTargetType.check,
                          label: 'Centang',
                          icon: Icons.check_rounded,
                        ),
                        ChunkySegment(
                          value: HabitTargetType.count,
                          label: 'Jumlah',
                          icon: Icons.exposure_plus_1_rounded,
                        ),
                        ChunkySegment(
                          value: HabitTargetType.duration,
                          label: 'Durasi',
                          icon: Icons.timer_rounded,
                        ),
                      ],
                      value: _targetType,
                      onChanged: (t) => setState(() {
                        _targetType = t;
                        _goal.text = switch (t) {
                          HabitTargetType.count => '8',
                          HabitTargetType.duration => '30',
                          HabitTargetType.check => '',
                        };
                        if (t == HabitTargetType.count && _unit.text.isEmpty) {
                          _unit.text = 'gelas';
                        }
                        _errors.remove('target');
                      }),
                    ),
                    GhinaSpace.gapMd,
                    if (_targetType == HabitTargetType.check)
                      Text(
                        'Cukup satu ketukan kalau hari ini sudah dilakukan ✅',
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ChunkyTextField(
                              key: const ValueKey('habit-goal'),
                              controller: _goal,
                              label: _targetType == HabitTargetType.duration
                                  ? 'Menit per hari'
                                  : 'Jumlah per hari',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              errorText: _errors['target'],
                            ),
                          ),
                          if (_targetType == HabitTargetType.count) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChunkyTextField(
                                key: const ValueKey('habit-unit'),
                                controller: _unit,
                                label: 'Satuan',
                                hint: 'gelas, halaman…',
                                maxLength: habitUnitMax,
                              ),
                            ),
                          ],
                        ],
                      ),
                    if (_targetType == HabitTargetType.duration) ...[
                      GhinaSpace.gapSm,
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in const [10, 15, 30, 60])
                            ChunkyChip(
                              label: formatMinutes(m),
                              selected: _goal.text.trim() == '$m',
                              onTap: () => setState(() => _goal.text = '$m'),
                            ),
                        ],
                      ),
                    ],
                  ],
                  GhinaSpace.gapXl,
                  FieldLabel(
                    'Pengingat',
                    trailing: Text(
                      '${_reminders.length}/$habitRemindersMax',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in _reminders)
                        InputChip(
                          label: Text(r.replaceFirst(':', '.')),
                          avatar: const Icon(
                            Icons.notifications_active_rounded,
                            size: 18,
                          ),
                          onDeleted: () => setState(
                            () => _reminders = [..._reminders]..remove(r),
                          ),
                        ),
                      if (_reminders.length < habitRemindersMax)
                        ChunkyChip(
                          key: const ValueKey('habit-reminder-add'),
                          label: 'Tambah jam',
                          icon: Icons.add_alarm_rounded,
                          selected: false,
                          onTap: _addReminder,
                        ),
                    ],
                  ),
                  if (_errors['reminders'] case final e?) _ErrorText(e),
                  GhinaSpace.gapXl,
                  ChunkyCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ChunkyTile(
                      framed: false,
                      title: 'Pribadi',
                      subtitle:
                          'Nama & emoji disamarkan jadi “$privateHabitTitle” di Beranda, '
                          'widget dan notifikasi. Di halaman Kebiasaan tetap terlihat.',
                      leading: CategoryAvatar(
                        icon: Icons.lock_rounded,
                        color: GhinaColors.purple.base,
                        size: 40,
                      ),
                      trailing: Switch(
                        key: const ValueKey('habit-private'),
                        value: _private,
                        onChanged: (v) => setState(() => _private = v),
                      ),
                      onTap: () => setState(() => _private = !_private),
                    ),
                  ),
                  GhinaSpace.gapXl,
                  ChunkyTextField(
                    key: const ValueKey('habit-why'),
                    controller: _why,
                    label: quit
                        ? 'Kenapa kamu mau berhenti?'
                        : 'Kenapa ini penting buatmu?',
                    hint: quit
                        ? 'Muncul di layar darurat saat lagi pengen.'
                        : 'Pengingat saat lagi malas.',
                    maxLines: 4,
                    minLines: 2,
                    maxLength: habitWhyMax,
                    errorText: _errors['why'],
                  ),
                  GhinaSpace.gapMd,
                  DateField(
                    label: quit ? 'Sudah bersih sejak…' : 'Mulai tanggal',
                    helper: quit
                        ? 'Hari bersih dihitung dari tanggal ini.'
                        : 'Hari sebelum tanggal ini nggak dihitung.',
                    value: _start,
                    today: today,
                    lastDate: quit ? today : addDays(today, 365),
                    onChanged: (d) => setState(() => _start = d),
                  ),
                  if (_errors['startDate'] case final e?) _ErrorText(e),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.sm,
                GhinaSpace.page,
                GhinaSpace.lg,
              ),
              child: ChunkyButton(
                key: const ValueKey('habit-save'),
                label: _isEdit ? 'Simpan' : 'Buat kebiasaan',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: GhinaType.caption.w(800).copyWith(color: GhinaColors.red.base),
    ),
  );
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
    required this.selected,
    required this.onChanged,
    required this.color,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = (c.maxWidth / 46).floor().clamp(6, 10);
        final size = (c.maxWidth - (perRow - 1) * 6) / perRow;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in habitEmojis)
              Semantics(
                button: true,
                selected: e == selected,
                label: 'Emoji $e',
                child: GestureDetector(
                  key: ValueKey('emoji-$e'),
                  onTap: () => onChanged(e == selected ? null : e),
                  child: AnimatedContainer(
                    duration: GhinaMotion.fast,
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e == selected
                          ? color.tint(g.brightness)
                          : g.surfaceAlt,
                      borderRadius: GhinaRadii.rMd,
                      border: Border.all(
                        color: e == selected ? color.base : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      e,
                      style: TextStyle(fontSize: size * 0.5),
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (var d = 1; d <= 7; d++)
        ChunkyChip(
          key: ValueKey('weekday-$d'),
          label: weekdaysShort[d - 1],
          selected: selected.contains(d),
          onTap: () {
            final next = {...selected};
            if (!next.remove(d)) next.add(d);
            onChanged(next);
          },
        ),
    ],
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Row(
      children: [
        ChunkyIconButton(
          icon: Icons.remove_rounded,
          size: 40,
          tooltip: 'Kurangi',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
        ),
        ChunkyIconButton(
          icon: Icons.add_rounded,
          size: 40,
          tooltip: 'Tambah',
          color: GhinaColors.green,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
