import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';

/// `POST /api/offices/<id>/open-local`: opens an office path on the Mac
/// (VS Code, or Finder with [finder]).
Future<void> kantorOpenOnMac(
  BuildContext context,
  WidgetRef ref,
  String office,
  String path, {
  bool finder = false,
}) async {
  final api = ref.read(kantorApiProvider);
  if (api == null) return;
  await kantorGuard(context, () async {
    await api.post('/api/offices/${Uri.encodeComponent(office)}/open-local', {
      'path': path,
      if (finder) 'app': 'finder',
    });
    if (context.mounted)
      kantorToast(context, finder ? 'Ditampilkan di Finder' : 'Dibuka di Mac');
  });
}

Future<void> kantorCopy(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) kantorToast(context, done);
}

/// Row of "Buka di Mac" / "Finder" / "Salin" actions for an office path.
class KantorMacActions extends ConsumerWidget {
  const KantorMacActions({
    super.key,
    required this.office,
    required this.path,
    this.hint,
  });

  final String office;
  final String path;
  final String? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: GhinaSpace.page,
      vertical: GhinaSpace.sm,
    ),
    child: Wrap(
      spacing: GhinaSpace.sm,
      runSpacing: GhinaSpace.sm,
      children: [
        ChunkyButton(
          label: 'Buka di Mac',
          size: ChunkyButtonSize.small,
          icon: Icons.laptop_mac_rounded,
          onPressed: () => kantorOpenOnMac(context, ref, office, path),
        ),
        ChunkyButton(
          label: 'Finder',
          size: ChunkyButtonSize.small,
          variant: ChunkyButtonVariant.secondary,
          onPressed: () =>
              kantorOpenOnMac(context, ref, office, path, finder: true),
        ),
        ChunkyButton(
          label: 'Salin path',
          size: ChunkyButtonSize.small,
          variant: ChunkyButtonVariant.secondary,
          onPressed: () => kantorCopy(context, path, 'Path disalin'),
        ),
      ],
    ),
  );
}
