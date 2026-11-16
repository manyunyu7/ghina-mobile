import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import '../../notes/widgets/dictation_bar.dart';
import '../widgets/kantor_markdown.dart';
import 'attach_picker.dart';
import 'attachment_tray.dart';
import 'chat_look.dart';
import 'chat_look_paint.dart';
import 'chat_timeline.dart';
import 'compact_card.dart';
import 'compact_summary.dart';
import 'teammate_card.dart';
import 'teammate_message.dart';
import 'attachment_model.dart';
import 'attachment_uploader.dart';
import 'attachment_uploads.dart';
import 'attachment_views.dart';
import '../pratinjau/pratinjau_chat_bubble.dart';
import 'chat_dictation.dart';
import 'chat_context.dart';
import 'chat_images.dart';
import 'chat_subagents.dart';
import 'chat_model.dart';
import 'chat_view_prefs.dart';
import 'chat_style.dart';
import '../board/kantor_card_detail.dart';
import 'kantor_actions.dart';
import 'kantor_feed.dart';
import 'stop_choice.dart';
import 'permission_card.dart';

/// Fallback only: new lines normally arrive through the daemon's `transcript`
/// event on /ws. The poll covers a dropped or reconnecting socket.
const _pollEvery = Duration(seconds: 15);
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

class _KantorChatTabState extends ConsumerState<KantorChatTab>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  late final KantorApi? _api;
  late final String _connection;
  late final KantorChatMemory _memory;
  late final ScrollController _scroll;
  late final String _openKey;

  bool get _active {
    if (!mounted) return false;
    final current = ref.read(kantorApiProvider);
    return current == null
        ? _api == null
        : kantorConnectionKey(current.config) == _connection;
  }

  void _saveDraft() => _memory.draft = _input.value;
  void _saveScroll() {
    if (_scroll.hasClients) _memory.scrollOffset = _scroll.offset;
  }

  Timer? _timer;
  Timer? _bump;
  List<ChatEntry>? _entries;
  Object? _error;
  Object? _size;

  /// Raw transcript items behind [_entries], the daemon's delta cursor, and
  /// the shared in-memory cache they are kept in between visits.
  late final KantorTranscriptCache _transcripts;
  late final KantorChatKey _chatKey;
  List<Map<String, dynamic>>? _raw;
  String? _cursor;

  /// False until the daemon answered once in this visit: the history may then
  /// come from the cache and the chat shows that it is still syncing.
  bool _synced = false;
  bool _syncFailed = false;
  DateTime? _syncedAt;
  bool _loading = false;
  bool _loadAgain = false;
  bool _sending = false;
  List<KantorAttachment> _atts = const [];
  bool _loadingAtts = false;
  bool _attsAgain = false;

  /// Files held in the tray until Kirim.
  List<StagedFile> _staged = const [];
  int _stageSeq = 0;

  /// Files from before the last /clear the daemon left out, and whether the
  /// owner asked to see them.
  int _oldN = 0;
  bool _showOld = false;
  late final ChatDictation _dictation = ChatDictation(
    ref: ref,
    context: () => context,
    text: _input,
  );
  bool _holdMic = false;

  KantorActions? get _actions {
    return !_active || _api == null ? null : KantorActions(_api);
  }

  Json get _sess => widget.feed.session(widget.sid) ?? const {};

  @override
  void initState() {
    super.initState();
    _api = ref.read(kantorApiProvider);
    _connection = _api == null ? '' : kantorConnectionKey(_api.config);
    _chatKey = (
      connection: _connection,
      office: widget.feed.officeId,
      sid: widget.sid,
    );
    _memory = ref
        .read(kantorChatMemoryProvider)
        .putIfAbsent(_chatKey, KantorChatMemory.new);
    _transcripts = ref.read(kantorTranscriptCacheProvider);
    final held = _transcripts.get(_chatKey);
    if (held != null) {
      // history only grows, so it can show at once; the delta follows below
      _raw = held.items;
      _cursor = held.cursor;
      _size = held.size;
      _syncedAt = held.at;
      _entries = buildChat(held.items);
    }
    _input.value = _memory.draft;
    _input.addListener(_saveDraft);
    _scroll = ScrollController(initialScrollOffset: _memory.scrollOffset)
      ..addListener(_saveScroll);
    _openKey = kantorOpenChatKey(_connection, widget.feed.officeId, widget.sid);
    kantorOpenChats[_openKey] = (kantorOpenChats[_openKey] ?? 0) + 1;
    _load();
    _loadAtts();
    _timer = Timer.periodic(_pollEvery, (_) => _load());
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _bump?.cancel();
    widget.feed.removeListener(_onFeed);
    _dictation.dispose();
    // Draf dan scroll sudah disimpan oleh listener di setiap perubahan. Tidak
    // disimpan ulang di sini: di layar lebar chat yang sama bisa terbuka dua
    // kali (panel kanan di bawah + halaman penuh di atas), dan yang dibuang
    // belakangan tidak boleh menimpa draf terbaru dengan isinya yang basi.
    _scroll.dispose();
    final open = (kantorOpenChats[_openKey] ?? 1) - 1;
    if (open <= 0) {
      kantorOpenChats.remove(_openKey);
    } else {
      kantorOpenChats[_openKey] = open;
    }
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (!_active || api == null) return;
    if (_loading) {
      _loadAgain = true; // an event arrived mid-fetch: fetch once more after
      return;
    }
    _loading = true;
    try {
      final data = asJson(
        await api.get(
          '/api/sessions/${widget.sid}/transcript',
          query: {'n': 200, 'delta': 1, 'after': ?_cursor},
        ),
      );
      if (!_active) return;
      final wasSynced = _synced && !_syncFailed;
      _synced = true;
      _syncFailed = false;
      _syncedAt = DateTime.now();
      // daemons without delta support: unchanged size means nothing new
      final same =
          data['cursor'] == null &&
          data['size'] != null &&
          data['size'] == _size &&
          _entries != null;
      final merged = same ? null : mergeTranscript(_raw, data);
      if (merged != null) {
        _raw = merged.items;
        _cursor = merged.cursor;
      }
      _size = data['size'];
      final raw = _raw;
      if (raw != null) {
        _transcripts.put(
          _chatKey,
          KantorTranscriptSnap(
            items: raw,
            cursor: _cursor,
            size: _size,
            at: _syncedAt!,
          ),
        );
      }
      if (merged == null || (!merged.changed && _entries != null)) {
        if (!wasSynced) setState(() => _error = null); // drop the sync badge
        return;
      }
      _loadAtts();
      setState(() {
        _entries = buildChat(merged.items);
        _error = null;
      });
    } catch (e) {
      if (!_active) return;
      if (_entries == null) {
        setState(() => _error = e);
      } else if (!_syncFailed) {
        setState(() => _syncFailed = true);
      }
    } finally {
      _loading = false;
      if (_loadAgain) {
        _loadAgain = false;
        unawaited(_load());
      }
    }
  }

  /// Attachments are optional for the daemon (older builds answer 404): a
  /// failure just leaves the list as it was.
  Future<void> _loadAtts() async {
    final api = _api;
    if (!_active || api == null) return;
    if (_loadingAtts) {
      _attsAgain = true; // asked meanwhile (e.g. "show older files"): run again
      return;
    }
    _loadingAtts = true;
    try {
      final data = await api.get(
        '/api/sessions/${widget.sid}/attachments',
        query: _showOld ? {'all': 1} : null,
      );
      final list = parseAttachments(data);
      final hidden = _showOld ? 0 : hiddenBeforeClear(data);
      if (_active && (!_sameAtts(list) || hidden != _oldN)) {
        setState(() {
          _atts = list;
          _oldN = hidden;
        });
      }
    } catch (_) {
      // keep what we have
    } finally {
      _loadingAtts = false;
      if (_attsAgain) {
        _attsAgain = false;
        unawaited(_loadAtts());
      }
    }
  }

  bool _sameAtts(List<KantorAttachment> n) =>
      n.length == _atts.length &&
      [
        for (var i = 0; i < n.length; i++)
          n[i].id == _atts[i].id &&
              n[i].processing == _atts[i].processing &&
              n[i].delivered == _atts[i].delivered &&
              n[i].message == _atts[i].message &&
              n[i].note == _atts[i].note,
      ].every((x) => x);

  /// No fetching while the app is in the background or the screen is off;
  /// coming back fetches the delta at once and restarts the fallback poll.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timer?.cancel();
      _timer = Timer.periodic(_pollEvery, (_) => _load());
      _load();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
      _bump?.cancel();
    }
  }

  void _onEvent(Json? msg) {
    if (_active &&
        msg != null &&
        msg['t'] == 'transcript' &&
        msg['sid'] == widget.sid) {
      _bumpLoad(150); // the daemon says this transcript grew: fetch the delta
      return;
    }
    if (!_active ||
        msg == null ||
        msg['t'] != 'attachment' ||
        msg['sid'] != widget.sid)
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
          j.connection == _connection &&
          j.status == UploadStatus.done &&
          was[j.id] != UploadStatus.done,
    );
    if (landed) _loadAtts();
  }

  bool get _canAttach => _active && _sess['status'] != 'ended';

  Future<void> _attach() async {
    final choice = await showAttachSheet(context);
    if (choice == null || !_active) return;
    List<PickedAttachment> picked;
    try {
      picked = await pickAttachments(choice);
    } catch (e) {
      if (_active) _err('Tidak bisa mengambil berkas.');
      return;
    }
    if (picked.isEmpty || !_active) return;
    _stage(picked);
  }

  /// Files only wait in the tray; nothing is sent until Kirim.
  void _stage(List<PickedAttachment> picked) {
    final room = maxStagedFiles - _staged.length;
    if (picked.length > room) {
      _err('Maksimal $maxStagedFiles file sekali kirim.');
    }
    if (room <= 0) return;
    setState(
      () => _staged = [
        ..._staged,
        for (final f in picked.take(room)) StagedFile('f${_stageSeq++}', f),
      ],
    );
    HapticFeedback.selectionClick();
  }

  void _unstage(StagedFile f) => setState(
    () => _staged = [
      for (final x in _staged)
        if (x != f) x,
    ],
  );

  /// Uploads every file held in the tray (held on the daemon), then hands them
  /// all to the agent in ONE message together with the text of the field.
  Future<void> _sendStaged() async {
    if (!_active || _sending) return;
    final api = _api;
    if (api == null) return;
    if (_dictation.active) await _dictation.stop();
    if (!_active) return;
    final batch = _staged;
    final text = _input.text.trim();
    final who = sessionName(widget.feed, _sess);
    final uploads = ref.read(kantorUploadsProvider.notifier);
    setState(() {
      _staged = const [];
      _sending = true;
    });
    _input.clear();
    try {
      final r = await uploads.sendBatch(
        sid: widget.sid,
        connection: _connection,
        office: widget.feed.officeId,
        agent: who,
        files: [for (final f in batch) f.file],
        text: text,
      );
      if (!_active) return;
      if (r.sent == 0) {
        // nothing arrived: the words still go, like a plain message
        if (text.isNotEmpty) await _actions?.sendText(widget.sid, text);
      } else if (!r.delivered) {
        _err('File sudah terunggah, tapi belum sampai ke agen.');
      }
      if (r.failed > 0 && r.sent > 0) {
        _err('${r.failed} file gagal diunggah dan tidak ikut terkirim.');
      }
      _loadAtts();
      _bumpLoad(1200);
    } catch (e) {
      if (_active) {
        // could not even start: put everything back
        if (_input.text.isEmpty) _input.text = text;
        setState(() => _staged = [...batch, ..._staged]);
        _err('Gagal menyiapkan file: ${uploadErrorText(e)}');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Kirim: the tray first when it holds files, else just the text.
  void _send() => _staged.isNotEmpty ? _sendStaged() : _say(_input.text);

  bool get _canSend {
    final s = _sess;
    if (!_active) return false;
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
    if (!_active) return;
    // sending mid-dictation takes the last words along
    final fromField = text == _input.text;
    if (_dictation.active) await _dictation.stop();
    if (!_active) return;
    if (fromField) text = _input.text;
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final actions = _actions;
      if (actions == null) return;
      await actions.sendText(widget.sid, t);
      if (!_active) {
        if (_memory.draft.text == text) _memory.draft = TextEditingValue.empty;
        return;
      }
      if (text == _input.text) _input.clear();
      HapticFeedback.selectionClick();
      _bumpLoad(1200);
    } catch (e) {
      if (_active) _err(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _act(String action) async {
    if (!_active) return;
    if (action == 'esc') {
      final pick = await askStopMode(context, _sess);
      if (pick == null || !_active) return;
      action = pick;
    }
    try {
      final did = await _actions?.action(widget.sid, action) ?? true;
      if (mounted && _active) {
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
      if (_active) _err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) => _onEvent(next.value));
    ref.listen(kantorUploadsProvider, _onUploads);
    ref.listen(dictationControllerProvider, _dictation.onChange);
    final dictating = ref.watch(dictationControllerProvider).isActive;
    final view = ref.watch(chatViewPrefsProvider);
    ref.watch(kantorApiProvider);
    final api = _api;
    final outbox = [
      for (final j in ref.watch(kantorUploadsProvider))
        if (j.sid == widget.sid &&
            j.connection == _connection &&
            (j.office.isEmpty || j.office == widget.feed.officeId))
          j,
    ];
    return ChatScope(
      scale: view.scale,
      child: MessengerWallpaper(
        view: view,
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
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _pinchDown,
                    onPointerMove: _pinchMove,
                    onPointerUp: _pinchEnd,
                    onPointerCancel: _pinchEnd,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _list(context, api, outbox, view),
                        ),
                        if (_entries != null && (!_synced || _syncFailed))
                          Positioned(
                            top: GhinaSpace.sm,
                            left: GhinaSpace.md,
                            right: GhinaSpace.md,
                            child: Center(child: _syncBadge(context)),
                          ),
                      ],
                    ),
                  ),
                ),
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
                                  style: view.style,
                                  item: p,
                                  who: sessionName(widget.feed, _sess),
                                  onDismiss: () async {
                                    try {
                                      await _actions?.dismiss('${p['id']}');
                                    } catch (e) {
                                      if (_active) _err(e);
                                    }
                                  },
                                  onDecide: (b) async {
                                    try {
                                      await _actions?.decide('${p['id']}', b);
                                    } catch (e) {
                                      if (_active) _err(e);
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
                                      if (_active) _err(e);
                                    }
                                  },
                                  onAnswer: (n) async {
                                    try {
                                      await _actions?.answerAsk(p, n);
                                      _bumpLoad();
                                    } catch (e) {
                                      if (_active) _err(e);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _Glass(
                  on: view.hasWall,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChatSubagentsPanel(subs: asJsonList(_sess['subs'])),
                      if (!view.messenger)
                        _StatusLine(feed: widget.feed, sess: _sess),
                      _Quick(
                        scale: view.scale,
                        shape: view.bubble,
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
                      AttachmentTray(items: _staged, onRemove: _unstage),
                      if (view.messenger)
                        _messengerComposer(view, can, dictating)
                      else
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
                                    color: dictating
                                        ? GhinaColors.blue.base
                                        : null,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _ThemedField(
                                  shape: view.bubble,
                                  me: view.me,
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
                              ),
                              const SizedBox(width: GhinaSpace.sm),
                              ChunkyIconButton(
                                icon: Icons.send_rounded,
                                tooltip: 'Kirim',
                                color: can
                                    ? _meSwatch(view.me)
                                    : GhinaColors.gray,
                                onPressed: can && !_sending ? _send : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _messengerComposer(ChatViewPrefs view, bool can, bool dictating) {
    final c = ChatStyleColors.of(context, view.style);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _input,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty || _staged.isNotEmpty;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const ValueKey('kantor-attach'),
                        tooltip: 'Kirim foto, video, atau file',
                        onPressed: _canAttach ? _attach : null,
                        icon: Icon(Icons.attach_file_rounded, color: c.muted),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('messenger-input'),
                          controller: _input,
                          enabled: can,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          style: GhinaType.body.copyWith(color: c.ink),
                          decoration: InputDecoration(
                            hintText: can
                                ? 'Pesan ke ${sessionName(widget.feed, _sess)}, atau / untuk perintah'
                                : 'Sesi tidak bisa dikirimi pesan',
                            hintStyle: GhinaType.body.copyWith(color: c.muted),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 2,
                            ),
                          ),
                        ),
                      ),
                      if (hasText)
                        IconButton(
                          key: const ValueKey('kantor-mic'),
                          tooltip: dictating ? 'Selesai dikte' : 'Dikte',
                          onPressed: can ? _dictation.toggle : null,
                          icon: Icon(
                            dictating ? Icons.stop_circle : Icons.mic_none,
                            color: c.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: ValueKey(hasText ? 'messenger-send' : 'kantor-mic'),
                style: IconButton.styleFrom(
                  backgroundColor: c.send,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(44, 44),
                ),
                tooltip: hasText
                    ? 'Kirim'
                    : dictating
                    ? 'Selesai dikte'
                    : 'Dikte',
                onPressed: can && !_sending
                    ? (hasText ? _send : _dictation.toggle)
                    : null,
                icon: Icon(
                  hasText
                      ? Icons.send_rounded
                      : dictating
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  size: 20,
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

  /// Shown over a history that came from the in-memory cache until the
  /// daemon confirms it, or that could not be refreshed.
  Widget _syncBadge(BuildContext context) {
    final g = context.ghina;
    final at = _syncedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final label = _syncFailed
        ? 'Belum tersinkron${at == null ? '' : ' · terakhir ${two(at.hour)}:${two(at.minute)}'}'
        : 'Menyinkronkan…';
    return Container(
      key: const ValueKey('chat-sync-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: g.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: g.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_syncFailed)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          else
            Icon(Icons.cloud_off_outlined, size: 12, color: g.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    KantorApi? api,
    List<UploadJob> outbox,
    ChatViewPrefs view,
  ) {
    if (!_active) return const SizedBox.shrink();
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
        mergeAttachments(hideBatchMessages(transcript, _atts), _atts),
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
        child: _Backed(
          on: view.hasWall,
          child: Padding(
            padding: const EdgeInsets.all(GhinaSpace.sm),
            child: Text(
              'Belum ada percakapan di transcript.',
              style: GhinaType.body.copyWith(color: context.ghina.textMuted),
            ),
          ),
        ),
      );
    }
    final running =
        _sess['status'] == 'working' || _sess['status'] == 'waiting';
    // reversed list: the newest message stays in view without scroll juggling
    final rev = entries.reversed.toList();
    return ListView.builder(
      key: const ValueKey('chat-list'),
      controller: _scroll,
      reverse: true,
      physics: _pinching ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(GhinaSpace.md),
      itemCount: rev.length + (_oldN > 0 ? 1 : 0),
      itemBuilder: (context, i) {
        // the oldest end of the chat is the last item of the reversed list
        if (i == rev.length) return _oldFiles(view);
        final e = rev[i];
        final last = i == 0;
        final row = Padding(
          padding: EdgeInsets.only(bottom: GhinaSpace.sm * view.density.factor),
          child: switch (e) {
            UserEntry() => _userRow(e, view),
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
            ToolsEntry() => _Backed(
              on: view.hasWall,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.calls.isNotEmpty)
                    _ToolGroup(
                      style: view.style,
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
                  ChatImageThumbs(
                    api: api,
                    sid: widget.sid,
                    // Messenger look: pictures the agent only looked at stay
                    // behind the folded tool line (open it to see them).
                    images: view.messenger && view.tools == ChatToolMode.compact
                        ? [
                            for (final x in e.images)
                              if (x.src != 'view') x,
                          ]
                        : e.images,
                  ),
                ],
              ),
            ),
          },
        );
        final date = DateTime.tryParse(e.at)?.toLocal();
        final older = i + 1 < rev.length
            ? DateTime.tryParse(rev[i + 1].at)?.toLocal()
            : null;
        if (!view.messenger) return row;
        final card = asJson(asJson(_sess['konteks'])['card']);
        return Column(
          children: [
            if (date != null && !DateUtils.isSameDay(date, older))
              MessengerDay(at: date),
            row,
            if (i == 0 && card['title'] != null)
              MessengerBoardCard(
                card: card,
                style: view.style,
                onTap: card['id'] == null
                    ? null
                    : () => openKantorCard(
                        context,
                        officeId: widget.feed.officeId,
                        cardId: '${card['id']}',
                      ),
              ),
          ],
        );
      },
    );
  }

  /// A prompt of the owner. A message from another Claude session shows as a
  /// card on the left; words the owner typed around it stay a normal bubble.
  Widget _userRow(UserEntry e, ChatViewPrefs view) {
    final cs = compactSummary(e.text);
    if (cs != null) {
      final pasted = !e.text.trimLeft().startsWith('This session is being');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cs.rest.isNotEmpty) ...[
            _Bubble(text: cs.rest, at: e.at, mine: true, view: view),
            const SizedBox(height: GhinaSpace.sm),
          ],
          CompactCard(msg: cs, at: e.at, view: view, pasted: pasted),
        ],
      );
    }
    final tm = teammateMsgs(e.text);
    if (tm == null) {
      return _Bubble(text: e.text, at: e.at, mine: true, view: view);
    }
    final rest = teammateRest(e.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tm.length; i++) ...[
          if (i > 0) const SizedBox(height: GhinaSpace.sm),
          TeammateCard(msg: tm[i], at: e.at, view: view),
        ],
        if (rest.isNotEmpty) ...[
          const SizedBox(height: GhinaSpace.sm),
          _Bubble(text: rest, at: e.at, mine: true, view: view),
        ],
      ],
    );
  }

  /// "Tampilkan N berkas dari sebelum /clear": the daemon hides them until asked.
  Widget _oldFiles(ChatViewPrefs view) => Center(
    child: Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyButton(
        key: const ValueKey('chat-old-files'),
        label: 'Tampilkan $_oldN berkas dari sebelum /clear',
        size: ChunkyButtonSize.small,
        uppercase: false,
        expand: false,
        variant: ChunkyButtonVariant.outline,
        onPressed: () {
          _showOld = true;
          _loadAtts();
        },
      ),
    ),
  );

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
    if (view.messenger && (mine || !view.flatClaude)) {
      final c = ChatStyleColors.of(context, view.style);
      final body = mine
          ? SelectableText(
              text,
              style: GhinaType.body.copyWith(
                color: view.useStyleMe ? c.ink : view.me.ink,
                height: view.lineHeight.value,
              ),
            )
          : KantorMarkdown(
              text,
              selectable: true,
              lineHeight: view.lineHeight.value,
              codeScale: view.codeScale,
              wrapCode: view.wrapCode,
            );
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: kantorBubbleMaxWidth(
              MediaQuery.sizeOf(context).width,
              view.bubbleWidth.fraction,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: mine && view.peek != ChatPeek.none ? 16 : 0,
            ),
            child: !mine && view.flatClaude
                ? body
                : MessengerBubble(
                    view: view,
                    mine: mine,
                    time: hhmm(at),
                    child: body,
                  ),
          ),
        ),
      );
    }
    final w = MediaQuery.sizeOf(context).width;
    final flat = !mine && view.flatClaude;
    final d = view.density.factor;
    final peeking = mine && view.peek != ChatPeek.none;
    final pad = EdgeInsets.symmetric(
      horizontal: flat ? 2 : GhinaSpace.md * (0.6 + 0.4 * d),
      vertical: GhinaSpace.sm * d,
    );
    final body = mine
        ? SelectableText(
            text,
            style: GhinaType.body.copyWith(
              color: view.me.ink,
              height: view.lineHeight.value,
            ),
          )
        : KantorMarkdown(
            text,
            selectable: true,
            lineHeight: view.lineHeight.value,
            codeScale: view.codeScale,
            wrapCode: view.wrapCode,
          );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: flat
              ? double.infinity
              : kantorBubbleMaxWidth(w, view.bubbleWidth.fraction),
        ),
        child: Padding(
          // room for the mascot sitting on the bubble
          padding: EdgeInsets.only(top: peeking ? 16 : 0),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (flat)
                Container(width: double.infinity, padding: pad, child: body)
              else
                ThemedBubble(
                  shape: view.bubble,
                  mine: mine,
                  me: view.me,
                  peek: view.peek,
                  padding: pad,
                  child: body,
                ),
              if (view.showTime && hhmm(at).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: _Backed(
                    on: view.hasWall,
                    radius: 6,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: view.hasWall ? 6 : 0,
                        vertical: view.hasWall ? 1 : 0,
                      ),
                      child: Text(
                        hhmm(at),
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin backing for loose text that sits right on a wallpaper (time, tool
/// rows, empty note) so it stays readable. Nothing without a wallpaper.
class _Backed extends StatelessWidget {
  const _Backed({required this.on, required this.child, this.radius = 10});

  final bool on;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.ghina.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// The bottom bar (status, quick buttons, message field): over a wallpaper it
/// becomes a thin frosted layer so the wallpaper shows through.
class _Glass extends StatelessWidget {
  const _Glass({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    final g = context.ghina;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: g.surface.withValues(alpha: 0.74),
            border: Border(
              top: BorderSide(color: g.border.withValues(alpha: 0.6)),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The message field in the corner shape of the chosen bubble, with the
/// owner's color on its focus ring.
class _ThemedField extends StatelessWidget {
  const _ThemedField({
    required this.shape,
    required this.me,
    required this.child,
  });

  final ChatBubbleShape shape;
  final ChatMeColor me;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = context.ghina;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(shape.fieldRadius),
      borderSide: BorderSide(
        color: c,
        width: 2,
        style: shape == ChatBubbleShape.awan
            ? BorderStyle.none
            : BorderStyle.solid,
      ),
    );
    final base = theme.inputDecorationTheme;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: base.copyWith(
          border: border(g.border),
          enabledBorder: border(g.border),
          focusedBorder: border(me.solid),
          disabledBorder: border(g.border.withValues(alpha: 0.5)),
        ),
      ),
      child: child,
    );
  }
}

/// The owner's color as a button swatch (a gradient falls back to its middle
/// color, buttons cannot paint one).
ChunkySwatch _meSwatch(ChatMeColor me) => ChunkySwatch(
  base: me.solid,
  edge: Color.lerp(me.solid, Colors.black, 0.38)!,
  light: Color.alphaBlend(me.solid.withValues(alpha: 0.16), Colors.white),
  on: me.ink,
);

class _ToolGroup extends StatefulWidget {
  const _ToolGroup({
    super.key,
    required this.entry,
    required this.last,
    required this.running,
    this.mode = ChatToolMode.compact,
    this.style = ChatStyle.bawaan,
    this.codeScale = 1,
    this.onImage,
  });

  final ToolsEntry entry;
  final ChatStyle style;
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
    if (widget.style != ChatStyle.bawaan &&
        !_open &&
        widget.mode == ChatToolMode.compact) {
      final c = ChatStyleColors.of(context, widget.style);
      final muted = c.wa && !c.dark ? const Color(0xFF667781) : c.muted;
      final n = calls.length;
      final text = widget.running
          ? 'sedang bekerja · $n langkah'
          : '$n langkah · ${toolSummary(calls)}';
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          key: ValueKey('tool-line-${widget.entry.at}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.running)
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: muted,
                    ),
                  )
                else
                  Icon(Icons.check_rounded, size: 13, color: muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(
                      color: muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 14, color: muted),
              ],
            ),
          ),
        ),
      );
    }
    final fold =
        widget.mode == ChatToolMode.compact &&
        !widget.last &&
        calls.length > _toolFold;
    if (!fold || _open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fold || widget.style != ChatStyle.bawaan) _foldHeader(g, calls),
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
                        fontSize:
                            (GhinaType.bodyS.fontSize ?? 13) * widget.codeScale,
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
                  fontSize:
                      (GhinaType.caption.fontSize ?? 12) * widget.codeScale,
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
    required this.shape,
    required this.enabled,
    required this.onSay,
    required this.onEsc,
    required this.onCompact,
  });

  final double scale;
  final ChatBubbleShape shape;
  final bool enabled;
  final void Function(String) onSay;
  final VoidCallback onEsc;
  final VoidCallback onCompact;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget chip(String label, VoidCallback f, {bool halt = false}) {
      final radius = BorderRadius.circular(shape.fieldRadius + 6);
      final fg = !enabled
          ? g.onDisabled
          : halt
          ? Colors.white
          : g.textSecondary;
      return Padding(
        padding: const EdgeInsets.only(right: GhinaSpace.sm),
        child: Material(
          color: !enabled
              ? g.disabled
              : halt
              ? GhinaColors.red.base
              : g.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: !enabled
                  ? g.disabledEdge
                  : halt
                  ? GhinaColors.red.edge
                  : g.border,
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? f : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                label,
                style: GhinaType.bodyS.w(800).copyWith(color: fg),
              ),
            ),
          ),
        ),
      );
    }

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

