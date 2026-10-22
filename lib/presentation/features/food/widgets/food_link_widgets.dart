import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../../transactions/widgets/tx_visuals.dart';
import 'food_photo.dart';

/// Food log ⇄ transaction link pieces (`docs/food-transaction-link.md`),
/// shared by the Food page, the food detail and the transaction detail.

/// Links (or with null unlinks) and tells the user.
Future<bool> setFoodLink(
  BuildContext context,
  WidgetRef ref,
  String foodId,
  String? transactionId,
) async {
  final r = await ref.read(linkFoodToTransactionProvider)(
    foodId,
    transactionId,
  );
  if (!context.mounted) return r.isOk;
  switch (r) {
    case Ok():
      showOkToast(
        context,
        transactionId == null ? 'Tautan dilepas' : 'Tertaut 🔗',
        icon: transactionId == null
            ? Icons.link_off_rounded
            : Icons.link_rounded,
      );
      return true;
    case Err(:final failure):
      showFailureToast(context, failure);
      return false;
  }
}

/// "Ini makanan yang sama?" — one tap links, "Bukan" never asks again.
class FoodLinkSuggestionCard extends ConsumerWidget {
  const FoodLinkSuggestionCard({super.key, required this.suggestion});

  final FoodLinkSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final f = suggestion.food;
    final t = suggestion.transaction;
    final currency = ref.watch(currencyProvider);
    final note = t.note?.trim();
    return ChunkyCard(
      key: ValueKey('food-link-suggestion-${suggestion.key}'),
      tinted: GhinaColors.blue,
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, color: GhinaColors.blue.base),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Ini makanan yang sama?', style: GhinaType.h3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FoodPhoto(log: f, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${f.name} · ${Fmt.time(f.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              CategoryAvatar(
                icon: Icons.receipt_long_rounded,
                color: GhinaColors.red.base,
                size: 40,
                soft: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    Fmt.money(t.amount, currency: currency),
                    if (note != null && note.isNotEmpty) note,
                    Fmt.time(t.date),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.copyWith(color: g.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  key: ValueKey('food-link-yes-${suggestion.key}'),
                  label: 'Ya, tautkan',
                  icon: Icons.link_rounded,
                  size: ChunkyButtonSize.small,
                  color: GhinaColors.blue,
                  onPressed: () => setFoodLink(context, ref, f.id, t.id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  key: ValueKey('food-link-no-${suggestion.key}'),
                  label: 'Bukan',
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  onPressed: () => ref
                      .read(foodLinkDismissedProvider.notifier)
                      .dismiss(suggestion.key),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The transaction a food log is linked to (food detail): amount, wallet,
/// category and its receipt photos. Tap opens it.
class LinkedTransactionCard extends ConsumerWidget {
  const LinkedTransactionCard({
    super.key,
    required this.transactionId,
    this.onUnlink,
  });

  final String transactionId;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final v = ref.watch(watchTransactionProvider(transactionId)).value;
    if (v == null) return const SizedBox.shrink();
    final photos = viewerPhotos(v.transaction.photos);
    final cat = v.category;
    return ChunkyCard(
      key: const ValueKey('food-linked-tx'),
      padding: const EdgeInsets.all(GhinaSpace.md),
      onTap: () => context.push(txRoute(v)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DIBAYAR DARI',
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              cat == null
                  ? CategoryAvatar(
                      icon: Icons.receipt_long_rounded,
                      color: GhinaColors.red.base,
                      size: 40,
                    )
                  : CategoryAvatar(
                      iconName: cat.icon,
                      colorHex: cat.color,
                      size: 40,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3,
                    ),
                    Text(
                      [?v.wallet?.name, Fmt.time(v.date)].join(' · '),
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                Fmt.money(
                  v.amount,
                  currency: v.wallet?.currency ?? ref.watch(currencyProvider),
                ),
                key: const ValueKey('food-linked-tx-amount'),
                style: GhinaType.body
                    .w(900)
                    .copyWith(color: GhinaColors.red.base),
              ),
            ],
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            PhotoStrip(
              key: const ValueKey('food-linked-tx-photos'),
              photos: photos,
              size: 56,
              heroScope: 'food-linked-tx',
            ),
          ],
          if (onUnlink != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: ChunkyButton(
                key: const ValueKey('food-unlink'),
                label: 'Lepas tautan',
                icon: Icons.link_off_rounded,
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.ghost,
                onPressed: onUnlink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A food log linked to a transaction (transaction detail): photo, name and
/// calories. Tap opens it.
class LinkedFoodCard extends StatelessWidget {
  const LinkedFoodCard({super.key, required this.log, this.onUnlink});

  final FoodLog log;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final lo = log.calories;
    final hi = log.caloriesMax;
    final kcal = lo == null
        ? null
        : hi != null && hi > lo
        ? '${Fmt.number(lo)}–${Fmt.number(hi)} kkal'
        : '${Fmt.number(lo)} kkal';
    return ChunkyCard(
      key: ValueKey('tx-linked-food-${log.id}'),
      padding: const EdgeInsets.all(10),
      onTap: () => context.push('/food/${log.id}'),
      child: Row(
        children: [
          FoodPhoto(log: log, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3,
                ),
                Text(
                  [?log.mealText, Fmt.time(log.date), ?kcal].join(' · '),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
          if (onUnlink != null)
            IconButton(
              key: ValueKey('tx-unlink-food-${log.id}'),
              tooltip: 'Lepas tautan',
              icon: const Icon(Icons.link_off_rounded),
              onPressed: onUnlink,
            ),
        ],
      ),
    );
  }
}

/// Small "linked" marker for list rows.
class FoodLinkBadge extends StatelessWidget {
  const FoodLinkBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: label,
    icon: Icons.link_rounded,
    color: GhinaColors.blue,
    soft: true,
    uppercase: false,
  );
}

/// This month's food money vs calories (Food page).
class FoodSpendCard extends ConsumerWidget {
  const FoodSpendCard({super.key, required this.stats});

  final FoodSpendStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final currency = ref.watch(currencyProvider);
    String money(num v) => Fmt.money(v, currency: currency);
    final menus = stats.topMenus.map((m) => '${m.name} (${m.count}×)');
    final places = stats.topPlaces.map((m) => '${m.name} (${m.count}×)');
    Widget line(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              key: key,
              textAlign: TextAlign.right,
              style: GhinaType.bodyS.w(800),
            ),
          ),
        ],
      ),
    );
    return ChunkyCard(
      key: const ValueKey('food-spend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'BULAN INI',
                  style: GhinaType.overline.copyWith(color: g.textSecondary),
                ),
              ),
              InkWell(
                key: const ValueKey('food-categories-open'),
                onTap: () => showFoodCategorySheet(context),
                child: Text(
                  'Kategori makanan',
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: GhinaColors.blue.base),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            stats.costPerMeal == null
                ? 'Belum ada makanan yang tertaut'
                : '${money(stats.costPerMeal!)} per makan',
            key: const ValueKey('food-cost-per-meal'),
            style: GhinaType.h3,
          ),
          if (stats.costPerMeal != null)
            Text(
              '${stats.linkedMeals} makanan tertaut · ${money(stats.linkedSpend)}',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          const SizedBox(height: 6),
          line(
            'Pengeluaran makanan',
            money(stats.foodSpend),
            key: const ValueKey('food-spend-total'),
          ),
          line('Kalori tercatat', '${Fmt.number(stats.kcal)} kkal'),
          if (stats.spendPer1000Kcal != null)
            line('Per 1.000 kkal', money(stats.spendPer1000Kcal!)),
          if (menus.isNotEmpty) line('Menu tersering', menus.join(', ')),
          if (places.isNotEmpty) line('Tempat tersering', places.join(', ')),
        ],
      ),
    );
  }
}

