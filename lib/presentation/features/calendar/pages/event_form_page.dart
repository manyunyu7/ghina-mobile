import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// Create (`/calendar/new?date=YYYY-MM-DD`) or edit (`/calendar/:id`) an
/// event. All-day events pick dates only; the end is the last day, inclusive.
class EventFormPage extends ConsumerStatefulWidget {
  const EventFormPage({super.key, this.id, this.initialDate});

  final String? id;

  /// `YYYY-MM-DD` to start on (new events).
  final String? initialDate;

  @override
  ConsumerState<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends ConsumerState<EventFormPage> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _start;
  DateTime? _end;
  bool _allDay = false;
  bool _hasEnd = true;
  String _color = defaultEventColor;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    final key = widget.initialDate;
    final day = key != null && isDateKey(key) ? parseDateKey(key) : now;
    // Next full hour on that day, one hour long.
    final hour = isSameDay(day, now) ? (now.hour + 1).clamp(0, 23) : 9;
    _start = DateTime(day.year, day.month, day.day, hour);
    _end = _start.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _fill(CalendarEvent e) {
    if (_loaded) return;
    _loaded = true;
    _title.text = e.title;
    _location.text = e.location ?? '';
    _notes.text = e.notes ?? '';
    _start = e.startAt;
    _end = e.endAt;
    _hasEnd = e.endAt != null;
    _allDay = e.allDay;
    _color = e.color ?? defaultEventColor;
    if (_allDay) {
      _start = DateTime(_start.year, _start.month, _start.day, 9);
      if (_end != null) _end = DateTime(_end!.year, _end!.month, _end!.day, 10);
    }
  }

  DateTime get _endOrDefault =>
      _end ?? (_allDay ? _start : _start.add(const Duration(hours: 1)));

  Future<void> _pickDate({required bool end}) async {
    final cur = end ? _endOrDefault : _start;
    final d = await showGhinaDatePicker(
      context,
      initial: cur,
      title: end ? 'Tanggal selesai' : 'Tanggal mulai',
      firstDate: end ? _start : null,
      today: ref.read(clockProvider).now(),
    );
    if (d == null || !mounted) return;
    setState(() {
      final picked = DateTime(d.year, d.month, d.day, cur.hour, cur.minute);
      if (end) {
        _end = picked;
        _hasEnd = true;
      } else {
        // Keep the duration when the start moves.
        final dur = _endOrDefault.difference(_start);
        _start = picked;
        if (_hasEnd) _end = picked.add(dur.isNegative ? Duration.zero : dur);
      }
    });
  }

