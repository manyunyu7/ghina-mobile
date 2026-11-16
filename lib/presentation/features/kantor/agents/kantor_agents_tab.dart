import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/chat_context.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import '../dm/kantor_dm_screen.dart';
import '../session/kantor_actions.dart';
import '../session/kantor_feed.dart';
import '../session/kantor_konteks.dart';
import '../session/kantor_label.dart';
import '../session/permission_card.dart';
import '../roles/kantor_new_agent_sheet.dart';
import '../session/start_shift_sheet.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import '../session/chat_view_prefs.dart';
import '../session/chat_style.dart';
import 'kantor_room_marks.dart';
import '../meetings/kantor_meeting.dart';
import '../meetings/kantor_meeting_detail.dart';
import 'kantor_office_bar.dart';
import 'kantor_two_pane.dart';

/// Agents of one office, grouped by what needs the user: waiting (permission
/// or question), working, idle, and roles off shift.
///
/// Lebar >= [kKantorTwoPaneMin] (Fold terbuka): daftar di kiri, chat di kanan
/// ([KantorTwoPane]). Di bawahnya tetap satu panel, ketuk agen membuka halaman
/// sesi seperti biasa.
class KantorAgentsTab extends ConsumerStatefulWidget {
  const KantorAgentsTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorAgentsTab> createState() => _KantorAgentsTabState();
}

class _KantorAgentsTabState extends ConsumerState<KantorAgentsTab> {
  /// Daftar dipindah (bukan dibuat ulang) antara satu dan dua panel, jadi
  /// filter, pencarian, dan posisi scroll daftar tetap saat Fold dilipat/dibuka.
  final _listKey = GlobalKey(debugLabel: 'kantor-agent-list');

  /// Tata letak pada build sebelumnya; null sebelum layout pertama.
  bool? _wasWide;

  void _onLayout(bool wide) {
    final was = _wasWide;
    _wasWide = wide;
    if (was == true && !wide) {
      // dua panel -> satu panel: chat di panel kanan jadi halaman penuh
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wasWide == false) kantorUndockToRoute(context, ref);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final officeId = widget.officeId;
    final feed = ref.watch(kantorOfficeFeedProvider(officeId));
    final api = ref.watch(kantorApiProvider);
    final style = ref.watch(chatViewPrefsProvider.select((p) => p.style));
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        if (feed.loading) return const KantorLoading();
        if (feed.error != null && feed.office == null) {
          return KantorErrorView(error: feed.error!, onRetry: feed.load);
        }
        final list = KeyedSubtree(
          key: _listKey,
          child: kantorAgentList(feed, style, api),
        );
        return LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= kKantorTwoPaneMin;
            _onLayout(wide);
            if (!wide) {
              // ganti kantor di bawah (jempol); "Agen baru" tetap di atasnya
              return Column(
                children: [
                  Expanded(child: list),
                  KantorOfficeBar(currentId: officeId),
                ],
              );
            }
            return KantorTwoPane(
              officeId: officeId,
              officeName: '${feed.office?['name'] ?? officeId}',
              list: list,
              width: box.maxWidth,
            );
          },
        );
      },
    );
  }
}

/// Daftar agen satu kantor (tanpa header), sesuai gaya chat. Dipakai tab Agen
/// dan panel kiri halaman sesi di layar lebar ([KantorSessionHost]).
Widget kantorAgentList(
  KantorOfficeFeed feed,
  ChatStyle style,
  KantorApi? api,
) => _ChatPrefetch(
  feed: feed,
  api: api,
  child: RefreshIndicator(
    onRefresh: feed.load,
    child: style != ChatStyle.bawaan
        ? _MessengerAgentList(feed: feed, style: style)
        : _AgentList(
            feed: feed,
            actions: api == null ? null : KantorActions(api),
          ),
  ),
);

