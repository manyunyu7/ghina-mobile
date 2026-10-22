import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../state/session_controller.dart' show currencyProvider;
import '../../transactions/widgets/tx_visuals.dart' show lastUsedWalletProvider;
import '../widgets/food_link_widgets.dart';
import '../widgets/food_photo.dart';

/// Log or edit a meal: photo (camera/gallery, compressed), name, meal type,
/// calories, date and note. A new meal can also be recorded as an expense
/// (price → "Catat juga sebagai pengeluaran", on by default) or linked to an
/// existing one; an existing meal shows its linked expense
/// (`docs/food-transaction-link.md`).
class FoodFormPage extends ConsumerStatefulWidget {
  const FoodFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<FoodFormPage> createState() => _FoodFormPageState();
}

class _FoodFormPageState extends ConsumerState<FoodFormPage> {
  final _name = TextEditingController();
  final _calories = TextEditingController();
  final _caloriesMax = TextEditingController();
  final _mealText = TextEditingController();
  final _tagInput = TextEditingController();
  List<String> _tags = const [];
  final _note = TextEditingController();
  final _dateText = TextEditingController();
  final _price = TextEditingController();

  /// New meal: record the price as an expense too (default on), or link
  /// [_linkTxId] — an existing expense — instead.
  bool _alsoExpense = true;
  String? _expenseWalletId;
  String? _expenseCategoryId;
  String? _linkTxId;

  DateTime? _date;
  FoodLog? _existing;
  String? _pickedPath;
  bool _removePhoto = false;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _calories,
      _caloriesMax,
      _mealText,
      _tagInput,
      _note,
      _dateText,
      _price,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _dateOrNow => _date ?? ref.read(clockProvider).now();

  void _setDate(DateTime d) {
    _date = d;
    _dateText.text = Fmt.dateFull(d);
  }

  static MealType _guessMeal(DateTime t) => t.hour < 10
      ? MealType.breakfast
      : t.hour < 15
      ? MealType.lunch
      : t.hour < 18
      ? MealType.snack
      : MealType.dinner;

  void _fill(FoodLog l) {
    if (_loaded) return;
    _loaded = true;
    _existing = l;
    _name.text = l.name;
    _calories.text = l.calories?.toString() ?? '';
    _caloriesMax.text = l.caloriesMax?.toString() ?? '';
    _note.text = l.note ?? '';
    _mealText.text = l.mealText ?? '';
    _tags = l.tags;
    _setDate(l.date);
  }

  bool get _hasPhoto =>
      _pickedPath != null || (!_removePhoto && (_existing?.hasPhoto ?? false));

  Future<void> _pickPhoto() async {
    final source = await showChunkyBottomSheet<ImageSource>(
      context,
      title: 'Tambah foto',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyTile(
            leading: const CategoryAvatar(
              icon: Icons.photo_camera_rounded,
              color: Color(0xFFFF9600),
              size: 40,
            ),
            title: 'Kamera',
            subtitle: 'Foto langsung makananmu',
            onTap: () => Navigator.of(c).pop(ImageSource.camera),
          ),
          const SizedBox(height: 10),
          ChunkyTile(
            leading: const CategoryAvatar(
              icon: Icons.photo_library_rounded,
              color: Color(0xFF1CB0F6),
              size: 40,
            ),
            title: 'Galeri',
            subtitle: 'Pilih dari foto yang ada',
            onTap: () => Navigator.of(c).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    try {
      // Compressed on pick: the server accepts up to 5 MB.
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (x == null || !mounted) return;
      setState(() {
        _pickedPath = x.path;
        _removePhoto = false;
      });
    } on PlatformException catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        source == ImageSource.camera
            ? 'Nggak bisa buka kamera. Cek izin kamera di pengaturan HP, ya.'
            : 'Nggak bisa buka galeri. Cek izin foto di pengaturan HP, ya.',
      );
    }
  }

