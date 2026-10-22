import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

ChunkySwatch txSwatch(TxType t) => switch (t) {
  TxType.expense => GhinaColors.expense,
  TxType.income => GhinaColors.income,
  TxType.transfer => GhinaColors.transfer,
  TxType.adjustment || TxType.investment => GhinaColors.gray,
};

IconData txTypeIcon(TxType t) => switch (t) {
  TxType.expense => Icons.arrow_upward_rounded,
  TxType.income => Icons.arrow_downward_rounded,
  TxType.transfer => Icons.swap_horiz_rounded,
  TxType.adjustment => Icons.tune_rounded,
  TxType.investment => Icons.trending_up_rounded,
};

MoneyTone txTone(TxType t) => switch (t) {
  TxType.expense => MoneyTone.expense,
  TxType.income => MoneyTone.income,
  TxType.transfer => MoneyTone.transfer,
  TxType.adjustment || TxType.investment => MoneyTone.neutral,
};

/// Amount of a transaction in its tone. Adjustments are neutral (theme text
/// color) and always show their sign (`+Rp 5.000` / `-Rp 5.000`).
class TxAmount extends StatelessWidget {
  const TxAmount({
    super.key,
    required this.type,
    required this.amount,
    required this.currency,
    this.style,
  });

  final TxType type;
  final double amount;
  final String currency;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (type.isSigned) {
      return MoneyText(
        text: GhinaMoney.format(amount, currency: currency, showSign: true),
        tone: MoneyTone.neutral,
        color: context.ghina.textSecondary,
        style: style,
      );
    }
    return MoneyText(
      amount: amount,
      currency: currency,
      tone: txTone(type),
      style: style,
    );
  }
}

/// Detail line of an adjustment: its note without the "Penyesuaian saldo: "
/// prefix (e.g. `Rp 10.000 → Rp 12.500`), or null.
String? adjustmentDetail(Transaction t) {
  final note = t.note?.trim();
  if (note == null || note.isEmpty) return null;
  const prefix = 'Penyesuaian saldo: ';
  return note.startsWith(prefix) ? note.substring(prefix.length) : note;
}

/// Avatar for a transaction: category avatar, transfer arrows, or a gray
/// "no category" bubble.
class TxAvatar extends StatelessWidget {
  const TxAvatar({super.key, required this.view, this.size = 44});

  final TransactionView view;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (view.type == TxType.investment) {
      return CategoryAvatar(
        icon: Icons.trending_up_rounded,
        color: GhinaColors.purple.base,
        size: size,
        soft: true,
      );
    }
    if (view.type == TxType.adjustment) {
      return CategoryAvatar(
        icon: Icons.tune_rounded,
        color: GhinaColors.gray.base,
        size: size,
        soft: true,
      );
    }
    if (view.type == TxType.transfer) {
      return CategoryAvatar(
        icon: Icons.swap_horiz_rounded,
        color: GhinaColors.transfer.base,
        size: size,
      );
    }
    final c = view.category;
    if (c == null) {
      return CategoryAvatar(
        icon: view.type == TxType.income
            ? Icons.south_west_rounded
            : Icons.north_east_rounded,
        color: GhinaColors.gray.base,
        size: size,
      );
    }
    return CategoryAvatar(iconName: c.icon, colorHex: c.color, size: size);
  }
}

