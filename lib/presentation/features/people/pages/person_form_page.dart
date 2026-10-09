import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../reminders/reminder_actions.dart' show ensureReminderPermission;
import '../widgets/field_input.dart';
import '../widgets/people_widgets.dart' show SwitchRow;
import '../widgets/person_form_sheets.dart';

/// Create (`/people/new`) or edit (`/people/:id/edit`) a person — offline
/// first through sync. Notes are **not** part of this form (online-only, on
/// the detail screen).
class PersonFormPage extends ConsumerStatefulWidget {
  const PersonFormPage({super.key, this.id});

  final String? id;

  @override
  ConsumerState<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends ConsumerState<PersonFormPage> {
  final _text = <String, TextEditingController>{
    for (final k in _textKeys) k: TextEditingController(),
  };
  static const _textKeys = [
    'name',
    'fullName',
    'relation',
    'status',
    'howMet',
    'summary',
    'phone',
    'instagram',
    'email',
    'address',
    'organization',
    'day',
    'year',
    'tag',
  ];

  TextEditingController _c(String k) => _text[k]!;

  String _category = otherCategoryKey;
  PersonVibe _vibe = PersonVibe.unknown;
  PersonDataStatus _dataStatus = PersonDataStatus.sparse;
  bool _sensitive = false;
  int? _month;
  List<String> _tags = [];
  Map<String, Object?> _fields = {};
  List<PersonDateInput> _dates = [];
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider).now();

  void _fill(PersonDetail d) {
    if (_loaded) return;
    _loaded = true;
    final p = d.person;
    _c('name').text = p.name;
    _c('fullName').text = p.fullName ?? '';
    _c('relation').text = p.relation ?? '';
    _c('status').text = p.status ?? '';
    _c('howMet').text = p.howMet ?? '';
    _c('summary').text = p.summary ?? '';
    _c('phone').text = p.phone ?? '';
    _c('instagram').text = p.instagram ?? '';
    _c('email').text = p.email ?? '';
    _c('address').text = p.address ?? '';
    _c('organization').text = p.organization ?? '';
    _c('day').text = p.birthDay?.toString() ?? '';
    _c('year').text = p.birthYear?.toString() ?? '';
    _month = p.birthMonth;
    _category = p.category;
    _vibe = p.vibe;
    _dataStatus = p.dataStatus;
    _sensitive = p.sensitive;
    _tags = [...p.tags];
    _fields = {...p.fields};
    _dates = [for (final x in d.dates) PersonDateInput.of(x)];
  }

  void _addTag([String? raw]) {
    final t = (raw ?? _c('tag').text).trim().replaceAll(RegExp(r'^#+'), '');
    _c('tag').clear();
    if (t.isEmpty) return;
    if (_tags.any((x) => x.toLowerCase() == t.toLowerCase())) return;
    setState(() => _tags = [..._tags, t]);
  }