  Future<void> _pickTime({required bool end}) async {
    final cur = end ? _endOrDefault : _start;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(cur),
      helpText: end ? 'Jam selesai' : 'Jam mulai',
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(() {
      final picked = DateTime(cur.year, cur.month, cur.day, t.hour, t.minute);
      if (end) {
        _end = picked;
        _hasEnd = true;
      } else {
        final dur = _endOrDefault.difference(_start);
        _start = picked;
        if (_hasEnd) _end = picked.add(dur.isNegative ? Duration.zero : dur);
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    final title = _title.text.trim();
    if (title.isEmpty) errors['title'] = 'Kasih judul dulu, ya';
    if (title.length > reminderTitleMax) {
      errors['title'] = 'Maks $reminderTitleMax karakter';
    }
    if (_location.text.trim().length > eventLocationMax) {
      errors['location'] = 'Maks $eventLocationMax karakter';
    }
    if (_notes.text.trim().length > reminderNotesMax) {
      errors['notes'] = 'Maks $reminderNotesMax karakter';
    }
    final end = _hasEnd ? _endOrDefault : null;
    if (end != null) {
      final before = _allDay
          ? startOfDay(end).isBefore(startOfDay(_start))
          : end.isBefore(_start);
      if (before) errors['endAt'] = 'Selesai nggak boleh sebelum mulai';
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    final input = CalendarEventInput(
      title: title,
      startAt: _start,
      endAt: end,
      allDay: _allDay,
      color: _color == defaultEventColor ? null : _color,
      location: _location.text,
      notes: _notes.text,
    );
    setState(() => _saving = true);
    final r = _isEdit
        ? await ref.read(updateCalendarEventProvider)(widget.id!, input)
        : await ref.read(createCalendarEventProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          _isEdit ? 'Perubahan tersimpan 👍' : 'Acara masuk kalender 📅',
        );
        popOr(context, '/calendar');
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

  Future<void> _delete(CalendarEvent e) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus acara ini?',
      message: '"${e.title}" akan dihapus dari kalender di semua perangkat.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteCalendarEventProvider)(e.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Acara dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        popOr(context, '/calendar');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    CalendarEvent? current;
    Widget body;
    if (_isEdit) {
      final async = ref.watch(watchCalendarEventProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          current = value;
          body = _form();
        case AsyncData():
          body = EmptyState(
            title: 'Acara nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Kembali',
            onAction: () => popOr(context, '/calendar'),
          );
        case AsyncError():
          body = ErrorRetry(
            onRetry: () =>
                ref.invalidate(watchCalendarEventProvider(widget.id!)),
          );
        default:
          body = const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 4),
          );
      }
    } else {
      body = _form();
    }
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah acara' : 'Acara baru'),
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
      bottomNavigationBar: !_isEdit || _loaded
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

  Widget _row({
    required String label,
    required DateTime value,
    required bool end,
    String? error,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 3,
        child: PickerField(
          label: label,
          value: Fmt.dateShortWeekday(value),
          errorText: error,
          leading: Icon(
            end ? Icons.flag_rounded : Icons.play_arrow_rounded,
            color: end ? GhinaColors.red.base : GhinaColors.green.base,
          ),
          trailingIcon: Icons.calendar_month_rounded,
          onTap: () => _pickDate(end: end),
        ),
      ),
      if (!_allDay) ...[
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: PickerField(
            label: 'Jam',
            value: Fmt.time(value),
            leading: Icon(
              Icons.schedule_rounded,
              color: GhinaColors.orange.base,
            ),
            trailingIcon: Icons.edit_rounded,
            onTap: () => _pickTime(end: end),
          ),
        ),
      ],
    ],
  );

  Widget _form() {
    final g = context.ghina;
    final swatch = CategoryColors.swatch(_color);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        12,
        GhinaSpace.page,
        32,
      ),
      children: [
        ChunkyTextField(
          key: const ValueKey('event-title'),
          label: 'Judul',
          hint: 'mis. Arisan keluarga',
          controller: _title,
          errorText: _errors['title'],
          autofocus: !_isEdit,
          maxLength: reminderTitleMax,
          textInputAction: TextInputAction.next,
          prefixIcon: Icons.event_note_rounded,
        ),
        const SizedBox(height: 12),
        ChunkyCard(
          tinted: swatch,
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
            title: Text(
              'Sepanjang hari',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            subtitle: Text(
              _allDay
                  ? 'Cukup pilih tanggal, tanpa jam.'
                  : 'Pakai jam mulai & selesai.',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
            secondary: Icon(Icons.wb_sunny_rounded, color: swatch.base),
          ),
        ),
        const SizedBox(height: 16),
        _row(label: _allDay ? 'Tanggal' : 'Mulai', value: _start, end: false),
        const SizedBox(height: 12),
        if (_hasEnd)
          _row(
            label: _allDay ? 'Sampai tanggal' : 'Selesai',
            value: _endOrDefault,
            end: true,
            error: _errors['endAt'],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _hasEnd = !_hasEnd;
              if (_hasEnd && _end == null) _end = _endOrDefault;
            }),
            icon: Icon(
              _hasEnd ? Icons.remove_circle_outline : Icons.add_circle_outline,
            ),
            label: Text(
              _hasEnd
                  ? (_allDay ? 'Cuma satu hari' : 'Tanpa jam selesai')
                  : (_allDay ? 'Beberapa hari' : 'Tambah jam selesai'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Warna'),
        ChunkyColorPicker(
          selected: _color,
          palette: eventColors,
          onChanged: (c) => setState(() => _color = c),
        ),
        const SizedBox(height: 20),
        ChunkyTextField(
          key: const ValueKey('event-location'),
          label: 'Lokasi (opsional)',
          hint: 'mis. Rumah Nenek',
          controller: _location,
          errorText: _errors['location'],
          maxLength: eventLocationMax,
          prefixIcon: Icons.place_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        ChunkyTextField(
          key: const ValueKey('event-notes'),
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
}

/// Reads `?date=` for the new-event route.
String? initialDateOf(GoRouterState s) => s.uri.queryParameters['date'];
