import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../board/kantor_card_detail.dart';
import '../kantor_format.dart';
import '../roles/kantor_role.dart' show KantorRole, kantorRolesProvider;
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

/// Obrolan agen: pesan langsung antaragen (`/api/offices/:id/dm`).

/// Satu ujung utas: siapa agennya.
class DmParty {
  const DmParty({required this.id, required this.name, required this.title});

  factory DmParty.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return DmParty(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? m['id'] ?? ''}',
      title: '${m['title'] ?? ''}',
    );
  }

  final String id;
  final String name;
  final String title;
}

/// Satu pesan dalam utas.
class DmMessage {
  const DmMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.fromName,
    required this.toName,
    required this.kind,
    required this.text,
    required this.status,
    this.card,
    this.replyTo,
    this.at,
  });

  factory DmMessage.fromJson(Map<String, dynamic> j) => DmMessage(
    id: '${j['id'] ?? ''}',
    from: '${j['from'] ?? ''}',
    to: '${j['to'] ?? ''}',
    fromName: '${j['fromName'] ?? j['from'] ?? ''}',
    toName: '${j['toName'] ?? j['to'] ?? ''}',
    kind: '${j['kind'] ?? 'pesan'}',
    text: '${j['text'] ?? ''}',
    status: '${j['status'] ?? ''}',
    card: j['card'] == null ? null : '${j['card']}',
    replyTo: j['replyTo'] == null ? null : '${j['replyTo']}',
    at: j['at'] ?? j['sentAt'],
  );

  final String id;
  final String from;
  final String to;
  final String fromName;
  final String toName;

  /// pesan | tanya | balasan.
  final String kind;
  final String text;

  /// menunggu | terkirim | dibaca | dibalas.
  final String status;
  final String? card;
  final String? replyTo;
  final Object? at;

  String get kindLabel => switch (kind) {
    'tanya' => 'Tanya',
    'balasan' => 'Balasan',
    _ => 'Pesan',
  };
}

/// Satu utas dua agen.
class DmThread {
  const DmThread({
    required this.key,
    required this.a,
    required this.b,
    required this.count,
    required this.pending,
    this.last,
  });

  factory DmThread.fromJson(Map<String, dynamic> j) => DmThread(
    key: '${j['key'] ?? ''}',
    a: DmParty.fromJson(j['a']),
    b: DmParty.fromJson(j['b']),
    count: (j['count'] as num?)?.toInt() ?? 0,
    pending: (j['pending'] as num?)?.toInt() ?? 0,
    last: j['last'] is Map
        ? DmMessage.fromJson(Map<String, dynamic>.from(j['last'] as Map))
        : null,
  );

  final String key;
  final DmParty a;
  final DmParty b;
  final int count;
  final int pending;
  final DmMessage? last;
}

/// Daftar utas kantor; [role] menyaring ke satu agen.
typedef DmListArgs = ({String officeId, String? role});

KantorApi _need(Ref ref) {
  final api = ref.read(kantorApiProvider);
  if (api == null) {
    throw const KantorException(
      KantorFailure.unauthorized,
      'Token Kantor belum diisi.',
    );
  }
  return api;
}

String _base(String officeId) =>
    '/api/offices/${Uri.encodeComponent(officeId)}/dm';

/// Muat ulang saat daemon mendorong event `dm` untuk kantor ini.
void _refetchOnDm(Ref ref, String officeId) {
  ref.listen(kantorEventsProvider, (_, next) {
    final e = next.value;
    if (e != null && e['t'] == 'dm' && e['office'] == officeId) {
      ref.invalidateSelf();
    }
  });
}

final kantorDmThreadsProvider = FutureProvider.autoDispose
    .family<List<DmThread>, DmListArgs>((ref, args) async {
      final api = _need(ref);
      _refetchOnDm(ref, args.officeId);
      final role = args.role;
      final j = await api.get(
        role == null
            ? _base(args.officeId)
            : '${_base(args.officeId)}?role=${Uri.encodeQueryComponent(role)}',
      );
      return [
        for (final t in ((j as Map)['threads'] as List? ?? const []))
          if (t is Map) DmThread.fromJson(Map<String, dynamic>.from(t)),
      ];
    });

