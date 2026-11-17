import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../agents/kantor_active_agents.dart';
import '../kantor_data.dart';
import '../pages/kantor_complex_agent_switcher.dart';
import '../widgets/kantor_sprite.dart';
import 'chat_context.dart';
import 'kantor_feed.dart';
import 'kantor_konteks.dart';
import 'kantor_label.dart';
import 'kantor_snapshot_store.dart';

/// Peringkat semua agen hidup dari semua kantor dan semua koneksi server
/// tersimpan, untuk pindah cepat (avatar kecil di header chat, pencari cepat,
/// kartu agen mode meja).
///
/// Urutan: perlu tindakan (menunggu izin / bertanya / `blocker` dari server)
/// → sedang bekerja → terakhir dibuka ([kantorRecentComplexChatsProvider]) →
/// idle lainnya.

/// Kelompok peringkat. Angka kecil tampil lebih dulu.
enum KantorAgentGroup { action, working, recent, idle }

/// Satu sumber `GET /api/state`: koneksi aktif atau koneksi tersimpan lain.
typedef KantorAgentSource = ({
  String connection,
  String connectionName,
  bool active,
  Json state,
});

/// Satu agen (sesi hidup) beserta kantor dan koneksinya.
@immutable
class KantorRankedAgent {
  const KantorRankedAgent({
    required this.connection,
    required this.connectionName,
    required this.active,
    required this.office,
    required this.session,
    this.recent = -1,
  });

  /// Id profil kompleks (koneksi server); '' bila koneksi aktif tanpa profil.
  final String connection;

  /// Nama mesin/kompleks (mis. "Mac mini"); bisa kosong.
  final String connectionName;

  /// Sesi ini ada di koneksi yang sedang aktif (pindah tanpa ganti server).
  final bool active;

  final Json office;
  final Json session;

  /// Posisi di daftar "terakhir dibuka" (0 = paling baru), -1 bila tidak ada.
  final int recent;

  KantorAgentRef get _ref => KantorAgentRef(office, session);

  String get officeId => '${office['id']}';
  String get officeName => '${office['name'] ?? officeId}';
  String get sid => '${session['sid']}';
  String get name => _ref.name;
  Json get look => _ref.look;
  String get status => '${session['status'] ?? ''}';

  /// Apa yang sedang dikerjakan / diminta (untuk subjudul).
  String get doing => _ref.doing;
  bool get codex => _ref.codex;

  /// Permintaan izin / pertanyaan yang menunggu pemilik.
  bool get waiting => _ref.waiting;

  /// Field `blocker` dari server (mis. perlu login). Server lama tidak
  /// mengirimnya; nilai kosong (null, false, '', {}) dianggap tidak ada.
  Object? get blocker {
    final b = session['blocker'];
    if (b == null || b == false) return null;
    if (b is String && b.trim().isEmpty) return null;
    if (b is Map && b.isEmpty) return null;
    return b;
  }

  /// Merah: pemilik perlu bertindak.
  bool get needsAction => waiting || blocker != null;

  /// Biru: sedang bekerja (dan tidak sedang menunggu pemilik).
  bool get working =>
      !needsAction && (status == 'working' || status == 'starting');

  KantorAgentGroup get group => needsAction
      ? KantorAgentGroup.action
      : working
      ? KantorAgentGroup.working
      : recent >= 0
      ? KantorAgentGroup.recent
      : KantorAgentGroup.idle;

  /// Label singkat alasan perlu tindakan: izin, tanya, login, atau perlu.
  String get actionLabel {
    final w = session['waiting'];
    if (w is Map) return w['tool'] == 'AskUserQuestion' ? 'tanya' : 'izin';
    if (waiting) return 'izin';
    final b = blocker;
    final kind = b is Map ? '${b['kind'] ?? b['type'] ?? ''}' : '$b';
    return kind.toLowerCase().contains('login') ? 'login' : 'perlu';
  }

  /// Sama dengan kunci "terakhir dibuka" di pemilih kompleks.
  String get identity => kantorComplexChatIdentity(connection, officeId, sid);