/// Once the office is loaded, fetches the chats of the first few live agents
/// (working or waiting first) into the in-memory transcript cache, so the
/// first open of those chats is instant. See [kantorPrefetchChats].
class _ChatPrefetch extends ConsumerStatefulWidget {
  const _ChatPrefetch({
    required this.feed,
    required this.api,
    required this.child,
  });

  final KantorOfficeFeed feed;
  final KantorApi? api;
  final Widget child;

  @override
  ConsumerState<_ChatPrefetch> createState() => _ChatPrefetchState();
}

class _ChatPrefetchState extends ConsumerState<_ChatPrefetch> {
  String? _done;

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_maybe);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybe());
  }

  @override
  void didUpdateWidget(_ChatPrefetch old) {
    super.didUpdateWidget(old);
    if (old.feed != widget.feed) {
      old.feed.removeListener(_maybe);
      widget.feed.addListener(_maybe);
      _maybe();
    }
  }

  @override
  void dispose() {
    widget.feed.removeListener(_maybe);
    super.dispose();
  }

  void _maybe() {
    final api = widget.api;
    final feed = widget.feed;
    if (!mounted || api == null || feed.office == null) return;
    if (_done == feed.officeId) return;
    _done = feed.officeId;
    int rank(Json s) => switch ('${s['status']}') {
      'working' || 'waiting' => 0,
      'idle' || 'starting' => 1,
      _ => 2,
    };
    final live = [
      for (final s in feed.sessions)
        if (s['status'] != 'ended' && s['sid'] is String) s,
    ]..sort((a, b) => rank(a) - rank(b));
    kantorPrefetchChats(
      api,
      ref.read(kantorTranscriptCacheProvider),
      feed.officeId,
      [for (final s in live.take(4)) s['sid'] as String],
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MessengerAgentList extends ConsumerStatefulWidget {
  const _MessengerAgentList({required this.feed, required this.style});
  final KantorOfficeFeed feed;
  final ChatStyle style;
  @override
  ConsumerState<_MessengerAgentList> createState() =>
      _MessengerAgentListState();
}

/// One room row's data, worked out once per build.
class _Room {
  _Room({
    required this.s,
    required this.role,
    required this.name,
    required this.preview,
    required this.kind,
    required this.at,
    required this.mine,
    required this.unread,
    required this.pinned,
    required this.muted,
    required this.live,
  });
  final Json s;
  final Json? role;
  final String name;
  final String preview;

  /// 'izin' | 'kerja' | 'pesan'
  final String kind;
  final DateTime? at;
  final bool mine;
  final bool unread;
  final bool pinned;
  final bool muted;
  final bool live;
  String get sid => '${s['sid']}';
}

const _avatarTints = [
  Color(0xFFDDEBFF),
  Color(0xFFFFE6D5),
  Color(0xFFE3F5E1),
  Color(0xFFF1E4FF),
  Color(0xFFFFE1EA),
  Color(0xFFDFF4F4),
  Color(0xFFFFF3C9),
];

Color _tintFor(String key) =>
    _avatarTints[key.codeUnits.fold<int>(
          0,
          (a, b) => (a * 31 + b) & 0x7fffffff,
        ) %
        _avatarTints.length];

class _MessengerAgentListState extends ConsumerState<_MessengerAgentList> {
  String _filter = 'Semua';
  String _query = '';

  Future<void> _open(BuildContext context, String sid) async {
    final marks = ref.read(kantorRoomMarksProvider.notifier);
    marks.markRead(sid);
    // dua panel: ganti panel kanan; layar sempit: push halaman sesi
    await kantorOpenFromList(context, widget.feed.officeId, sid);
    marks.markRead(sid);
  }

  Future<void> _roomSheet(BuildContext context, _Room r) async {
    final marks = ref.read(kantorRoomMarksProvider.notifier);
    final label = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // label lengkap + "Beri label" / "Ubah label"
            if (r.live)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: KantorLabelMenuBody(
                  session: r.s,
                  onEdit: () => Navigator.pop(ctx, true),
                ),
              ),
            ListTile(
              leading: Icon(
                r.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              ),
              title: Text(r.pinned ? 'Lepas sematan' : 'Sematkan'),
              onTap: () {
                marks.togglePin(r.sid);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(
                r.muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              ),
              title: Text(r.muted ? 'Bunyikan' : 'Bisukan'),
              subtitle: const Text('Hanya di daftar ini, di HP ini'),
              onTap: () {
                marks.toggleMute(r.sid);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(
                r.unread
                    ? Icons.mark_chat_read_outlined
                    : Icons.mark_chat_unread_outlined,
              ),
              title: Text(
                r.unread ? 'Tandai sudah dibaca' : 'Tandai belum dibaca',
              ),
              onTap: () {
                r.unread ? marks.markRead(r.sid) : marks.markUnread(r.sid);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
    if (label != true || !context.mounted) return;
    await kantorEditLabel(context, r.s, name: r.name, feed: widget.feed);
  }

  Future<void> _newChat(BuildContext context) async {
    final feed = widget.feed;
    final api = ref.read(kantorApiProvider);
    final liveRoles = {
      for (final s in feed.sessions)
        if (s['status'] != 'ended') s['role'],
    };
    final off = feed.roles
        .where((r) => r['archived'] != true && !liveRoles.contains(r['id']))
        .toList();
    final c = ChatStyleColors.of(context, widget.style);
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Chat baru',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: c.send,
                  child: const Icon(
                    Icons.person_add_alt_1,
                    color: Colors.white,
                  ),
                ),
                title: const Text('Agen baru'),
                onTap: () => Navigator.pop(ctx, 'baru'),
              ),
              if (off.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    'Mulai shift',
                    style: GhinaType.caption.copyWith(color: c.muted),
                  ),
                ),
              for (final r in off)
                ListTile(
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: _tintFor('${r['id']}'),
                    child: KantorSprite(look: r, size: 34),
                  ),
                  title: Text('${r['name']}'),
                  subtitle: Text('${r['title'] ?? ''}'),
                  onTap: () => Navigator.pop(ctx, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || picked == null) return;
    if (picked == 'baru') {
      await showKantorNewAgentSheet(context, officeId: feed.officeId);
      return;
    }
    final sid = await showStartShiftSheet(
      context,
      feed: feed,
      actions: api == null ? null : KantorActions(api),
      role: picked as Json,
    );
    if (sid != null && context.mounted) await _open(context, sid);
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final c = ChatStyleColors.of(context, widget.style);
    final marks = ref.watch(kantorRoomMarksProvider);
    final meetings =
        ref.watch(kantorMeetingsProvider(feed.officeId)).value ??
        const <KantorMeetingBrief>[];
    final waiting = {for (final item in feed.inbox) '${item['sid']}'};
    final filters = [
      'Semua',
      'Belum dibaca',
      'Aktif',
      'Menunggu izin',
      if (meetings.isNotEmpty) 'Rapat',
    ];
    final selected = filters.contains(_filter) ? _filter : 'Semua';

    _Room room(Json s) {
      final sid = '${s['sid']}';
      final role = feed.role(s['role'] as String?);
      final k = KantorKonteks.ofSession(s);
      final status = '${s['status']}';
      final inbox = feed.inbox.where((i) => i['sid'] == s['sid']).toList();
      final w = s['waiting'] is Map ? asJson(s['waiting']) : null;
      final askAt = kantorTime(k?.ask?.at);
      final replyAt = kantorTime(k?.reply?.at);
      final ownerLast =
          k?.ask != null &&
          !k!.ask!.fromAgent &&
          (replyAt == null || (askAt != null && askAt.isAfter(replyAt)));
      final at = [askAt, replyAt, kantorTime(s['lastSeen'])]
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      final String kind;
      final String preview;
      if (inbox.isNotEmpty || w != null || status == 'waiting') {
        kind = 'izin';
        final it = inbox.isNotEmpty ? inbox.first : w;
        final ask = it?['tool'] == 'AskUserQuestion';
        preview =
            '${ask ? 'Bertanya' : 'Menunggu izin'}: ${it?['summary'] ?? it?['tool'] ?? ''}';
      } else if (status == 'working' || status == 'starting') {
        kind = 'kerja';
        preview = status == 'starting' ? 'baru datang…' : 'sedang bekerja…';
      } else {
        kind = 'pesan';
        preview = ownerLast
            ? k.ask!.s
            : (k?.reply?.s ??
                  k?.step ??
                  k?.detail(s) ??
                  (kantorStatusLabel[status] ?? status));
      }
      final read = marks.readAt[sid];
      final unread =
          marks.unread.contains(sid) ||
          (!ownerLast &&
              replyAt != null &&
              read != null &&
              replyAt.millisecondsSinceEpoch > read);
      return _Room(
        s: s,
        role: role,
        name: sessionName(feed, s),
        preview: preview.replaceAll('\n', ' '),
        kind: kind,
        at: at,
        mine: ownerLast && kind == 'pesan',
        unread: unread,
        pinned: marks.pinned.contains(sid),
        muted: marks.muted.contains(sid),
        live: status != 'ended',
      );
    }

    final rooms =
        feed.sessions.map(room).where((r) {
          if (selected == 'Rapat') return false;
          if (selected == 'Aktif' && !r.live) return false;
          if (selected == 'Belum dibaca' && !r.unread) return false;
          if (selected == 'Menunggu izin' &&
              r.kind != 'izin' &&
              !waiting.contains(r.sid)) {
            return false;
          }
          final k = KantorKonteks.ofSession(r.s);
          return '${r.name} ${r.role?['title'] ?? ''} ${r.preview} '
                  '${k?.label ?? ''} ${k?.auto ?? ''}'
              .toLowerCase()
              .contains(_query);
        }).toList()..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          final ta = a.at, tb = b.at;
          if (ta == null || tb == null) return ta == null ? 1 : -1;
          return tb.compareTo(ta);
        });
    final unreadCount = feed.sessions.map(room).where((r) => r.unread).length;
    final visibleMeetings = meetings
        .where((m) => m.topic.toLowerCase().contains(_query))
        .toList();
    final badge = c.send;

    Widget row(_Room r) {
      final previewColor = switch (r.kind) {
        'izin' => const Color(0xFFC2410C),
        'kerja' => badge,
        _ => c.muted,
      };
      final stamp = messengerStamp(r.at);
      final open = KantorPaneScope.maybeOf(context)?.selectedSid == r.sid;
      return InkWell(
        key: ValueKey('room-${r.sid}'),
        onTap: () => _open(context, r.sid),
        onLongPress: () => _roomSheet(context, r),
        child: Container(
          key: open ? ValueKey('room-open-${r.sid}') : null,
          color: open ? c.mine : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: _tintFor(
                        r.role?['id']?.toString() ?? r.sid,
                      ),
                      child: KantorSprite(
                        look: r.role ?? KantorSprite.guestLook(r.sid),
                        size: 44,
                      ),
                    ),
                    if (r.live)
                      Positioned(
                        right: 0,
                        bottom: 1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: c.muted.withValues(alpha: .12),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GhinaType.body.copyWith(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              stamp,
                              style: GhinaType.caption.copyWith(
                                fontSize: 12,
                                color: r.unread && !r.muted ? badge : c.muted,
                                fontWeight: r.unread
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        KantorSessionLabel(
                          session: r.s,
                          maxLines: 2,
                          size: 14,
                          padding: const EdgeInsets.only(top: 3, bottom: 1),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (r.mine) ...[
                              Icon(
                                Icons.done_all_rounded,
                                size: 17,
                                color: c.tick,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (r.mine)
                                      TextSpan(
                                        text: 'Kamu: ',
                                        style: TextStyle(color: c.muted),
                                      ),
                                    TextSpan(text: r.preview),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GhinaType.bodyS.copyWith(
                                  fontSize: 14,
                                  color: previewColor,
                                  fontWeight: r.kind == 'pesan'
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (r.muted) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.volume_off_rounded,
                                size: 17,
                                color: c.muted,
                                semanticLabel: 'Dibisukan',
                              ),
                            ],
                            if (r.pinned) ...[
                              const SizedBox(width: 6),
                              Transform.rotate(
                                angle: .6,
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 16,
                                  color: c.muted,
                                  semanticLabel: 'Disematkan',
                                ),
                              ),
                            ],
                            if (r.unread || r.kind == 'izin') ...[
                              const SizedBox(width: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: r.muted
                                      ? c.muted.withValues(alpha: .6)
                                      : r.kind == 'izin'
                                      ? const Color(0xFFEA580C)
                                      : badge,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  r.kind == 'izin' ? '!' : '1',
                                  style: GhinaType.caption.copyWith(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 10, bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('room-search'),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Cari agent, ruangan, atau pesan',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: c.muted.withValues(alpha: .08),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final filter in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        showCheckmark: false,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        backgroundColor: c.muted.withValues(alpha: .08),
                        selectedColor: c.mine,
                        labelStyle: GhinaType.caption.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected == filter ? c.accent : c.muted,
                        ),
                        label: Text(
                          filter == 'Belum dibaca' && unreadCount > 0
                              ? '$filter $unreadCount'
                              : filter,
                        ),
                        selected: selected == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (selected == 'Rapat')
              for (final meeting in visibleMeetings)
                ListTile(
                  leading: CircleAvatar(
                    radius: 27,
                    backgroundColor: c.mine,
                    child: Icon(Icons.groups_outlined, color: c.accent),
                  ),
                  title: Text(
                    meeting.topic,
                    style: GhinaType.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(meeting.status),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => KantorMeetingDetailScreen(
                        officeId: feed.officeId,
                        meetingId: meeting.id,
                      ),
                    ),
                  ),
                ),
            for (final r in rooms) row(r),
            if (rooms.isEmpty &&
                (selected != 'Rapat' || visibleMeetings.isEmpty))
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tidak ada percakapan pada filter ini.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 20,
          child: FloatingActionButton(
            key: const ValueKey('room-new-chat'),
            heroTag: 'room-new-chat',
            tooltip: 'Chat baru',
            backgroundColor: c.send,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            // which roles are off shift is not known until the daemon answers
            onPressed: feed.fromDisk ? null : () => _newChat(context),
            child: const Icon(Icons.add_comment_rounded),
          ),
        ),
      ],
    );
  }
}

class _Row {
  const _Row({
    required this.look,
    required this.name,
    required this.job,
    required this.sub,
    this.session,
    this.role,
    this.boss = false,
  });
  final Json look;
  final String name;
  final String job;
  final String sub;
  final Json? session;
  final Json? role;
  final bool boss;
}

class _AgentList extends StatelessWidget {
  const _AgentList({required this.feed, required this.actions});

  final KantorOfficeFeed feed;
  final KantorActions? actions;

  void _toast(BuildContext context, String m) => showToastBadge(
    context,
    message: m,
    icon: Icons.error_outline_rounded,
    color: GhinaColors.red,
    tag: 'kantor-agents',
  );

  void _open(BuildContext context, String sid) =>
      kantorOpenFromList(context, feed.officeId, sid);

  Future<void> _decide(BuildContext context, Json item, String behavior) async {
    try {
      await actions?.decide('${item['id']}', behavior);
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  Future<void> _dismiss(BuildContext context, Json item) async {
    try {
      await actions?.dismiss('${item['id']}');
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  Future<void> _answer(BuildContext context, Json item, int n) async {
    try {
      await actions?.answerAsk(item, n);
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  Future<void> _startShift(BuildContext context, Json role) async {
    final sid = await showStartShiftSheet(
      context,
      feed: feed,
      actions: actions,
      role: role,
    );
    if (sid != null && context.mounted) _open(context, sid);
  }

  Future<void> _newAgent(BuildContext context) =>
      showKantorNewAgentSheet(context, officeId: feed.officeId);

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final live = feed.sessions.where((s) => s['status'] != 'ended').toList();
    final waiting = <_Row>[];
    final working = <_Row>[];
    final idle = <_Row>[];
    final syncing = <_Row>[]; // from the disk snapshot, status not known yet
    final off = <Json>[];
    final inboxSids = {for (final i in feed.inbox) i['sid']};

    void put(
      Json s,
      Json look,
      String name,
      String job,
      bool boss,
      Json? role,
    ) {
      final w = s['waiting'] is Map ? asJson(s['waiting']) : null;
      final status = s['status'];
      final room = feed.roomName(s['room'] as String?);
      _Row row(String sub) => _Row(
        look: look,
        name: name,
        job: job,
        sub: sub,
        session: s,
        role: role,
        boss: boss,
      );
      if (status == '') {
        syncing.add(row('menyinkronkan…'));
      } else if (w != null || status == 'waiting') {
        if (inboxSids.contains(s['sid'])) return; // shown as a card above
        final what = w?['tool'] == 'AskUserQuestion'
            ? 'bertanya'
            : 'minta izin';
        waiting.add(
          row('$what: ${clip('${w?['summary'] ?? w?['tool'] ?? ''}', 60)}'),
        );
      } else if (status == 'working' || status == 'starting') {
        final t = toolFull(s['tool']);
        working.add(
          row(
            t.isNotEmpty
                ? t
                : status == 'starting'
                ? 'baru datang'
                : 'sedang bekerja',
          ),
        );
      } else {
        final since = agoText(s['lastSeen']);
        idle.add(
          row(
            'diam ${since.isEmpty ? 'baru saja' : since}${room.isEmpty ? '' : ' - $room'}',
          ),
        );
      }
    }

    for (final r in feed.roles.where((r) => r['archived'] != true)) {
      final ss = live.where((s) => s['role'] == r['id']).toList();
      if (ss.isEmpty) {
        off.add(r);
        continue;
      }
      for (final s in ss) {
        final slot = (s['slot'] as num?)?.toInt() ?? 0;
        final boss = r['isMgr'] == true && slot == 0;
        put(
          s,
          r,
          '${r['name']}${slot > 0 ? ' #${slot + 1}' : ''}',
          boss ? '' : '${r['title'] ?? ''}',
          boss,
          r,
        );
      }
    }
    for (final s in live.where((s) => s['role'] == null)) {
      put(
        s,
        KantorSprite.guestLook('${s['sid']}'),
        sessionName(feed, s),
        '',
        false,
        null,
      );
    }

    Widget group(String title, int n, List<Widget> body, {Color? color}) =>
        n == 0
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                  child: Row(
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: GhinaType.overline.copyWith(
                          color: color ?? g.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$n',
                        style: GhinaType.overline.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                ),
                ...body,
              ],
            ),
          );

    Widget tile(_Row r) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: _AgentTile(
        row: r,
        open:
            r.session != null &&
            KantorPaneScope.maybeOf(context)?.selectedSid ==
                '${r.session!['sid']}',
        onTap: () => _open(context, '${r.session!['sid']}'),
        onLongPress: () =>
            showKantorLabelMenu(context, r.session!, name: r.name, feed: feed),
      ),
    );

    final waitCards = [
      for (final i in feed.inbox)
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: KantorPermissionCard(
            item: i,
            who: i['who'] as String?,
            onDecide: (b) => _decide(context, i, b),
            onAnswer: (n) => _answer(context, i, n),
            onDismiss: () => _dismiss(context, i),
            onOpen: i['tool'] == 'AskUserQuestion' && i['sid'] != null
                ? () => _open(context, '${i['sid']}')
                : null,
          ),
        ),
    ];

    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.page,
            GhinaSpace.page,
            96,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: ChunkyButton(
                label: 'Obrolan agen',
                icon: Icons.forum_outlined,
                variant: ChunkyButtonVariant.outline,
                expand: true,
                onPressed: () => openKantorDm(context, officeId: feed.officeId),
              ),
            ),
            if (live.isEmpty && feed.inbox.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
                child: EmptyState(
                  title: 'Belum ada sesi berjalan',
                  message:
                      'Mulai agen baru dari role yang ada, atau buat role.',
                  actionLabel: 'Agen baru',
                  onAction: () => _newAgent(context),
                  compact: true,
                ),
              ),
            group(
              'Menunggu kamu',
              waiting.length + feed.inbox.length,
              [...waitCards, ...waiting.map(tile)],
              color: GhinaColors.orange.edge,
            ),
            group('Bekerja', working.length, working.map(tile).toList()),
            group('Idle', idle.length, idle.map(tile).toList()),
            group('Menyinkronkan', syncing.length, syncing.map(tile).toList()),
            if (off.isNotEmpty)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(
                        'LIBUR',
                        style: GhinaType.overline.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${off.length}',
                        style: GhinaType.overline.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                  children: [
                    for (final r in off)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                        child: _AgentTile(
                          row: _Row(
                            look: r,
                            name: '${r['name']}',
                            job: '${r['title'] ?? ''}',
                            sub: feed.fromDisk
                                ? 'menyinkronkan…'
                                : 'Ketuk untuk mulai shift - ${feed.roomName(r['room'] as String?)}',
                            role: r,
                            boss: r['isMgr'] == true,
                          ),
                          onTap: feed.fromDisk
                              ? null
                              : () => _startShift(context, r),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        Positioned(
          right: GhinaSpace.page,
          bottom: GhinaSpace.page,
          child: FloatingActionButton.extended(
            heroTag: 'kantor-agent-add',
            onPressed: () => _newAgent(context),
            icon: const Icon(Icons.add),
            label: const Text('Agen baru'),
          ),
        ),
      ],
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({
    required this.row,
    required this.onTap,
    this.onLongPress,
    this.open = false,
  });

  final _Row row;
  final bool open;
  final VoidCallback? onTap;

  /// Tahan: menu label (hanya agen yang sedang shift).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = row.session;
    final waiting =
        s != null && (s['waiting'] != null || s['status'] == 'waiting');
    final working =
        s != null && (s['status'] == 'working' || s['status'] == 'starting');
    final dot = s == null
        ? g.textMuted
        : waiting
        ? GhinaColors.orange.base
        : working
        ? GhinaColors.green.base
        : g.textMuted;
    final card = ChunkyCard(
      key: s == null ? null : ValueKey('agent-tile-${s['sid']}'),
      tinted: waiting ? GhinaColors.orange : null,
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: GhinaSpace.sm,
      ),
      child: Row(
        children: [
          Opacity(
            opacity: s == null ? 0.55 : 1,
            child: KantorSprite(look: row.look, size: 48),
          ),
          const SizedBox(width: GhinaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (row.job.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          row.job,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                      ),
                    ],
                    if (kantorEngineIsCodex(row.session, row.role)) ...[
                      const SizedBox(width: 6),
                      const KantorCodexBadge(),
                    ],
                    if (row.boss) ...[
                      const SizedBox(width: 6),
                      const ChunkyPill(
                        label: 'bos',
                        color: GhinaColors.purple,
                        soft: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (s != null && KantorKonteks.ofSession(s) != null)
                  KantorKonteksLines(session: s, fallback: row.sub)
                else
                  Text(
                    row.sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: GhinaSpace.sm),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ],
      ),
    );
    if (!open) return card;
    return DecoratedBox(
      key: const ValueKey('tile-open'),
      decoration: BoxDecoration(
        borderRadius:
            GhinaRadii.rLg + const BorderRadius.all(Radius.circular(4)),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: card,
    );
  }
}