/// One transaction line (flat, meant to sit inside a grouped card).
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.view,
    required this.currency,
    this.onTap,
    this.onLongPress,
    this.foods = const [],
  });

  final TransactionView view;

  /// Menus of the food logs this transaction carries
  /// (`docs/food-transaction-link.md`), shown as a small marker.
  final List<String> foods;

  /// Fallback currency when the wallet is unknown.
  final String currency;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  String get _subtitle {
    final parts = <String>[];
    final note = view.transaction.note?.trim();
    if (view.type == TxType.transfer) {
      parts.add('Dari ${view.wallet?.name ?? 'dompet terhapus'}');
    } else if (view.type == TxType.adjustment) {
      if (adjustmentDetail(view.transaction) case final d?) parts.add(d);
      parts.add(view.wallet?.name ?? 'Dompet terhapus');
    } else if (view.type == TxType.investment) {
      parts.add('Investasi');
      parts.add(view.wallet?.name ?? 'Dompet terhapus');
    } else {
      if (note != null && note.isNotEmpty && view.category != null) {
        parts.add(view.category!.name);
      }
      parts.add(view.wallet?.name ?? 'Dompet terhapus');
    }
    parts.add(Fmt.time(view.date));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final photos = view.transaction.photos;
    return ChunkyTile(
      framed: false,
      leading: TxAvatar(view: view, size: 42),
      title: view.title,
      titleWidget: photos.isEmpty && foods.isEmpty
          ? null
          : Row(
              children: [
                Flexible(
                  flex: 3,
                  child: Text(
                    view.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body
                        .w(800)
                        .copyWith(color: context.ghina.textPrimary),
                  ),
                ),
                if (photos.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.15,
                    child: PhotoCountBadge(
                      key: ValueKey('tx-photos-${view.id}'),
                      count: photos.length,
                      onTap: () => showPhotoViewer(
                        context,
                        viewerPhotos(photos),
                        heroScope: 'row-${view.id}',
                      ),
                    ),
                  ),
                ],
                if (foods.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    flex: 2,
                    child: _FoodMarker(id: view.id, foods: foods),
                  ),
                ],
              ],
            ),
      subtitle: _subtitle,
      dense: true,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: TxAmount(
          type: view.type,
          amount: view.amount,
          currency: view.wallet?.currency ?? currency,
          style: GhinaType.moneyM,
        ),
      ),
    );
  }
}

/// "🍽 Nasi goreng +1": the transaction carries food logs.
class _FoodMarker extends StatelessWidget {
  const _FoodMarker({required this.id, required this.foods});

  final String id;
  final List<String> foods;

  @override
  Widget build(BuildContext context) {
    final sw = GhinaColors.orange;
    return Container(
      key: ValueKey('tx-food-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: sw.tint(context.ghina.brightness),
        borderRadius: GhinaRadii.rPill,
      ),
      // One Text (icon as a WidgetSpan) so it ellipsizes instead of
      // overflowing when the title leaves little room.
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Icon(Icons.restaurant_rounded, size: 12, color: sw.base),
              ),
            ),
            TextSpan(
              text: foods.length > 1
                  ? '${foods.first} +${foods.length - 1}'
                  : foods.first,
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GhinaType.caption.w(800).copyWith(color: sw.base),
      ),
    );
  }
}

// ---------------------------------------------------------------- photos

/// Transaction photo → generic viewer photo (pending = local file).
ViewerPhoto viewerPhoto(TransactionPhoto p) =>
    p.isPending ? ViewerPhoto.file(p.localPath!) : ViewerPhoto.network(p.url!);

List<ViewerPhoto> viewerPhotos(List<TransactionPhoto> ps) => [
  for (final p in ps) viewerPhoto(p),
];

/// Viewer photo back to a transaction photo (exact round trip).
TransactionPhoto txPhoto(ViewerPhoto p) => p.isLocal
    ? TransactionPhoto.local(p.filePath!)
    : TransactionPhoto.remote(p.url!);

// ---------------------------------------------------------------- form presets

/// What the next "new transaction" form should start with (set by a caller right
/// before `context.push('/transactions/new')`; consumed once by the form).
final class TxFormPreset {
  const TxFormPreset({this.type, this.walletId, this.categoryId});
  final TxType? type;
  final String? walletId;
  final String? categoryId;
}

class TxFormPresetNotifier extends Notifier<TxFormPreset?> {
  @override
  TxFormPreset? build() => null;

  void set(TxFormPreset? preset) => state = preset;

  /// Returns the preset and clears it.
  TxFormPreset? take() {
    final p = state;
    state = null;
    return p;
  }
}

final txFormPresetProvider =
    NotifierProvider<TxFormPresetNotifier, TxFormPreset?>(
      TxFormPresetNotifier.new,
    );

/// Wallet used for the last saved transaction during this app session.
class LastWalletNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final lastUsedWalletProvider = NotifierProvider<LastWalletNotifier, String?>(
  LastWalletNotifier.new,
);

// ---------------------------------------------------------------- investments

/// Where a transaction row opens: the cash effect of a trade (`investment`)
/// is managed from the portfolio (its trade), never from the transaction form.
String txRoute(TransactionView v) => v.type == TxType.investment
    ? '/investments/cash/${v.id}'
    : '/transactions/${v.id}';
