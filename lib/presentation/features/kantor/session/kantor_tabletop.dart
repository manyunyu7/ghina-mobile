import 'dart:async';
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import 'kantor_feed.dart';
import 'permission_card.dart';

/// Mode meja (tabletop): Fold setengah terbuka dengan engsel MENDATAR, HP
/// berdiri di meja. Bagian atas menghadap mata (untuk dilihat), bagian bawah
/// rata di meja (untuk disentuh).
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
/// [header] (header mini di atas) dan [agents] (baris chip agen di bawah).
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
/// engselnya tidak ada, layar dibagi dua tanpa celah supaya kotak ketik tetap
/// kelihatan. Kedua anak tetap di posisi pohon yang sama dalam semua kasus,
/// jadi state-nya (scroll, draf, fokus) tidak hilang.
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
          child: DecoratedBox(
            key: const ValueKey('tabletop-bottom'),
            decoration: BoxDecoration(
              color: g.surface,
              border: Border(top: BorderSide(color: g.border)),
            ),
            child: widget.bottom,
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
    final topH = split ? t : (size.height / 2).floorToDouble();
    final bottomY = split ? b : topH;
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
  });

  final KantorOfficeFeed feed;
  final Json sess;
  final VoidCallback? onBack;

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
            if (feed.office?['name'] != null) ...[
              const SizedBox(width: GhinaSpace.sm),
              Flexible(
                child: Text(
                  '${feed.office!['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
            ],
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

/// Alat yang izinnya bisa "selalu" diberikan dari Kantor: daemon belum
/// mengenal aturan izin per perintah, jadi "Izinkan selalu" = izinkan sekarang
/// lalu mode izin sesi jadi "Edit otomatis" (acceptEdits), sama seperti
/// pilihan "izinkan semua edit di sesi ini" di Claude Code. Untuk alat lain
/// (Bash dan sebagainya) tombol itu tidak ditampilkan.
const kantorAllowAlwaysTools = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'};

bool kantorAllowAlwaysFits(Json item) =>
    kantorPermissionCanDecide(item) &&
    kantorAllowAlwaysTools.contains('${item['tool']}');

/// Tombol izin besar di bagian bawah: Izinkan / Tolak / Izinkan selalu.
/// Aksinya sama dengan tombol di [KantorPermissionCard] (dipanggil lewat
/// callback yang sama dari chat).
class KantorTabletopPermissionBar extends StatelessWidget {
  const KantorTabletopPermissionBar({
    super.key,
    required this.item,
    required this.onDecide,
    this.onAlways,
    this.who,
  });

  final Json item;
  final String? who;
  final void Function(String behavior) onDecide;

  /// Null = tombol "Izinkan selalu" tidak ditampilkan.
  final VoidCallback? onAlways;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final id = '${item['id']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${who ?? 'Sesi'} minta izin ${item['tool'] ?? ''}: '
            '${clip('${item['summary'] ?? ''}', 160)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  key: ValueKey('tabletop-allow-$id'),
                  label: 'Izinkan',
                  icon: Icons.check_rounded,
                  size: ChunkyButtonSize.medium,
                  uppercase: false,
                  onPressed: () => onDecide('allow'),
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              Expanded(
                child: ChunkyButton(
                  key: ValueKey('tabletop-deny-$id'),
                  label: 'Tolak',
                  icon: Icons.close_rounded,
                  variant: ChunkyButtonVariant.danger,
                  size: ChunkyButtonSize.medium,
                  uppercase: false,
                  onPressed: () => onDecide('deny'),
                ),
              ),
              if (onAlways != null) ...[
                const SizedBox(width: GhinaSpace.sm),
                Expanded(
                  flex: 2,
                  child: ChunkyButton(
                    key: ValueKey('tabletop-always-$id'),
                    label: 'Izinkan selalu',
                    variant: ChunkyButtonVariant.outline,
                    size: ChunkyButtonSize.medium,
                    uppercase: false,
                    onPressed: onAlways,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Tombol terminal besar di bagian bawah (seperti laptop mini): baris 1 Esc,
/// Tab, panah, Ctrl+C, Enter; baris 2 Tempel, Salin layar, "/", "y", "n";
/// lalu kolom ketik + mic dikte.
class KantorTabletopTermKeys extends StatelessWidget {
  const KantorTabletopTermKeys({
    super.key,
    required this.onSeq,
    required this.onArrow,
    required this.onPaste,
    required this.onCopyScreen,
    required this.line,
    required this.onSend,
    this.onMic,
    this.dictating = false,
  });

  /// Kirim byte apa adanya ke terminal.
  final void Function(String seq) onSeq;

  /// Panah: huruf A (atas), B (bawah), C (kanan), D (kiri).
  final void Function(String letter) onArrow;
  final VoidCallback onPaste;
  final VoidCallback onCopyScreen;

  /// Kolom ketik ke terminal.
  final TextEditingController line;
  final VoidCallback onSend;
  final VoidCallback? onMic;
  final bool dictating;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget key(String label, VoidCallback f, {String? id}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: g.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: GhinaRadii.rMd,
            side: BorderSide(color: g.border, width: 1.5),
          ),
          child: InkWell(
            key: ValueKey('tabletop-key-${id ?? label}'),
            borderRadius: GhinaRadii.rMd,
            onTap: () {
              HapticFeedback.selectionClick();
              f();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: GhinaType.body
                      .w(800)
                      .copyWith(color: g.textPrimary, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.sm,
        GhinaSpace.xs,
        GhinaSpace.sm,
        GhinaSpace.xs,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              key('Esc', () => onSeq('\x1b')),
              key('Tab', () => onSeq('\t')),
              key('↑', () => onArrow('A'), id: 'up'),
              key('↓', () => onArrow('B'), id: 'down'),
              key('←', () => onArrow('D'), id: 'left'),
              key('→', () => onArrow('C'), id: 'right'),
              key('Ctrl+C', () => onSeq('\x03')),
              key('⏎ Enter', () => onSeq('\r'), id: 'Enter'),
            ],
          ),
          Row(
            children: [
              key('Tempel', onPaste),
              key('Salin layar', onCopyScreen),
              key('/', () => onSeq('/')),
              key('y', () => onSeq('y')),
              key('n', () => onSeq('n')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: GhinaSpace.xs),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('tabletop-term-input'),
                    controller: line,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: GhinaType.body.copyWith(
                      color: g.textPrimary,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'ketik ke terminal…',
                      border: OutlineInputBorder(borderRadius: GhinaRadii.rMd),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('tabletop-term-mic'),
                  tooltip: dictating ? 'Selesai dikte' : 'Dikte',
                  onPressed: onMic,
                  icon: Icon(
                    dictating ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: dictating ? GhinaColors.blue.base : null,
                  ),
                ),
                IconButton(
                  key: const ValueKey('tabletop-term-send'),
                  tooltip: 'Kirim ke terminal (dengan Enter)',
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
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
