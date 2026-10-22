import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import '../../notes/widgets/dictation_bar.dart';
import '../widgets/kantor_markdown.dart';
import 'attach_picker.dart';
import 'attachment_model.dart';
import 'attachment_uploader.dart';
import 'attachment_uploads.dart';
import 'attachment_views.dart';
import '../pratinjau/pratinjau_chat_bubble.dart';
import 'chat_dictation.dart';
import 'chat_images.dart';
import 'chat_subagents.dart';
import 'chat_model.dart';
import 'chat_view_prefs.dart';
import 'kantor_actions.dart';
import 'kantor_feed.dart';
import 'stop_choice.dart';
import 'permission_card.dart';

const _pollEvery = Duration(seconds: 2, milliseconds: 500);
const _toolFold = 3;

/// Conversation of one session from its transcript: user bubbles on the right,
/// Claude on the left (markdown), tool calls folded into small rows, the
/// permission and question cards of this session, and the message box.
class KantorChatTab extends ConsumerStatefulWidget {
  const KantorChatTab({super.key, required this.feed, required this.sid});

  final KantorOfficeFeed feed;
  final String sid;

  @override
  ConsumerState<KantorChatTab> createState() => _KantorChatTabState();
}

class _KantorChatTabState extends ConsumerState<KantorChatTab> {
  final _input = TextEditingController();
  Timer? _timer;
  Timer? _bump;
  List<ChatEntry>? _entries;
  Object? _error;
  Object? _size;
  bool _loading = false;
  bool _sending = false;
  List<KantorAttachment> _atts = const [];
  bool _loadingAtts = false;
  late final ChatDictation _dictation = ChatDictation(
    ref: ref,
    context: () => context,
    text: _input,
  );
  bool _holdMic = false;

  KantorActions? get _actions {
    final api = ref.read(kantorApiProvider);
    return api == null ? null : KantorActions(api);
  }

  Json get _sess => widget.feed.session(widget.sid) ?? const {};

  @override
  void initState() {
    super.initState();
    kantorOpenChats[widget.sid] = (kantorOpenChats[widget.sid] ?? 0) + 1;
    _load();
    _loadAtts();
    _timer = Timer.periodic(_pollEvery, (_) => _load());
    widget.feed.addListener(_onFeed);
  }

  String? _lastStatus;
  void _onFeed() {
    // a status change usually means new transcript lines
    final st = '${_sess['status']}|${_sess['tool']}';
    if (st != _lastStatus) {
      _lastStatus = st;
      _bumpLoad(700);
    }
  }