/// Pick an expense of the same day to link a food log to. Returns its id.
Future<String?> showLinkTransactionSheet(
  BuildContext context, {
  required DateTime at,
}) => showChunkyBottomSheet<String>(
  context,
  title: 'Tautkan ke transaksi',
  showClose: true,
  builder: (_) => _LinkTxSheet(at: at),
);

class _LinkTxSheet extends ConsumerWidget {
  const _LinkTxSheet({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final list = ref.watch(foodLinkCandidatesProvider(at)).value;
    final cats = {
      for (final c
          in ref.watch(watchCategoriesProvider(null)).value ??
              const <TxCategory>[])
        c.id: c,
    };
    final currency = ref.watch(currencyProvider);
    if (list == null) return const SkeletonList(count: 3);
    if (list.isEmpty) {
      return EmptyState(
        compact: true,
        title: 'Belum ada pengeluaran',
        message:
            'Nggak ada pengeluaran tercatat di ${Fmt.dateFull(startOfDay(at))}.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in list) ...[
          ChunkyTile(
            key: ValueKey('link-candidate-${t.id}'),
            leading: switch (cats[t.categoryId]) {
              final c? => CategoryAvatar(
                iconName: c.icon,
                colorHex: c.color,
                size: 40,
              ),
              null => CategoryAvatar(
                icon: Icons.receipt_long_rounded,
                color: GhinaColors.red.base,
                size: 40,
              ),
            },
            title: (t.note?.trim().isNotEmpty ?? false)
                ? t.note!.trim()
                : (cats[t.categoryId]?.name ?? 'Pengeluaran'),
            subtitle: Fmt.time(t.date),
            trailing: Text(
              Fmt.money(t.amount, currency: currency),
              style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
            ),
            onTap: () => Navigator.of(context).pop(t.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Settings → "Kategori makanan": automatic (by name) or picked by hand.
Future<void> showFoodCategorySheet(BuildContext context) =>
    showChunkyBottomSheet<void>(
      context,
      title: 'Kategori makanan',
      showClose: true,
      builder: (_) => const FoodCategorySheet(),
    );

class FoodCategorySheet extends ConsumerStatefulWidget {
  const FoodCategorySheet({super.key});

  @override
  ConsumerState<FoodCategorySheet> createState() => _FoodCategorySheetState();
}

class _FoodCategorySheetState extends ConsumerState<FoodCategorySheet> {
  bool? _auto;
  Set<String>? _picked;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await ref
        .read(sessionControllerProvider.notifier)
        .setFoodCategories(_auto! ? null : _picked!.toList());
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Kategori makanan disimpan');
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(() => _saving = false);
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final setting = ref.watch(currentUserProvider)?.foodCategoryIds;
    final cats =
        ref.watch(watchCategoriesProvider(CategoryType.expense)).value ??
        const <TxCategory>[];
    final current = ref.watch(foodCategoryIdsProvider);
    _auto ??= setting == null;
    _picked ??= {...current};
    final auto = _auto!;
    final shown = auto ? current : _picked!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pengeluaran di kategori ini dianggap makanan: dipakai buat saran '
          'tautan, "Catat juga di Food log" dan ringkasan biaya makan.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 12),
        ChunkySegmented<bool>(
          key: const ValueKey('food-cat-mode'),
          value: auto,
          onChanged: (v) => setState(() => _auto = v),
          segments: const [
            ChunkySegment(value: true, label: 'Otomatis'),
            ChunkySegment(value: false, label: 'Pilih sendiri'),
          ],
        ),
        const SizedBox(height: 8),
        if (auto)
          Text(
            'Kategori bernama Makanan, Makan, Kuliner atau Food (dan '
            'turunannya, mis. "Makan Siang").',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        const SizedBox(height: 8),
        for (final c in cats)
          CheckboxListTile(
            key: ValueKey('food-cat-${c.id}'),
            value: shown.contains(c.id),
            onChanged: auto
                ? null
                : (v) => setState(() {
                    final next = {..._picked!};
                    v == true ? next.add(c.id) : next.remove(c.id);
                    _picked = next;
                  }),
            title: Text(c.name, style: GhinaType.body.w(700)),
            secondary: CategoryAvatar(
              iconName: c.icon,
              colorHex: c.color,
              size: 36,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 12),
        ChunkyButton(
          key: const ValueKey('food-cat-save'),
          label: 'Simpan',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- transaction-first

/// "Tautkan food log yang ada": unlinked meals around the transaction's time.
/// Returns the food id.
Future<String?> showLinkFoodSheet(BuildContext context, Transaction tx) =>
    showChunkyBottomSheet<String>(
      context,
      title: 'Tautkan food log',
      showClose: true,
      builder: (_) => _LinkFoodSheet(tx: tx),
    );

class _LinkFoodSheet extends ConsumerWidget {
  const _LinkFoodSheet({required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final list = ref.watch(foodCandidatesForTransactionProvider(tx));
    if (list.isEmpty) {
      return const EmptyState(
        compact: true,
        title: 'Belum ada food log',
        message: 'Nggak ada catatan makan tanpa tautan di sekitar tanggal ini.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in list) ...[
          ChunkyTile(
            key: ValueKey('link-food-${f.id}'),
            leading: FoodPhoto(log: f, size: 40),
            title: f.name,
            subtitle: [
              ?f.mealText,
              isSameDay(f.date, tx.date)
                  ? Fmt.time(f.date)
                  : '${Fmt.dateShortWeekday(f.date)} ${Fmt.time(f.date)}',
            ].join(' · '),
            trailing: Icon(Icons.link_rounded, color: g.textMuted),
            onTap: () => Navigator.of(context).pop(f.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// "Tambah food log" from a transaction: the meal gets the transaction's
/// date/time and link; its price and photos are the transaction's (shown
/// through the link, files not copied). The user fills the menu and calories.
Future<void> showAddFoodForTransactionSheet(
  BuildContext context,
  Transaction tx,
) => showChunkyBottomSheet<void>(
  context,
  title: 'Tambah food log',
  showClose: true,
  builder: (_) => AddFoodForTransactionSheet(tx: tx),
);

class AddFoodForTransactionSheet extends ConsumerStatefulWidget {
  const AddFoodForTransactionSheet({super.key, required this.tx});

  final Transaction tx;

  @override
  ConsumerState<AddFoodForTransactionSheet> createState() =>
      _AddFoodForTransactionSheetState();
}

class _AddFoodForTransactionSheetState
    extends ConsumerState<AddFoodForTransactionSheet> {
  late final _name = TextEditingController();
  final _kcal = TextEditingController();
  late MealType? _meal = _guessMeal(widget.tx.date);
  String? _error;
  bool _saving = false;

  static MealType _guessMeal(DateTime t) => t.hour < 10
      ? MealType.breakfast
      : t.hour < 15
      ? MealType.lunch
      : t.hour < 18
      ? MealType.snack
      : MealType.dinner;

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Isi nama menunya dulu ya');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final r = await ref.read(logFoodForTransactionProvider)(
      widget.tx,
      name: name,
      meal: _meal,
      calories: int.tryParse(_kcal.text.trim()),
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Food log ditambahkan 🍽️');
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(() => _saving = false);
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final tx = widget.tx;
    final currency = ref.watch(currencyProvider);
    final photos = viewerPhotos(tx.photos);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            '${Fmt.dateShortWeekday(tx.date)} ${Fmt.time(tx.date)}',
            Fmt.money(tx.amount, currency: currency),
          ].join(' · '),
          key: const ValueKey('add-food-tx-info'),
          style: GhinaType.body.w(800).copyWith(color: g.textSecondary),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          PhotoStrip(photos: photos, size: 56, heroScope: 'add-food-tx'),
          const SizedBox(height: 4),
          Text(
            'Foto transaksi dipakai sebagai foto food log ini.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const ValueKey('add-food-name'),
          label: 'Nama menu',
          hint: (tx.note?.trim().isNotEmpty ?? false)
              ? 'mis. ${tx.note!.trim()}'
              : 'mis. Nasi goreng',
          controller: _name,
          errorText: _error,
          prefixIcon: Icons.restaurant_rounded,
          maxLength: 120,
          autofocus: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in MealType.values)
              ChunkyChip(
                key: ValueKey('add-food-meal-${m.wire}'),
                label: '${m.emoji} ${m.label}',
                selected: _meal == m,
                color: mealSwatch(m),
                onTap: () => setState(() => _meal = _meal == m ? null : m),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ChunkyTextField(
          key: const ValueKey('add-food-kcal'),
          label: 'Kalori (opsional)',
          hint: 'mis. 450',
          controller: _kcal,
          prefixIcon: Icons.local_fire_department_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 5,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        ChunkyButton(
          key: const ValueKey('add-food-save'),
          label: 'Simpan',
          loading: _saving,
          color: GhinaColors.orange,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
