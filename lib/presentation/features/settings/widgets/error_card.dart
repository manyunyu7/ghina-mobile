import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// Opens Diagnostik › Log error; set by the app shell (go_router).
VoidCallback? openErrorLog;

/// Release-mode replacement for the grey [ErrorWidget] box: a small friendly
/// card in place of the widget that failed to build. Debug keeps the default
/// red error screen. Safe above `MaterialApp` (no Theme / Navigator needed).
Widget ghinaErrorWidgetBuilder(FlutterErrorDetails details) {
  if (!kReleaseMode) return ErrorWidget(details.exception);
  return const GhinaErrorCard();
}

class GhinaErrorCard extends StatelessWidget {
  const GhinaErrorCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Plain widgets only: this can be built anywhere, under any ancestor.
    final dark =
        MediaQuery.maybeOf(context)?.platformBrightness == Brightness.dark;
    final g = dark ? GhinaTokens.dark : GhinaTokens.light;
    final open = openErrorLog;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            key: const ValueKey('ghina-error-card'),
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(14),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: g.surface,
              borderRadius: GhinaRadii.rLg,
              border: Border.all(color: g.border, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bagian ini gagal dimuat',
                  textAlign: TextAlign.center,
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(
                        color: g.textPrimary,
                        decoration: TextDecoration.none,
                      ),
                ),
                if (open != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: open,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        'Lihat detail',
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(
                              color: GhinaColors.blue.base,
                              decoration: TextDecoration.none,
                            ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