  /// Teks yang dicari: nama agen, kantor, mesin, judul, model, alat.
  String get haystack => '$connectionName ${_ref.haystack}'.toLowerCase();

  /// Untuk urutan dalam satu kelompok: yang terakhir aktif lebih dulu.
  Object? get lastSeen => session['lastSeen'];
}

int _cmpSeen(Object? a, Object? b) {
  if (a is num && b is num) return b.compareTo(a);
  return '${b ?? ''}'.compareTo('${a ?? ''}');
}

/// Fungsi murni pengurut peringkat (mudah dites). [recent] = daftar identitas
/// [kantorComplexChatIdentity], terbaru dulu.
List<KantorRankedAgent> kantorRankAgents(
  Iterable<KantorAgentSource> sources,
  List<String> recent,
) {
  final seen = <String>{};
  final out = <KantorRankedAgent>[];
  for (final src in sources) {
    for (final o in asJsonList(src.state['offices'])) {
      for (final s in asJsonList(o['sessions'])) {
        if (s['status'] == 'ended' || s['sid'] == null) continue;
        final id = kantorComplexChatIdentity(
          src.connection,
          '${o['id']}',
          '${s['sid']}',
        );
        if (!seen.add(id)) continue;
        out.add(
          KantorRankedAgent(
            connection: src.connection,
            connectionName: src.connectionName,
            active: src.active,
            office: o,
            session: s,
            recent: recent.indexOf(id),
          ),
        );
      }
    }
  }
  final order = {for (var i = 0; i < out.length; i++) out[i]: i};
  out.sort((a, b) {
    final g = a.group.index - b.group.index;
    if (g != 0) return g;
    // dalam kelompok: yang baru dibuka dulu, lalu yang terakhir aktif
    final ra = a.recent < 0 ? 1 << 20 : a.recent;
    final rb = b.recent < 0 ? 1 << 20 : b.recent;
    if (ra != rb) return ra - rb;
    final s = _cmpSeen(a.lastSeen, b.lastSeen);
    return s != 0 ? s : order[a]! - order[b]!;
  });
  return out;
}

/// Hasil [kantorAgentRankProvider].
@immutable
class KantorAgentRanking {
  const KantorAgentRanking({
    this.agents = const [],
    this.sources = const [],
    this.offline = const [],
    this.loading = false,
  });

  /// Semua agen hidup, sudah diurutkan.
  final List<KantorRankedAgent> agents;

  /// Data mentah per koneksi (untuk menggabungkan data kantor yang sedang
  /// dibuka bila state belum ada).
  final List<KantorAgentSource> sources;

  /// Koneksi tersimpan yang gagal dihubungi.
  final List<KantorComplexProfile> offline;

  /// Masih ada koneksi yang sedang dimuat.
  final bool loading;
}

/// Semua agen hidup: koneksi aktif dari [kantorStateProvider] (sudah hidup di
/// app dan ikut event), koneksi tersimpan lain dari [kantorComplexStateProvider]
/// (sama seperti pemilih kompleks). Satu koneksi yang mati tidak menyembunyikan
/// agen koneksi lain.
final kantorAgentRankProvider = Provider.autoDispose<KantorAgentRanking>((ref) {
  final active = ref.watch(kantorActiveComplexProvider);
  final profiles =
      ref.watch(kantorComplexProfilesProvider).value ??
      const <KantorComplexProfile>[];
  final recent = ref.watch(kantorRecentComplexChatsProvider);
  final sources = <KantorAgentSource>[];
  final offline = <KantorComplexProfile>[];
  var loading = false;

  final here = ref.watch(kantorStateProvider);
  if (here.value != null) {
    sources.add((
      connection: active?.id ?? '',
      connectionName: active?.name ?? '',
      active: true,
      state: here.value!,
    ));
  } else if (here.isLoading) {
    loading = true;
  }
  for (final p in profiles) {
    if (p.id == active?.id) continue;
    final st = ref.watch(kantorComplexStateProvider(p.id));
    if (st.value != null) {
      sources.add((
        connection: p.id,
        connectionName: p.name,
        active: false,
        state: st.value!,
      ));
    } else if (st.hasError) {
      offline.add(p);
    } else {
      loading = true;
    }
  }
  return KantorAgentRanking(
    agents: kantorRankAgents(sources, recent),
    sources: sources,
    offline: offline,
    loading: loading,
  );
});

