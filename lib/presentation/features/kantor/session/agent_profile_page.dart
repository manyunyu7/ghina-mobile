part of 'kantor_session_page.dart';

class _ProfilePersona extends StatefulWidget {
  const _ProfilePersona({required this.text, required this.colors});
  final String text;
  final ChatStyleColors colors;
  @override
  State<_ProfilePersona> createState() => _ProfilePersonaState();
}

class _ProfilePersonaState extends State<_ProfilePersona> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final style = GhinaType.body.copyWith(color: widget.colors.ink);
        final measure = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
        )..layout(maxWidth: constraints.maxWidth);
        final truncated = measure.didExceedMaxLines;
        measure.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              key: const ValueKey('profile-persona'),
              style: style,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
            if (truncated)
              TextButton(
                key: const ValueKey('profile-persona-expand'),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Lebih sedikit' : 'Selengkapnya'),
              ),
            const SizedBox(height: 3),
            Text(
              'Kepribadian',
              style: GhinaType.caption.copyWith(color: widget.colors.muted),
            ),
          ],
        );
      },
    ),
  );
}

/// Telegram "Media"-style tile: real thumbnail for images/video, a tinted
/// kind tile for HTML bundles, PDFs and the rest; title on a dark gradient,
/// status dot, file count and version badges.
class _ProfilePreviewTile extends StatelessWidget {
  const _ProfilePreviewTile({
    required this.item,
    required this.api,
    required this.colors,
    required this.onTap,
  });
  final PratinjauItem item;
  final KantorApi api;
  final ChatStyleColors colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final files = item.files;
    final visual = files
        .where((f) => f.kind == 'image' || f.kind == 'video')
        .firstOrNull;
    final kind =
        files.firstOrNull?.kind ?? (item.mode == 'bundle' ? 'html' : 'other');
    final (statusLabel, statusSwatch) = pratinjauStatusLook(item.status);
    final label = _kindLabel(
      item.mode == 'bundle' ? 'html' : kind,
      files.firstOrNull?.name,
    );
    return Semantics(
      button: true,
      label: '${item.title}, $statusLabel',
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('profile-preview-${item.id}'),
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (visual != null)
                PratinjauThumb(
                  api: api,
                  file: visual,
                  compact: true,
                  purged: item.filesPurged,
                )
              else
                Container(
                  color: colors.accent.withValues(
                    alpha: colors.dark ? 0.18 : 0.10,
                  ),
                  alignment: const Alignment(0, -0.35),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pratinjauKindIcon(
                          item.mode == 'bundle' ? 'html' : kind,
                        ),
                        size: 30,
                        color: colors.accent,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: GhinaType.caption.copyWith(
                          color: colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.45, 1],
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(
                        color: Colors.white,
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusSwatch.base,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (files.length > 1 || item.version > 1)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _TileBadge(
                    [
                      if (files.length > 1) '${files.length} berkas',
                      if (item.version > 1) 'v${item.version}',
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: GhinaType.caption.copyWith(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// "PNG", "PDF", "HTML": the file's extension, else its kind.
String _kindLabel(String kind, [String? name]) {
  final n = name ?? '';
  final dot = n.lastIndexOf('.');
  if (dot > 0 && dot < n.length - 1 && n.length - dot <= 6) {
    return n.substring(dot + 1).toUpperCase();
  }
  return switch (kind) {
    'html' => 'HTML',
    'image' => 'GAMBAR',
    'video' => 'VIDEO',
    'audio' => 'AUDIO',
    'pdf' => 'PDF',
    _ => 'FILE',
  };
}

Color _extColor(String ext) => switch (ext) {
  'PDF' => const Color(0xFFD93F3F),
  'PNG' ||
  'JPG' ||
  'JPEG' ||
  'WEBP' ||
  'GIF' ||
  'GAMBAR' => const Color(0xFF2F6FEB),
  'MP4' || 'MOV' || 'WEBM' || 'VIDEO' => const Color(0xFF7C4DFF),
  'MP3' || 'M4A' || 'WAV' || 'AUDIO' => const Color(0xFFE84393),
  'HTML' || 'ZIP' => const Color(0xFFF28C28),
  'APK' => const Color(0xFF3DA35D),
  'CSV' || 'XLS' || 'XLSX' => const Color(0xFF1E8E5A),
  'MD' || 'TXT' || 'JSON' => const Color(0xFF5B6E6A),
  _ => const Color(0xFF0F766E),
};

const _bulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// One row of the Telegram "Files"-style list: a session attachment or a
/// file inside a pratinjau item.
class _ProfileFileEntry {
  _ProfileFileEntry({
    required this.name,
    required this.size,
    required this.ext,
    required this.source,
    required this.at,
    required this.onTap,
    this.thumb,
  });
  final String name;
  final int size;
  final String ext;
  final String source;
  final DateTime? at;
  final VoidCallback? onTap;
  final Widget? thumb;
}

class _ProfileFileRow extends StatelessWidget {
  const _ProfileFileRow({required this.entry, required this.colors});
  final _ProfileFileEntry entry;
  final ChatStyleColors colors;
  @override
  Widget build(BuildContext context) {
    final e = entry;
    final t = e.at;
    final when = t == null
        ? null
        : '${t.day} ${_bulan[t.month - 1].substring(0, 3)} · '
              '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
    final sub = [
      if (e.size > 0) fmtSize(e.size),
      ?when,
      e.source,
    ].where((x) => x.isNotEmpty).join(' · ');
    return InkWell(
      onTap: e.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child:
                    e.thumb ??
                    ColoredBox(
                      color: _extColor(e.ext),
                      child: Center(
                        child: Text(
                          e.ext.length > 4 ? e.ext.substring(0, 4) : e.ext,
                          style: GhinaType.caption.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(
                      color: colors.muted,
                      fontSize: 12.5,
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
    this.onLongPress,
  });
  final KantorOfficeFeed feed;
  final Json sess;
  final ChatStyle style;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final role = feed.role(sess['role'] as String?);
    final c = ChatStyleColors.of(context, style);
    return InkWell(
      key: const ValueKey('messenger-profile-header'),
      onTap: onTap,
      onLongPress: onLongPress,
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
                        _ProfilePersona(text: '${role!['persona']}', colors: c),
                      if (kantorSessionModelText(role, sess).isNotEmpty)
                        fact(
                          kantorSessionModelText(role, sess),
                          'Model',
                          trailing: TextButton(
                            key: const ValueKey('profile-change-model'),
                            onPressed: controllable && tmux && !busy
                                ? () => menu._codex
                                      ? menu._codexSettings(context)
                                      : menu._model(context)
                                : null,
                            child: const Text('Ganti'),
                          ),
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
                        key: const ValueKey('profile-chat-view'),
                        title: const Text('Tampilan chat'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(view.style.label),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right, size: 20, color: c.muted),
                          ],
                        ),
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
                  if (selected == 'Pratinjau' && api != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        children: [
                          for (final item in items)
                            _ProfilePreviewTile(
                              item: item,
                              api: api,
                              colors: c,
                              onTap: () => openPreview(item),
                            ),
                        ],
                      ),
                    ),
                  if (selected == 'File' && api != null)
                    Builder(
                      builder: (context) {
                        DateTime? when(String? iso) => iso == null
                            ? null
                            : DateTime.tryParse(iso)?.toLocal();
                        final entries =
                            <_ProfileFileEntry>[
                              for (final a in attachments)
                                _ProfileFileEntry(
                                  name: a.name,
                                  size: a.size,
                                  ext: _kindLabel(a.kind.name, a.name),
                                  source: a.mine
                                      ? 'kamu kirim'
                                      : (a.agent.isEmpty
                                            ? 'dari agent'
                                            : 'dari ${a.agent}'),
                                  at: when(a.at),
                                  thumb: a.hasThumb
                                      ? Image.network(
                                          api.url(a.thumbPath).toString(),
                                          headers: api.authHeaders,
                                          fit: BoxFit.cover,
                                          cacheWidth: 144,
                                          errorBuilder: (_, _, _) => ColoredBox(
                                            color: _extColor(
                                              _kindLabel(a.kind.name, a.name),
                                            ),
                                            child: const Icon(
                                              Icons.image_outlined,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () async {
                                    if (a.kind == AttachmentKind.image ||
                                        a.kind == AttachmentKind.video) {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              a.kind == AttachmentKind.video
                                              ? KantorVideoViewer(
                                                  item: a,
                                                  api: api,
                                                )
                                              : KantorImageViewer(
                                                  item: a,
                                                  api: api,
                                                ),
                                        ),
                                      );
                                      return;
                                    }
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    try {
                                      final f = await downloadAttachment(
                                        api,
                                        a,
                                      );
                                      await shareAttachmentFile(f, a);
                                    } catch (_) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Gagal membuka ${a.name}',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              for (final row in fileRows)
                                _ProfileFileEntry(
                                  name: row.file.name,
                                  size: row.file.size,
                                  ext: _kindLabel(row.file.kind, row.file.name),
                                  source: 'Pratinjau: ${row.item.title}',
                                  at: when(row.item.createdAt),
                                  thumb:
                                      (row.file.kind == 'image' ||
                                              row.file.kind == 'video') &&
                                          !row.item.filesPurged
                                      ? PratinjauThumb(
                                          api: api,
                                          file: row.file,
                                          compact: true,
                                        )
                                      : null,
                                  onTap: () =>
                                      openPreview(row.item, row.file.id),
                                ),
                            ]..sort((x, y) {
                              final ax = x.at, ay = y.at;
                              if (ax == null && ay == null) return 0;
                              if (ax == null) return 1;
                              if (ay == null) return -1;
                              return ay.compareTo(ax);
                            });
                        final children = <Widget>[];
                        String? month;
                        for (final e in entries) {
                          final m = e.at == null
                              ? 'Lainnya'
                              : '${_bulan[e.at!.month - 1]} ${e.at!.year}';
                          if (m != month) {
                            month = m;
                            children.add(
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  6,
                                  children.isEmpty ? 2 : 14,
                                  6,
                                  4,
                                ),
                                child: Text(
                                  m,
                                  style: GhinaType.caption.copyWith(
                                    color: c.muted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }
                          children.add(_ProfileFileRow(entry: e, colors: c));
                        }
                        return surface(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children,
                          ),
                        );
                      },
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
