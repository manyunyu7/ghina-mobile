import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../pages/kantor_office_switcher.dart';
import '../session/chat_context.dart';
import '../session/chat_view_prefs.dart';
import '../session/kantor_feed.dart';
import '../session/kantor_session_page.dart';
import '../session/kantor_snapshot_store.dart';
import '../session/kantor_tabletop.dart';
import '../widgets/kantor_states.dart';
import 'kantor_agents_tab.dart';
import 'kantor_office_bar.dart';

/// Layar selebar ini (dp) atau lebih memakai dua panel: daftar agen di kiri,
/// chat sesi di kanan. Di bawahnya (layar luar, Fold tertutup) tampilan tetap
/// satu panel seperti biasa.
const kKantorTwoPaneMin = 600.0;

/// Lebar panel daftar di kiri (±320–360dp).
double kantorListPaneWidth(double total) => total >= 900 ? 360 : 330;

/// Chat yang terbuka di panel kanan. Kantornya ikut disimpan: setelah pindah
/// kantor lewat header panel kiri, daftar kiri ikut kantor baru tetapi chat di
/// kanan tetap terbuka sampai pengguna memilih agen lain.
typedef KantorPaneChat = ({String connection, String office, String sid});

@immutable
class KantorPaneState {
  const KantorPaneState({this.chat, this.routed = false});

  final KantorPaneChat? chat;

  /// True selama [chat] tampil sebagai halaman penuh (route sesi) yang dibuka
  /// dari daftar agen di layar sempit. Selama itu panel kanan daftar agen tidak
  /// ikut menampilkannya (supaya tidak ada dua chat yang sama). Saat layar
  /// dibuka lagi (>= 600dp) halaman itu menutup sendiri dan chat pindah ke
  /// panel kanan.
  final bool routed;
}

/// Satu untuk seluruh app (bukan per kantor), di memori saja, jadi tetap ada
/// saat layar dilipat/dibuka dan saat pindah kantor.
class KantorPaneNotifier extends Notifier<KantorPaneState> {
  @override
  KantorPaneState build() => const KantorPaneState();

  /// Dua panel: [chat] tampil di panel kanan.
  void select(KantorPaneChat chat) => state = KantorPaneState(chat: chat);

  /// Layar sempit: [chat] dibuka sebagai halaman penuh.
  void routed(KantorPaneChat chat) =>
      state = KantorPaneState(chat: chat, routed: true);

  /// Halaman penuh [chat] menutup karena layar melebar: chat pindah ke panel.
  void dock(KantorPaneChat chat) {
    if (state.chat == chat) state = KantorPaneState(chat: chat);
  }

  /// Pengguna kembali dari halaman penuh [chat] ke daftar (layar sempit).
  void left(KantorPaneChat chat) {
    if (state.routed && state.chat == chat) state = const KantorPaneState();
  }

  /// [chat] dibuka di halaman sesi lewat jalur lain (Kompleks, notifikasi,
  /// switcher, panel kiri halaman sesi): chat itu pindah ke sana, panel kanan
  /// daftar agen dikosongkan supaya chat yang sama tidak terbuka dua kali.
  void release(KantorPaneChat chat) {
    if (!state.routed && state.chat == chat) state = const KantorPaneState();
  }
}

final kantorPaneProvider =
    NotifierProvider<KantorPaneNotifier, KantorPaneState>(
      KantorPaneNotifier.new,
    );

String kantorPaneConnection(KantorApi? api) =>
    api == null ? '' : kantorConnectionKey(api.config);

/// Halaman sesi yang dibuka dari daftar agen (sama seperti sebelum dua panel).
String _sessionPath(String office, String sid) => '/kantor/o/$office/s/$sid';

/// Ketuk agen di daftar. Dua panel: ganti panel kanan tanpa push route. Layar
/// sempit: push halaman sesi seperti biasa, dan dicatat supaya chat itu bisa
/// pindah ke panel kanan kalau layar dibuka selagi chat masih terbuka.
Future<void> kantorOpenFromList(
  BuildContext context,
  String office,
  String sid,
) async {
  final pane = KantorPaneScope.read(context);
  final c = ProviderScope.containerOf(context, listen: false);
  final chat = (
    connection: kantorPaneConnection(c.read(kantorApiProvider)),
    office: office,
    sid: sid,
  );
  // a chat kept on disk but not in memory shows at once too
  await kantorWarmChat(c, chat);
  if (!context.mounted) return;
  if (pane != null) {
    pane.onSelect(sid);
    return;
  }
  final notifier = c.read(kantorPaneProvider.notifier)..routed(chat);
  await context.push(_sessionPath(office, sid));
  notifier.left(chat);
}

