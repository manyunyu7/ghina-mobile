import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../people/widgets/people_widgets.dart' show SwitchRow;
import '../lock/habit_lock_gate.dart';

/// Indonesian name of a `appliesTo` scope.
String habitScopeLabel(String scope) => switch (scope) {
  'done' => 'Selesai / bersih',
  'skip' => 'Libur',
  'relapse' => 'Kambuh',
  'urge' => 'Godaan',
  'journal' => 'Jurnal',
  'milestone' => 'Pencapaian',
  'event' => 'Kejadian',
  _ => scope,
};

/// `/habits/fields?habit=`: the user's dimensions (per-event columns such as
/// "Tingkat stres") — list, add, rename, change where they show, reorder and
/// delete. Deleting strips the key from every log and event, so it warns first.
class HabitFieldsPage extends StatelessWidget {
  const HabitFieldsPage({super.key, this.habitId});

  /// When set, shows the dimensions that apply to this habit and new ones can
  /// be scoped to it.
  final String? habitId;

  @override
  Widget build(BuildContext context) =>
      HabitLockGate(child: _FieldsView(habitId: habitId));
}

class _FieldsView extends ConsumerWidget {
  const _FieldsView({this.habitId});

  final String? habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(watchHabitFieldsProvider);
    final habit = habitId == null
        ? null
        : ref.watch(watchHabitTodayProvider(habitId!)).value?.habit;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Dimensi'),
        actions: [
          IconButton(
            key: const ValueKey('dim-add'),
            tooltip: 'Dimensi baru',
            icon: const Icon(Icons.add_circle_rounded),
            onPressed: () => _add(context, habit),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            8,
            GhinaSpace.page,
            32,
          ),
          children: [
            Text(
              'Dimensi adalah kolom tambahan untuk tiap catatan, misalnya '
              '"Tingkat stres" (skala 1–10) atau "Suasana". Isinya muncul di '
              'form kambuh, godaan dan kejadian.',
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: 16),
            switch (async) {
              AsyncData(:final value) => _list(
                context,
                ref,
                habitId == null ? value : fieldsForHabit(value, habitId!),
                habit,
              ),
              AsyncError() => ErrorRetry(
                onRetry: () => ref.invalidate(watchHabitFieldsProvider),
              ),
              _ => const SkeletonList(count: 3),
            },
          ],
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<HabitFieldDef> defs,
    Habit? habit,
  ) {
    final g = context.ghina;
    if (defs.isEmpty) {
      return Text(
        'Belum ada dimensi. Ketuk + untuk membuat yang pertama.',
        key: const ValueKey('dim-empty'),
        style: GhinaType.body.copyWith(color: g.textSecondary),
      );
    }
    return ReorderableListView.builder(
      key: const ValueKey('dim-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: defs.length,
      onReorderItem: (from, to) async {
        final ids = [for (final d in defs) d.id];
        ids.insert(to, ids.removeAt(from));
        final r = await ref.read(reorderHabitFieldsProvider)(ids);
        if (!context.mounted) return;
        if (r case Err(:final failure)) showFailureToast(context, failure);
      },
      itemBuilder: (_, i) {
        final d = defs[i];
        final where = d.appliesTo == null || d.appliesTo!.isEmpty
            ? 'kambuh, godaan, kejadian'
            : d.appliesTo!.map(habitScopeLabel).join(', ');
        return Padding(
          key: ValueKey('dim-${d.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            dense: true,
            leading: Icon(Icons.tune_rounded, color: g.textSecondary),
            title: d.label,
            subtitle:
                '${d.type.label} · '
                '${d.habitId == null ? 'semua kebiasaan' : 'satu kebiasaan'}'
                ' · $where',
            trailing: Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
            onTap: () => _edit(context, ref, d),
          ),
        );
      },
    );
  }

  Future<void> _add(BuildContext context, Habit? habit) =>
      showChunkyBottomSheet<HabitFieldDef>(
        context,
        title: 'Dimensi baru',
        showClose: true,
        builder: (_) => _AddFieldForm(habit: habit),
      );

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    HabitFieldDef d,
  ) async {
    final r = await showChunkyBottomSheet<_EditResult>(
      context,
      title: 'Ubah dimensi',
      showClose: true,
      builder: (_) => _EditFieldSheet(def: d),
    );
    if (r == null || !context.mounted) return;
    if (r.delete) return _delete(context, ref, d);
    final res = await ref.read(updateHabitFieldProvider)(
      d.id,
      label: r.label,
      appliesTo: r.appliesTo,
      clearAppliesTo: r.appliesTo == null || r.appliesTo!.isEmpty,
    );
    if (!context.mounted) return;
    if (res case Err(:final failure)) showFailureToast(context, failure);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    HabitFieldDef d,
  ) async {
    final usage = await ref.read(countHabitFieldUsageProvider)(d.id);
    if (!context.mounted) return;
    final u = usage.valueOrNull;
    final used = u == null ? 0 : u.logs + u.events;
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus dimensi "${d.label}"?',
      message: used == 0
          ? 'Belum ada catatan yang memakainya.'
          : 'Isinya akan dihapus dari $used catatan '
                '(${u!.logs} catatan harian, ${u.events} kejadian). '
                'Ini tidak bisa dibatalkan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final r = await ref.read(deleteHabitFieldProvider)(d.id);
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Dimensi dihapus');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }
}

typedef _EditResult = ({String? label, List<String>? appliesTo, bool delete});

/// Where a dimension shows: chips for each scope; none selected = the default
/// (kambuh, godaan and events — not the one-tap check-in).
class _ScopeChips extends StatelessWidget {
  const _ScopeChips({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FieldLabel('Tampil di'),
      ChunkyChoiceChips<String>(
        multi: true,
        allowEmpty: true,
        options: [
          for (final s in habitFieldScopes)
            ChunkyChoice(value: s, label: habitScopeLabel(s)),
        ],
        selected: selected,
        onChanged: onChanged,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Kosongkan untuk kambuh, godaan dan kejadian. Pilih "Selesai / '
          'bersih" kalau mau diisi setelah check-in.',
          style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
        ),
      ),
    ],
  );
}