typedef DmThreadArgs = ({String officeId, String a, String b});

final kantorDmMessagesProvider = FutureProvider.autoDispose
    .family<List<DmMessage>, DmThreadArgs>((ref, args) async {
      final api = _need(ref);
      _refetchOnDm(ref, args.officeId);
      final j = await api.get(
        '${_base(args.officeId)}/${Uri.encodeComponent(args.a)}/${Uri.encodeComponent(args.b)}',
      );
      return [
        for (final m in ((j as Map)['items'] as List? ?? const []))
          if (m is Map) DmMessage.fromJson(Map<String, dynamic>.from(m)),
      ];
    });

/// Buka daftar utas; [role] (id role) menyaring ke satu agen.
Future<void> openKantorDm(
  BuildContext context, {
  required String officeId,
  String? role,
  String? roleName,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        KantorDmScreen(officeId: officeId, role: role, roleName: roleName),
  ),
);

ChunkySwatch _statusColor(String s) => switch (s) {
  'menunggu' => GhinaColors.orange,
  'dibaca' => GhinaColors.purple,
  'dibalas' => GhinaColors.green,
  _ => GhinaColors.blue,
};

String _statusLabel(String s) => switch (s) {
  'menunggu' => 'Menunggu',
  'dibaca' => 'Dibaca',
  'dibalas' => 'Dibalas',
  'terkirim' => 'Terkirim',
  _ => s,
};

String _clock(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}.${two(t.minute)}';
}

/// Peta id role -> tampilan sprite (role yang sudah diarsipkan ikut).
Map<String, Map<String, dynamic>> _looks(List<KantorRole>? roles) => {
  for (final r in roles ?? const <KantorRole>[]) r.id: r.look,
};

Map<String, dynamic> _look(
  Map<String, Map<String, dynamic>> looks,
  String id,
) => looks[id] ?? KantorSprite.guestLook(id);

/// Daftar utas obrolan antaragen.
class KantorDmScreen extends ConsumerWidget {
  const KantorDmScreen({
    super.key,
    required this.officeId,
    this.role,
    this.roleName,
  });

