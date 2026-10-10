import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_field_input.dart';
import 'dream_form_lists.dart';
import 'dream_form_metric_sheet.dart';
import 'dream_form_models.dart';
import 'dream_form_sheets.dart';
import 'dream_form_step_sheet.dart';
import 'dream_form_target.dart';
import 'dream_target_input.dart';

/// Create (`/dreams/new`) or edit (`/dreams/:id/edit`) a dream. Steps and
/// metrics are edited in memory and written right after the dream itself; all
/// of it is offline first through sync.
class DreamFormPage extends ConsumerStatefulWidget {
  const DreamFormPage({super.key, this.id});

  final String? id;

  @override
  ConsumerState<DreamFormPage> createState() => _DreamFormPageState();
}

class _DreamFormPageState extends ConsumerState<DreamFormPage> {
  static const _textKeys = [
    'title',
    'emoji',
    'condition',
    'why',
    'summary',
    'costEstimate',
    'costNote',
    'tag',
  ];
  final _text = <String, TextEditingController>{
    for (final k in _textKeys) k: TextEditingController(),
  };
  TextEditingController _c(String k) => _text[k]!;

  String _category = 'other';
  DreamStatus _status = DreamStatus.idea;
  int? _priority;
  DreamHorizon? _horizon;
  DreamTargetValue _target = (
    date: null,
    precision: TargetPrecision.day,
    error: null,
  );
  int? _progress;
  String? _noteId;
  String? _parentId;
  List<String> _tags = [];
  Map<String, Object?> _fields = {};
  List<StepDraft> _steps = [];
  List<MetricDraft> _metrics = [];
  final _removedSteps = <String>[];
  final _removedMetrics = <String>[];

  /// The stored dream (edit): carries what the form does not show.
  Dream? _original;

