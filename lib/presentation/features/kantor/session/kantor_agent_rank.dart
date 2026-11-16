import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
import 'kantor_snapshot_store.dart';

/// Peringkat semua agen hidup dari semua kantor dan semua koneksi server
/// tersimpan, untuk pindah cepat (strip avatar di bawah header chat, pencari
/// cepat, baris chip mode meja).
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
/// kosong cache), supaya pindah lewat strip langsung menampilkan riwayat.
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

/// Status tampil strip setelah [n] dari daftar chat/terminal di bawahnya:
/// true = tampilkan, false = sembunyikan, null = biarkan.
///
/// Digulir menjauhi pesan terbaru (membaca riwayat) → sembunyi; digulir ke
/// arah pesan terbaru atau berhenti di dasar → tampil. Daftar chat terbalik
/// (`reverse: true`, pesan terbaru di offset 0); terminal biasa (terbaru di
/// bawah). Scrollable kecil (kolom ketik) dan horizontal diabaikan.
bool? kantorStripVisibility(ScrollNotification n) {
  final m = n.metrics;
  if (m.axis != Axis.vertical || m.viewportDimension < 160) return null;
  final reversed = m.axisDirection == AxisDirection.up;
  if (n is UserScrollNotification) {
    if (n.direction == ScrollDirection.idle) return _atNewest(m) ? true : null;
    // forward = offset mengecil. Di daftar terbalik offset membesar = ke riwayat
    final away = reversed
        ? n.direction == ScrollDirection.reverse
        : n.direction == ScrollDirection.forward;
    return !away;
  }
  if (n is ScrollEndNotification && _atNewest(m)) return true;
  return null;
}

bool _atNewest(ScrollMetrics m) {
  final reversed = m.axisDirection == AxisDirection.up;
  final d = reversed
      ? m.pixels - m.minScrollExtent
      : m.maxScrollExtent - m.pixels;
  return d <= 24;
}

/// Baris agen untuk pindah cepat. Dipakai:
/// - di bawah header chat (layar sempit): avatar 38dp + nama kecil;
/// - [dense]: avatar lebih kecil, untuk ruang sempit;
/// - [chips]: pil avatar + nama sebaris (mode meja).
///
/// Cincin merah = perlu tindakan, biru = bekerja, garis aksen = [currentSid].
/// Garis tipis memisahkan kelompok. Ketuk = [onOpen], atau bila null pindah
/// lewat [kantorOpenRankedAgent]. Tidak tampil bila tidak ada agen lain.
class KantorAgentStrip extends ConsumerStatefulWidget {
  const KantorAgentStrip({
    super.key,
    this.currentSid,
    this.onOpen,
    this.dense = false,
    this.chips = false,
  });

  final String? currentSid;
  final void Function(KantorRankedAgent agent)? onOpen;
  final bool dense;
  final bool chips;

  @override
  ConsumerState<KantorAgentStrip> createState() => _KantorAgentStripState();
}

class _KantorAgentStripState extends ConsumerState<KantorAgentStrip> {
  final _currentKey = GlobalKey();
  String _prefetched = '';
  bool _scrolledToCurrent = false;

  bool _isCurrent(KantorRankedAgent a) =>
      a.active && widget.currentSid != null && a.sid == widget.currentSid;

