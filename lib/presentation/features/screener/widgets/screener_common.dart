import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../screener_format.dart';

/// The web page where Stockbit gets connected (from a laptop).
const screenerWebUrl = 'https://ghina.tentrem.space/investments/screener';

/// Stockbit's page of [ticker].
String stockbitSymbolUrl(String ticker) =>
    'https://stockbit.com/symbol/${Uri.encodeComponent(ticker)}';

/// Opens an https link in the browser; a toast when it can't.
Future<void> openScreenerLink(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    showErrorToast(context, 'Tautan ini nggak bisa dibuka');
  }
}

/// User-facing text of any error from a Screener call.
String screenerErrorMessage(Object error) => switch (error) {
  ScreenerException(:final message) => message,
  StockbitException(:final message) => message,
  _ => 'Ups, ada yang salah. Coba lagi, yuk.',
};

bool isScreenerForbidden(Object? error) =>
    error is ScreenerException && error.kind == ScreenerErrorKind.forbidden;

/// Error state: a locked message for 403, else the retry view.
class ScreenerErrorView extends StatelessWidget {
  const ScreenerErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (isScreenerForbidden(error)) {
      return EmptyState(
        mood: MascotMood.sleeping,
        compact: compact,
        title: 'Screener belum terbuka',
        message: screenerErrorMessage(error),
      );
    }
    return ErrorRetry(
      compact: compact,
      onRetry: onRetry,
      message: screenerErrorMessage(error),
    );
  }
}

/// IDX colours: green up, red down, muted flat. Never the only signal: the
/// text always carries a sign.
Color idxColor(GhinaTokens g, num? v) {
  if (v == null || v == 0) return g.textSecondary;
  return v > 0 ? GhinaColors.green.base : GhinaColors.red.base;
}

/// `1.250  +1,2%` — price with its signed daily change.
class PriceWithChange extends StatelessWidget {
  const PriceWithChange({
    super.key,
    required this.price,
    required this.changePercent,
    this.large = false,
    this.align = CrossAxisAlignment.end,
  });

  final double? price;
  final double? changePercent;
  final bool large;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (price == null) {
      return Text('–', style: GhinaType.body.copyWith(color: g.textMuted));
    }
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          screenerNum(price!),
          style: (large ? GhinaType.h1 : GhinaType.body.w(900)).copyWith(
            color: g.textPrimary,
          ),
        ),
        if (changePercent != null)
          Text(
            screenerPercent(changePercent!, decimals: 2),
            style: (large ? GhinaType.bodyL : GhinaType.caption)
                .w(800)
                .copyWith(color: idxColor(g, changePercent)),
          ),
      ],
    );
  }
}
