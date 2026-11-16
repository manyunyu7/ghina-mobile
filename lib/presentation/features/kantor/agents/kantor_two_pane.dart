import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../pages/kantor_office_switcher.dart';
import '../session/chat_context.dart';
import '../session/kantor_session_page.dart';

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
  /// dari daftar agen di layar sempit. Saat layar dibuka lagi (>= 600dp)
  /// halaman itu menutup sendiri dan chat pindah ke panel kanan.
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
  if (pane != null) {
    pane.onSelect(sid);
    return;
  }
  final c = ProviderScope.containerOf(context, listen: false);
  final chat = (
    connection: kantorPaneConnection(c.read(kantorApiProvider)),
    office: office,
    sid: sid,
  );
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

/// Daftar di kiri (dengan header kantor aktif), detail di kanan.
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
    // pilihan dari koneksi (server) lain tidak berlaku di sini
    final chat = pane.chat?.connection == connection ? pane.chat : null;
    final g = context.ghina;
    return Row(
      children: [
        SizedBox(
          width: kantorListPaneWidth(width),
          child: Column(
            children: [
              _OfficeHeader(officeId: officeId, name: officeName),
              Divider(height: 1, thickness: 1, color: g.border),
              Expanded(
                child: KantorPaneScope(
                  selectedSid: chat?.office == officeId ? chat?.sid : null,
                  onSelect: (sid) =>
                      ref.read(kantorPaneProvider.notifier).select((
                        connection: connection,
                        office: officeId,
                        sid: sid,
                      )),
                  child: list,
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: g.border),
        Expanded(
          child: chat == null
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
                      key: ValueKey('pane-session-${chat.office}-${chat.sid}'),
                      officeId: chat.office,
                      sid: chat.sid,
                      embedded: true,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Nama kantor aktif di atas panel kiri; satu ketukan membuka pemilih kantor
/// yang sama dengan judul halaman kantor.
class _OfficeHeader extends StatelessWidget {
  const _OfficeHeader({required this.officeId, required this.name});

  final String officeId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Material(
      color: g.surface,
      child: InkWell(
        key: const ValueKey('pane-office'),
        onTap: () =>
            showKantorOfficeSwitcher(context, currentId: officeId, tab: 'agen'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.apartment_rounded, size: 20, color: g.textSecondary),
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
    );
  }
}

/// Dipanggil di halaman sesi penuh (bukan panel). Bila halaman ini dibuka dari
/// daftar agen di layar sempit lalu layar dibuka (>= 600dp), halaman menutup
/// sendiri dan chat yang sama pindah ke panel kanan. Draf dan posisi scroll
/// ikut karena disimpan di KantorChatMemory per koneksi+kantor+sesi.
void kantorDockIfWide(
  BuildContext context,
  WidgetRef ref, {
  required String officeId,
  required String sid,
}) {
  final pane = ref.watch(kantorPaneProvider);
  final wide = MediaQuery.sizeOf(context).width >= kKantorTwoPaneMin;
  if (!wide || !pane.routed) return;
  final chat = (
    connection: kantorPaneConnection(ref.read(kantorApiProvider)),
    office: officeId,
    sid: sid,
  );
  if (pane.chat != chat) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final now = ref.read(kantorPaneProvider);
    if (!now.routed || now.chat != chat) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (MediaQuery.sizeOf(context).width < kKantorTwoPaneMin) return;
    ref.read(kantorPaneProvider.notifier).dock(chat);
    Navigator.of(context).pop();
  });
}

/// Kebalikan dari [kantorDockIfWide]: daftar agen yang tadinya dua panel
/// menjadi satu panel (Fold ditutup) selagi ada chat di panel kanan. Chat itu
/// dibuka sebagai halaman penuh supaya pengguna tetap di percakapannya.
Future<void> kantorUndockToRoute(BuildContext context, WidgetRef ref) async {
  final chat = ref.read(kantorPaneProvider).chat;
  if (chat == null) return;
  if (chat.connection != kantorPaneConnection(ref.read(kantorApiProvider))) {
    return;
  }
  // ada halaman lain di atas daftar (mis. sesi yang sama sudah terbuka)
  if (ModalRoute.of(context)?.isCurrent == false) return;
  final notifier = ref.read(kantorPaneProvider.notifier)..routed(chat);
  await context.push(_sessionPath(chat.office, chat.sid));
  notifier.left(chat);
}