  Future<void> _open(KantorRankedAgent a) async {
    if (_isCurrent(a)) return;
    final cb = widget.onOpen;
    if (cb != null) return cb(a);
    try {
      await kantorOpenRankedAgent(context, a);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Tidak bisa membuka ${a.connectionName.isEmpty ? a.officeName : a.connectionName}. '
            'Periksa koneksi lalu coba lagi.',
          ),
        ),
      );
    }
  }

  /// Sekali per daftar: hangatkan chat beberapa agen teratas, dan geser strip
  /// supaya agen saat ini terlihat.
  void _afterBuild(List<KantorRankedAgent> agents) {
    final top = agents.where((a) => !_isCurrent(a)).take(6).toList();
    final sig = top.map((a) => a.identity).join('|');
    final scroll = !_scrolledToCurrent;
    if (sig == _prefetched && !scroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (sig != _prefetched) {
        _prefetched = sig;
        kantorPrefetchRanked(
          ProviderScope.containerOf(context, listen: false),
          top,
        );
      }
      final cur = _currentKey.currentContext;
      if (scroll && cur != null) {
        _scrolledToCurrent = true;
        Scrollable.ensureVisible(cur, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(kantorAgentRankProvider).agents;
    if (!agents.any((a) => !_isCurrent(a))) return const SizedBox.shrink();
    _afterBuild(agents);
    final g = context.ghina;
    final items = <Widget>[];
    KantorAgentGroup? last;
    for (final a in agents) {
      if (last != null && a.group != last) {
        items.add(
          Container(
            width: 1,
            margin: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: widget.chips ? 8 : 10,
            ),
            color: g.border,
          ),
        );
      }
      last = a.group;
      final cur = _isCurrent(a);
      items.add(
        KeyedSubtree(
          key: cur ? _currentKey : null,
          child: widget.chips
              ? _Chip(agent: a, current: cur, onTap: () => _open(a))
              : _Avatar(
                  agent: a,
                  current: cur,
                  dense: widget.dense,
                  onTap: () => _open(a),
                ),
        ),
      );
    }
    final avatar = widget.dense ? 30.0 : 38.0;
    final height = widget.chips
        ? (widget.dense ? 40.0 : 48.0)
        : avatar + 10 + 16 + (widget.dense ? 8 : 14);
    return Material(
      key: const ValueKey('kantor-agent-strip'),
      color: widget.chips ? Colors.transparent : g.surface,
      child: Container(
        decoration: widget.chips
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: g.border)),
              ),
        height: height,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: GhinaSpace.sm,
            vertical: widget.chips ? 4 : (widget.dense ? 4 : 7),
          ),
          children: [
            for (final w in items)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.chips ? 3 : 4),
                child: w,
              ),
          ],
        ),
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
/// garis aksen di luar bila agen ini yang sedang dibuka.
class _Face extends StatelessWidget {
  const _Face({required this.agent, required this.size, this.current = false});

  final KantorRankedAgent agent;
  final double size;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final ring = _ringColor(context, agent);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: current ? accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: g.surfaceAlt,
          border: Border.all(
            color: ring ?? g.border,
            width: ring == null ? 1 : 2.5,
          ),
        ),
        child: ClipOval(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: KantorSprite(look: agent.look, size: size * .78),
          ),
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
].join(', ');

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.agent,
    required this.current,
    required this.dense,
    required this.onTap,
  });

  final KantorRankedAgent agent;
  final bool current;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final size = dense ? 30.0 : 38.0;
    return Semantics(
      button: true,
      selected: current,
      label: _semantic(agent),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('strip-agent-${agent.identity}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: size + 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Face(agent: agent, size: size, current: current),
              const SizedBox(height: 2),
              Text(
                agent.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GhinaType.caption.copyWith(
                  fontSize: dense ? 9.5 : 10.5,
                  height: 1.2,
                  fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                  color: current ? g.textPrimary : g.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pil avatar + nama sebaris (mode meja).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.agent,
    required this.current,
    required this.onTap,
  });

  final KantorRankedAgent agent;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: current,
      label: _semantic(agent),
      excludeSemantics: true,
      child: Center(
        child: Material(
          color: current ? accent.withValues(alpha: .12) : g.surface,
          shape: StadiumBorder(
            side: BorderSide(
              color: current ? accent : g.borderEdge,
              width: 1.5,
            ),
          ),
          child: InkWell(
            key: ValueKey('strip-agent-${agent.identity}'),
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Face(agent: agent, size: 24),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      agent.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS
                          .w(700)
                          .copyWith(color: g.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
