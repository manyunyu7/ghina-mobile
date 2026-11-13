part of 'kantor_session_page.dart';

final _profileFilesProvider = FutureProvider.autoDispose
    .family<List<KantorAttachment>, (String, String)>((ref, key) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) return const [];
      ref.listen(kantorEventsProvider, (_, next) {
        if (next.value?['t'] == 'attachment' && next.value?['sid'] == key.$2) {
          ref.invalidateSelf();
        }
      });
      return parseAttachments(
        await api.get(
          '/api/sessions/${Uri.encodeComponent(key.$2)}/attachments',
        ),
      );
    });

String _messengerStatus(Json sess, Json? role) {
  final status = '${sess['status'] ?? ''}';
  final label = sess['machineOffline'] == true
      ? 'mesin offline'
      : switch (status) {
          'working' || 'starting' => 'sedang bekerja…',
          'waiting' => 'menunggu izin',
          'idle' => 'online',
          'ended' => 'sesi selesai',
          _ => kantorStatusLabel[status] ?? status,
        };
  // Only include context usage when the server actually supplies it.
  final usage = asJson(sess['ctx']);
  final pct = usage['pct'];
  return [
    label,
    if (role?['title'] != null) '${role!['title']}',
    kantorSessionModelText(role, sess),
    if (pct is num) 'konteks ${pct.round()}%',
  ].where((s) => s.isNotEmpty).join(' · ');
}