/// Pindah ke chat [a] dengan navigasi yang sama dengan pemilih agen: rute
/// `/kantor/o/:office/s/:sid` lewat `go` (mengganti halaman sesi). Agen di
/// koneksi lain: koneksi itu diaktifkan dulu (dicek, gagal = tetap di koneksi
/// lama dan error dilempar). Chat dihangatkan dari cache disk dulu supaya
/// riwayatnya langsung tampil. [beforeGo] dipanggil tepat sebelum pindah
/// (mis. menutup sheet).
Future<void> kantorOpenRankedAgent(
  BuildContext context,
  KantorRankedAgent a, {
  String? tab,
  VoidCallback? beforeGo,
}) async {
  final c = ProviderScope.containerOf(context, listen: false);
  final router = GoRouter.of(context);
  if (!a.active) {
    await c.read(kantorConfigProvider.notifier).activate(a.connection);
    unawaited(
      c
          .read(kantorRecentComplexChatsProvider.notifier)
          .remember(a.connection, a.officeId, a.sid),
    );
  }
  final api = c.read(kantorApiProvider);
  if (api != null) {
    await kantorWarmChat(c, (
      connection: kantorConnectionKey(api.config),
      office: a.officeId,
      sid: a.sid,
    ));
  }
  beforeGo?.call();
  router.go(
    kantorAgentPath(a.officeId, a.sid, tab: kantorSwitchSessionTab(tab)),
  );
}

/// Ambil riwayat chat beberapa agen teratas lebih dulu (hanya mengisi ruang
/// kosong cache), supaya pindah lewat avatar langsung menampilkan riwayat.
void kantorPrefetchRanked(
  ProviderContainer c,
  Iterable<KantorRankedAgent> agents,
) {
  final byOffice = <(String, String), List<String>>{};
  for (final a in agents) {
    byOffice.putIfAbsent((a.connection, a.officeId), () => []).add(a.sid);
  }
  final cache = c.read(kantorTranscriptCacheProvider);
  for (final MapEntry(key: (conn, office), value: sids) in byOffice.entries) {
    KantorApi? api;
    try {
      final active = c.read(kantorActiveComplexProvider)?.id ?? '';
      api = conn == active
          ? c.read(kantorApiProvider)
          : c.read(kantorComplexApiProvider(conn));
    } catch (_) {
      api = null;
    }
    if (api == null) continue;
    unawaited(kantorPrefetchChats(api, cache, office, sids));
  }
}

/// Diameter luar avatar header: wajah 22dp + garis pemisah 1.5dp di tiap sisi.
const kKantorHeaderAvatar = 25.0;

/// Tumpang-tindih antar-avatar header.
const kKantorHeaderAvatarOverlap = 6.0;

/// Chip "+N" sedikit menumpang avatar terakhir (seperti tumpukan avatar).
const _kHeaderChipOverlap = 2.0;

/// Jumlah avatar header maksimum; 4 bila header selebar
/// [kKantorHeaderAgentsWide] atau lebih.
const kKantorHeaderAgentsMax = 3;
const kKantorHeaderAgentsWide = 400.0;

/// Deret avatar kecil agen penting di kanan judul chat (layar sempit, tab Chat
/// dan Terminal), tanpa nama dan tanpa tinggi tambahan di bawah header.
///
/// Isi hanya agen lain (bukan [currentSid]) yang perlu tindakan (cincin merah:
/// izin, tanya, blocker login) lalu yang sedang bekerja (cincin biru), urut
/// dari [kantorAgentRankProvider], maks [kKantorHeaderAgentsMax] (4 bila layar
/// ≥ [kKantorHeaderAgentsWide]). Avatar saling tumpang
/// [kKantorHeaderAvatarOverlap]; pojok kuning kecil = agen berlabel.
///
/// Lebar dibatasi [maxWidth] (sisa judul setelah nama agen saat ini mendapat
/// ruang minimumnya): bila tidak muat, jumlah avatar dikurangi dulu. Setelah
/// avatar ada chip "+N" (N = agen lain yang tidak tampil) yang membuka pencari
/// cepat lewat [onMore]. Tanpa agen penting hanya chip "+N"; tanpa agen lain
/// sama sekali tidak tampil apa-apa.
///
/// Ketuk avatar = [onOpen] (atau [kantorOpenRankedAgent] bila null). Tahan =
/// menu label ([showKantorLabelMenu]).
class KantorHeaderAgents extends ConsumerStatefulWidget {
  const KantorHeaderAgents({
    super.key,
    required this.maxWidth,
    this.currentSid,
    this.onOpen,
    this.onMore,
    this.background,
  });