  void _bumpLoad([int ms = 900]) {
    _bump?.cancel();
    _bump = Timer(Duration(milliseconds: ms), _load);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bump?.cancel();
    widget.feed.removeListener(_onFeed);
    final open = (kantorOpenChats[widget.sid] ?? 1) - 1;
    if (open <= 0) {
      kantorOpenChats.remove(widget.sid);
    } else {
      kantorOpenChats[widget.sid] = open;
    }
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _loading || !mounted) return;
    _loading = true;
    try {
      final data = asJson(
        await api.get(
          '/api/sessions/${widget.sid}/transcript',
          query: {'n': 200},
        ),
      );
      if (!mounted) return;
      if (data['size'] != null && data['size'] == _size && _entries != null)
        return;
      _size = data['size'];
      _loadAtts();
      setState(() {
        _entries = buildChat(asJsonList(data['items']));
        _error = null;
      });
    } catch (e) {
      if (mounted && _entries == null) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  /// Attachments are optional for the daemon (older builds answer 404): a
  /// failure just leaves the list as it was.
  Future<void> _loadAtts() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _loadingAtts || !mounted) return;
    _loadingAtts = true;
    try {
      final list = parseAttachments(
        await api.get('/api/sessions/${widget.sid}/attachments'),
      );
      if (mounted && !_sameAtts(list)) setState(() => _atts = list);
    } catch (_) {
      // keep what we have
    } finally {
      _loadingAtts = false;
    }
  }

  bool _sameAtts(List<KantorAttachment> n) =>
      n.length == _atts.length &&
      [
        for (var i = 0; i < n.length; i++)
          n[i].id == _atts[i].id &&
              n[i].processing == _atts[i].processing &&
              n[i].delivered == _atts[i].delivered,
      ].every((x) => x);

  void _onEvent(Json? msg) {
    if (msg == null || msg['t'] != 'attachment' || msg['sid'] != widget.sid)
      return;
    final item = KantorAttachment.fromJson(asJson(msg['item']));
    if (item.id.isEmpty) return;
    // the daemon re-sends an item when it changes (frames ready, delivered)
    final i = _atts.indexWhere((a) => a.id == item.id);
    setState(
      () => _atts = i < 0 ? [..._atts, item] : [..._atts]
        ..[i] = item,
    );
  }

  void _onUploads(List<UploadJob>? prev, List<UploadJob> next) {
    final was = {for (final j in prev ?? const <UploadJob>[]) j.id: j.status};
    final landed = next.any(
      (j) =>
          j.sid == widget.sid &&
          j.status == UploadStatus.done &&
          was[j.id] != UploadStatus.done,
    );
    if (landed) _loadAtts();
  }

  bool get _canAttach => _sess['status'] != 'ended';

  Future<void> _attach() async {
    final choice = await showAttachSheet(context);
    if (choice == null || !mounted) return;
    List<PickedAttachment> picked;
    try {
      picked = await pickAttachments(choice);
    } catch (e) {
      if (mounted) _err('Tidak bisa mengambil berkas.');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    var caption = _input.text.trim();
    final who = sessionName(widget.feed, _sess);
    final uploads = ref.read(kantorUploadsProvider.notifier);
    try {
      for (final f in picked) {
        // the text in the field is the caption of the first file only
        await uploads.enqueue(
          sid: widget.sid,
          agent: who,
          source: f.file,
          name: f.name,
          mime: f.mime,
          caption: caption,
        );
        if (caption.isNotEmpty) {
          _input.clear();
          caption = '';
        }
      }
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) _err('Gagal menyiapkan file: $e');
    }
  }

  bool get _canSend {
    final s = _sess;
    if (s['status'] == 'ended') return false;
    final typeable =
        s['tty'] != null && !['vscode', 'lain'].contains(s['host']);
    return s['tmux'] != null || typeable;
  }

  void _err(Object e) => showToastBadge(
    context,
    message: '$e',
    icon: Icons.error_outline_rounded,
    color: GhinaColors.red,
    tag: 'kantor-chat',
  );

  Future<void> _say(String text) async {
    // sending mid-dictation takes the last words along
    final fromField = text == _input.text;
    if (_dictation.active) await _dictation.stop();
    if (!mounted) return;
    if (fromField) text = _input.text;
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _actions?.sendText(widget.sid, t);
      if (text == _input.text) _input.clear();
      HapticFeedback.selectionClick();
      _bumpLoad(1200);
    } catch (e) {
      if (mounted) _err(e);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _act(String action) async {
    if (action == 'esc') {
      final pick = await askStopMode(context, _sess);
      if (pick == null || !mounted) return;
      action = pick;
    }
    try {
      final did = await _actions?.action(widget.sid, action) ?? true;
      if (mounted) {
        showToastBadge(
          context,
          message: !did
              ? 'Sesi sedang tidak bekerja, jadi tidak ada yang dihentikan.'
              : action == 'esc'
              ? 'Esc dikirim'
              : action == 'stop-all'
              ? 'Semua dihentikan'
              : 'Meminta ringkasan',
          icon: Icons.check_rounded,
          color: GhinaColors.green,
          tag: 'kantor-chat',
        );
      }
    } catch (e) {
      if (mounted) _err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) => _onEvent(next.value));
    ref.listen(kantorUploadsProvider, _onUploads);
    ref.listen(dictationControllerProvider, _dictation.onChange);
    final dictating = ref.watch(dictationControllerProvider).isActive;
    final view = ref.watch(chatViewPrefsProvider);
    final api = ref.watch(kantorApiProvider);
    final outbox = [
      for (final j in ref.watch(kantorUploadsProvider))
        if (j.sid == widget.sid) j,
    ];
    return ChatScope(
      scale: view.scale,
      child: ListenableBuilder(
      listenable: widget.feed,
      builder: (context, _) {
        final can = _canSend;
        final perms = [
          for (final i in widget.feed.inbox)
            if (i['sid'] == widget.sid) i,
        ];
        return Column(
          children: [
            Expanded(child: _list(context, api, outbox, view)),
            if (perms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.md,
                  GhinaSpace.sm,
                  GhinaSpace.md,
                  0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final p in perms)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: GhinaSpace.sm,
                            ),
                            child: KantorPermissionCard(
                              item: p,
                              who: sessionName(widget.feed, _sess),
                              onDecide: (b) async {
                                try {
                                  await _actions?.decide('${p['id']}', b);
                                } catch (e) {
                                  if (mounted) _err(e);
                                }
                              },
                              onSubmit: (answers) async {
                                try {
                                  await _actions?.submitAsk(
                                    '${p['id']}',
                                    answers,
                                  );
                                  _bumpLoad();
                                } catch (e) {
                                  if (mounted) _err(e);
                                }
                              },
                              onAnswer: (n) async {
                                try {
                                  await _actions?.answerAsk(p, n);
                                  _bumpLoad();
                                } catch (e) {
                                  if (mounted) _err(e);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ChatSubagentsPanel(subs: asJsonList(_sess['subs'])),
            _StatusLine(feed: widget.feed, sess: _sess),
            _Quick(
              scale: view.scale,
              enabled: can,
              onSay: _say,
              onEsc: () => _act('esc'),
              onCompact: () => _act('compact'),
            ),
            if (dictating)
              DictationBar(
                onStop: _dictation.stop,
                onCancel: _dictation.cancel,
              ),
            Container(
              padding: EdgeInsets.fromLTRB(
                GhinaSpace.md,
                GhinaSpace.xs,
                GhinaSpace.md,
                GhinaSpace.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const ValueKey('kantor-attach'),
                    tooltip: 'Kirim foto, video, atau file',
                    onPressed: _canAttach ? _attach : null,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  GestureDetector(
                    onLongPressStart: can
                        ? (_) {
                            if (_dictation.active) return;
                            _holdMic = true;
                            HapticFeedback.lightImpact();
                            _dictation.start();
                          }
                        : null,
                    onLongPressEnd: can
                        ? (_) {
                            if (_holdMic) _dictation.stop();
                            _holdMic = false;
                          }
                        : null,
                    child: IconButton(
                      key: const ValueKey('kantor-mic'),
                      tooltip: dictating
                          ? 'Selesai dikte'
                          : 'Dikte (ketuk atau tahan)',
                      onPressed: can ? _dictation.toggle : null,
                      icon: Icon(
                        dictating
                            ? Icons.stop_circle_rounded
                            : Icons.mic_rounded,
                        color: dictating ? GhinaColors.blue.base : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ChunkyTextField(
                      controller: _input,
                      enabled: can,
                      hint: can
                          ? 'Pesan untuk ${sessionName(widget.feed, _sess)}'
                          : _sess['status'] == 'ended'
                          ? 'Sesi sudah selesai'
                          : 'Tidak bisa mengetik ke sesi ini dari sini',
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(width: GhinaSpace.sm),
                  ChunkyIconButton(
                    icon: Icons.send_rounded,
                    tooltip: 'Kirim',
                    color: can ? GhinaColors.green : GhinaColors.gray,
                    onPressed: can && !_sending
                        ? () => _say(_input.text)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
    );
  }

  // Pinch: tracked by hand from raw pointers, so no gesture competes with the
  // list's scroll. Two fingers down freezes the scroll and scales the text.
  final _pointers = <int, Offset>{};
  double? _pinchFrom;
  double _pinchScale = 1;
  bool _pinching = false;

  double? get _span {
    if (_pointers.length != 2) return null;
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _pinchDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    final span = _span;
    if (span != null && span > 0) {
      _pinchFrom = span;
      _pinchScale = ref.read(chatViewPrefsProvider).scale;
      setState(() => _pinching = true);
    }
  }

  void _pinchMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final span = _span;
    final from = _pinchFrom;
    if (span == null || from == null) return;
    ref
        .read(chatViewPrefsProvider.notifier)
        .setScale(_pinchScale * span / from, save: false);
  }

  void _pinchEnd(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    if (_pinchFrom != null) {
      _pinchFrom = null;
      ref.read(chatViewPrefsProvider.notifier).commit();
    }
    if (_pinching && _pointers.length < 2) setState(() => _pinching = false);
  }

  Widget _list(
    BuildContext context,
    KantorApi? api,
    List<UploadJob> outbox,
    ChatViewPrefs view,
  ) {
    final transcript = _entries;
    if (transcript == null) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(GhinaSpace.page),
            child: Text(
              '$_error',
              style: GhinaType.body.copyWith(
                color: context.ghina.textSecondary,
              ),
            ),
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(GhinaSpace.page),
        child: SkeletonList(count: 4),
      );
    }
    final entries = [
      for (final e in mergePratinjau(
        mergeAttachments(transcript, _atts),
        ref
                .watch(
                  kantorPratinjauSessionProvider((
                    widget.feed.officeId,
                    widget.sid,
                  )),
                )
                .value
                ?.items ??
            const [],
      ))
        if (!(view.tools == ChatToolMode.hidden && e is ToolsEntry)) e,
      for (final j in outbox) UploadEntry(j.id, ''),
    ];
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Belum ada percakapan di transcript.',
          style: GhinaType.body.copyWith(color: context.ghina.textMuted),
        ),
      );
    }
    final running =
        _sess['status'] == 'working' || _sess['status'] == 'waiting';
    // reversed list: the newest message stays in view without scroll juggling
    final rev = entries.reversed.toList();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pinchDown,
      onPointerMove: _pinchMove,
      onPointerUp: _pinchEnd,
      onPointerCancel: _pinchEnd,
      child: ListView.builder(
      key: const ValueKey('chat-list'),
      reverse: true,
      physics: _pinching ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(GhinaSpace.md),
      itemCount: rev.length,
      itemBuilder: (context, i) {
        final e = rev[i];
        final last = i == 0;
        return Padding(
          padding: EdgeInsets.only(bottom: GhinaSpace.sm * view.density.factor),
          child: switch (e) {
            UserEntry() => _Bubble(
              text: e.text,
              at: e.at,
              mine: true,
              view: view,
            ),
            ClaudeEntry() => _Bubble(
              text: e.text,
              at: e.at,
              mine: false,
              view: view,
            ),
            AttachmentEntry() => AttachmentBubble(
              key: ValueKey('a${e.item.id}'),
              item: e.item,
              api: api,
            ),
            UploadEntry() => _uploadRow(e.localId, outbox),
            PratinjauEntry() => PratinjauChatBubble(
              key: ValueKey('p${e.item.id}'),
              item: e.item,
              api: api,
            ),
            ImageEntry() => ChatImageBubble(
              key: ValueKey('i${e.image.path}${e.at}'),
              api: api,
              sid: widget.sid,
              image: e.image,
              big: view.bigImages,
            ),
            ToolsEntry() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.calls.isNotEmpty)
                  _ToolGroup(
                    key: ValueKey('g${e.at}${e.calls.length}'),
                    entry: e,
                    last: last,
                    running: running && last,
                    mode: view.tools,
                    codeScale: view.codeScale,
                    onImage: api == null
                        ? null
                        : (p) {
                            final img =
                                e.images
                                    .where((x) => x.path == p || x.name == p)
                                    .firstOrNull ??
                                (p.startsWith('/')
                                    ? ChatImage(
                                        src: 'view',
                                        path: p,
                                        name: p.split('/').last,
                                      )
                                    : null);
                            if (img != null) {
                              openChatImage(context, api, widget.sid, img);
                            }
                          },
                  ),
                ChatImageThumbs(api: api, sid: widget.sid, images: e.images),
              ],
            ),
          },
        );
      },
    ),
    );
  }

  Widget _uploadRow(String id, List<UploadJob> outbox) {
    final job = outbox.where((j) => j.id == id).firstOrNull;
    if (job == null) return const SizedBox.shrink();
    final uploads = ref.read(kantorUploadsProvider.notifier);
    return UploadBubble(
      job: job,
      onCancel: () => uploads.cancel(job.id),
      onRetry: () => uploads.retry(job.id),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.at,
    required this.mine,
    required this.view,
  });

  final String text;
  final String at;
  final bool mine;
  final ChatViewPrefs view;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final w = MediaQuery.sizeOf(context).width;
    final flat = !mine && view.flatClaude;
    final d = view.density.factor;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: flat ? double.infinity : w * view.bubbleWidth.fraction,
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              width: flat ? double.infinity : null,
              padding: EdgeInsets.symmetric(
                horizontal: flat ? 2 : GhinaSpace.md * (0.6 + 0.4 * d),
                vertical: GhinaSpace.sm * d,
              ),
              decoration: flat
                  ? null
                  : BoxDecoration(
                color: mine ? GhinaColors.blue.base : g.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(GhinaRadii.lg),
                  topRight: const Radius.circular(GhinaRadii.lg),
                  bottomLeft: Radius.circular(mine ? GhinaRadii.lg : 4),
                  bottomRight: Radius.circular(mine ? 4 : GhinaRadii.lg),
                ),
                border: mine ? null : Border.all(color: g.border, width: 2),
              ),
              child: mine
                  ? SelectableText(
                      text,
                      style: GhinaType.body.copyWith(
                        color: GhinaColors.blue.on,
                        height: view.lineHeight.value,
                      ),
                    )
                  : KantorMarkdown(
                      text,
                      selectable: true,
                      lineHeight: view.lineHeight.value,
                      codeScale: view.codeScale,
                      wrapCode: view.wrapCode,
                    ),
            ),
            if (view.showTime && hhmm(at).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  hhmm(at),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolGroup extends StatefulWidget {
  const _ToolGroup({
    super.key,
    required this.entry,
    required this.last,
    required this.running,
    this.mode = ChatToolMode.compact,
    this.codeScale = 1,
    this.onImage,
  });

  final ToolsEntry entry;
  final double codeScale;
  final void Function(String path)? onImage;
  final bool last;
  final bool running;
  final ChatToolMode mode;

  @override
  State<_ToolGroup> createState() => _ToolGroupState();
}

class _ToolGroupState extends State<_ToolGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final calls = widget.entry.calls;
    final fold =
        widget.mode == ChatToolMode.compact &&
        !widget.last &&
        calls.length > _toolFold;
    if (!fold || _open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fold) _foldHeader(g, calls),
          for (var i = 0; i < calls.length; i++)
            _ToolRow(
              call: calls[i],
              running: widget.running && i == calls.length - 1,
              codeScale: widget.codeScale,
              onImage: widget.onImage,
            ),
        ],
      );
    }
    return _foldHeader(g, calls);
  }

  Widget _foldHeader(GhinaTokens g, List<ToolCall> calls) {
    final cnt = <String, int>{};
    for (final c in calls) {
      cnt[c.shortName] = (cnt[c.shortName] ?? 0) + 1;
    }
    final sum = cnt.entries
        .map((e) => e.value > 1 ? '${e.key} x${e.value}' : e.key)
        .join(', ');
    return InkWell(
      borderRadius: GhinaRadii.rMd,
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              _open ? Icons.expand_less_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: g.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              '${calls.length} aksi',
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                clip(sum, 80),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatefulWidget {
  const _ToolRow({
    required this.call,
    required this.running,
    this.codeScale = 1,
    this.onImage,
  });

  final ToolCall call;
  final bool running;
  final double codeScale;
  final void Function(String path)? onImage;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = widget.call;
    final hasBody = c.label.length > 90 || c.resultText.isNotEmpty;
    final img = readImagePath(c);
    final status = c.done
        ? Icon(
            c.failed ? Icons.close_rounded : Icons.check_rounded,
            size: 16,
            color: c.failed ? GhinaColors.red.base : GhinaColors.green.base,
          )
        : Text(
            '...',
            style: GhinaType.bodyS.copyWith(
              color: widget.running ? GhinaColors.orange.base : g.textMuted,
            ),
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: GhinaRadii.rMd,
            onTap: img != null && widget.onImage != null
                ? () => widget.onImage!(img)
                : hasBody
                ? () => setState(() => _open = !_open)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GhinaSpace.sm,
                vertical: 7,
              ),
              child: Row(
                children: [
                  Text(
                    c.shortName,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clip(c.label.replaceAll('\n', ' '), 90),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS.copyWith(
                        color: g.textSecondary,
                        fontFamily: 'monospace',
                        fontSize: (GhinaType.bodyS.fontSize ?? 13) *
                            widget.codeScale,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  status,
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.sm,
                0,
                GhinaSpace.sm,
                GhinaSpace.sm,
              ),
              child: SelectableText(
                [
                  if (c.label.length > 90) c.label,
                  if (c.resultText.isNotEmpty) c.resultText,
                ].join('\n\n'),
                style: GhinaType.caption.copyWith(
                  color: g.textSecondary,
                  fontFamily: 'monospace',
                  fontSize: (GhinaType.caption.fontSize ?? 12) *
                      widget.codeScale,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.feed, required this.sess});

  final KantorOfficeFeed feed;
  final Json sess;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final status = '${sess['status'] ?? ''}';
    if (status.isEmpty) return const SizedBox.shrink();
    final n = sessionName(feed, sess);
    final subs = asJsonList(
      sess['subs'],
    ).where((x) => x['status'] != 'done').length;
    final tl = toolFull(sess['tool']);
    final String text;
    final Color dot;
    if (status == 'ended') {
      text = 'Sesi selesai';
      dot = g.textMuted;
    } else if (sess['waiting'] != null || status == 'waiting') {
      text = '$n menunggu izin';
      dot = GhinaColors.orange.base;
    } else if (sess['compacting'] == true) {
      text = '$n sedang meringkas percakapan';
      dot = GhinaColors.blue.base;
    } else if (status == 'working' || status == 'starting') {
      text =
          '$n sedang ${tl.isNotEmpty ? 'memakai ${clip(tl, 60)}' : 'berpikir'}';
      dot = GhinaColors.green.base;
    } else {
      text = '$n idle, menunggu pesanmu';
      dot = g.textMuted;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: 4,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$text${subs > 0 ? ' - $subs subagent jalan' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({
    required this.scale,
    required this.enabled,
    required this.onSay,
    required this.onEsc,
    required this.onCompact,
  });

  final double scale;
  final bool enabled;
  final void Function(String) onSay;
  final VoidCallback onEsc;
  final VoidCallback onCompact;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, VoidCallback f, {bool halt = false}) => Padding(
      padding: const EdgeInsets.only(right: GhinaSpace.sm),
      child: ChunkyButton(
        label: label,
        size: ChunkyButtonSize.small,
        uppercase: false,
        variant: halt
            ? ChunkyButtonVariant.danger
            : ChunkyButtonVariant.outline,
        onPressed: enabled ? f : null,
      ),
    );
    return SizedBox(
      // the chips grow with the chat text
      height: 48 * (scale > 1 ? scale : 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: GhinaSpace.md,
          vertical: 4,
        ),
        children: [
          chip('lanjut', () => onSay('lanjut')),
          chip('ya', () => onSay('ya')),
          chip('Hentikan', onEsc, halt: true),
          chip('/compact', onCompact),
        ],
      ),
    );
  }
}