class KantorMessengerHeader extends StatelessWidget {
  const KantorMessengerHeader({
    super.key,
    required this.feed,
    required this.sess,
    required this.style,
    required this.onTap,
  });
  final KantorOfficeFeed feed;
  final Json sess;
  final ChatStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = feed.role(sess['role'] as String?);
    final c = ChatStyleColors.of(context, style);
    return InkWell(
      key: const ValueKey('messenger-profile-header'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: c.surface,
              radius: 20,
              child: KantorSprite(
                look: role ?? KantorSprite.guestLook('${sess['sid']}'),
                size: 36,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sessionName(feed, sess),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body.copyWith(
                      color: c.headerInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _messengerStatus(sess, role),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(
                      fontSize: 12,
                      color: style == ChatStyle.whatsapp
                          ? Colors.white
                          : c.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile is pushed over the conversation. The original chat remains mounted,
/// retaining draft, scroll position, attachments and terminal focus isolation.
class KantorAgentProfilePage extends ConsumerStatefulWidget {
  const KantorAgentProfilePage({
    super.key,
    required this.feed,
    required this.sid,
    required this.actions,
  });
  final KantorOfficeFeed feed;
  final String sid;
  final KantorActions? actions;
  @override
  ConsumerState<KantorAgentProfilePage> createState() => _AgentProfileState();
}

class _AgentProfileState extends ConsumerState<KantorAgentProfilePage> {
  String? _selected;
  void _tab(int n) => Navigator.of(context).pop(n);

  @override
  Widget build(BuildContext context) {
    final previews = ref.watch(
      kantorPratinjauSessionProvider((widget.feed.officeId, widget.sid)),
    );
    final attachments =
        ref
            .watch(_profileFilesProvider((widget.feed.officeId, widget.sid)))
            .value ??
        const <KantorAttachment>[];
    final meetings =
        ref.watch(kantorMeetingsProvider(widget.feed.officeId)).value ??
        const <KantorMeetingBrief>[];
    final api = ref.watch(kantorApiProvider);
    final view = ref.watch(chatViewPrefsProvider);
    return ListenableBuilder(
      listenable: widget.feed,
      builder: (context, _) {
        final sess = widget.feed.session(widget.feed.follow(widget.sid));
        if (sess == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Profil agent')),
            body: const Center(child: Text('Sesi tidak ditemukan.')),
          );
        }
        final role = widget.feed.role(sess['role'] as String?);
        final c = ChatStyleColors.of(context, view.style);
        final menu = _Menu(
          feed: widget.feed,
          sess: sess,
          actions: widget.actions,
        );
        final alive = sess['status'] != 'ended';
        final controllable = alive && widget.actions != null;
        final tmux = sess['tmux'] != null;
        final busy =
            sess['status'] == 'working' || sess['status'] == 'starting';
        final skills = (role?['skills'] as List?) ?? const [];
        final subs = asJsonList(sess['subs']);
        final items = previews.value?.items ?? const <PratinjauItem>[];
        final fileRows = [
          for (final item in items)
            for (final file in item.files) (item: item, file: file),
        ];
        final card = asJson(asJson(sess['konteks'])['card']);
        final roleMeetings = role == null
            ? const <KantorMeetingBrief>[]
            : meetings
                  .where((m) => m.participants.contains(role['id']))
                  .toList();
        final tabs = <String>[
          if (items.isNotEmpty && api != null) 'Pratinjau',
          if (card['title'] != null) 'Kartu',
          if ((fileRows.isNotEmpty || attachments.isNotEmpty) && api != null)
            'File',
          if (roleMeetings.isNotEmpty) 'Rapat',
        ];
        final selected = tabs.contains(_selected)
            ? _selected
            : tabs.firstOrNull;
        Widget surface(
          Widget child, {
          EdgeInsets padding = const EdgeInsets.all(18),
        }) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: padding, child: child),
          ),
        );
        Widget fact(String value, String label, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: GhinaType.body.copyWith(color: c.ink)),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: GhinaType.caption.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        );
        Widget action(
          String label,
          IconData icon,
          VoidCallback onTap, {
          bool destructive = false,
        }) => Expanded(
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 72,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: destructive ? GhinaColors.red.base : c.ink,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: GhinaType.caption.copyWith(
                        color: destructive ? GhinaColors.red.base : c.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        void openPreview(PratinjauItem item, [String? fileId]) =>
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => KantorPratinjauDetailPage(
                  officeId: widget.feed.officeId,
                  itemId: item.id,
                  fileId: fileId,
                ),
              ),
            );
        return Scaffold(
          backgroundColor: c.dark
              ? const Color(0xFF14232D)
              : const Color(0xFFF0F1F4),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Material(
                      color: c.surface,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Kembali ke chat',
                        onPressed: () => _tab(0),
                        icon: const Icon(Icons.arrow_back),
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                      ),
                    ),
                    Material(
                      color: c.surface,
                      shape: const CircleBorder(),
                      child: SizedBox(width: 48, height: 48, child: menu),
                    ),
                  ],
                ),
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: c.surface,
                        child: KantorSprite(
                          look:
                              role ?? KantorSprite.guestLook('${sess['sid']}'),
                          size: 88,
                        ),
                      ),
                      if (alive && sess['machineOffline'] != true)
                        Positioned(
                          right: 3,
                          bottom: 3,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: GhinaColors.green.base,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: c.surface, width: 3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  sessionName(widget.feed, sess),
                  textAlign: TextAlign.center,
                  style: GhinaType.h2.copyWith(color: c.ink),
                ),
                Text(
                  _messengerStatus(sess, role),
                  textAlign: TextAlign.center,
                  style: GhinaType.bodyS.copyWith(color: c.muted),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    action('Pesan', Icons.chat_bubble_outline, () => _tab(0)),
                    if (alive && tmux) ...[
                      const SizedBox(width: 8),
                      action('Terminal', Icons.terminal, () => _tab(1)),
                    ],
                    if (controllable) ...[
                      const SizedBox(width: 8),
                      action(
                        'Hentikan',
                        Icons.remove_circle_outline,
                        () => menu._run(context, 'esc'),
                        destructive: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                surface(
                  Column(
                    children: [
                      if (role?['id'] != null)
                        fact(
                          '@${role!['id']}',
                          [
                            'Nama di kantor',
                            widget.feed.roomName(sess['room'] as String?),
                          ].where((x) => x.isNotEmpty).join(' · '),
                        ),
                      if ('${role?['persona'] ?? ''}'.trim().isNotEmpty)
                        fact('${role!['persona']}', 'Kepribadian'),
                      if (kantorSessionModelText(role, sess).isNotEmpty)
                        fact(
                          kantorSessionModelText(role, sess),
                          'Model',
                          trailing: controllable && tmux && !busy
                              ? TextButton(
                                  onPressed: () => menu._codex
                                      ? menu._codexSettings(context)
                                      : menu._model(context),
                                  child: const Text('Ganti'),
                                )
                              : null,
                        ),
                      if ('${sess['cwd'] ?? ''}'.isNotEmpty)
                        fact(
                          '${sess['cwd']}',
                          [
                            'Folder kerja',
                            if (sess['machine'] != null) '${sess['machine']}',
                          ].join(' · '),
                        ),
                    ],
                  ),
                ),
                if (role != null && widget.actions != null)
                  surface(
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.group_add_outlined),
                      title: const Text('Undang ke rapat atau ruangan'),
                      subtitle: const Text(
                        'Pilih peserta melalui form rapat kantor.',
                      ),
                      onTap: () async {
                        final id = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (_) => KantorMeetingFormScreen(
                              officeId: widget.feed.officeId,
                            ),
                          ),
                        );
                        if (id != null && context.mounted) {
                          ref.invalidate(
                            kantorMeetingsProvider(widget.feed.officeId),
                          );
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => KantorMeetingDetailScreen(
                                officeId: widget.feed.officeId,
                                meetingId: id,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                surface(
                  Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tampilan chat'),
                        trailing: Text(view.style.label),
                        onTap: () => showChatViewSheet(context),
                      ),
                      if (controllable && tmux)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mode izin'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => menu._mode(context),
                        ),
                      if (skills.isNotEmpty || subs.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Skills & subagent'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Skills & subagent'),
                                ),
                                body: DefaultTabController(
                                  length: subs.isEmpty ? 1 : 2,
                                  child: Column(
                                    children: [
                                      TabBar(
                                        tabs: [
                                          const Tab(text: 'Skills'),
                                          if (subs.isNotEmpty)
                                            const Tab(text: 'Subagent'),
                                        ],
                                      ),
                                      Expanded(
                                        child: TabBarView(
                                          children: [
                                            KantorProfileTab(
                                              feed: widget.feed,
                                              sid: '${sess['sid']}',
                                            ),
                                            if (subs.isNotEmpty)
                                              KantorSubsTab(
                                                feed: widget.feed,
                                                sid: '${sess['sid']}',
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                ),
                if (tabs.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tab in tabs)
                        ChoiceChip(
                          label: Text(tab),
                          selected: selected == tab,
                          onSelected: (_) => setState(() => _selected = tab),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selected == 'Pratinjau')
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      children: [
                        for (final item in items)
                          Semantics(
                            button: true,
                            label: item.title,
                            child: InkWell(
                              onTap: () => openPreview(item),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: item.files.isEmpty
                                    ? ColoredBox(
                                        color: c.surface,
                                        child: Center(
                                          child: Text(
                                            item.title,
                                            maxLines: 3,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      )
                                    : PratinjauThumb(
                                        api: api!,
                                        file: item.files.first,
                                        compact: true,
                                        purged: item.filesPurged,
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (selected == 'File')
                    surface(
                      Column(
                        children: [
                          for (final attachment in attachments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AttachmentBubble(
                                item: attachment,
                                api: api,
                              ),
                            ),
                          for (final row in fileRows)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.insert_drive_file_outlined,
                              ),
                              title: Text(row.file.name),
                              onTap: () => openPreview(row.item, row.file.id),
                            ),
                        ],
                      ),
                    ),
                  if (selected == 'Rapat')
                    surface(
                      Column(
                        children: [
                          for (final meeting in roleMeetings)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.groups_outlined),
                              title: Text(meeting.topic),
                              subtitle: Text(meeting.status),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => KantorMeetingDetailScreen(
                                    officeId: widget.feed.officeId,
                                    meetingId: meeting.id,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (selected == 'Kartu')
                    surface(
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.view_kanban_outlined),
                        title: Text('${card['title']}'),
                        onTap: card['id'] == null
                            ? null
                            : () => openKantorCard(
                                context,
                                officeId: widget.feed.officeId,
                                cardId: '${card['id']}',
                              ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