  /// Lebar maksimum deret (avatar + chip).
  final double maxWidth;
  final String? currentSid;
  final void Function(KantorRankedAgent agent)? onOpen;
  final VoidCallback? onMore;

  /// Warna latar header, untuk garis pemisah antar-avatar yang bertumpuk.
  final Color? background;

  @override
  ConsumerState<KantorHeaderAgents> createState() => _KantorHeaderAgentsState();
}

class _KantorHeaderAgentsState extends ConsumerState<KantorHeaderAgents> {
  String _prefetched = '';

  bool _isCurrent(KantorRankedAgent a) =>
      a.active && widget.currentSid != null && a.sid == widget.currentSid;

  Future<void> _open(KantorRankedAgent a) async {
    final cb = widget.onOpen;
    if (cb != null) return cb(a);
    try {
      await kantorOpenRankedAgent(context, a);
    } catch (_) {
      if (!mounted) return;
      final where = a.connectionName.isEmpty ? a.officeName : a.connectionName;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Tidak bisa membuka $where. Periksa koneksi lalu coba lagi.',
          ),
        ),
      );
    }
  }

  /// Tahan avatar: label lengkap dan aksi ubah label.
  void _label(KantorRankedAgent a) => showKantorLabelMenu(
    context,
    a.session,
    name: a.name,
    officeId: a.officeId,
    connection: a.active ? null : a.connection,
  );

  /// Hangatkan chat beberapa agen teratas (sekali per daftar), supaya pindah
  /// lewat avatar langsung menampilkan riwayat dari cache.
  void _prefetch(List<KantorRankedAgent> others) {
    final top = others.take(6).toList();
    final sig = top.map((a) => a.identity).join('|');
    if (sig.isEmpty || sig == _prefetched) return;
    _prefetched = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      kantorPrefetchRanked(
        ProviderScope.containerOf(context, listen: false),
        top,
      );
    });
  }

  TextStyle _chipStyle(GhinaTokens g) => GhinaType.caption.copyWith(
    fontSize: 11.5,
    height: 1,
    fontWeight: FontWeight.w800,
    color: g.textSecondary,
  );

  /// Lebar chip "+[n]" (sama dengan tata letak [_MoreChip]).
  double _chipWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return math.max(_MoreChip.minWidth, w + 2 * _MoreChip.padding);
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(kantorAgentRankProvider).agents;
    final others = agents.where((a) => !_isCurrent(a)).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    _prefetch(others);
    final g = context.ghina;
    final style = _chipStyle(g);
    final limit = MediaQuery.sizeOf(context).width >= kKantorHeaderAgentsWide
        ? kKantorHeaderAgentsMax + 1
        : kKantorHeaderAgentsMax;
    final hot = others
        .where((a) => a.needsAction || a.working)
        .take(limit)
        .toList();
    const step = kKantorHeaderAvatar - kKantorHeaderAvatarOverlap;
    double faces(int k) => k == 0 ? 0 : kKantorHeaderAvatar + (k - 1) * step;
    double width(int k) {
      final n = others.length - k;
      if (n == 0) return faces(k);
      return faces(k) -
          (k > 0 ? _kHeaderChipOverlap : 0) +
          _chipWidth('+$n', style);
    }

    // avatar mengalah lebih dulu: kurangi jumlah sampai muat
    var k = hot.length;
    while (k > 0 && width(k) > widget.maxWidth) {
      k--;
    }
    final shown = hot.take(k).toList();
    final more = others.length - k;
    final bg = widget.background ?? Theme.of(context).colorScheme.surface;
    final chipLeft = k == 0 ? 0.0 : faces(k) - _kHeaderChipOverlap;
    return SizedBox(
      key: const ValueKey('kantor-header-agents'),
      width: width(k),
      height: kKantorHeaderAvatar,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // yang paling penting (kiri) digambar paling atas
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              top: 0,
              child: _HeaderFace(
                agent: shown[i],
                background: bg,
                onTap: () => _open(shown[i]),
                onLongPress: () => _label(shown[i]),
              ),
            ),
          if (more > 0)
            Positioned(
              left: chipLeft,
              top: 0,
              bottom: 0,
              child: Center(
                child: _MoreChip(
                  count: more,
                  style: style,
                  onTap: widget.onMore,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Warna cincin status: merah perlu tindakan, biru bekerja, null idle.
Color? _ringColor(BuildContext context, KantorRankedAgent a) => a.needsAction
    ? Theme.of(context).colorScheme.error
    : a.working
    ? GhinaColors.blue.base
    : null;

/// Lingkaran avatar: sprite agen di atas latar lembut, cincin status, dan
/// pojok kertas kuning bila agen berlabel (ikut berubah saat label disimpan).
class _Face extends StatelessWidget {
  const _Face({required this.agent, required this.size});

  final KantorRankedAgent agent;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kantorLabelPatches,
    builder: (context, _) {
      final face = _face(context);
      if (kantorLabelOf(agent.session) == null) return face;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          face,
          Positioned(
            right: -1,
            top: -1,
            child: KantorLabelCorner(
              key: ValueKey('label-corner-${agent.identity}'),
              size: size < 30 ? 10 : 13,
            ),
          ),
        ],
      );
    },
  );

  Widget _face(BuildContext context) {
    final g = context.ghina;
    final ring = _ringColor(context, agent);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: g.surfaceAlt,
        border: Border.all(
          color: ring ?? g.border,
          width: ring == null ? 1 : 2,
        ),
      ),
      child: ClipOval(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: KantorSprite(look: agent.look, size: size * .78),
        ),
      ),
    );
  }
}

