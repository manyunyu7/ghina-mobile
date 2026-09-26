import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../notification_log_format.dart';

/// Add or edit a parsing rule. A new rule can start from a log entry
/// ([NotificationRuleDraft]: app filled in, its text shown as the example and
/// used for "Tes rule") or from a preset ([NotificationRulePreset]).
class NotificationRuleFormPage extends ConsumerWidget {
  const NotificationRuleFormPage({super.key, this.id, this.draft, this.preset});

  /// Null when creating.
  final String? id;
  final NotificationRuleDraft? draft;
  final NotificationRulePreset? preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) {
      return _RuleForm(existing: null, draft: draft, preset: preset);
    }
    final rule = ref.watch(watchNotificationRuleProvider(id));
    Scaffold frame(Widget body) => Scaffold(
      appBar: AppBar(title: const Text('Ubah rule')),
      body: body,
    );
    return rule.when(
      skipLoadingOnReload: true,
      loading: () => frame(const LoadingListView(tiles: 3)),
      error: (_, _) => frame(
        ErrorRetry(
          onRetry: () => ref.invalidate(watchNotificationRuleProvider(id)),
        ),
      ),
      data: (r) => r == null
          ? frame(
              EmptyState(
                mood: MascotMood.thinking,
                title: 'Rule nggak ketemu',
                message: 'Mungkin sudah dihapus.',
                actionLabel: 'Kembali',
                onAction: () => context.pop(),
              ),
            )
          : _RuleForm(existing: r),
    );
  }
}

class _RuleForm extends ConsumerStatefulWidget {
  const _RuleForm({required this.existing, this.draft, this.preset});
  final NotificationRule? existing;
  final NotificationRuleDraft? draft;
  final NotificationRulePreset? preset;

  @override
  ConsumerState<_RuleForm> createState() => _RuleFormState();
}

final _incomeHint = RegExp(
  r'masuk|terima|diterima|menerima|kredit|received|cashback|refund',
  caseSensitive: false,
);

class _RuleFormState extends ConsumerState<_RuleForm> {
  NotificationRule? get e => widget.existing;
  NotificationRuleDraft? get d => widget.draft;
  NotificationRulePreset? get p => widget.preset;
  bool get _isEdit => e != null;

  late final String _currency = ref.read(currencyProvider);
  late final _name = TextEditingController(text: _initialName());
  late final _packages = TextEditingController(
    text: (e?.packages ?? p?.packages ?? [?d?.packageName]).join(', '),
  );
  late final _pattern = TextEditingController(text: _initialPattern());
  late final _amountPattern = TextEditingController(
    text: e?.amountPattern ?? '',
  );
  late final _sampleTitle = TextEditingController(text: d?.sampleTitle ?? '');
  late final _sampleBody = TextEditingController(text: d?.sampleBody ?? '');
  late TxType _type = e?.type ?? p?.type ?? _guessType();
  late RuleMatchField _field =
      e?.matchField ?? p?.matchField ?? RuleMatchField.any;
  late bool _isRegex = e?.isRegex ?? p?.isRegex ?? false;
  late bool _enabled = e?.enabled ?? true;
  late String? _walletId = e?.walletId;
  late String? _categoryId = e?.categoryId;

  /// Labels of apps picked from the list (display only).
  final Map<String, String> _labels = {};

  String? _nameError;
  String? _packagesError;
  String? _patternError;
  String? _amountPatternError;
  bool _saving = false;

  String _initialName() {
    if (e != null) return e!.name;
    if (p != null) return p!.name;
    final draft = d;
    if (draft == null) return '';
    final app = draft.appName ?? draft.packageName;
    final t = draft.sampleTitle.trim();
    final name = t.isEmpty ? app : '$app — $t';
    return name.length > 80 ? name.substring(0, 80) : name;
  }

  /// From a log entry: its title is usually a good keyword ("Transfer Masuk").
  String _initialPattern() {
    if (e != null) return e!.pattern;
    if (p != null) return p!.pattern;
    final t = d?.sampleTitle.trim() ?? '';
    return t.isNotEmpty && t.length <= 40 && !t.contains('|') ? t : '';
  }

  TxType _guessType() {
    final draft = d;
    if (draft == null) return TxType.expense;
    return _incomeHint.hasMatch('${draft.sampleTitle} ${draft.sampleBody}')
        ? TxType.income
        : TxType.expense;
  }

  @override
  void initState() {
    super.initState();
    final draft = d;
    if (draft?.appName != null) _labels[draft!.packageName] = draft.appName!;
  }

  @override
  void dispose() {
    _name.dispose();
    _packages.dispose();
    _pattern.dispose();
    _amountPattern.dispose();
    _sampleTitle.dispose();
    _sampleBody.dispose();
    super.dispose();
  }