class _EditFieldSheet extends StatefulWidget {
  const _EditFieldSheet({required this.def});

  final HabitFieldDef def;

  @override
  State<_EditFieldSheet> createState() => _EditFieldSheetState();
}

class _EditFieldSheetState extends State<_EditFieldSheet> {
  late final _label = TextEditingController(text: widget.def.label);
  late Set<String> _scopes = {...?widget.def.appliesTo};

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChunkyTextField(
              key: const ValueKey('dim-rename'),
              label: 'Nama dimensi',
              controller: _label,
              maxLength: 80,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Jenis: ${d.type.label}. Jenis dan kunci ("${d.key}") tidak bisa '
              'diubah supaya isi yang sudah ada aman.',
              style: GhinaType.caption.copyWith(
                color: context.ghina.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _ScopeChips(
              selected: _scopes,
              onChanged: (s) => setState(() => _scopes = s),
            ),
            const SizedBox(height: 16),
            ChunkyButton(
              key: const ValueKey('dim-rename-save'),
              label: 'Simpan',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop((
                label: _label.text,
                appliesTo: _scopes.toList(),
                delete: false,
              )),
            ),
            const SizedBox(height: 8),
            ChunkyButton(
              key: const ValueKey('dim-delete'),
              label: 'Hapus dimensi',
              icon: Icons.delete_outline_rounded,
              variant: ChunkyButtonVariant.ghost,
              color: GhinaColors.red,
              onPressed: () => Navigator.of(
                context,
              ).pop((label: null, appliesTo: null, delete: true)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddFieldForm extends ConsumerStatefulWidget {
  const _AddFieldForm({this.habit});

  final Habit? habit;

  @override
  ConsumerState<_AddFieldForm> createState() => _AddFieldFormState();
}

class _AddFieldFormState extends ConsumerState<_AddFieldForm> {
  final _label = TextEditingController();
  final _options = TextEditingController();
  final _min = TextEditingController(text: '$habitScaleDefaultMin');
  final _max = TextEditingController(text: '$habitScaleDefaultMax');
  HabitFieldType _type = HabitFieldType.scale;
  Set<String> _scopes = {};
  late bool _thisHabitOnly = widget.habit != null;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ref.read(createHabitFieldProvider)(
      HabitFieldInput(
        label: _label.text,
        type: _type,
        habitId: _thisHabitOnly ? widget.habit?.id : null,
        options: _type == HabitFieldType.select
            ? _options.text.split(RegExp(r'[,\n]'))
            : null,
        min: _type == HabitFieldType.scale ? int.tryParse(_min.text) : null,
        max: _type == HabitFieldType.scale ? int.tryParse(_max.text) : null,
        appliesTo: _scopes.toList(),
      ),
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        setState(() {
          _saving = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChunkyTextField(
              key: const ValueKey('dim-label'),
              label: 'Nama dimensi',
              hint: 'mis. Tingkat stres',
              controller: _label,
              maxLength: 80,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            const FieldLabel('Jenis isi'),
            ChunkyChoiceChips<HabitFieldType>(
              options: [
                for (final t in HabitFieldType.values)
                  ChunkyChoice(value: t, label: t.label),
              ],
              selected: {_type},
              onChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == HabitFieldType.select) ...[
              const SizedBox(height: 12),
              ChunkyTextField(
                key: const ValueKey('dim-options'),
                label: 'Pilihan',
                hint: 'Pisahkan dengan koma: capek, tenang, bosan',
                controller: _options,
                minLines: 1,
                maxLines: 3,
              ),
            ],
            if (_type == HabitFieldType.scale) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChunkyTextField(
                      key: const ValueKey('dim-min'),
                      label: 'Dari',
                      controller: _min,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChunkyTextField(
                      key: const ValueKey('dim-max'),
                      label: 'Sampai',
                      controller: _max,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _ScopeChips(
              selected: _scopes,
              onChanged: (s) => setState(() => _scopes = s),
            ),
            if (h != null)
              SwitchRow(
                title: 'Hanya untuk "${h.name}"',
                subtitle: 'Matikan supaya berlaku di semua kebiasaan',
                value: _thisHabitOnly,
                onChanged: (v) => setState(() => _thisHabitOnly = v),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const ValueKey('dim-error'),
                  style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
                ),
              ),
            const SizedBox(height: 12),
            ChunkyButton(
              key: const ValueKey('dim-save'),
              label: 'Buat dimensi',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
