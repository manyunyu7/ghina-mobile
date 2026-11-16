import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../session/kantor_session_page.dart';

/// Layar selebar ini (dp) atau lebih memakai dua panel: daftar agen di kiri,
/// chat sesi di kanan. Di bawahnya (layar luar, Fold tertutup) tampilan tetap
/// satu panel seperti biasa.
const kKantorTwoPaneMin = 600.0;

/// Lebar panel daftar di kiri.
double kantorListPaneWidth(double total) => total >= 900 ? 360 : 330;

/// Sesi yang terbuka di panel kanan, per kantor. Disimpan di provider supaya
/// tetap ada saat layar dilipat lalu dibuka lagi.
class KantorPaneSel extends Notifier<String?> {
  KantorPaneSel(this.officeId);
  final String officeId;

  @override
  String? build() => null;

  void select(String? sid) => state = sid;
}

final kantorPaneSelProvider =
    NotifierProvider.family<KantorPaneSel, String?, String>(KantorPaneSel.new);

/// Dipasang di atas daftar agen saat dua panel aktif: baris yang diketuk
/// mengganti panel kanan (tanpa push route) dan baris terpilih disorot.
class KantorPaneScope extends InheritedWidget {
  const KantorPaneScope({
    super.key,
    required this.selectedSid,
    required this.onSelect,
    required super.child,
  });

  final String? selectedSid;
  final void Function(String sid) onSelect;

  static KantorPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KantorPaneScope>();

  @override
  bool updateShouldNotify(KantorPaneScope old) =>
      old.selectedSid != selectedSid;
}

/// Daftar di kiri, detail di kanan.
class KantorTwoPane extends ConsumerWidget {
  const KantorTwoPane({
    super.key,
    required this.officeId,
    required this.list,
    required this.width,
  });

  final String officeId;
  final Widget list;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(kantorPaneSelProvider(officeId));
    final g = context.ghina;
    return Row(
      children: [
        SizedBox(
          width: kantorListPaneWidth(width),
          child: KantorPaneScope(
            selectedSid: sel,
            onSelect: (sid) =>
                ref.read(kantorPaneSelProvider(officeId).notifier).select(sid),
            child: list,
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: g.border),
        Expanded(
          child: sel == null
              ? Center(
                  key: const ValueKey('pane-empty'),
                  child: Text(
                    'Pilih agen di sebelah kiri',
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  ),
                )
              // MediaQuery.size = lebar panel, supaya lebar bubble dihitung
              // dari panel kanan, bukan dari seluruh layar
              : LayoutBuilder(
                  builder: (context, box) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(size: Size(box.maxWidth, box.maxHeight)),
                    child: KantorSessionPage(
                      key: const ValueKey('pane-session'),
                      officeId: officeId,
                      sid: sel,
                      embedded: true,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
