import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import 'kantor_role.dart';

/// Small shared pieces for the Roles, Meetings, Archive and Files tabs.

void kantorToast(
  BuildContext context,
  String message, {
  bool bad = false,
  bool warn = false,
}) {
  showToastBadge(
    context,
    message: message,
    icon: bad
        ? Icons.error_outline_rounded
        : warn
        ? Icons.warning_amber_rounded
        : Icons.check_circle_rounded,
    color: bad
        ? GhinaColors.red
        : warn
        ? GhinaColors.orange
        : GhinaColors.green,
  );
}

/// Runs [action], toasting its failure. Returns whether it succeeded.
Future<bool> kantorGuard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) kantorToast(context, kantorErrorText(e), bad: true);
    return false;
  }
}

/// Option for [kantorPick].
final class KantorChoice<T> {
  const KantorChoice(this.value, this.label, [this.hint]);
  final T value;
  final String label;
  final String? hint;
}

/// Bottom-sheet single choice.
Future<T?> kantorPick<T>(
  BuildContext context, {
  required String title,
  required List<KantorChoice<T>> options,
  T? selected,
}) => showChunkyBottomSheet<T>(
  context,
  title: title,
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: ChunkyTile(
            title: o.label,
            subtitle: o.hint,
            tinted: o.value == selected ? GhinaColors.blue : null,
            trailing: o.value == selected
                ? const Icon(Icons.check_rounded, color: Color(0xFF1CB0F6))
                : null,
            onTap: () => Navigator.of(c).pop(o.value),
          ),
        ),
    ],
  ),
);

/// A read-only field that opens [kantorPick].
class KantorPickField<T> extends StatelessWidget {
  const KantorPickField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.emptyLabel = 'Pilih',
  });

  final String label;
  final List<KantorChoice<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    String text = emptyLabel;
    for (final o in options) {
      if (o.value == value) text = o.label;
    }
    return GestureDetector(
      onTap: () async {
        final v = await kantorPick<T>(
          context,
          title: label,
          options: options,
          selected: value,
        );
        if (v != null) onChanged(v);
      },
      child: AbsorbPointer(
        child: ChunkyTextField(
          key: ValueKey('$label/$text'),
          label: label,
          initialValue: text,
          readOnly: true,
          suffix: const Icon(Icons.expand_more_rounded),
        ),
      ),
    );
  }
}

class KantorFieldLabel extends StatelessWidget {
  const KantorFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
    child: Text(
      text,
      style: GhinaType.bodyS
          .w(800)
          .copyWith(color: context.ghina.textSecondary),
    ),
  );
}

/// Round colour dots, one selected.
class KantorSwatchRow extends StatelessWidget {
  const KantorSwatchRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Wrap(
      spacing: GhinaSpace.sm,
      runSpacing: GhinaSpace.sm,
      children: [
        for (final c in colors)
          Semantics(
            button: true,
            selected: c.toLowerCase() == selected.toLowerCase(),
            label: 'Warna $c',
            child: GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CategoryColors.parse(c),
                  border: Border.all(
                    color: c.toLowerCase() == selected.toLowerCase()
                        ? g.textPrimary
                        : g.border,
                    width: c.toLowerCase() == selected.toLowerCase() ? 3 : 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Single-choice chips from an id → label map.
class KantorChips extends StatelessWidget {
  const KantorChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ChunkyChoiceChips<String>(
    options: [
      for (final e in options.entries)
        ChunkyChoice(value: e.key, label: e.value),
    ],
    selected: {value},
    onChanged: (s) {
      if (s.isNotEmpty) onChanged(s.first);
    },
  );
}

/// Sprite for a name that may or may not be a known role (meeting chat).
Widget kantorAvatar(KantorRole? role, String key, {double size = 36}) =>
    KantorSprite(look: role?.look ?? KantorSprite.guestLook(key), size: size);

/// "Berjalan" / "Selesai" pill.
class KantorStatusPill extends StatelessWidget {
  const KantorStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'berjalan' || 'working' || 'starting' => ('Berjalan', GhinaColors.green),
      'gagal' => ('Gagal', GhinaColors.red),
      'terputus' => ('Terputus', GhinaColors.orange),
      'waiting' => ('Menunggu izin', GhinaColors.orange),
      'idle' => ('Idle', GhinaColors.blue),
      'selesai' => ('Selesai', GhinaColors.gray),
      _ => (status, GhinaColors.gray),
    };
    return ChunkyPill(label: label, color: color, soft: true, uppercase: false);
  }
}