  PersonInput _input() {
    final dayText = _c('day').text.trim();
    final yearText = _c('year').text.trim();
    return PersonInput(
      name: _c('name').text,
      fullName: _c('fullName').text,
      category: _category,
      relation: _c('relation').text,
      vibe: _vibe,
      status: _c('status').text,
      howMet: _c('howMet').text,
      summary: _c('summary').text,
      // An unparsable number is passed as an out-of-range value so the rules
      // report it instead of silently dropping what was typed.
      birthYear: yearText.isEmpty ? null : (int.tryParse(yearText) ?? -1),
      birthMonth: _month,
      birthDay: dayText.isEmpty ? null : (int.tryParse(dayText) ?? -1),
      phone: _c('phone').text,
      instagram: _c('instagram').text,
      email: _c('email').text,
      address: _c('address').text,
      organization: _c('organization').text,
      dataStatus: _dataStatus,
      sensitive: _sensitive,
      tags: _tags,
      fields: _fields,
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    // The tag being typed counts.
    if (_c('tag').text.trim().isNotEmpty) _addTag();
    final input = _input();
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final r = await ref.read(savePersonProvider)(
      id: widget.id,
      input: input,
      dates: _dates,
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        if (value.hasBirthday || _dates.isNotEmpty) {
          await ensureReminderPermission(context, ref);
          if (!mounted) return;
        }
        showOkToast(
          context,
          _isEdit ? 'Perubahan tersimpan 👍' : '${value.name} tersimpan 🙌',
        );
        popOr(context, '/people');
      case Err(:final failure):
        HapticFeedback.heavyImpact();
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(:final field?)) {
            _errors = {field: failure.message};
          }
        });
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete(Person p) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus ${p.name}?',
      message:
          'Datanya, tanggal pentingnya, dan catatannya akan dihapus dari '
          'semua perangkat.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deletePersonProvider)(p.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: '${p.name} dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        context.goBackToList();
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _editDate(int? index) async {
    final r = await showPersonDateSheet(
      context,
      existing: index == null ? null : _dates[index],
      currentYear: _now.year,
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r.delete && index != null) {
        _dates = [..._dates]..removeAt(index);
      } else if (r.input != null) {
        if (index == null) {
          _dates = [..._dates, r.input!];
        } else {
          _dates = [..._dates]..[index] = r.input!;
        }
      }
    });
  }

  Future<void> _addField() async {
    final def = await showAddFieldSheet(context);
    if (def == null || !mounted) return;
    showOkToast(context, 'Kolom "${def.label}" dibuat');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    PersonDetail? detail;
    Widget body;
    if (_isEdit) {
      final async = ref.watch(watchPersonDetailProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          detail = value;
          body = _form();
        case AsyncData():
          body = EmptyState(
            title: 'Orang ini nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Kembali',
            onAction: () => popOr(context, '/people'),
          );
        case AsyncError():
          body = ErrorRetry(
            onRetry: () =>
                ref.invalidate(watchPersonDetailProvider(widget.id!)),
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
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah orang' : 'Orang baru'),
        actions: [
          if (detail != null)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(detail!.person),
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
                key: const ValueKey('person-save'),
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
    int max = 200,
    IconData? icon,
    TextInputType? type,
    TextCapitalization caps = TextCapitalization.sentences,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ChunkyTextField(
      key: ValueKey('person-$key'),
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

  Widget _form() {
    final cats = ref.watch(watchPersonCategoriesProvider).value ?? const [];
    final allDefs = ref.watch(watchPersonFieldsProvider).value ?? const [];
    final allTagSuggestions = allTags(
      ref.watch(watchPeopleOverviewProvider).value?.people ?? const [],
    );
    final defs = defsFor(allDefs, _category);
    final categoryOptions = [
      for (final c in cats)
        ChunkyChoice(value: c.key, label: '${c.emoji} ${c.label}'),
      if (!cats.any((c) => c.key == otherCategoryKey))
        const ChunkyChoice(value: otherCategoryKey, label: '👤 Lainnya'),
      if (_category != otherCategoryKey && !cats.any((c) => c.key == _category))
        ChunkyChoice(value: _category, label: prettifyKey(_category)),
    ];
    final suggestions = [
      for (final t in allTagSuggestions)
        if (!_tags.any((x) => x.toLowerCase() == t.toLowerCase())) t,
    ].take(8);
    return ListView(
      // A long form: keep every field built so focusing one (which scrolls
      // it to the top) never tears down the others.
      scrollCacheExtent: const ScrollCacheExtent.pixels(6000),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        12,
        GhinaSpace.page,
        32,
      ),
      children: [
        _field(
          'name',
          'Nama',
          hint: 'mis. Budi Contoh',
          max: personNameMax,
          icon: Icons.person_rounded,
        ),
        _field('fullName', 'Nama lengkap (opsional)', max: personFullNameMax),
        const FieldLabel('Kategori'),
        ChunkyChoiceChips<String>(
          key: const ValueKey('person-category'),
          options: categoryOptions,
          selected: {_category},
          onChanged: (s) => setState(() => _category = s.first),
        ),
        if (_errors['category'] != null) _errorText(_errors['category']!),
        const SizedBox(height: 14),
        _field(
          'relation',
          'Hubungan',
          hint: 'mis. Ayah, Rekan kerja',
          max: personRelationMax,
        ),
        const FieldLabel('Kesan'),
        ChunkyChoiceChips<PersonVibe>(
          key: const ValueKey('person-vibe'),
          options: [
            for (final v in PersonVibe.values)
              ChunkyChoice(value: v, label: '${v.emoji} ${v.label}'),
          ],
          selected: {_vibe},
          onChanged: (s) => setState(() => _vibe = s.first),
        ),
        const SizedBox(height: 14),
        _field(
          'summary',
          'Ringkasan',
          hint: 'Satu baris konteks',
          max: personSummaryMax,
          lines: 2,
        ),
        _field('status', 'Status', max: personStatusMax),
        _field('howMet', 'Kenal dari', max: personHowMetMax),
        _birthdaySection(),
        _field(
          'phone',
          'Telepon',
          max: personPhoneMax,
          icon: Icons.phone_rounded,
          type: TextInputType.phone,
        ),
        _field(
          'instagram',
          'Instagram',
          max: personInstagramMax,
          icon: Icons.alternate_email_rounded,
          caps: TextCapitalization.none,
        ),
        _field(
          'email',
          'Email',
          max: personEmailMax,
          icon: Icons.mail_rounded,
          type: TextInputType.emailAddress,
          caps: TextCapitalization.none,
        ),
        _field('organization', 'Organisasi', max: personOrganizationMax),
        _field('address', 'Alamat', max: personAddressMax, lines: 2),
        const FieldLabel('Kelengkapan data'),
        ChunkyChoiceChips<PersonDataStatus>(
          options: [
            for (final s in PersonDataStatus.values)
              ChunkyChoice(value: s, label: s.label),
          ],
          selected: {_dataStatus},
          onChanged: (s) => setState(() => _dataStatus = s.first),
        ),
        const SizedBox(height: 14),
        ChunkyCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: SwitchRow(
            key: const ValueKey('person-sensitive'),
            title: 'Catatan sensitif',
            subtitle:
                'Catatannya disembunyikan sampai kamu menekan "Tampilkan".',
            value: _sensitive,
            onChanged: (v) => setState(() => _sensitive = v),
          ),
        ),
        const SizedBox(height: 20),
        _tagsSection(suggestions),
        const SizedBox(height: 20),
        _fieldsSection(defs),
        const SizedBox(height: 20),
        _datesSection(),
      ],
    );
  }

  Widget _errorText(String t) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      t,
      style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
    ),
  );

  Widget _birthdaySection() {
    final g = context.ghina;
    final err = _errors['birthday'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel('Ulang tahun', error: err != null),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ChunkyTextField(
                  key: const ValueKey('person-day'),
                  hint: 'Tgl',
                  controller: _c('day'),
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _MonthButton(
                  month: _month,
                  onTap: () async {
                    final m = await pickMonth(context, current: _month);
                    if (m != null) setState(() => _month = m == 0 ? null : m);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyTextField(
                  key: const ValueKey('person-year'),
                  hint: 'Tahun',
                  controller: _c('year'),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          if (err != null)
            _errorText(err)
          else
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Boleh sebagian: bulan saja, tanggal + bulan, atau tahun saja. '
                'Pengingat butuh tanggal dan bulan.',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tagsSection(Iterable<String> suggestions) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Tag', error: _errors['tags'] != null),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              key: const ValueKey('person-tag-list'),
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
          key: const ValueKey('person-tag'),
          hint: 'Ketik tag lalu tekan Enter',
          controller: _c('tag'),
          maxLength: personTagMax,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.done,
          onSubmitted: _addTag,
          suffix: IconButton(
            tooltip: 'Tambah tag',
            icon: const Icon(Icons.add_circle_rounded),
            onPressed: _addTag,
          ),
        ),
        if (_errors['tags'] != null) _errorText(_errors['tags']!),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in suggestions)
                ActionChip(
                  label: Text('#$t'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addTag(t),
                ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Maks $personTagsMax tag.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _fieldsSection(List<PersonFieldDef> defs) {
    final err = _errors['fields'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Kolom khusus', error: err != null),
        if (defs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Belum ada kolom untuk kategori ini. Tambah sendiri: ukuran '
              'sepatu, hobi, golongan darah…',
              style: GhinaType.bodyS.copyWith(
                color: context.ghina.textSecondary,
              ),
            ),
          ),
        for (final d in defs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CustomFieldInput(
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
        if (err != null) _errorText(err),
        ChunkyButton(
          key: const ValueKey('add-field'),
          label: 'Tambah kolom',
          size: ChunkyButtonSize.small,
          expand: false,
          variant: ChunkyButtonVariant.outline,
          icon: Icons.add_rounded,
          onPressed: _addField,
        ),
      ],
    );
  }

  Widget _datesSection() {
    final g = context.ghina;
    final err =
        _errors['label'] ?? _errors['date'] ?? _errors['remindDaysBefore'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Tanggal penting', error: err != null),
        for (final (i, d) in _dates.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              key: ValueKey('date-tile-$i'),
              dense: true,
              leading: Text(
                d.kind.eventKind.emoji,
                style: const TextStyle(fontSize: 22),
              ),
              title: d.label,
              subtitle:
                  '${formatDayMonth(d.month, d.day, d.year)}'
                  '${d.remindDaysBefore == null ? '' : ' · ingatkan ${d.remindDaysBefore} hari sebelumnya'}',
              trailing: Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
              onTap: () => _editDate(i),
            ),
          ),
        if (err != null) _errorText(err),
        ChunkyButton(
          key: const ValueKey('add-date'),
          label: 'Tambah tanggal penting',
          size: ChunkyButtonSize.small,
          expand: false,
          variant: ChunkyButtonVariant.outline,
          icon: Icons.event_rounded,
          onPressed: () => _editDate(null),
        ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({required this.month, required this.onTap});

  final int? month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkySurface(
      key: const ValueKey('person-month'),
      color: g.surfaceAlt,
      edgeColor: g.border,
      borderColor: g.border,
      depth: 0,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      semanticLabel: 'Bulan lahir',
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              month == null ? 'Bulan' : monthNameId(month!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyL
                  .w(700)
                  .copyWith(color: month == null ? g.textMuted : g.textPrimary),
            ),
          ),
          Icon(Icons.expand_more_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}

extension on BuildContext {
  void goBackToList() => popOr(this, '/people');
}
