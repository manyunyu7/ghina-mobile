import 'dart:async';
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_wide.dart';
import 'kantor_agent_rank.dart';
import 'kantor_feed.dart';
import 'kantor_konteks.dart';
import 'kantor_label.dart';

/// Mode meja (tabletop): Fold setengah terbuka dengan engsel MENDATAR, HP
/// berdiri di meja. Bagian atas menghadap mata: header mini + chat (kartu
/// izin ringkas inline) + composer satu baris tepat di atas engsel, atau layar terminal dengan
/// bar tombol kecilnya. Bagian bawah rata di meja: grid kartu agen untuk
/// pindah cepat ([KantorTabletopAgents]).
///
/// Flutter di Android melaporkan engsel lewat androidx.window (sudah ikut
/// embedding Flutter, tanpa dependency tambahan) sebagai
/// [MediaQueryData.displayFeatures]. Di luar posisi meja (rata, terlipat, gaya
/// buku dengan engsel tegak, HP biasa) fungsi di sini mengembalikan null dan
/// tampilan tidak berubah sama sekali.

/// Batas engsel dalam koordinat layar (logical px) bila HP sedang dalam posisi
/// meja; null di posisi lain.
Rect? kantorTabletopHinge(BuildContext context) {
  final features = MediaQuery.maybeDisplayFeaturesOf(context);
  if (features == null || features.isEmpty) return null;
  final size = MediaQuery.sizeOf(context);
  if (size.isEmpty) return null;
  for (final f in features) {
    if (f.type == DisplayFeatureType.cutout) continue;
    if (f.state != DisplayFeatureState.postureHalfOpened) continue;
    final b = f.bounds;
    // mendatar: selebar layar (engsel tegak = gaya buku, bukan meja), tipis,
    // dan kira-kira di tengah tinggi layar
    final across = b.width >= size.width * 0.9 && b.width > b.height;
    final middle =
        b.center.dy > size.height * 0.2 && b.center.dy < size.height * 0.8;
    if (across && middle) return b;
  }
  return null;
}

/// Isi layar meja yang disiapkan halaman sesi untuk tab Chat dan Terminal:
/// [header] (header mini di atas) dan [agents] (grid kartu agen di bawah).
/// [enabled] false bila tab yang tampil bukan Chat/Terminal: tab itu memakai
/// tata letak biasa.
class KantorTabletopScope extends InheritedWidget {
  const KantorTabletopScope({
    super.key,
    this.header,
    this.agents,
    this.enabled = true,
    required super.child,
  });

  final Widget? header;
  final Widget? agents;
  final bool enabled;

  static KantorTabletopScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KantorTabletopScope>();

  @override
  bool updateShouldNotify(KantorTabletopScope old) =>
      old.header != header || old.agents != agents || old.enabled != enabled;
}

/// Engsel bila tata letak meja berlaku di [context] (posisi meja dan, di
/// halaman sesi, tab Chat/Terminal yang tampil); null kalau tidak.
Rect? kantorTabletopActive(BuildContext context) {
  final hinge = kantorTabletopHinge(context);
  if (hinge == null) return null;
  final scope = KantorTabletopScope.maybeOf(context);
  return scope == null || scope.enabled ? hinge : null;
}

enum _Slot { top, bottom }

/// [top] tepat di atas engsel, [bottom] tepat di bawahnya; area engsel
/// dibiarkan kosong. Posisi engsel dihitung dari letak widget ini di layar,
/// jadi tetap pas walau ada bar lain di atasnya.
///
/// Bila ruang di bawah engsel terlalu sempit (mis. keyboard terbuka) atau
/// engselnya tidak ada, [top] memakai seluruh tinggi (composer ada di atas,
/// jadi tetap kelihatan) dan [bottom] diciutkan. Kedua anak tetap di posisi
/// pohon yang sama dalam semua kasus, jadi state-nya (scroll, draf, fokus)
/// tidak hilang.
class KantorTabletopLayout extends StatefulWidget {
  const KantorTabletopLayout({
    super.key,
    required this.top,
    required this.bottom,
    this.hinge,
  });

  final Widget top;
  final Widget bottom;

  /// Batas engsel di layar; null = baca dari [MediaQuery].
  final Rect? hinge;

