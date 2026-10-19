import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// Confirmation in a bottom sheet (not a dialog). True when confirmed.
Future<bool> showStatementConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showChunkyBottomSheet<bool>(
    context,
    title: title,
    builder: (c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: GhinaType.body.copyWith(color: c.ghina.textSecondary),
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const Key('statement-confirm'),
          label: confirmLabel,
          variant: destructive
              ? ChunkyButtonVariant.danger
              : ChunkyButtonVariant.primary,
          size: ChunkyButtonSize.large,
          onPressed: () => Navigator.of(c).pop(true),
        ),
        const SizedBox(height: 8),
        ChunkyButton(
          label: 'Batal',
          variant: ChunkyButtonVariant.ghost,
          onPressed: () => Navigator.of(c).pop(false),
        ),
      ],
    ),
  );
  return ok ?? false;
}