  void _clearPhoto() => setState(() {
    _pickedPath = null;
    _removePhoto = true;
  });

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final cur = _dateOrNow;
    final picked = await showGhinaDatePicker(
      context,
      initial: cur.isAfter(now) ? now : cur,
      title: 'Tanggal makan',
      firstDate: DateTime(2000),
      lastDate: now,
      today: now,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _setDate(
        DateTime(picked.year, picked.month, picked.day, cur.hour, cur.minute),
      ),
    );
  }

  Map<String, String> _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'Isi nama makanannya dulu ya';
    e.addAll(parseCalorieRange(_calories.text, _caloriesMax.text).errors);
    return e;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    final range = parseCalorieRange(_calories.text, _caloriesMax.text);
    final meal = resolveMealText(_mealText.text);
    final input = FoodInput(
      date: _dateOrNow,
      name: _name.text,
      meal: meal.meal,
      mealLabel: meal.label,
      clearMealLabel: _isEdit && meal.label == null,
      calories: range.min,
      caloriesMax: range.max,
      clearCaloriesMax: _isEdit && range.max == null,
      tags: _tags,
      note: _note.text,
    );
    final wantsExpense =
        !_isEdit &&
        _linkTxId == null &&
        _alsoExpense &&
        (parseAmountInput(_price.text) ?? 0) > 0;
    final expense = wantsExpense ? _expenseInput() : null;
    if (wantsExpense && expense == null) {
      showErrorToast(context, 'Bikin dompet dulu buat mencatat pengeluaran');
      return;
    }
    setState(() => _saving = true);
    final rewards = RewardTracker.start(ref);
    final Result<Object> r = _isEdit
        ? await ref.read(updateFoodLogProvider)(
            widget.id!,
            input,
            photoPath: _pickedPath,
            removePhoto: _removePhoto && _pickedPath == null,
          )
        : expense != null
        ? await ref.read(createFoodWithExpenseProvider)(
            input,
            expense,
            photoPath: _pickedPath,
          )
        : await ref.read(createFoodLogProvider)(
            input,
            photoPath: _pickedPath,
            transactionId: _linkTxId,
          );
    if (!mounted) return;
    if (r.isOk && expense != null) {
      ref.read(lastUsedWalletProvider.notifier).set(expense.walletId);
    }
    switch (r) {
      case Ok():
        if (_isEdit) {
          showToastBadge(
            context,
            message: 'Perubahan tersimpan 👍',
            icon: Icons.check_circle_rounded,
            color: GhinaColors.green,
          );
        } else {
          await rewards.finish(
            context,
            xpToast: (xp) => 'Nyam! +$xp XP',
            doneToast: 'Tercatat 👍',
          );
        }
        if (mounted) context.pop();
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(:final field?)) {
            _errors = {..._errors, field: failure.message};
          }
        });
        showErrorToast(context, failure.message);
    }
  }

  // ------------------------------------------------------------- link / price

  List<Wallet> get _wallets =>
      ref.read(watchWalletsProvider).value ?? const <Wallet>[];

  String? _walletIdOrDefault() {
    final ids = {for (final w in _wallets) w.id};
    for (final id in [_expenseWalletId, ref.read(lastUsedWalletProvider)]) {
      if (id != null && ids.contains(id)) return id;
    }
    return _wallets.firstOrNull?.id;
  }

  String? _categoryIdOrDefault() {
    if (_expenseCategoryId case final id?) return id.isEmpty ? null : id;
    return defaultFoodCategoryId(
      ref.read(watchCategoriesProvider(CategoryType.expense)).value ??
          const <TxCategory>[],
      ref.read(foodCategoryIdsProvider),
    );
  }

  /// The expense to record with a new meal (the price is > 0), or null when
  /// there is no wallet to take it from.
  FoodExpenseInput? _expenseInput() {
    final walletId = _walletIdOrDefault();
    if (walletId == null) return null;
    return FoodExpenseInput(
      amount: parseAmountInput(_price.text)!,
      walletId: walletId,
      categoryId: _categoryIdOrDefault(),
      note: _name.text,
    );
  }

  Future<void> _pickLinkTx() async {
    final id = await showLinkTransactionSheet(context, at: _dateOrNow);
    if (id == null || !mounted) return;
    if (_isEdit) {
      await setFoodLink(context, ref, widget.id!, id);
    } else {
      setState(() => _linkTxId = id);
    }
  }

  Future<void> _pickExpenseWallet() async {
    final id = await showWalletPickerSheet(
      context,
      wallets: _wallets,
      currency: ref.read(currencyProvider),
      selectedId: _walletIdOrDefault(),
    );
    if (id == null || id.isEmpty || !mounted) return;
    setState(() => _expenseWalletId = id);
  }

  Future<void> _pickExpenseCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories:
          ref.read(watchCategoriesProvider(CategoryType.expense)).value ??
          const <TxCategory>[],
      selectedId: _categoryIdOrDefault(),
      noneLabel: 'Tanpa kategori',
    );
    if (id == null || !mounted) return;
    setState(() => _expenseCategoryId = id);
  }

  /// Price + "Catat juga sebagai pengeluaran" / "Tautkan ke transaksi"
  /// (new meal), or the linked expense (existing meal).
  Widget _moneySection() {
    final g = context.ghina;
    if (_isEdit) {
      final txId = _existing?.transactionId;
      if (txId != null) {
        return LinkedTransactionCard(
          transactionId: txId,
          onUnlink: () => setFoodLink(context, ref, widget.id!, null),
        );
      }
      final suggestion = ref.watch(
        foodLinkSuggestionForFoodProvider(widget.id!),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (suggestion != null) ...[
            FoodLinkSuggestionCard(suggestion: suggestion),
            const SizedBox(height: 8),
          ],
          ChunkyButton(
            key: const ValueKey('food-link-pick'),
            label: 'Tautkan ke transaksi',
            icon: Icons.link_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: _pickLinkTx,
          ),
        ],
      );
    }
    if (_linkTxId case final id?) {
      return LinkedTransactionCard(
        transactionId: id,
        onUnlink: () => setState(() => _linkTxId = null),
      );
    }
    // Watched so the defaults below are ready when the user saves.
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final cats =
        ref.watch(watchCategoriesProvider(CategoryType.expense)).value ??
        const <TxCategory>[];
    ref.watch(foodCategoryIdsProvider);
    final walletId = _walletIdOrDefault();
    final wallet = wallets.where((w) => w.id == walletId).firstOrNull;
    final catId = _categoryIdOrDefault();
    final cat = cats.where((c) => c.id == catId).firstOrNull;
    final hasPrice = (parseAmountInput(_price.text) ?? 0) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmountField(
          key: const ValueKey('food-price'),
          controller: _price,
          currency: wallet?.currency ?? ref.watch(currencyProvider),
          label: 'Harga (opsional)',
          onChanged: (_) => setState(() {}),
        ),
        if (hasPrice) ...[
          SwitchListTile(
            key: const ValueKey('food-also-expense'),
            value: _alsoExpense,
            onChanged: (v) => setState(() => _alsoExpense = v),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Catat juga sebagai pengeluaran',
              style: GhinaType.body.w(800),
            ),
            subtitle: Text(
              'Langsung masuk ke transaksi & tertaut ke makanan ini',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ),
          if (_alsoExpense) ...[
            PickerField(
              key: const ValueKey('food-expense-wallet'),
              label: 'Dompet',
              value: wallet?.name,
              placeholder: 'Pilih dompet',
              leading: wallet == null
                  ? null
                  : WalletAvatar(wallet: wallet, size: 28),
              onTap: _pickExpenseWallet,
            ),
            const SizedBox(height: 10),
            PickerField(
              key: const ValueKey('food-expense-category'),
              label: 'Kategori',
              value: cat?.name,
              placeholder: 'Tanpa kategori',
              leading: cat == null
                  ? null
                  : CategoryAvatar(
                      iconName: cat.icon,
                      colorHex: cat.color,
                      size: 28,
                    ),
              onTap: _pickExpenseCategory,
            ),
          ],
        ],
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('food-link-pick'),
          label: hasPrice && _alsoExpense
              ? 'Atau tautkan ke transaksi yang sudah ada'
              : 'Tautkan ke transaksi',
          icon: Icons.link_rounded,
          size: ChunkyButtonSize.small,
          variant: ChunkyButtonVariant.ghost,
          onPressed: _pickLinkTx,
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus catatan makan?',
      message:
          '"${_name.text.trim()}" akan dihapus permanen, termasuk fotonya.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteFoodLogProvider)(widget.id!);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Catatan dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        context.pop();
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget body;
    if (_isEdit) {
      final async = ref.watch(watchFoodLogProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          // Keep the photo state fresh (e.g. uploaded while open).
          _existing = value;
          body = _form();
        case AsyncData():
          body = EmptyState(
            title: 'Catatan nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Kembali',
            onAction: () => context.pop(),
          );
        case AsyncError():
          body = ErrorRetry(
            onRetry: () => ref.invalidate(watchFoodLogProvider(widget.id!)),
          );
        default:
          body = const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 4),
          );
      }
    } else {
      if (_date == null) {
        final now = ref.read(clockProvider).now();
        _setDate(now);
        _mealText.text = _guessMeal(now).label;
      }
      body = _form();
    }
    final showSave = !_isEdit || _loaded;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah catatan makan' : 'Catat makanan'),
        actions: [
          if (_isEdit && _loaded)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
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
                12 +
                    MediaQuery.paddingOf(context).bottom +
                    MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ChunkyButton(
                label: _isEdit ? 'Simpan perubahan' : 'Simpan',
                loading: _saving,
                color: GhinaColors.orange,
                onPressed: _save,
              ),
            )
          : null,
    );
  }

  Widget _photo() {
    final g = context.ghina;
    if (!_hasPhoto) {
      return Semantics(
        button: true,
        label: 'Tambah foto',
        child: ChunkySurface(
          color: g.surfaceAlt,
          edgeColor: g.border,
          borderColor: g.border,
          depth: GhinaDepth.md,
          borderRadius: GhinaRadii.rXl,
          onTap: _pickPhoto,
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_a_photo_rounded,
                  size: 36,
                  color: GhinaColors.orange.base,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tambah foto',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                Text(
                  'Opsional, tapi bikin diary-mu lebih seru',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final Widget image = _pickedPath != null
            ? ClipRRect(
                borderRadius: GhinaRadii.rXl,
                child: Image.file(
                  File(_pickedPath!),
                  width: w,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => MealEmojiTile(
                    meal: resolveMealText(_mealText.text).meal,
                    width: w,
                    height: 200,
                    radius: GhinaRadii.rXl,
                  ),
                ),
              )
            : FoodPhoto(
                log: _existing!,
                width: w,
                height: 200,
                radius: GhinaRadii.rXl,
              );
        return Stack(
          children: [
            image,
            Positioned(
              top: 10,
              right: 10,
              child: ChunkyIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Hapus foto',
                size: 40,
                onPressed: _clearPhoto,
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: ChunkyButton(
                label: 'Ganti foto',
                icon: Icons.photo_camera_rounded,
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.outline,
                onPressed: _pickPhoto,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mealChips() {
    final logs = ref.watch(watchFoodLogsProvider).value ?? const <FoodLog>[];
    final current = _mealText.text.trim().toLowerCase();
    final labels = [
      for (final m in MealType.values) (text: m.label, emoji: m.emoji, m: m),
      for (final l in recentMealLabels(logs)) (text: l, emoji: '', m: null),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in labels)
          ChunkyChip(
            key: ValueKey('meal-chip-${c.text}'),
            label: c.emoji.isEmpty ? c.text : '${c.emoji} ${c.text}',
            selected: current == c.text.toLowerCase(),
            color: c.m == null ? GhinaColors.purple : mealSwatch(c.m!),
            onTap: () => setState(() => _mealText.text = c.text),
          ),
      ],
    );
  }

  void _addTag([String? raw]) {
    final text = raw ?? _tagInput.text;
    final next = addFoodTag(_tags, text);
    if (identical(next, _tags)) {
      if (text.trim().isNotEmpty) {
        showErrorToast(
          context,
          _tags.length >= foodTagsMax
              ? 'Maksimal $foodTagsMax tag'
              : text.trim().length > foodTagMax
              ? 'Tag maksimal $foodTagMax karakter'
              : 'Tag itu sudah ada',
        );
      }
      return;
    }
    setState(() {
      _tags = next;
      _tagInput.clear();
    });
  }

  Widget _tagsEditor() {
    final g = context.ghina;
    final known = [
      for (final c in foodTagCounts(
        ref.watch(watchFoodLogsProvider).value ?? const <FoodLog>[],
      ).take(8))
        if (!_tags.any((t) => t.toLowerCase() == c.tag.toLowerCase())) c.tag,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tag (opsional)', style: GhinaType.h3),
        const SizedBox(height: 8),
        ChunkyTextField(
          key: const ValueKey('tag-input'),
          hint: 'mis. pedas, porsi besar',
          controller: _tagInput,
          maxLength: foodTagMax,
          prefixIcon: Icons.sell_rounded,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addTag(),
          suffix: IconButton(
            key: const ValueKey('tag-add'),
            tooltip: 'Tambah tag',
            icon: const Icon(Icons.add_rounded),
            onPressed: _addTag,
          ),
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _tags)
                ChunkyChip(
                  key: ValueKey('tag-$t'),
                  label: '#$t  ✕',
                  selected: true,
                  color: GhinaColors.blue,
                  onTap: () => setState(() => _tags = [..._tags]..remove(t)),
                ),
            ],
          ),
        ],
        if (known.isNotEmpty && _tags.length < foodTagsMax) ...[
          const SizedBox(height: 8),
          Text(
            'Tag yang pernah dipakai',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in known)
                ChunkyChip(
                  key: ValueKey('tag-suggest-$t'),
                  label: '#$t',
                  selected: false,
                  onTap: () => _addTag(t),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        24,
      ),
      children: [
        _photo(),
        const SizedBox(height: 20),
        ChunkyTextField(
          key: const ValueKey('name'),
          label: 'Makan apa?',
          hint: 'mis. Nasi goreng + telur',
          controller: _name,
          prefixIcon: Icons.restaurant_rounded,
          errorText: _errors['name'],
          maxLength: 120,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        Text('Waktu makan', style: GhinaType.h3),
        const SizedBox(height: 8),
        ChunkyTextField(
          key: const ValueKey('meal-label'),
          hint: 'mis. Sarapan, atau tulis sendiri',
          controller: _mealText,
          maxLength: foodMealLabelMax,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        _mealChips(),
        const SizedBox(height: 18),
        ChunkyTextField(
          key: const ValueKey('calories'),
          label: 'Kalori (opsional)',
          hint: 'mis. 450',
          controller: _calories,
          prefixIcon: Icons.local_fire_department_rounded,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                'kkal',
                style: GhinaType.body
                    .w(800)
                    .copyWith(color: context.ghina.textSecondary),
              ),
            ),
          ),
          errorText: _errors['calories'],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const ValueKey('calories-max'),
          label: 'Sampai (opsional, untuk rentang)',
          hint: 'mis. 600',
          controller: _caloriesMax,
          prefixIcon: Icons.swap_horiz_rounded,
          errorText: _errors['caloriesMax'],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        ChunkyTextField(
          label: 'Tanggal',
          controller: _dateText,
          readOnly: true,
          prefixIcon: Icons.event_rounded,
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),
        Text(_isEdit ? 'Pengeluaran' : 'Harga', style: GhinaType.h3),
        const SizedBox(height: 8),
        _moneySection(),
        const SizedBox(height: 16),
        _tagsEditor(),
        const SizedBox(height: 16),
        ChunkyTextField(
          key: const ValueKey('note'),
          label: 'Catatan (opsional)',
          hint: 'mis. kepedesan, kenyang banget',
          controller: _note,
          prefixIcon: Icons.sticky_note_2_rounded,
          maxLength: 200,
        ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            label: 'Hapus catatan',
            icon: Icons.delete_outline_rounded,
            variant: ChunkyButtonVariant.ghost,
            color: GhinaColors.red,
            onPressed: _delete,
          ),
        ],
      ],
    );
  }
}