/// "menjalankan perintah, membaca file": what a run of tool calls did, in
/// words, the two most frequent kinds first.
String toolSummary(List<ToolCall> calls) {
  String kind(ToolCall c) {
    final n = c.name;
    if (n == 'Bash') return 'menjalankan perintah';
    if (n == 'Read') return 'membaca file';
    if (n == 'Edit' ||
        n == 'Write' ||
        n == 'MultiEdit' ||
        n == 'NotebookEdit') {
      return 'mengubah file';
    }
    if (n == 'Grep' || n == 'Glob') return 'mencari di kode';
    if (n == 'WebFetch' || n == 'WebSearch') return 'mencari di web';
    if (n == 'Agent' || n == 'Task') return 'memakai subagent';
    if (n == 'AskUserQuestion') return 'bertanya';
    if (n == 'ToolSearch') return 'menyiapkan alat';
    if (n.startsWith('mcp__kantor')) return 'memakai alat kantor';
    if (n.startsWith('mcp__mobile')) return 'mengoperasikan HP';
    if (n.startsWith('mcp__claude-in-chrome')) return 'memakai browser';
    if (n.startsWith('mcp__')) return 'memakai ${c.shortName}';
    return n;
  }

  final cnt = <String, int>{};
  for (final c in calls) {
    final k = kind(c);
    cnt[k] = (cnt[k] ?? 0) + 1;
  }
  final top = cnt.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final words = top.take(2).map((e) => e.key).toList();
  return top.length > 2 ? '${words.join(', ')}, …' : words.join(', ');
}
