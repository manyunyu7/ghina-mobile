import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../reminder_actions.dart';

/// Material time picker in 24-hour format (the app's copy is Indonesian).
Future<TimeOfDay?> pickTime24(
  BuildContext context,
  TimeOfDay initial, {
  String? helpText,
}) => showTimePicker(
  context: context,
  initialTime: initial,
  helpText: helpText,
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
    child: child!,
  ),
);

/// Create (`/reminders/new`) or edit (`/reminders/:id`) a reminder.
class ReminderFormPage extends ConsumerStatefulWidget {
  const ReminderFormPage({super.key, this.id});

  final String? id;

  @override
  ConsumerState<ReminderFormPage> createState() => _ReminderFormPageState();
}

class _ReminderFormPageState extends ConsumerState<ReminderFormPage> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _due;
  ReminderRecurrence? _recurrence;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider).now();

  /// Next full hour (a new reminder's default).
  DateTime _defaultDue() {
    final n = _now;
    return DateTime(n.year, n.month, n.day, n.hour + 1);
  }

  void _fill(ReminderItem r) {
    if (_loaded) return;
    _loaded = true;
    _title.text = r.title;
    _notes.text = r.notes ?? '';
    _due = r.dueAt;
    _recurrence = r.recurrence;
  }

  Future<void> _pickDate() async {
    final cur = _due ?? _defaultDue();
    final d = await showGhinaDatePicker(
      context,
      initial: cur,
      title: 'Tanggal pengingat',
      today: _now,
    );
    if (d == null || !mounted) return;
    setState(
      () => _due = DateTime(d.year, d.month, d.day, cur.hour, cur.minute),
    );
  }

  Future<void> _pickTime() async {
    final cur = _due ?? _defaultDue();
    final t = await pickTime24(
      context,
      TimeOfDay.fromDateTime(cur),
      helpText: 'Jam pengingat',
    );
    if (t == null || !mounted) return;
    setState(
      () => _due = DateTime(cur.year, cur.month, cur.day, t.hour, t.minute),
    );
  }

  List<(String, DateTime)> _presets() {
    final n = _now;
    final today = startOfDay(n);
    DateTime at(DateTime day, int h) =>
        DateTime(day.year, day.month, day.day, h);
    final tonight = at(today, 20);
    return [
      ('1 jam lagi', DateTime(n.year, n.month, n.day, n.hour + 1, n.minute)),
      if (tonight.isAfter(n)) ('Nanti malam 20.00', tonight),
      ('Besok pagi 07.00', at(addDays(today, 1), 7)),
      ('Besok siang 12.00', at(addDays(today, 1), 12)),
      ('Minggu depan', at(addDays(today, 7), 9)),
    ];
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    final title = _title.text.trim();
    if (title.isEmpty) errors['title'] = 'Kasih judul dulu, ya';
    if (title.length > reminderTitleMax) {
      errors['title'] = 'Maks $reminderTitleMax karakter';
    }
    if (_notes.text.trim().length > reminderNotesMax) {
      errors['notes'] = 'Maks $reminderNotesMax karakter';
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    final input = ReminderInput(
      title: title,
      notes: _notes.text,
      dueAt: _due ?? _defaultDue(),
      recurrence: _recurrence,
    );
    setState(() => _saving = true);
    final r = _isEdit
        ? await ref.read(updateReminderProvider)(widget.id!, input)
        : await ref.read(createReminderProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        if (!value.done && value.dueAt.isAfter(_now)) {
          await ensureReminderPermission(context, ref);
          if (!mounted) return;
        }
        showOkToast(
          context,
          _isEdit
              ? 'Perubahan tersimpan 👍'
              : 'Siap! Ghina ingetin ${reminderDueLabel(value.dueAt, _now)} 🔔',
        );
        popOr(context, '/reminders');
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(:final field?)) {
            _errors = {..._errors, field: failure.message};
          }
        });
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete(ReminderItem r) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus pengingat ini?',
      message: '"${r.title}" akan dihapus dari semua perangkat.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final res = await ref.read(deleteReminderProvider)(r.id);
    if (!mounted) return;
    switch (res) {
      case Ok():
        showToastBadge(
          context,
          message: 'Pengingat dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        popOr(context, '/reminders');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _toggleDone(ReminderItem r) async {
    if (r.done) {
      final res = await ref.read(reopenReminderProvider)(r.id);
      if (!mounted) return;
      if (res case Err(:final failure)) showFailureToast(context, failure);
      return;
    }
    await completeReminderWithUndo(context, ref, r);
    if (mounted && !r.repeats) popOr(context, '/reminders');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    ReminderItem? current;
    Widget body;
    if (_isEdit) {
      final async = ref.watch(watchReminderItemProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          current = value;
          body = _form(value);
        case AsyncData():
          body = EmptyState(
            title: 'Pengingat nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Kembali',
            onAction: () => popOr(context, '/reminders'),
          );
        case AsyncError():
          body = ErrorRetry(
            onRetry: () =>
                ref.invalidate(watchReminderItemProvider(widget.id!)),
          );
        default:
          body = const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 4),
          );
      }
    } else {
      body = _form(null);
    }
    final showSave = !_isEdit || _loaded;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah pengingat' : 'Pengingat baru'),
        actions: [
          if (current != null)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(current!),
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: showSave
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                GhinaSpace.page,
                8,
                GhinaSpace.page,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: ChunkyButton(
                label: 'Simpan',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            )
          : null,
    );
  }

  Widget _form(ReminderItem? existing) {
    final g = context.ghina;
    final due = _due ?? _defaultDue();
    final now = _now;
    final inPast = due.isBefore(now) && !(existing?.done ?? false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        12,
        GhinaSpace.page,
        32,
      ),
      children: [
        if (existing != null) ...[
          _StatusCard(
            reminder: existing,
            now: now,
            onToggle: () => _toggleDone(existing),
          ),
          const SizedBox(height: 20),
        ],
        ChunkyTextField(
          key: const ValueKey('reminder-title'),
          label: 'Judul',
          hint: 'mis. Minum vitamin',
          controller: _title,
          errorText: _errors['title'],
          autofocus: !_isEdit,
          maxLength: reminderTitleMax,
          textInputAction: TextInputAction.next,
          prefixIcon: Icons.alarm_rounded,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: PickerField(
                label: 'Tanggal',
                value: _dayLabel(due, now),
                leading: Icon(
                  Icons.event_rounded,
                  color: GhinaColors.blue.base,
                ),
                trailingIcon: Icons.calendar_month_rounded,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PickerField(
                label: 'Jam',
                value: Fmt.time(due),
                leading: Icon(
                  Icons.schedule_rounded,
                  color: GhinaColors.orange.base,
                ),
                trailingIcon: Icons.edit_rounded,
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        if (inPast) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: GhinaColors.orange.base,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Waktunya sudah lewat — nggak ada notifikasi yang dikirim.',
                  style: GhinaType.caption.copyWith(
                    color: GhinaColors.orange.base,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (label, at) in _presets())
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.bolt_rounded, size: 16),
                    label: Text(label),
                    onPressed: () => setState(() => _due = at),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const FieldLabel('Ulangi'),
        ChunkyChoiceChips<ReminderRecurrence?>(
          options: [
            const ChunkyChoice(
              value: null,
              label: 'Sekali',
              icon: Icons.looks_one_rounded,
            ),
            for (final r in ReminderRecurrence.values)
              ChunkyChoice(
                value: r,
                label: switch (r) {
                  ReminderRecurrence.daily => 'Harian',
                  ReminderRecurrence.weekly => 'Mingguan',
                  ReminderRecurrence.monthly => 'Bulanan',
                  ReminderRecurrence.yearly => 'Tahunan',
                },
                icon: Icons.repeat_rounded,
              ),
          ],
          selected: {_recurrence},
          onChanged: (s) => setState(() => _recurrence = s.firstOrNull),
        ),
        if (_recurrence != null) ...[
          const SizedBox(height: 8),
          Text(
            _recurrenceHint(_recurrence!, due),
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ],
        const SizedBox(height: 20),
        ChunkyTextField(
          key: const ValueKey('reminder-notes'),
          label: 'Catatan (opsional)',
          hint: 'Detail tambahan…',
          controller: _notes,
          errorText: _errors['notes'],
          maxLines: 5,
          minLines: 3,
          maxLength: reminderNotesMax,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
      ],
    );
  }

  String _dayLabel(DateTime d, DateTime now) {
    final rel = Fmt.relativeDay(d, now: now);
    const near = {'Hari ini', 'Besok', 'Kemarin'};
    return near.contains(rel)
        ? '$rel, ${Fmt.dateShortWeekday(d)}'
        : Fmt.dateShortWeekday(d);
  }

  String _recurrenceHint(ReminderRecurrence r, DateTime due) {
    final when = switch (r) {
      ReminderRecurrence.daily => 'Tiap hari jam ${Fmt.time(due)}.',
      ReminderRecurrence.weekly =>
        'Tiap ${Fmt.dateShortWeekday(due).split(',').first} jam ${Fmt.time(due)}.',
      ReminderRecurrence.monthly =>
        'Tiap tanggal ${due.day} jam ${Fmt.time(due)}'
            '${due.day > 28 ? ' (bulan yang lebih pendek: hari terakhirnya)' : ''}.',
      ReminderRecurrence.yearly =>
        'Tiap ${Fmt.dateLong(due).replaceAll(RegExp(r' \d{4}$'), '')} jam ${Fmt.time(due)}.',
    };
    return '$when Saat ditandai selesai, pindah ke jadwal berikutnya.';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.reminder,
    required this.now,
    required this.onToggle,
  });

  final ReminderItem reminder;
  final DateTime now;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = reminder;
    final status = r.statusAt(now);
    final (swatch, icon, label) = switch (status) {
      ReminderStatus.done => (
        GhinaColors.green,
        Icons.check_circle_rounded,
        'Selesai${r.doneAt == null ? '' : ' · ${reminderDueLabel(r.doneAt!, now)}'}',
      ),
      ReminderStatus.overdue => (
        GhinaColors.red,
        Icons.warning_amber_rounded,
        'Terlambat · ${reminderDueLabel(r.dueAt, now)}',
      ),
      ReminderStatus.upcoming => (
        GhinaColors.blue,
        Icons.notifications_active_rounded,
        'Mendatang · ${reminderDueLabel(r.dueAt, now)}',
      ),
    };
    return ChunkyCard(
      tinted: swatch,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Icon(icon, color: swatch.base),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GhinaType.body.w(800)),
                if (r.repeats && r.doneAt != null && !r.done)
                  Text(
                    'Terakhir selesai ${reminderDueLabel(r.doneAt!, now)}',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ChunkyButton(
            label: r.done ? 'Buka lagi' : 'Selesai',
            size: ChunkyButtonSize.small,
            expand: false,
            variant: r.done
                ? ChunkyButtonVariant.outline
                : ChunkyButtonVariant.primary,
            color: r.done ? null : GhinaColors.green,
            icon: r.done ? Icons.undo_rounded : Icons.check_rounded,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}