String _semantic(KantorRankedAgent a) => [
  'Buka ${a.name}',
  a.officeName,
  if (!a.active && a.connectionName.isNotEmpty) a.connectionName,
  if (a.needsAction) 'perlu tindakan' else if (a.working) 'bekerja',
  if (kantorLabelOf(a.session) case final l?) 'label: $l',
].join(', ');

/// Satu avatar header: wajah + garis pemisah warna header (supaya avatar yang
/// bertumpuk tetap terbedakan).
class _HeaderFace extends StatelessWidget {
  const _HeaderFace({
    required this.agent,
    required this.background,
    required this.onTap,
    required this.onLongPress,
  });

  final KantorRankedAgent agent;
  final Color background;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _semantic(agent),
    excludeSemantics: true,
    child: InkResponse(
      key: ValueKey('header-agent-${agent.identity}'),
      radius: 18,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: kKantorHeaderAvatar,
        height: kKantorHeaderAvatar,
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: background),
        child: _Face(agent: agent, size: kKantorHeaderAvatar - 3),
      ),
    ),
  );
}

/// Chip "+N": agen lain yang tidak tampil; ketuk = pencari cepat.
class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.count, required this.style, this.onTap});

  static const minWidth = 24.0;
  static const padding = 5.0;

  final int count;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      label: 'Pindah agen, $count agen lain',
      excludeSemantics: true,
      child: Material(
        color: g.surfaceAlt,
        shape: StadiumBorder(side: BorderSide(color: g.border)),
        child: InkWell(
          key: const ValueKey('header-agents-more'),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 22,
            constraints: const BoxConstraints(minWidth: minWidth),
            padding: const EdgeInsets.symmetric(horizontal: padding),
            alignment: Alignment.center,
            child: Text('+$count', maxLines: 1, softWrap: false, style: style),
          ),
        ),
      ),
    );
  }
}