  /// Set once the dream row exists, so a retry after a failed child updates.
  String? _createdId;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;
  String? get _dreamId => widget.id ?? _createdId;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider).now();

  void _fill(DreamLocalDetail d) {
    if (_loaded) return;
    _loaded = true;
    final x = d.dream;
    _original = x;
    _c('title').text = x.title;
    _c('emoji').text = x.emoji ?? '';
    _c('condition').text = x.condition ?? '';
    _c('why').text = x.why ?? '';
    _c('summary').text = x.summary ?? '';
    _c('costEstimate').text = x.costEstimate == null
        ? ''
        : (x.costEstimate! == x.costEstimate!.roundToDouble()
              ? x.costEstimate!.toInt().toString()
              : '${x.costEstimate}');
    _c('costNote').text = x.costNote ?? '';
    _category = x.category;
    _status = x.status;
    _priority = x.priority;
    _horizon = x.horizon;
    _target = (date: x.targetDate, precision: x.targetPrecision, error: null);
    _progress = x.progressManual;
    _noteId = x.noteId;
    _parentId = x.parentId;
    _tags = [...x.tags];
    _fields = {...x.fields};
    _steps = [for (final s in d.steps) StepDraft.of(s)];
    _metrics = [for (final m in d.metrics) MetricDraft.of(m)];
  }

  void _addTag([String? raw]) {
    final text = raw ?? _c('tag').text;
    _c('tag').clear();
    final next = addDreamTag(_tags, text);
    if (next.length != _tags.length) setState(() => _tags = next);
  }

  /// Form-side checks that need no use case: the obvious empties and bad
  /// numbers. The use cases still validate everything on save.
  Map<String, String> _localErrors() {
    final e = <String, String>{};
    if (_c('title').text.trim().isEmpty) e['title'] = 'Judulnya diisi dulu ya';
    final cost = _c('costEstimate').text.trim();
    if (cost.isNotEmpty && parseDreamAmount(cost) == null) {
      e['costEstimate'] = 'Estimasi biaya harus berupa angka';
    }
    if (_target.error != null) e['targetDate'] = _target.error!;
    return e;
  }

  DreamInput _input() {
    final o = _original;
    final cost = _c('costEstimate').text.trim();
    final defs = ref.read(watchDreamFieldsProvider).value ?? const [];
    final shown = {
      for (final d in defs)
        if (d.appliesToCategory(_category)) d.key,
    };
    String? text(String k) {
      final t = _c(k).text.trim();
      return t.isEmpty ? null : t;
    }

    return DreamInput(
      title: _c('title').text,
      emoji: text('emoji'),
      category: _category,
      status: _status,
      priority: _priority,
      horizon: _horizon,
      targetDate: _target.date,
      targetPrecision: _target.precision,
      condition: text('condition'),
      why: text('why'),
      summary: text('summary'),
      costEstimate: cost.isEmpty ? null : parseDreamAmount(cost),
      costNote: text('costNote'),
      progressManual: _progress,
      startedAt: o?.startedAt,
      completedAt: o?.completedAt,
      noteId: _noteId,
      parentId: _parentId,
      tags: _tags,
      fields: {
        for (final e in _fields.entries)
          if (shown.contains(e.key)) e.key: e.value,
      },
      links: o?.links ?? DreamLinks.empty,
      sortOrder: o?.sortOrder ?? 0,
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    // The tag being typed counts.
    if (_c('tag').text.trim().isNotEmpty) _addTag();
    final local = _localErrors();
    if (local.isNotEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _errors = local);
      showErrorToast(context, 'Ada yang perlu dibenahi dulu');
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final input = _input();
    final existingId = _dreamId;
    final r = existingId == null
        ? await ref.read(createDreamProvider)(input)
        : await ref.read(updateDreamProvider)(existingId, input);
    if (!mounted) return;
    switch (r) {
      case Err(:final failure):
        _fail(failure);
        return;
      case Ok(:final value):
        _createdId = value.id;
        final children = await _saveChildren(value.id);
        if (!mounted) return;
        if (children != null) {
          _fail(children);
          return;
        }
        showOkToast(
          context,
          _isEdit ? 'Perubahan tersimpan 👍' : '${value.title} tersimpan 🙌',
        );
        popOr(context, _isEdit ? '/dreams/${value.id}' : '/dreams');
    }
  }

  /// Writes the metrics, then the steps (they may point at a metric), then
  /// the order. Returns the first failure, or null. Every draft carries its
  /// own id, so running this again after a failure only updates.
  Future<Failure?> _saveChildren(String dreamId) async {
    for (final id in [..._removedSteps]) {
      final r = await ref.read(deleteDreamStepProvider)(id);
      if (r case Err(:final failure)) return failure;
      _removedSteps.remove(id);
    }
    for (final id in [..._removedMetrics]) {
      final r = await ref.read(deleteDreamMetricProvider)(id);
      if (r case Err(:final failure)) return failure;
      _removedMetrics.remove(id);
    }
    for (final m in _metrics) {
      final r = await ref.read(saveDreamMetricProvider)(
        dreamId: dreamId,
        id: m.id,
        input: m.toInput(),
      );
      if (r case Err(:final failure)) {
        return _scoped(failure, 'metrics', 'Metrik "${m.label}"');
      }
    }
    for (final s in _steps) {
      final r = await ref.read(saveDreamStepProvider)(
        dreamId: dreamId,
        id: s.id,
        input: s.toInput(),
      );
      if (r case Err(:final failure)) {
        return _scoped(failure, 'steps', 'Langkah "${s.title}"');
      }
    }
    if (_steps.length > 1) {
      final r = await ref.read(reorderDreamStepsProvider)(
        dreamId: dreamId,
        orderedIds: [for (final s in _steps) s.id],
      );
      if (r case Err(:final failure)) return failure;
    }
    return null;
  }

  /// A child's validation message, tied to the steps / metrics section.
  Failure _scoped(Failure f, String field, String what) =>
      f is ValidationFailure
      ? ValidationFailure('$what: ${f.message}', field: field)
      : f;

  void _fail(Failure failure) {
    HapticFeedback.heavyImpact();
    setState(() {
      _saving = false;
      if (failure case ValidationFailure(:final field?)) {
        _errors = {field: failure.message};
      }
    });
    showFailureToast(context, failure);
  }

  // ---------------------------------------------------------------- pickers

  Future<void> _pickNote() async {
    final r = await showDreamNoteSheet(context, selectedId: _noteId);
    if (r == null || !mounted) return;
    setState(() => _noteId = r.isEmpty ? null : r);
  }

  Future<void> _pickParent(List<Dream> all) async {
    final self = _dreamId;
    final parentOf = {for (final d in all) d.id: d.parentId};
    final options = [
      for (final d in all)
        if (self == null ||
            (d.id != self && !wouldCreateDreamCycle(self, d.id, parentOf)))
          d,
    ];
    final r = await showDreamPickSheet<String>(
      context,
      title: 'Pilih mimpi induk',
      noneLabel: 'Tanpa induk',
      selected: _parentId,
      items: [
        for (final d in options)
          DreamPickItem(value: d.id, title: d.title, leading: d.emoji),
      ],
      emptyMessage: 'Belum ada mimpi lain.',
    );
    if (r == null || !mounted) return;
    setState(() => _parentId = r.value);
  }

  // ------------------------------------------------------- steps and metrics

  Future<void> _editStep(int? index) async {
    final r = await showDreamStepSheet(
      context,
      existing: index == null ? null : _steps[index],
      metrics: _metrics,
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r.delete && index != null) {
        final gone = _steps[index];
        if (gone.persisted) _removedSteps.add(gone.id);
        _steps = [..._steps]..removeAt(index);
      } else if (r.draft != null) {
        if (index == null) {
          _steps = [..._steps, r.draft!];
        } else {
          _steps = [..._steps]..[index] = r.draft!;
        }
      }
    });
  }

  void _reorderSteps(int oldIndex, int newIndex) {
    setState(() {
      final list = [..._steps];
      list.insert(newIndex, list.removeAt(oldIndex));
      _steps = list;
    });
  }

  Future<void> _editMetric(int? index) async {
    final r = await showDreamMetricSheet(
      context,
      existing: index == null ? null : _metrics[index],
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r.delete && index != null) {
        final gone = _metrics[index];
        if (gone.persisted) _removedMetrics.add(gone.id);
        _metrics = [..._metrics]..removeAt(index);
        // A step hanging on the metric loses the link with it.
        _steps = [
          for (final s in _steps)
            s.metricRef == gone.id
                ? StepDraft(
                    id: s.id,
                    title: s.title,
                    notes: s.notes,
                    done: s.done,
                    dueDate: s.dueDate,
                    cost: s.cost,
                    reward: s.reward,
                    persisted: s.persisted,
                  )
                : s,
        ];
      } else if (r.draft != null) {
        if (index == null) {
          _metrics = [..._metrics, r.draft!];
        } else {
          _metrics = [..._metrics]..[index] = r.draft!;
        }
      }
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget body;
    if (_isEdit) {
      final async = ref.watch(watchDreamLocalDetailProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          body = _form();
        case AsyncData():
          body = EmptyState(
            title: 'Mimpi ini nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Kembali',
            onAction: () => popOr(context, '/dreams'),
          );
        case AsyncError():
          body = ErrorRetry(
            onRetry: () =>
                ref.invalidate(watchDreamLocalDetailProvider(widget.id!)),
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
    final showSave = !_isEdit || _loaded;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: Text(_isEdit ? 'Ubah mimpi' : 'Mimpi baru')),
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
                key: const ValueKey('dream-save'),
                label: 'Simpan',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            )
          : null,
    );
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    int? max,
    IconData? icon,
    TextInputType? type,
    int lines = 1,
    TextCapitalization caps = TextCapitalization.sentences,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ChunkyTextField(
      key: ValueKey('dream-$key'),
      label: label,
      hint: hint,
      controller: _c(key),
      errorText: _errors[key],
      maxLength: max,
      prefixIcon: icon,
      keyboardType: type,
      textCapitalization: caps,
      minLines: lines > 1 ? lines : null,
      maxLines: lines,
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 12),
    child: Text(
      text,
      style: GhinaType.h3.copyWith(color: context.ghina.textPrimary),
    ),
  );

  Widget _form() {
    final cats = ref.watch(watchDreamCategoriesProvider).value ?? const [];
    final allDefs = ref.watch(watchDreamFieldsProvider).value ?? const [];
    final dreams = ref.watch(watchDreamsProvider).value ?? const <Dream>[];
    final defs = [
      for (final d in allDefs)
        if (d.appliesToCategory(_category)) d,
    ];
    final categoryOptions = [
      for (final c in cats)
        ChunkyChoice(value: c.key, label: '${c.emoji} ${c.label}'),
      if (!cats.any((c) => c.key == 'other'))
        const ChunkyChoice(value: 'other', label: '✨ Lainnya'),
      if (_category != 'other' && !cats.any((c) => c.key == _category))
        ChunkyChoice(value: _category, label: _category),
    ];
    final parent = dreams.where((d) => d.id == _parentId).firstOrNull;
    final parentName = _parentId == null
        ? null
        : (parent?.title ?? 'Mimpi tidak ditemukan');
    return ListView(
      // A long form: keep every field built so focusing one (which scrolls it
      // to the top) never tears down the others.
      scrollCacheExtent: const ScrollCacheExtent.pixels(9000),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        12,
        GhinaSpace.page,
        32,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: _field(
                'emoji',
                'Emoji',
                hint: '🌟',
                max: dreamEmojiMax,
                caps: TextCapitalization.none,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'title',
                'Judul mimpi',
                hint: 'mis. Trip contoh ke Kota Sample',
                max: dreamTitleMax,
              ),
            ),
          ],
        ),
        FieldLabel('Kategori', error: _errors['category'] != null),
        ChunkyChoiceChips<String>(
          key: const ValueKey('dream-category'),
          options: categoryOptions,
          selected: {_category},
          onChanged: (s) => setState(() => _category = s.first),
        ),
        if (_errors['category'] != null) DreamFormError(_errors['category']!),
        const SizedBox(height: 14),
        const FieldLabel('Status'),
        ChunkyChoiceChips<DreamStatus>(
          key: const ValueKey('dream-status'),
          options: [
            for (final s in DreamStatus.values)
              ChunkyChoice(value: s, label: '${s.emoji} ${s.label}'),
          ],
          selected: {_status},
          onChanged: (s) => setState(() => _status = s.first),
        ),
        const SizedBox(height: 14),
        FieldLabel(
          'Prioritas (1 = paling penting)',
          error: _errors['priority'] != null,
        ),
        ChunkyChoiceChips<int>(
          key: const ValueKey('dream-priority'),
          allowEmpty: true,
          options: [
            for (var p = dreamPriorityMin; p <= dreamPriorityMax; p++)
              ChunkyChoice(value: p, label: '$p'),
          ],
          selected: {?_priority},
          onChanged: (s) => setState(() => _priority = s.firstOrNull),
        ),
        if (_errors['priority'] != null) DreamFormError(_errors['priority']!),
        _heading('Kapan'),
        const FieldLabel('Rentang waktu'),
        ChunkyChoiceChips<DreamHorizon>(
          key: const ValueKey('dream-horizon'),
          allowEmpty: true,
          options: [
            for (final h in DreamHorizon.values)
              ChunkyChoice(value: h, label: h.label),
          ],
          selected: {?_horizon},
          onChanged: (s) => setState(() => _horizon = s.firstOrNull),
        ),
        const SizedBox(height: 14),
        DreamTargetSection(
          key: const ValueKey('dream-target'),
          initialDate: _target.date,
          initialPrecision: _target.precision,
          today: _now,
          errorText: _errors['targetDate'],
          onChanged: (v) => setState(() {
            _target = v;
            _errors = {..._errors}..remove('targetDate');
          }),
        ),
        _heading('Cerita'),
        _field(
          'condition',
          'Syarat',
          hint: 'Apa yang harus terpenuhi dulu?',
          max: dreamConditionMax,
          lines: 2,
        ),
        _field(
          'why',
          'Alasan',
          hint: 'Kenapa ini penting buatmu?',
          max: dreamWhyMax,
          lines: 3,
        ),
        _field(
          'summary',
          'Ringkasan',
          hint: 'Gambaran singkat',
          max: dreamSummaryMax,
          lines: 3,
        ),
        _heading('Biaya'),
        _field(
          'costEstimate',
          'Estimasi biaya (Rp)',
          hint: 'mis. 15.000.000',
          icon: Icons.payments_rounded,
          type: const TextInputType.numberWithOptions(decimal: true),
        ),
        _field(
          'costNote',
          'Catatan biaya',
          hint: 'mis. belum termasuk tiket',
          max: dreamCostNoteMax,
          lines: 2,
        ),
        _heading('Progres'),
        _progressSection(),
        _heading('Tag'),
        _tagsSection(),
        if (defs.isNotEmpty || _errors['fields'] != null) ...[
          _heading('Kolom khusus'),
          _fieldsSection(defs),
        ],
        _heading('Tautan'),
        PickerField(
          key: const ValueKey('dream-note-picker'),
          label: 'Catatan',
          value: _noteId == null ? null : _noteTitle(),
          placeholder: 'Hubungkan catatan',
          errorText: _errors['noteId'],
          trailingIcon: Icons.sticky_note_2_rounded,
          onTap: _pickNote,
        ),
        const SizedBox(height: 14),
        PickerField(
          key: const ValueKey('dream-parent-picker'),
          label: 'Mimpi induk',
          value: parentName,
          placeholder: 'Tanpa induk',
          errorText: _errors['parentId'],
          trailingIcon: Icons.account_tree_rounded,
          onTap: () => _pickParent(dreams),
        ),
        _heading('Langkah'),
        DreamStepsEditor(
          steps: _steps,
          metrics: _metrics,
          errorText: _errors['steps'],
          onAdd: () => _editStep(null),
          onEdit: _editStep,
          onToggle: (i) => setState(
            () =>
                _steps = [..._steps]
                  ..[i] = _steps[i].copyWith(done: !_steps[i].done),
          ),
          onReorder: _reorderSteps,
        ),
        _heading('Metrik'),
        DreamMetricsEditor(
          metrics: _metrics,
          errorText: _errors['metrics'],
          onAdd: () => _editMetric(null),
          onEdit: _editMetric,
        ),
      ],
    );
  }

  /// Title of the linked note (the notes list is only read when there is one).
  String _noteTitle() {
    final notes = ref.watch(watchNotesProvider(NoteFilter.all)).value;
    final hit = notes?.where((n) => n.id == _noteId).firstOrNull;
    return hit?.note.displayTitle ?? 'Catatan tertaut';
  }

  Widget _progressSection() {
    final g = context.ghina;
    final manual = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                manual == null ? 'Otomatis' : '$manual%',
                key: const ValueKey('dream-progress-value'),
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
            ),
            if (manual == null)
              ChunkyButton(
                key: const ValueKey('dream-progress-manual'),
                label: 'Atur manual',
                size: ChunkyButtonSize.small,
                expand: false,
                variant: ChunkyButtonVariant.outline,
                onPressed: () => setState(() => _progress = 50),
              )
            else
              ChunkyButton(
                key: const ValueKey('dream-progress-auto'),
                label: 'Otomatis',
                size: ChunkyButtonSize.small,
                expand: false,
                variant: ChunkyButtonVariant.outline,
                icon: Icons.auto_awesome_rounded,
                onPressed: () => setState(() => _progress = null),
              ),
          ],
        ),
        if (manual != null)
          Slider(
            key: const ValueKey('dream-progress-slider'),
            value: manual.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$manual%',
            onChanged: (v) => setState(() => _progress = v.round()),
          ),
        Text(
          manual == null
              ? 'Progres dihitung dari langkah dan metrik.'
              : 'Angka ini menggantikan progres hitungan dari langkah dan '
                    'metrik. Pilih "Otomatis" untuk kembali ke hitungan.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        if (_errors['progressManual'] != null)
          DreamFormError(_errors['progressManual']!),
      ],
    );
  }

  Widget _tagsSection() {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              key: const ValueKey('dream-tag-list'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _tags)
                  InputChip(
                    label: Text('#$t'),
                    onDeleted: () =>
                        setState(() => _tags = [..._tags]..remove(t)),
                  ),
              ],
            ),
          ),
        ChunkyTextField(
          key: const ValueKey('dream-tag'),
          hint: 'Ketik tag lalu tekan Enter',
          controller: _c('tag'),
          maxLength: dreamTagMax,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.done,
          onSubmitted: _addTag,
          suffix: IconButton(
            tooltip: 'Tambah tag',
            icon: const Icon(Icons.add_circle_rounded),
            onPressed: _addTag,
          ),
        ),
        if (_errors['tags'] != null) DreamFormError(_errors['tags']!),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Maks $dreamTagsMax tag.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _fieldsSection(List<DreamFieldDef> defs) {
    final err = _errors['fields'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in defs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DreamFieldInput(
              // Re-created when the def changes so its text follows.
              key: ValueKey('${d.id}-${d.type.wire}'),
              def: d,
              value: _fields[d.key],
              today: _now,
              onChanged: (v) => setState(() {
                if (v == null) {
                  _fields = {..._fields}..remove(d.key);
                } else {
                  _fields = {..._fields, d.key: v};
                }
              }),
            ),
          ),
        if (err != null) DreamFormError(err),
      ],
    );
  }
}
