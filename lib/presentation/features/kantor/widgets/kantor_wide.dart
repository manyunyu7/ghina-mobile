import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// Layar selebar ini (dp) atau lebih dianggap "lebar": layar dalam Galaxy Fold
/// (±830dp), tablet, HP diputar mendatar. Sama dengan ambang dua panel chat
/// (`kKantorTwoPaneMin`) supaya seluruh app berpindah layout bersamaan.
const kKantorWideMin = 600.0;

/// Lebar baca nyaman untuk teks panjang (wiki, detail kartu, transkrip).
const kKantorReadableMax = 760.0;

/// Lebar maksimal daftar/form satu kolom di layar lebar.
const kKantorListMax = 720.0;

bool kantorIsWideWidth(double width) => width >= kKantorWideMin;

/// Layar sekarang lebar? (berdasarkan ukuran jendela, bukan constraint lokal)
bool kantorIsWide(BuildContext context) =>
    kantorIsWideWidth(MediaQuery.sizeOf(context).width);

/// Lebar panel daftar di kiri pada tampilan daftar–detail.
double kantorMasterWidth(double total) => total >= 900 ? 360 : 320;

/// Jumlah kolom grid supaya tiap ubin minimal [minTile] dp, antara 1..[max].
int kantorGridColumns(double width, {double minTile = 280, int max = 4}) =>
    math.max(1, math.min(max, (width / minTile).floor()));

/// Membatasi lebar [child] dan menaruhnya di tengah. Di layar sempit tidak
/// berpengaruh (lebarnya memang di bawah [maxWidth]).
class KantorReadable extends StatelessWidget {
  const KantorReadable({
    super.key,
    required this.child,
    this.maxWidth = kKantorReadableMax,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Membuka halaman detail secara adaptif:
/// - layar sempit: halaman penuh biasa (MaterialPageRoute);
/// - layar lebar: panel samping dari kanan (lebar ±560dp) di atas halaman
///   asal, jadi konteks di belakangnya tetap terlihat. Tutup dengan back,
///   ketuk di luar panel, atau `Navigator.pop` seperti biasa.
Future<T?> kantorPushAdaptive<T>(
  BuildContext context,
  WidgetBuilder builder, {
  double panelWidth = 560,
}) {
  final nav = Navigator.of(context);
  if (!kantorIsWide(context)) {
    return nav.push<T>(MaterialPageRoute<T>(builder: builder));
  }
  return nav.push<T>(
    KantorSidePanelRoute<T>(builder: builder, width: panelWidth),
  );
}

/// Route panel samping kanan untuk layar lebar.
class KantorSidePanelRoute<T> extends PopupRoute<T> {
  KantorSidePanelRoute({required this.builder, this.width = 560});

  final WidgetBuilder builder;
  final double width;

  @override
  Color? get barrierColor => Colors.black38;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Tutup panel';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final total = MediaQuery.sizeOf(context).width;
    final w = math.min(width, total * 0.75);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: w,
        height: double.infinity,
        child: Material(
          elevation: 8,
          clipBehavior: Clip.antiAlias,
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween(
      begin: const Offset(0.25, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: FadeTransition(opacity: animation, child: child),
  );
}

/// Tampilan daftar–detail (master–detail) seperti WhatsApp di tablet:
///
/// - layar lebar: daftar di kiri ([kantorMasterWidth]), detail item terpilih
///   di kanan. Detail punya Navigator sendiri, jadi halaman lanjutan dari
///   detail (tautan wiki, editor, dsb.) tetap terbuka di panel kanan dan
///   tombol kembali di AppBar-nya hanya mundur di panel itu.
/// - layar sempit: hanya daftar; memilih item membuka detail sebagai halaman
///   penuh biasa.
///
/// [master] menerima item terpilih (untuk disorot) dan fungsi `open` yang
/// harus dipanggil saat item diketuk. [keyOf] memberi kunci unik per item
/// supaya detail dibuat ulang saat item berganti.
class KantorMasterDetail<T> extends StatefulWidget {
  const KantorMasterDetail({
    super.key,
    required this.master,
    required this.detail,
    required this.keyOf,
    this.empty,
    this.onClosed,
    this.initial,
  });

  final Widget Function(
    BuildContext context,
    T? selected,
    void Function(T) open,
  )
  master;
  final Widget Function(BuildContext context, T item) detail;
  final String Function(T item) keyOf;

  /// Isi panel kanan saat belum ada yang dipilih.
  final Widget? empty;

  /// Dipanggil setelah detail ditutup (halaman penuh kembali) atau diganti,
  /// misalnya untuk memuat ulang daftar.
  final VoidCallback? onClosed;

  final T? initial;

  @override
  State<KantorMasterDetail<T>> createState() => _KantorMasterDetailState<T>();
}

class _KantorMasterDetailState<T> extends State<KantorMasterDetail<T>> {
  T? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  Future<void> _open(T item) async {
    if (kantorIsWide(context)) {
      final changed =
          _selected != null &&
          widget.keyOf(_selected as T) != widget.keyOf(item);
      setState(() => _selected = item);
      if (changed) widget.onClosed?.call();
      return;
    }
    setState(() => _selected = item);
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (c) => widget.detail(c, item)));
    if (!mounted) return;
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = kantorIsWide(context) && c.maxWidth >= kKantorWideMin;
      if (!wide) return widget.master(context, null, _open);
      final colors = Theme.of(context).colorScheme;
      final sel = _selected;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: kantorMasterWidth(c.maxWidth),
            child: widget.master(context, sel, _open),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
          Expanded(
            child: sel == null
                ? (widget.empty ?? const KantorPaneEmpty())
                : HeroControllerScope.none(
                    child: Navigator(
                      key: ValueKey('md-${widget.keyOf(sel)}'),
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (c) => widget.detail(c, sel),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

/// Isi panel kanan kosong standar.
class KantorPaneEmpty extends StatelessWidget {
  const KantorPaneEmpty({
    super.key,
    this.icon = Icons.touch_app_outlined,
    this.text = 'Pilih item di kiri untuk melihat isinya.',
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GhinaSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.outline),
            const SizedBox(height: GhinaSpace.sm),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