/// Dipasang di atas daftar agen saat dua panel aktif: baris yang diketuk
/// mengganti panel kanan (tanpa push route) dan baris terpilih disorot.
class KantorPaneScope extends InheritedWidget {
  const KantorPaneScope({
    super.key,
    required this.selectedSid,
    required this.onSelect,
    required super.child,
  });

  /// Sesi di panel kanan, hanya bila sesi itu milik kantor yang sedang
  /// ditampilkan di kiri.
  final String? selectedSid;
  final void Function(String sid) onSelect;

  /// Untuk build: ikut dibangun ulang saat pilihan berubah.
  static KantorPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KantorPaneScope>();

  /// Untuk callback (onTap), tanpa mendaftarkan dependensi.
  static KantorPaneScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<KantorPaneScope>();

  @override
  bool updateShouldNotify(KantorPaneScope old) =>
      old.selectedSid != selectedSid;
}

/// Daftar di kiri (dengan header kantor aktif), detail di kanan. Dipakai tab
/// Agen di halaman kantor; chat kanan diambil dari [kantorPaneProvider].
class KantorTwoPane extends ConsumerWidget {
  const KantorTwoPane({
    super.key,
    required this.officeId,
    required this.officeName,
    required this.list,
    required this.width,
  });

  final String officeId;
  final String officeName;
  final Widget list;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = kantorPaneConnection(ref.watch(kantorApiProvider));
    final pane = ref.watch(kantorPaneProvider);
    // pilihan dari koneksi (server) lain tidak berlaku di sini; chat yang
    // sedang tampil sebagai halaman penuh tidak dibuka dua kali
    final chat = pane.chat?.connection == connection && !pane.routed
        ? pane.chat
        : null;
    return _PaneRow(
      width: width,
      header: _OfficeHeader(officeId: officeId, name: officeName),
      bar: KantorOfficeBar(currentId: officeId),
      selectedSid: chat?.office == officeId ? chat?.sid : null,
      onSelect: (sid) => ref.read(kantorPaneProvider.notifier).select((
        connection: connection,
        office: officeId,
        sid: sid,
      )),
      list: list,
      right: chat == null
          ? const _PaneEmpty()
          // MediaQuery.size = lebar panel, supaya lebar bubble dihitung
          // dari panel kanan, bukan dari seluruh layar
          : LayoutBuilder(
              builder: (context, box) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(size: Size(box.maxWidth, box.maxHeight)),
                child: KantorSessionPage(
                  key: ValueKey('pane-session-${chat.office}-${chat.sid}'),
                  officeId: chat.office,
                  sid: chat.sid,
                  embedded: true,
                ),
              ),
            ),
    );
  }
}

/// Tata letak dua panel bersama: header kantor + daftar agen + [bar] (ganti
/// kantor, di jangkauan jempol) di kiri, [right] di kanan. [safe] untuk
/// halaman tanpa AppBar (padding status bar di kiri).
class _PaneRow extends StatelessWidget {
  const _PaneRow({
    required this.width,
    required this.header,
    required this.bar,
    required this.selectedSid,
    required this.onSelect,
    required this.list,
    required this.right,
    this.safe = false,
  });

  final double width;
  final Widget header;
  final Widget bar;
  final String? selectedSid;
  final void Function(String sid) onSelect;
  final Widget list;
  final Widget right;
  final bool safe;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final left = Column(
      children: [
        header,
        Divider(height: 1, thickness: 1, color: g.border),
        Expanded(
          child: KantorPaneScope(
            selectedSid: selectedSid,
            onSelect: onSelect,
            child: list,
          ),
        ),
        bar,
      ],
    );
    return Row(
      children: [
        SizedBox(
          width: kantorListPaneWidth(width),
          child: safe
              ? SafeArea(right: false, bottom: false, child: left)
              : left,
        ),
        VerticalDivider(width: 1, thickness: 1, color: g.border),
        Expanded(child: right),
      ],
    );
  }
}