  @override
  State<KantorTabletopLayout> createState() => _KantorTabletopLayoutState();
}

class _KantorTabletopLayoutState extends State<KantorTabletopLayout> {
  /// Jarak tepi atas widget ini dari tepi atas layar.
  double _originY = 0;

  void _measure(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final y = box.localToGlobal(Offset.zero).dy;
    if ((y - _originY).abs() > 0.5) setState(() => _originY = y);
  }

  @override
  Widget build(BuildContext context) {
    final hinge = widget.hinge ?? kantorTabletopHinge(context);
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    final g = context.ghina;
    return CustomMultiChildLayout(
      delegate: _TabletopDelegate(
        hingeTop: hinge == null ? null : hinge.top - _originY,
        hingeBottom: hinge == null ? null : hinge.bottom - _originY,
      ),
      children: [
        LayoutId(
          id: _Slot.top,
          child: SafeArea(bottom: false, child: widget.top),
        ),
        LayoutId(
          id: _Slot.bottom,
          // ClipRect: saat diciutkan (tanpa engsel / keyboard terbuka) isinya
          // tidak bocor ke atas
          child: ClipRect(
            child: DecoratedBox(
              key: const ValueKey('tabletop-bottom'),
              decoration: BoxDecoration(
                color: g.background,
                border: Border(top: BorderSide(color: g.border)),
              ),
              child: widget.bottom,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletopDelegate extends MultiChildLayoutDelegate {
  _TabletopDelegate({this.hingeTop, this.hingeBottom});

  final double? hingeTop;
  final double? hingeBottom;

  /// Tinggi minimum tiap bagian supaya pembagian di engsel masih berguna.
  static const _minTop = 120.0;
  static const _minBottom = 160.0;

  @override
  void performLayout(Size size) {
    final t = hingeTop, b = hingeBottom;
    final split =
        t != null && b != null && t >= _minTop && size.height - b >= _minBottom;
    // tanpa pembagian: atas (dengan composer) memakai seluruh tinggi
    final topH = split ? t : size.height;
    final bottomY = split ? b : size.height;
    layoutChild(_Slot.top, BoxConstraints.tight(Size(size.width, topH)));
    positionChild(_Slot.top, Offset.zero);
    layoutChild(
      _Slot.bottom,
      BoxConstraints.tight(Size(size.width, size.height - bottomY)),
    );
    positionChild(_Slot.bottom, Offset(0, bottomY));
  }

  @override
  bool shouldRelayout(_TabletopDelegate old) =>
      old.hingeTop != hingeTop || old.hingeBottom != hingeBottom;
}

/// Header mini bagian atas: avatar, nama, kantor, status ("minta izin" /
/// "bekerja"), dan tombol pindah Chat <-> Terminal.
class KantorTabletopHeader extends StatelessWidget {
  const KantorTabletopHeader({
    super.key,
    required this.feed,
    required this.sess,
    this.onBack,
    this.onSwap,
    this.onTerminal = false,
    this.onLabel,
  });

  final KantorOfficeFeed feed;
  final Json sess;
  final VoidCallback? onBack;

  /// Ketuk stiker label: buka form ubah label.
  final VoidCallback? onLabel;

  /// Pindah ke tab lain (Terminal bila di Chat, Chat bila di Terminal).
  final VoidCallback? onSwap;

  /// Tab yang tampil sekarang Terminal.
  final bool onTerminal;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final role = feed.role(sess['role'] as String?);
    final look = role ?? KantorSprite.guestLook('${sess['sid']}');
    final status = '${sess['status'] ?? ''}';
    final (ChunkySwatch color, String label) = switch (status) {
      'waiting' => (GhinaColors.red, 'minta izin'),
      'working' || 'starting' => (GhinaColors.green, 'bekerja'),
      'ended' => (GhinaColors.gray, 'selesai'),
      _ => (
        GhinaColors.blue,
        (kantorStatusLabel[status] ?? status).toLowerCase(),
      ),
    };
    return Material(
      color: g.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(GhinaSpace.sm, 4, GhinaSpace.sm, 4),
        child: Row(
          key: const ValueKey('tabletop-header'),
          children: [
            if (onBack != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            KantorSprite(look: look, size: 28),
            const SizedBox(width: GhinaSpace.sm),
            Flexible(
              child: Text(
                sessionName(feed, sess),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
            ),
            // berlabel: stiker satu baris menggantikan nama kantor
            const SizedBox(width: GhinaSpace.sm),
            Flexible(
              child: KantorSessionLabel(
                key: const ValueKey('tabletop-label'),
                session: sess,
                maxLines: 1,
                size: 13,
                padding: EdgeInsets.zero,
                onTap: onLabel,
                empty: feed.office?['name'] == null
                    ? const SizedBox.shrink()
                    : Text(
                        '${feed.office!['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
              ),
            ),
            const Spacer(),
            if (label.isNotEmpty)
              ChunkyPill(
                key: const ValueKey('tabletop-status'),
                label: label,
                color: color,
                soft: true,
                uppercase: false,
              ),
            if (onSwap != null)
              IconButton(
                key: const ValueKey('tabletop-swap'),
                tooltip: onTerminal ? 'Chat' : 'Terminal',
                visualDensity: VisualDensity.compact,
                onPressed: onSwap,
                icon: Icon(
                  onTerminal ? Icons.chat_bubble_outline : Icons.terminal,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Kartu izin ringkas mode meja (pengganti [KantorPermissionCard] untuk izin
/// yang bisa dijawab Izinkan/Tolak): satu baris judul, ringkasan perintah
/// maksimal 2 baris (ketuk untuk lihat penuh), dan tombol Tolak / Izinkan di
/// kanan sehingga selalu terlihat tanpa menggulir. Aksinya lewat callback yang
/// sama dengan kartu biasa.
class KantorTabletopPermissionCard extends StatefulWidget {
  const KantorTabletopPermissionCard({
    super.key,
    required this.item,
    required this.onDecide,
    this.onDismiss,
    this.who,
  });

  /// Item inbox: `{id, sid, tool, summary, held}`.
  final Json item;
  final String? who;
  final void Function(String behavior) onDecide;

  /// Tutup kartu tanpa menjawab. Null = tombol ✕ tidak ditampilkan.
  final VoidCallback? onDismiss;

  @override
  State<KantorTabletopPermissionCard> createState() =>
      _KantorTabletopPermissionCardState();
}

class _KantorTabletopPermissionCardState
    extends State<KantorTabletopPermissionCard> {
  /// Ringkasan perintah ditampilkan penuh (setelah diketuk).
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final item = widget.item;
    final id = '${item['id']}';
    final summary = '${item['summary'] ?? ''}'.trim();
    const tone = GhinaColors.orange;
    return Container(
      key: ValueKey('tabletop-perm-$id'),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: tone.tint(g.brightness),
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: tone.tintBorder(g.brightness), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: _full
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: tone.edge),
          const SizedBox(width: GhinaSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.who ?? 'Sesi'} minta izin ${item['tool'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(color: g.textPrimary, height: 1.3),
                ),
                if (summary.isNotEmpty)
                  GestureDetector(
                    key: ValueKey('tabletop-perm-summary-$id'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _full = !_full),
                    child: Text(
                      summary,
                      maxLines: _full ? null : 2,
                      overflow: _full ? null : TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(
                        color: g.textSecondary,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: GhinaSpace.sm),
          ChunkyButton(
            key: ValueKey('tabletop-perm-deny-$id'),
            label: 'Tolak',
            variant: ChunkyButtonVariant.outline,
            size: ChunkyButtonSize.small,
            expand: false,
            uppercase: false,
            onPressed: () => widget.onDecide('deny'),
          ),
          const SizedBox(width: 6),
          ChunkyButton(
            key: ValueKey('tabletop-perm-allow-$id'),
            label: 'Izinkan',
            icon: Icons.check_rounded,
            size: ChunkyButtonSize.small,
            expand: false,
            uppercase: false,
            onPressed: () => widget.onDecide('allow'),
          ),
          if (widget.onDismiss != null)
            IconButton(
              key: ValueKey('tabletop-perm-dismiss-$id'),
              tooltip: 'Tutup kartu ini (tidak menjawab)',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.close_rounded, size: 18, color: g.textMuted),
              onPressed: widget.onDismiss,
            ),
        ],
      ),
    );
  }
}

/// Tinggi seragam tiap kartu agen di bagian bawah layar meja.
const kantorTabletopCardHeight = 120.0;

/// Lebar minimum kartu agen: 830dp (Fold terbuka) jadi 4 kolom, ±600dp 3.
const kantorTabletopCardMin = 200.0;

/// Daftar agen di bawah engsel (pengganti strip avatar dalam mode meja):
/// grid kartu, bisa digulir vertikal, urut menurut [kantorAgentRankProvider]
/// (perlu tindakan → bekerja → terakhir dibuka → idle; semua kantor dan
/// koneksi). Agen yang sedang dibuka ([currentSid]) ditaruh pertama dan
/// disorot. Ketuk kartu = [onOpen] (atau [kantorOpenRankedAgent] bila null),
/// tahan = menu label.
class KantorTabletopAgents extends ConsumerStatefulWidget {
  const KantorTabletopAgents({super.key, this.currentSid, this.onOpen});

  final String? currentSid;
  final void Function(KantorRankedAgent agent)? onOpen;

  @override
  ConsumerState<KantorTabletopAgents> createState() =>
      _KantorTabletopAgentsState();
}

class _KantorTabletopAgentsState extends ConsumerState<KantorTabletopAgents> {
  String _prefetched = '';

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

  /// Tahan kartu: label lengkap dan aksi ubah label (sama dengan strip).
  void _label(KantorRankedAgent a) => showKantorLabelMenu(
    context,
    a.session,
    name: a.name,
    officeId: a.officeId,
    connection: a.active ? null : a.connection,
  );

  /// Hangatkan chat beberapa agen teratas (sekali per daftar), supaya ketuk
  /// kartu langsung menampilkan riwayat dari cache.
  void _prefetch(List<KantorRankedAgent> agents) {
    final top = agents.where((a) => !_isCurrent(a)).take(8).toList();
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

  @override
  Widget build(BuildContext context) {
    final ranked = ref.watch(kantorAgentRankProvider).agents;
    // agen yang sedang dibuka di depan, sisanya tetap urut peringkat
    final agents = [
      ...ranked.where(_isCurrent),
      ...ranked.where((a) => !_isCurrent(a)),
    ];
    _prefetch(agents);
    if (agents.isEmpty) {
      return Center(
        key: const ValueKey('tabletop-agents-empty'),
        child: Text(
          'Belum ada agen yang aktif',
          style: GhinaType.bodyS.copyWith(color: context.ghina.textSecondary),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = GhinaSpace.sm;
        final cols = kantorGridColumns(
          box.maxWidth - gap * 2,
          minTile: kantorTabletopCardMin,
        );
        return GridView.builder(
          key: const ValueKey('tabletop-agents'),
          padding: const EdgeInsets.all(gap),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: kantorTabletopCardHeight,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
          ),
          itemCount: agents.length,
          itemBuilder: (context, i) {
            final a = agents[i];
            return KantorTabletopAgentCard(
              agent: a,
              current: _isCurrent(a),
              onTap: () => _open(a),
              onLongPress: () => _label(a),
            );
          },
        );
      },
    );
  }
}

/// Satu kartu agen mode meja: avatar (sprite yang sama dengan strip, cincin
/// warna status), nama, kantor, pil status (merah perlu tindakan, biru
/// bekerja, abu idle), stiker label bila ada, dan satu baris aktivitas.
class KantorTabletopAgentCard extends StatelessWidget {
  const KantorTabletopAgentCard({
    super.key,
    required this.agent,
    this.current = false,
    this.onTap,
    this.onLongPress,
  });

  final KantorRankedAgent agent;

  /// Agen yang sedang dibuka di atas: garis aksen + latar tipis.
  final bool current;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final accent = Theme.of(context).colorScheme.primary;
    final (ChunkySwatch tone, String status) = agent.needsAction
        ? (GhinaColors.red, agent.actionLabel)
        : agent.working
        ? (GhinaColors.blue, 'bekerja')
        : (GhinaColors.gray, 'idle');
    final Color face, edge, border;
    if (current) {
      face = Color.alphaBlend(
        accent.withValues(alpha: g.isDark ? .14 : .10),
        g.surface,
      );
      border = accent;
      edge = accent;
    } else if (agent.needsAction) {
      face = g.surface;
      border = GhinaColors.red.tintBorder(g.brightness);
      edge = border;
    } else {
      face = g.surface;
      border = g.border;
      edge = g.borderEdge;
    }
    final ring = agent.needsAction
        ? GhinaColors.red.base
        : agent.working
        ? GhinaColors.blue.base
        : null;
    final where = [
      agent.officeName,
      if (!agent.active && agent.connectionName.isNotEmpty)
        agent.connectionName,
    ].join(' · ');
    return ChunkySurface(
      key: ValueKey('tabletop-agent-${agent.identity}'),
      color: face,
      edgeColor: edge,
      borderColor: border,
      borderWidth: current ? 2 : 1.5,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: [
        'Buka ${agent.name}',
        where,
        status,
        if (current) 'sedang dibuka',
      ].join(', '),
      child: ListenableBuilder(
        listenable: kantorLabelPatches,
        builder: (context, _) {
          final label = kantorLabelOf(agent.session);
          final doing = Text(
            agent.doing,
            maxLines: label == null ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(
              color: g.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CardFace(look: agent.look, ring: ring),
                  const SizedBox(width: GhinaSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          agent.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS
                              .w(800)
                              .copyWith(color: g.textPrimary, height: 1.25),
                        ),
                        Text(
                          where,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.caption.copyWith(
                            color: g.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: GhinaSpace.xs),
                  ChunkyPill(
                    key: ValueKey('tabletop-agent-status-${agent.identity}'),
                    label: status,
                    color: tone,
                    soft: true,
                    uppercase: false,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: label == null
                      ? doing
                      : KantorLabelSticker(label, maxLines: 2, size: 13),
                ),
              ),
              if (label != null) doing,
            ],
          );
        },
      ),
    );
  }
}

/// Avatar bulat kartu agen: sprite di atas latar lembut, cincin warna status.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.look, this.ring});

  final Json look;
  final Color? ring;

  static const _size = 34.0;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      width: _size,
      height: _size,
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
          child: KantorSprite(look: look, size: _size * .78),
        ),
      ),
    );
  }
}

/// Layar tetap menyala (FLAG_KEEP_SCREEN_ON di jendela Activity) lewat
/// channel kecil `ravel/screen` ke MainActivity. Di flavor Ghina, Android
/// mengabaikannya (no-op); di platform tanpa handler panggilannya diabaikan.
class KantorScreenAwake {
  KantorScreenAwake._();

  static const channel = MethodChannel('ravel/screen');

  /// Widget yang sedang meminta layar menyala.
  static final _holders = <Object>{};
  static bool _on = false;

  static void hold(Object who, bool want) {
    if (want) {
      _holders.add(who);
    } else {
      _holders.remove(who);
    }
    final on = _holders.isNotEmpty;
    if (on == _on) return;
    _on = on;
    unawaited(_send(on));
  }

  static Future<void> _send(bool on) async {
    try {
      await channel.invokeMethod<void>('keepOn', on);
    } on MissingPluginException {
      // iOS / desktop / tes tanpa handler
    } on PlatformException {
      // jendela sudah hilang
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _holders.clear();
    _on = false;
  }
}

/// Minta layar tetap menyala selama [on] dan app ada di depan; lepas saat
/// [on] jadi false, app ke background, atau widget ini dibuang.
class KantorKeepAwake extends StatefulWidget {
  const KantorKeepAwake({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<KantorKeepAwake> createState() => _KantorKeepAwakeState();
}

class _KantorKeepAwakeState extends State<KantorKeepAwake>
    with WidgetsBindingObserver {
  bool _front = true;

  @override
  void initState() {
    super.initState();
    final s = WidgetsBinding.instance.lifecycleState;
    _front = s == null || s == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  void _apply() => KantorScreenAwake.hold(this, widget.on && _front);

  @override
  void didUpdateWidget(KantorKeepAwake old) {
    super.didUpdateWidget(old);
    if (old.on != widget.on) _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive (mis. panel notifikasi ditarik) masih dianggap di depan
    final front =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (front == _front) return;
    _front = front;
    _apply();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    KantorScreenAwake.hold(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
