import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../habit_format.dart';
import 'habit_extra_fields.dart';

ChunkySwatch eventKindColor(HabitEventKind k) => switch (k) {
  HabitEventKind.journal => GhinaColors.blue,
  HabitEventKind.milestone => GhinaColors.yellow,
  HabitEventKind.event => GhinaColors.purple,
};

IconData eventKindIcon(HabitEventKind k) => switch (k) {
  HabitEventKind.journal => Icons.edit_note_rounded,
  HabitEventKind.milestone => Icons.emoji_events_rounded,
  HabitEventKind.event => Icons.event_note_rounded,
};

/// Timeline of a habit's journal days, milestones and neutral events, newest
/// first. They never change streaks. Works offline (synced later).
class HabitEventsSection extends ConsumerStatefulWidget {
  const HabitEventsSection({super.key, required this.habit});

  final Habit habit;

  @override
  ConsumerState<HabitEventsSection> createState() => _HabitEventsSectionState();
}

class _HabitEventsSectionState extends ConsumerState<HabitEventsSection> {
  static const _collapsed = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final h = widget.habit;
    final events = ref.watch(watchHabitEventsProvider(h.id)).value;
    final defs = fieldsForHabit(
      ref.watch(watchHabitFieldsProvider).value ?? const [],
      h.id,
    );
    final today = dateKey(ref.watch(clockProvider).now());
    final list = events ?? const <HabitEvent>[];
    final shown = _all ? list : list.take(_collapsed).toList();
    return Column(
      key: const ValueKey('habit-events-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Kejadian & pencapaian',
          subtitle: 'Tidak mengubah streak',
          actionLabel: 'Tambah',
          onAction: () => showHabitEventSheet(context, habit: h),
        ),
        if (events == null)
          const SkeletonList(count: 2)
        else if (list.isEmpty)
          Text(
            'Belum ada. Catat hari penting, pencapaian kecil, atau kejadian '
            'yang bukan kambuh.',
            style: GhinaType.body.copyWith(color: g.textSecondary),
          )
        else ...[
          for (final e in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EventTile(
                event: e,
                defs: defs,
                today: today,
                onTap: () => showHabitEventSheet(context, habit: h, event: e),
              ),
            ),
          if (list.length > _collapsed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('events-toggle'),
                onPressed: () => setState(() => _all = !_all),
                child: Text(
                  _all
                      ? 'Tampilkan lebih sedikit'
                      : 'Lihat semua (${list.length})',
                ),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('fields-manage'),
            onPressed: () => context.push('/habits/fields?habit=${h.id}'),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Kelola dimensi'),
          ),
        ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.defs,
    required this.today,
    required this.onTap,
  });