class _PaneEmpty extends StatelessWidget {
  const _PaneEmpty();

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('pane-empty'),
    child: Text(
      'Pilih agen di sebelah kiri',
      style: GhinaType.body.copyWith(color: context.ghina.textSecondary),
    ),
  );
}

/// Nama kantor aktif di atas panel kiri; satu ketukan membuka pemilih kantor
/// yang sama dengan judul halaman kantor. [onOffice]: pilihan kantor hanya
/// mengganti daftar kiri (tanpa pindah halaman). [onBack]: tombol kembali
/// untuk halaman sesi yang tidak punya AppBar di kiri.
class _OfficeHeader extends StatelessWidget {
  const _OfficeHeader({
    required this.officeId,
    required this.name,
    this.onOffice,
    this.onBack,
  });

  final String officeId;
  final String name;
  final void Function(String id)? onOffice;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Material(
      color: g.surface,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              key: const ValueKey('pane-back'),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: InkWell(
              key: const ValueKey('pane-office'),
              onTap: () => showKantorOfficeSwitcher(
                context,
                currentId: officeId,
                tab: 'agen',
                onOffice: onOffice,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  onBack == null ? 16 : 4,
                  10,
                  8,
                  10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.apartment_rounded,
                      size: 20,
                      color: g.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body.copyWith(
                          fontWeight: FontWeight.w800,
                          color: g.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: g.textSecondary,
                      semanticLabel: 'Pindah kantor',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Route sesi (`/kantor/o/:office/s/:sid`), dari jalur mana pun dibuka
/// (daftar agen, Kompleks, notifikasi, hub, switcher).
///
/// - Lebar < [kKantorTwoPaneMin]: halaman penuh seperti biasa.
/// - Lebar >= [kKantorTwoPaneMin]: dua panel. Kiri daftar agen kantor sesi ini
///   (header kantor + pemilih kantor yang hanya mengganti daftar kiri), kanan
///   chat. Ketuk agen di kiri mengganti chat kanan lewat state, tanpa menambah
///   route, jadi kembali tetap keluar dari halaman ini.
///
/// Isi sesi dipindah (GlobalKey), bukan dibuat ulang, saat lebar berubah, jadi
/// hanya ada satu chat untuk sesi ini dan tab/scroll/draf tetap.
///
/// Halaman yang dibuka dari daftar agen di layar sempit ([KantorPaneState.routed])
/// menutup sendiri saat layar dibuka, dan chatnya pindah ke panel kanan
/// halaman kantor di bawahnya.
class KantorSessionHost extends ConsumerStatefulWidget {
  const KantorSessionHost({
    super.key,
    required this.officeId,
    required this.sid,
    this.tab,
  });

  final String officeId;
  final String sid;
  final String? tab;

  @override
  ConsumerState<KantorSessionHost> createState() => _KantorSessionHostState();
}

class _KantorSessionHostState extends ConsumerState<KantorSessionHost> {
  late String _office = widget.officeId;
  late String _sid = widget.sid;
  late String? _tab = widget.tab;

  /// Kantor yang daftarnya tampil di kiri (bisa beda dari kantor chat kanan).
  late String _listOffice = widget.officeId;

  /// Satu per chat: chat lain = isi baru, lebar berubah = isi yang sama.
  GlobalKey _viewKey = GlobalKey(debugLabel: 'kantor-session-view');

  /// Sudah menyerahkan chatnya ke panel kanan halaman kantor dan sedang
  /// menutup: jangan tampilkan chat lagi (supaya tidak dobel saat animasi).
  bool _docked = false;

  KantorPaneChat get _chat => (
    connection: kantorPaneConnection(ref.read(kantorApiProvider)),
    office: _office,
    sid: _sid,
  );

  @override
  void initState() {
    super.initState();
    _claim();
  }

  @override
  void didUpdateWidget(KantorSessionHost old) {
    super.didUpdateWidget(old);
    if (old.officeId != widget.officeId || old.sid != widget.sid) {
      _show(widget.officeId, widget.sid, tab: widget.tab);
      _listOffice = widget.officeId;
    }
  }

  /// Chat ini sekarang tampil di sini: lepaskan dari panel kanan halaman
  /// kantor kalau di sana juga terbuka.
  void _claim() {
    final chat = _chat;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(kantorPaneProvider.notifier).release(chat);
    });
  }

  void _show(String office, String sid, {String? tab}) {
    if (office == _office && sid == _sid) return;
    _office = office;
    _sid = sid;
    _tab = tab;
    _viewKey = GlobalKey(debugLabel: 'kantor-session-view');
    _claim();
  }

  /// Lihat [KantorPaneState.routed]: halaman dari daftar agen di layar sempit
  /// menutup sendiri saat layar dibuka; chatnya pindah ke panel kanan. Draf dan
  /// posisi scroll ikut karena disimpan di KantorChatMemory.
  void _dockIfWide(KantorPaneState pane, bool wide) {
    if (!wide || !pane.routed || _docked) return;
    final chat = _chat;
    if (pane.chat != chat) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _docked) return;
      final now = ref.read(kantorPaneProvider);
      if (!now.routed || now.chat != chat) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (MediaQuery.sizeOf(context).width < kKantorTwoPaneMin) return;
      setState(() => _docked = true);
      ref.read(kantorPaneProvider.notifier).dock(chat);
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pane = ref.watch(kantorPaneProvider);
    final size = MediaQuery.sizeOf(context);
    // mode meja (Fold setengah terbuka, engsel mendatar): chat satu panel
    // selebar layar, dibagi atas/bawah engsel (lihat kantor_tabletop.dart)
    final wide =
        size.width >= kKantorTwoPaneMin && kantorTabletopHinge(context) == null;
    _dockIfWide(pane, wide);
    if (_docked) {
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    }
    final view = KeyedSubtree(
      key: _viewKey,
      child: KantorSessionView(
        officeId: _office,
        sid: _sid,
        tab: _tab,
        embedded: wide,
      ),
    );
    if (!wide) return view;
    final feed = ref.watch(kantorOfficeFeedProvider(_listOffice));
    final style = ref.watch(chatViewPrefsProvider.select((p) => p.style));
    final api = ref.watch(kantorApiProvider);
    final rightWidth = size.width - kantorListPaneWidth(size.width) - 1;
    return Material(
      key: const ValueKey('session-two-pane'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListenableBuilder(
        listenable: feed,
        builder: (context, _) => _PaneRow(
          width: size.width,
          safe: true,
          header: _OfficeHeader(
            officeId: _listOffice,
            name: '${feed.office?['name'] ?? _listOffice}',
            onOffice: (id) => setState(() => _listOffice = id),
            onBack: () => Navigator.of(context).maybePop(),
          ),
          bar: KantorOfficeBar(
            currentId: _listOffice,
            onOffice: (id) => setState(() => _listOffice = id),
          ),
          selectedSid: _office == _listOffice ? _sid : null,
          onSelect: (sid) => setState(() => _show(_listOffice, sid)),
          list: feed.loading
              ? const KantorLoading()
              : feed.error != null && feed.office == null
              ? KantorErrorView(error: feed.error!, onRetry: feed.load)
              : kantorAgentList(feed, style, api),
          // MediaQuery.size = lebar panel kanan (lebar bubble chat)
          right: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: Size(rightWidth, size.height)),
            child: view,
          ),
        ),
      ),
    );
  }
}

/// Kebalikan dari docking di [KantorSessionHost]: daftar agen yang tadinya dua
/// panel menjadi satu panel (Fold ditutup) selagi ada chat di panel kanan.
/// Chat itu dibuka sebagai halaman penuh supaya pengguna tetap di
/// percakapannya.
Future<void> kantorUndockToRoute(BuildContext context, WidgetRef ref) async {
  final chat = ref.read(kantorPaneProvider).chat;
  if (chat == null || ref.read(kantorPaneProvider).routed) return;
  if (chat.connection != kantorPaneConnection(ref.read(kantorApiProvider))) {
    return;
  }
  // ada halaman lain di atas daftar (mis. sesi yang sama sudah terbuka)
  if (ModalRoute.of(context)?.isCurrent == false) return;
  final notifier = ref.read(kantorPaneProvider.notifier)..routed(chat);
  await context.push(_sessionPath(chat.office, chat.sid));
  notifier.left(chat);
}