  NotificationRuleInput _input() => NotificationRuleInput(
    name: _name.text,
    packages: parsePackageList(_packages.text),
    matchField: _field,
    pattern: _pattern.text,
    isRegex: _isRegex,
    type: _type,
    amountPattern: _amountPattern.text,
    walletId: _walletId,
    categoryId: _categoryId,
    enabled: _enabled,
    presetKey: e?.presetKey ?? p?.key,
  );

  /// The rule as currently typed (for "Tes rule").
  NotificationRule _draftRule() {
    final now = DateTime.now();
    return NotificationRule(
      id: 'test',
      name: _name.text,
      packages: parsePackageList(_packages.text),
      matchField: _field,
      pattern: _pattern.text.trim(),
      isRegex: _isRegex,
      type: _type,
      amountPattern: _amountPattern.text.trim().isEmpty
          ? null
          : _amountPattern.text.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _save() async {
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Kasih nama dulu, ya' : null;
      _packagesError = parsePackageList(_packages.text).isEmpty
          ? 'Pilih aplikasi sumbernya'
          : null;
      _patternError = _pattern.text.trim().isEmpty
          ? 'Isi kata kunci dulu'
          : null;
      _amountPatternError = null;
    });
    if (_nameError != null || _packagesError != null || _patternError != null) {
      return;
    }
    setState(() => _saving = true);
    final r = await ref.read(saveNotificationRuleProvider)(e?.id, _input());
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: _isEdit ? 'Rule diperbarui 👍' : 'Rule disimpan! 🔔',
          icon: Icons.rule_rounded,
          color: GhinaColors.green,
        );
        context.pop();
      case Err(:final failure):
        final field = failure is ValidationFailure ? failure.field : null;
        setState(() {
          switch (field) {
            case 'name':
              _nameError = failure.message;
            case 'packages':
              _packagesError = failure.message;
            case 'pattern':
              _patternError = failure.message;
            case 'amountPattern':
              _amountPatternError = failure.message;
          }
        });
        if (field == null) showFailureToast(context, failure);
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus rule ini?',
      message:
          '"${e!.name}" nggak akan mencatat transaksi lagi. Transaksi yang sudah ada tetap aman.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteNotificationRuleProvider)(e!.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Rule dihapus');
        context.pop();
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _pickApp() async {
    final picked = await showChunkyBottomSheet<InstalledApp>(
      context,
      title: 'Pilih aplikasi',
      showClose: true,
      builder: (_) => const _AppPickerSheet(),
    );
    if (picked == null || !mounted) return;
    final list = parsePackageList(_packages.text);
    if (!list.contains(picked.packageName)) list.add(picked.packageName);
    setState(() {
      _labels[picked.packageName] = picked.label;
      _packages.text = list.join(', ');
      _packagesError = null;
      if (_name.text.trim().isEmpty) {
        _name.text =
            '${picked.label} — ${_type == TxType.income ? 'uang masuk' : 'uang keluar'}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final catType = _type == TxType.income
        ? CategoryType.income
        : CategoryType.expense;
    final cats =
        ref.watch(watchCategoriesProvider(catType)).value ??
        const <TxCategory>[];
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final draft = d;
    final pickedLabels = [
      for (final pkg in parsePackageList(_packages.text))
        if (_labels[pkg] != null) _labels[pkg]!,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah rule' : 'Rule baru'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Hapus',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: GhinaColors.red.base,
              ),
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ChunkyButton(
          key: const ValueKey('notif-rule-save'),
          label: _isEdit ? 'Perbarui' : 'Simpan',
          loading: _saving,
          onPressed: _save,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (draft != null) ...[
            _ExampleCard(draft: draft),
            const SizedBox(height: 20),
          ],
          ChunkySegmented<TxType>(
            segments: const [
              ChunkySegment(
                value: TxType.expense,
                label: 'Pengeluaran',
                icon: Icons.north_east_rounded,
                color: GhinaColors.expense,
              ),
              ChunkySegment(
                value: TxType.income,
                label: 'Pemasukan',
                icon: Icons.south_west_rounded,
                color: GhinaColors.income,
              ),
            ],
            value: _type,
            onChanged: (t) => setState(() {
              _type = t;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 18),
          ChunkyTextField(
            key: const ValueKey('notif-rule-name'),
            label: 'Nama rule',
            hint: 'mis. myBCA — transfer masuk',
            controller: _name,
            errorText: _nameError,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 10),
          const FieldLabel('Aplikasi sumber'),
          if (pickedLabels.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in pickedLabels)
                  ChunkyPill(
                    label: l,
                    color: GhinaColors.blue,
                    soft: true,
                    uppercase: false,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          ChunkyTextField(
            key: const ValueKey('notif-rule-packages'),
            hint: 'com.bca.mybca.omni.android',
            controller: _packages,
            errorText: _packagesError,
            helperText: 'Nama paket aplikasi, pisahkan dengan koma.',
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() => _packagesError = null),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ChunkyButton(
              key: const ValueKey('notif-rule-pick-app'),
              label: 'Pilih dari aplikasi terpasang',
              icon: Icons.apps_rounded,
              size: ChunkyButtonSize.small,
              variant: ChunkyButtonVariant.outline,
              color: GhinaColors.blue,
              expand: false,
              onPressed: _pickApp,
            ),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Cocokkan di'),
          ChunkyChoiceChips<RuleMatchField>(
            options: [
              for (final f in RuleMatchField.values)
                ChunkyChoice(value: f, label: f.label),
            ],
            selected: {_field},
            onChanged: (s) {
              if (s.isNotEmpty) setState(() => _field = s.first);
            },
          ),
          const SizedBox(height: 12),
          ChunkyTextField(
            key: const ValueKey('notif-rule-pattern'),
            label: _isRegex ? 'Pola (regex)' : 'Kata kunci',
            hint: _isRegex
                ? r'transfer (masuk|dari)'
                : 'Transfer masuk | Dana masuk',
            controller: _pattern,
            errorText: _patternError,
            helperText: _isRegex
                ? 'Regular expression, huruf besar/kecil diabaikan.'
                : 'Cocok kalau teks mengandung salah satu kata. Pisahkan dengan |',
            textCapitalization: TextCapitalization.none,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(() => _patternError = null),
          ),
          MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pakai regex',
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
                Switch(
                  value: _isRegex,
                  onChanged: (v) => setState(() {
                    _isRegex = v;
                    _patternError = null;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ChunkyTextField(
            key: const ValueKey('notif-rule-amount'),
            label: 'Regex nominal (opsional)',
            hint: r'Rp\s?([\d.,]+)',
            controller: _amountPattern,
            errorText: _amountPatternError,
            helperText:
                'Kosongkan: nominal Rp dibaca otomatis (Rp1.234.567, Rp 50.000,00, IDR 25,000). Grup pertama regex dipakai sebagai nominal.',
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => setState(() => _amountPatternError = null),
          ),
          const SizedBox(height: 18),
          PickerField(
            label: 'Dompet',
            placeholder: 'Dompet pertama (otomatis)',
            value: wallet?.name,
            leading: wallet == null
                ? null
                : WalletAvatar(wallet: wallet, size: 34),
            onTap: () async {
              final id = await showWalletPickerSheet(
                context,
                wallets: wallets,
                currency: _currency,
                selectedId: _walletId,
                noneLabel: 'Dompet pertama (otomatis)',
              );
              if (id != null) {
                setState(() => _walletId = id.isEmpty ? null : id);
              }
            },
          ),
          const SizedBox(height: 18),
          PickerField(
            label: 'Kategori',
            placeholder: 'Tanpa kategori',
            value: cat?.name,
            leading: cat == null
                ? null
                : CategoryAvatar(
                    iconName: cat.icon,
                    colorHex: cat.color,
                    size: 34,
                  ),
            onTap: () async {
              final id = await showCategoryPickerSheet(
                context,
                categories: cats,
                selectedId: _categoryId,
                noneLabel: 'Tanpa kategori',
              );
              if (id != null) {
                setState(() => _categoryId = id.isEmpty ? null : id);
              }
            },
          ),
          const SizedBox(height: 12),
          MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Rule aktif',
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                ),
                Switch(
                  key: const ValueKey('notif-rule-enabled'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Tes rule',
            subtitle: draft != null
                ? 'Diisi dari notifikasi tadi — ubah sesukamu'
                : 'Tempel contoh notifikasi buat dicoba',
          ),
          ChunkyTextField(
            key: const ValueKey('notif-rule-test-title'),
            label: 'Judul notifikasi',
            hint: 'Transfer Masuk',
            controller: _sampleTitle,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          ChunkyTextField(
            key: const ValueKey('notif-rule-test-body'),
            label: 'Isi notifikasi',
            hint: 'Dana masuk Rp 150.000 dari BUDI ke rekening …1234',
            controller: _sampleBody,
            maxLines: 5,
            minLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _TestResultCard(
            rule: _draftRule(),
            title: _sampleTitle.text,
            body: _sampleBody.text,
            currency: _currency,
          ),
        ],
      ),
    );
  }
}

/// The source notification of a "Jadikan rule", with the detected amount.
class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.draft});
  final NotificationRuleDraft draft;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final amount = detectRupiahAmount(
      '${draft.sampleTitle}\n${draft.sampleBody}',
    );
    return ChunkyCard(
      key: const ValueKey('notif-rule-example'),
      tinted: GhinaColors.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppInitialAvatar(
                packageName: draft.packageName,
                label: draft.appName ?? draft.packageName,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contoh dari ${draft.appName ?? draft.packageName}',
                  style: GhinaType.caption
                      .w(900)
                      .copyWith(color: g.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (draft.sampleTitle.isNotEmpty)
            SelectableText(
              draft.sampleTitle,
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
          if (draft.sampleBody.isNotEmpty)
            SelectableText(
              draft.sampleBody,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                amount == null
                    ? Icons.help_outline_rounded
                    : Icons.payments_rounded,
                size: 18,
                color: amount == null ? g.textMuted : GhinaColors.green.base,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  amount == null
                      ? 'Nggak ada nominal rupiah yang terdeteksi.'
                      : 'Nominal terdeteksi: ${GhinaMoney.format(amount.value)} '
                            '(dari "${amount.text}")',
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tip: pakai kata yang selalu ada di notifikasi sejenis (mis. '
            '"Transfer masuk"), bukan nama orang atau nominal.',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({
    required this.rule,
    required this.title,
    required this.body,
    required this.currency,
  });

  final NotificationRule rule;
  final String title;
  final String body;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (title.trim().isEmpty && body.trim().isEmpty) {
      return Text(
        'Isi judul/isi contoh di atas, hasilnya muncul di sini.',
        style: GhinaType.caption.copyWith(color: g.textMuted),
      );
    }
    final r = testNotificationRule(rule, title: title, body: body);
    Widget line(bool ok, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: ok ? GhinaColors.green.base : GhinaColors.red.base,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
    );
    final amount = r.amount;
    return ChunkyCard(
      key: const ValueKey('notif-rule-test-result'),
      tinted: r.wouldCreate ? GhinaColors.green : GhinaColors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            r.patternMatches,
            r.patternError ??
                (rule.pattern.isEmpty
                    ? 'Kata kunci masih kosong'
                    : r.patternMatches
                    ? 'Kata kunci cocok'
                    : 'Kata kunci nggak cocok'),
          ),
          line(
            amount != null,
            r.amountPatternError ??
                (amount == null
                    ? 'Nominal rupiah nggak ketemu'
                    : 'Nominal: ${GhinaMoney.format(amount.value, currency: currency)} (dari "${amount.text}")'),
          ),
          const SizedBox(height: 4),
          Text(
            r.wouldCreate
                ? 'Notifikasi seperti ini bakal dicatat sebagai '
                      '${rule.type.label.toLowerCase()} '
                      '${GhinaMoney.format(amount!.value, currency: currency)}.'
                : 'Notifikasi seperti ini belum bakal jadi transaksi.',
            style: GhinaType.bodyS.w(900).copyWith(color: g.textPrimary),
          ),
          if (rule.packages.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Jangan lupa pilih aplikasi sumbernya.',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Searchable list of launchable apps. Pops the picked [InstalledApp].
class _AppPickerSheet extends ConsumerStatefulWidget {
  const _AppPickerSheet();

  @override
  ConsumerState<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends ConsumerState<_AppPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(installedAppsProvider);
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          ChunkyTextField(
            hint: 'Cari aplikasi…',
            prefixIcon: Icons.search_rounded,
            autofocus: false,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: switch (async) {
              AsyncValue(:final value?) => Builder(
                builder: (_) {
                  final apps = [
                    for (final a in value)
                      if (_q.isEmpty ||
                          a.label.toLowerCase().contains(_q) ||
                          a.packageName.toLowerCase().contains(_q))
                        a,
                  ];
                  if (apps.isEmpty) {
                    return Center(
                      child: Text(
                        'Aplikasi nggak ketemu',
                        style: GhinaType.bodyS.copyWith(color: g.textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (c, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ChunkyTile(
                        dense: true,
                        leading: AppInitialAvatar(
                          packageName: apps[i].packageName,
                          label: apps[i].label,
                          size: 34,
                        ),
                        title: apps[i].label,
                        subtitle: apps[i].packageName,
                        onTap: () => Navigator.of(c).pop(apps[i]),
                      ),
                    ),
                  );
                },
              ),
              AsyncValue(hasError: true) => Center(
                child: Text(
                  'Daftar aplikasi nggak bisa dimuat',
                  style: GhinaType.bodyS.copyWith(color: g.textMuted),
                ),
              ),
              _ => const SkeletonList(count: 5),
            },
          ),
        ],
      ),
    );
  }
}