  final HabitEvent event;
  final List<HabitFieldDef> defs;
  final String today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final e = event;
    final color = eventKindColor(e.kind);
    return ChunkyCard(
      key: ValueKey('event-${e.id}'),
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryAvatar(
            icon: eventKindIcon(e.kind),
            color: color.base,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.label,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${e.kind.label} · ${habitDayLabel(e.date, today)}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
                if (e.note != null && e.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    e.note!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ],
                if (e.extra.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ExtraValueChips(extra: e.extra, defs: defs),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Add ([event] null) or edit an event. Resolves to true when saved or
/// deleted.
Future<bool> showHabitEventSheet(
  BuildContext context, {
  required Habit habit,
  HabitEvent? event,
}) async {
  final r = await showChunkyBottomSheet<bool>(
    context,
    title: event == null ? 'Catat kejadian' : 'Ubah kejadian',
    showClose: true,
    builder: (_) => HabitEventForm(habit: habit, event: event),
  );
  return r == true;
}

class HabitEventForm extends ConsumerStatefulWidget {
  const HabitEventForm({super.key, required this.habit, this.event});

  final Habit habit;
  final HabitEvent? event;

  @override
  ConsumerState<HabitEventForm> createState() => _HabitEventFormState();
}

class _HabitEventFormState extends ConsumerState<HabitEventForm> {
  late final _label = TextEditingController(text: widget.event?.label);
  late final _note = TextEditingController(text: widget.event?.note);
  late HabitEventKind _kind = widget.event?.kind ?? HabitEventKind.event;
  late DateTime _date = widget.event == null
      ? ref.read(clockProvider).now()
      : parseDateKey(widget.event!.date);
  late final Map<String, Object> _extra = {...?widget.event?.extra};
  Map<String, String> _extraErrors = const {};
  String? _labelError;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  List<HabitFieldDef> get _defs => fieldsForScope(
    ref.read(watchHabitFieldsProvider).value ?? const [],
    widget.habit.id,
    _kind.wire,
  );

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final picked = await showGhinaDatePicker(
      context,
      initial: _date.isAfter(now) ? now : _date,
      title: 'Tanggal',
      firstDate: DateTime(2000),
      lastDate: now,
      today: now,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _labelError = null;
      _extraErrors = const {};
    });
    // Values of a scope switched away from are dropped with their inputs.
    final keys = {for (final d in _defs) d.key};
    final r = await ref.read(saveHabitEventProvider)(
      HabitEventInput(
        id: widget.event?.id,
        habitId: widget.habit.id,
        date: _date,
        kind: _kind,
        label: _label.text,
        note: _note.text,
        at: widget.event?.at,
        extra: {
          for (final e in _extra.entries)
            if (keys.contains(e.key)) e.key: e.value,
        },
      ),
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(:final field)) {
            if (field == 'label') _labelError = failure.message;
            if (field == 'extra') {
              _extraErrors = extraErrorsFor(failure.message, _defs);
            }
          }
        });
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus kejadian ini?',
      message: '"${widget.event!.label}" akan dihapus. Streak tidak berubah.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteHabitEventProvider)(widget.event!.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final defs = fieldsForScope(
      ref.watch(watchHabitFieldsProvider).value ?? const [],
      widget.habit.id,
      _kind.wire,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Jenis'),
            ChunkyChoiceChips<HabitEventKind>(
              options: [
                for (final k in HabitEventKind.values)
                  ChunkyChoice(
                    value: k,
                    label: k.label,
                    icon: eventKindIcon(k),
                    color: eventKindColor(k),
                  ),
              ],
              selected: {_kind},
              onChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            ChunkyTextField(
              key: const ValueKey('event-label'),
              label: 'Judul',
              hint: 'mis. Lembur proyek contoh',
              controller: _label,
              maxLength: habitEventLabelMax,
              errorText: _labelError,
              autofocus: widget.event == null,
            ),
            const SizedBox(height: 12),
            PickerField(
              key: const ValueKey('event-date'),
              label: 'Tanggal',
              value: habitLongDate(dateKey(_date)),
              trailingIcon: Icons.calendar_month_rounded,
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            ChunkyTextField(
              key: const ValueKey('event-note'),
              label: 'Catatan (opsional)',
              controller: _note,
              maxLength: habitEventNoteMax,
              minLines: 2,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
            ),
            if (defs.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExtraFieldsForm(
                defs: defs,
                values: _extra,
                errors: _extraErrors,
                onChanged: (k, v) => setState(() {
                  if (v == null) {
                    _extra.remove(k);
                  } else {
                    _extra[k] = v;
                  }
                }),
              ),
            ],
            const SizedBox(height: 12),
            ChunkyButton(
              key: const ValueKey('event-save'),
              label: 'Simpan',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (widget.event != null) ...[
              const SizedBox(height: 8),
              ChunkyButton(
                key: const ValueKey('event-delete'),
                label: 'Hapus kejadian',
                icon: Icons.delete_outline_rounded,
                variant: ChunkyButtonVariant.ghost,
                color: GhinaColors.red,
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
