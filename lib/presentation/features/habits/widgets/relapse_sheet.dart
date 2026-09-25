import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../habit_format.dart';

/// "Aku kalah" — log a relapse without shaming: optional triggers, note and
/// time, then the ended streak shown as an achievement. With [convertUrge]
/// (emergency screen "Aku kalah kali ini") the urge just logged becomes the
/// relapse. Resolves to true when something was logged.
Future<bool> showRelapseSheet(
  BuildContext context, {
  required HabitToday today,
  bool convertUrge = false,
}) async {
  var logged = false;
  await showChunkyBottomSheet<bool>(
    context,
    showClose: true,
    builder: (_) => RelapseSheet(
      today: today,
      convertUrge: convertUrge,
      onLogged: () => logged = true,
    ),
  );
  return logged;
}

class RelapseSheet extends ConsumerStatefulWidget {
  const RelapseSheet({
    super.key,
    required this.today,
    this.convertUrge = false,
    this.onLogged,
  });

  final HabitToday today;
  final bool convertUrge;

  /// Called once the relapse is saved.
  final VoidCallback? onLogged;

  @override
  ConsumerState<RelapseSheet> createState() => _RelapseSheetState();
}

class _RelapseSheetState extends ConsumerState<RelapseSheet> {
  final _note = TextEditingController();
  final _custom = TextEditingController();
  final Set<String> _triggers = {};
  final List<String> _customTags = [];
  bool _yesterday = false;
  late TimeOfDay _time;
  bool _saving = false;
  bool _addingCustom = false;

  /// Set once logged: the clean streak the relapse ended.
  int? _previous;

  @override
  void initState() {
    super.initState();
    _time = TimeOfDay.fromDateTime(ref.read(clockProvider).now());
  }

  @override
  void dispose() {
    _note.dispose();
    _custom.dispose();
    super.dispose();
  }

  HabitToday get t => widget.today;

  /// The clean run this relapse ends (today counts as clean so far).
  int get _endingRun {
    if (t.relapsedToday && !_yesterday) return 0;
    final c = t.streak.current - (_yesterday ? 2 : 1);
    return c < 0 ? 0 : c;
  }

  DateTime _at() {
    final now = ref.read(clockProvider).now();
    final day = _yesterday ? addDays(startOfDay(now), -1) : startOfDay(now);
    final at = DateTime(day.year, day.month, day.day, _time.hour, _time.minute);
    return at.isAfter(now) ? now : at;
  }

  void _addCustom() {
    final tag = cleanHabitLine(_custom.text);
    if (tag.isEmpty) {
      setState(() => _addingCustom = false);
      return;
    }
    final clipped = tag.length > habitTriggerMax
        ? tag.substring(0, habitTriggerMax)
        : tag;
    setState(() {
      final known = [...habitTriggerPresets, ..._customTags];
      final existing = known.firstWhere(
        (k) => k.toLowerCase() == clipped.toLowerCase(),
        orElse: () => '',
      );
      if (existing.isEmpty) _customTags.add(clipped);
      if (_triggers.length < habitTriggersMax) {
        _triggers.add(existing.isEmpty ? clipped : existing);
      }
      _custom.clear();
      _addingCustom = false;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Jam berapa?',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_custom.text.trim().isNotEmpty) _addCustom();
    setState(() => _saving = true);
    final at = _at();
    final input = RelapseInput(
      day: at,
      at: at,
      triggers: _triggers.toList(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final r = widget.convertUrge
        ? await ref.read(convertUrgeToRelapseProvider)(t.id, input)
        : await ref.read(logRelapseProvider)(t.id, input);
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        widget.onLogged?.call();
        HapticFeedback.lightImpact();
        setState(() {
          _saving = false;
          _previous = value.previousStreak;
        });
      case Err(:final failure):
        setState(() => _saving = false);
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prev = _previous;
    if (prev != null) return _Done(previous: prev);
    final g = context.ghina;
    final tags = [...habitTriggerPresets, ..._customTags];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MascotView(mood: MascotMood.happy, size: 64, animate: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nggak apa-apa, kita catat ya',
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    relapseSheetMessage(_endingRun),
                    key: const ValueKey('relapse-message'),
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        GhinaSpace.gapLg,
        const FieldLabel('Kapan?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!widget.convertUrge) ...[
              ChunkyChip(
                label: 'Hari ini',
                selected: !_yesterday,
                onTap: () => setState(() => _yesterday = false),
              ),
              ChunkyChip(
                label: 'Kemarin',
                selected: _yesterday,
                onTap: () => setState(() => _yesterday = true),
              ),
            ],
            ChunkyChip(
              key: const ValueKey('relapse-time'),
              label:
                  '${_time.hour.toString().padLeft(2, '0')}.${_time.minute.toString().padLeft(2, '0')}',
              icon: Icons.schedule_rounded,
              selected: false,
              onTap: _pickTime,
            ),
          ],
        ),
        GhinaSpace.gapLg,
        const FieldLabel('Apa pemicunya? (boleh lebih dari satu)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              ChunkyChip(
                key: ValueKey('trigger-$tag'),
                label: tag,
                selected: _triggers.contains(tag),
                color: GhinaColors.purple,
                onTap: () => setState(() {
                  if (!_triggers.remove(tag) &&
                      _triggers.length < habitTriggersMax) {
                    _triggers.add(tag);
                  }
                }),
              ),
            if (!_addingCustom)
              ChunkyChip(
                key: const ValueKey('trigger-add'),
                label: 'Lainnya',
                icon: Icons.add_rounded,
                selected: false,
                color: GhinaColors.purple,
                onTap: () => setState(() => _addingCustom = true),
              ),
          ],
        ),
        if (_addingCustom) ...[
          GhinaSpace.gapSm,
          ChunkyTextField(
            key: const ValueKey('trigger-custom'),
            controller: _custom,
            hint: 'Misal: habis gajian',
            autofocus: true,
            maxLength: habitTriggerMax,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addCustom(),
            suffix: IconButton(
              icon: const Icon(Icons.check_rounded),
              onPressed: _addCustom,
            ),
          ),
        ],
        GhinaSpace.gapLg,
        ChunkyTextField(
          key: const ValueKey('relapse-note'),
          controller: _note,
          label: 'Catatan (opsional)',
          hint: 'Apa yang kamu rasakan? Ini cuma buat kamu.',
          maxLines: 3,
          minLines: 2,
          maxLength: habitNoteMax,
        ),
        GhinaSpace.gapLg,
        ChunkyButton(
          key: const ValueKey('relapse-save'),
          label: 'Catat dengan jujur',
          color: GhinaColors.blue,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.previous});

  final int previous;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: MascotView(mood: MascotMood.waving, size: 110, animate: false),
        ),
        GhinaSpace.gapMd,
        Text(
          relapseDoneTitle(previous),
          key: const ValueKey('relapse-done'),
          textAlign: TextAlign.center,
          style: GhinaType.h2.copyWith(color: g.textPrimary),
        ),
        GhinaSpace.gapSm,
        Text(
          relapseDoneBody,
          textAlign: TextAlign.center,
          style: GhinaType.body.copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapXl,
        ChunkyButton(
          key: const ValueKey('relapse-ok'),
          label: 'Oke, lanjut',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