  final String officeId;
  final String? role;
  final String? roleName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final args = (officeId: officeId, role: role);
    final threads = ref.watch(kantorDmThreadsProvider(args));
    final looks = _looks(ref.watch(kantorRolesProvider(officeId)).value);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(
          roleName == null ? 'Obrolan agen' : 'Pesan ${roleName!}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: threads.when(
        loading: () => const KantorLoading(),
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kantorDmThreadsProvider(args)),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(kantorDmThreadsProvider(args).future),
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: GhinaSpace.xl),
                    EmptyState(
                      title: 'Belum ada obrolan',
                      message:
                          'Pesan antaragen akan muncul di sini setelah ada yang saling kirim.',
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(GhinaSpace.page),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: GhinaSpace.sm),
                  itemBuilder: (context, i) => _ThreadTile(
                    thread: list[i],
                    looks: looks,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => KantorDmThreadScreen(
                          officeId: officeId,
                          thread: list[i],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.looks,
    required this.onTap,
  });

  final DmThread thread;
  final Map<String, Map<String, dynamic>> looks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final last = thread.last;
    final waiting = thread.pending > 0;
    return ChunkyCard(
      tinted: waiting ? GhinaColors.orange : null,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: GhinaSpace.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 48,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: KantorSprite(
                    look: _look(looks, thread.a.id),
                    size: 44,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: KantorSprite(
                    look: _look(looks, thread.b.id),
                    size: 44,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GhinaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${thread.a.name} ⇄ ${thread.b.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (last != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        kantorAgo(last.at),
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  last == null
                      ? 'Belum ada pesan.'
                      : '${last.fromName}: ${last.text}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ChunkyPill(
                      label: '${thread.count} pesan',
                      color: GhinaColors.gray,
                      soft: true,
                      uppercase: false,
                    ),
                    if (waiting)
                      ChunkyPill(
                        label: '${thread.pending} menunggu',
                        color: GhinaColors.orange,
                        soft: true,
                        uppercase: false,
                      )
                    else if (last != null)
                      ChunkyPill(
                        label: _statusLabel(last.status),
                        color: _statusColor(last.status),
                        soft: true,
                        uppercase: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Isi satu utas: gelembung per pengirim, lama ke baru.
class KantorDmThreadScreen extends ConsumerStatefulWidget {
  const KantorDmThreadScreen({
    super.key,
    required this.officeId,
    required this.thread,
  });

  final String officeId;
  final DmThread thread;

  @override
  ConsumerState<KantorDmThreadScreen> createState() => _ThreadState();
}

class _ThreadState extends ConsumerState<KantorDmThreadScreen> {
  final _scroll = ScrollController();
  int _shown = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Turun ke pesan terbaru saat jumlah pesan bertambah.
  void _toBottom(int count) {
    if (count == _shown) return;
    _shown = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final t = widget.thread;
    final args = (officeId: widget.officeId, a: t.a.id, b: t.b.id);
    final msgs = ref.watch(kantorDmMessagesProvider(args));
    final looks = _looks(ref.watch(kantorRolesProvider(widget.officeId)).value);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(
          '${t.a.name} ⇄ ${t.b.name}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: msgs.when(
        loading: () => const KantorLoading(),
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kantorDmMessagesProvider(args)),
        ),
        data: (items) {
          _toBottom(items.length);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(kantorDmMessagesProvider(args).future),
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: GhinaSpace.xl),
                      EmptyState(title: 'Belum ada pesan'),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(GhinaSpace.page),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _Bubble(
                      message: items[i],
                      mine: items[i].from == t.b.id,
                      look: _look(looks, items[i].from),
                      onCard: items[i].card == null
                          ? null
                          : () => openKantorCard(
                              context,
                              officeId: widget.officeId,
                              cardId: items[i].card!,
                            ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.look,
    this.onCard,
  });

  final DmMessage message;

  /// Pengirim agen kedua (b) tampil di kanan, agen pertama (a) di kiri.
  final bool mine;
  final Map<String, dynamic> look;
  final VoidCallback? onCard;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final dark = Theme.of(context).brightness;
    final sw = mine ? GhinaColors.blue : null;
    final m = message;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: GhinaSpace.sm,
      ),
      decoration: BoxDecoration(
        color: sw?.tint(dark) ?? g.surface,
        border: Border.all(color: sw?.tintBorder(dark) ?? g.border, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  m.fromName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              ChunkyPill(
                label: m.kindLabel,
                color: m.kind == 'tanya'
                    ? GhinaColors.orange
                    : m.kind == 'balasan'
                    ? GhinaColors.green
                    : GhinaColors.gray,
                soft: true,
                uppercase: false,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            m.text,
            style: GhinaType.body.copyWith(color: g.textPrimary, height: 1.35),
          ),
          if (onCard != null) ...[
            const SizedBox(height: GhinaSpace.sm),
            InkWell(
              onTap: onCard,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.style_outlined,
                      size: 16,
                      color: GhinaColors.blue.base,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Buka kartu ${m.card}',
                      style: GhinaType.bodyS
                          .w(800)
                          .copyWith(color: GhinaColors.blue.base),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _clock(m.at),
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
              const SizedBox(width: 6),
              ChunkyPill(
                label: _statusLabel(m.status),
                color: _statusColor(m.status),
                soft: true,
                uppercase: false,
              ),
            ],
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            KantorSprite(look: look, size: 32),
            const SizedBox(width: 6),
          ],
          Flexible(child: bubble),
          if (mine) ...[
            const SizedBox(width: 6),
            KantorSprite(look: look, size: 32),
          ],
        ],
      ),
    );
  }
}
