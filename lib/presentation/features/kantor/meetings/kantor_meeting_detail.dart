import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import 'kantor_meeting.dart';

const _ownerLook = {
  'color': '#55606E',
  'hair': '#2B1D14',
  'skin': '#F1C9A5',
  'tie': true,
};

/// A meeting: live conversation, minutes, and resume / continue.
class KantorMeetingDetailScreen extends ConsumerStatefulWidget {
  const KantorMeetingDetailScreen({
    super.key,
    required this.officeId,
    required this.meetingId,
  });

  final String officeId;
  final String meetingId;

  @override
  ConsumerState<KantorMeetingDetailScreen> createState() =>
      _MeetingDetailState();
}

class _MeetingDetailState extends ConsumerState<KantorMeetingDetailScreen> {
  final _scroll = ScrollController();
  final _say = TextEditingController();
  final _note = TextEditingController();
  KantorMeeting? _m;
  Object? _error;
  int _moreRounds = 1;
  bool _busy = false;

  String get _base =>
      '/api/offices/${Uri.encodeComponent(widget.officeId)}/meetings/${Uri.encodeComponent(widget.meetingId)}';

  @override
  void initState() {
    super.initState();
    _load(jump: true);
    ref.listenManual(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e == null || (e['office'] != widget.officeId && e['office'] != '*'))
        return;
      if (e['t'] == 'meeting-msg' && e['meetingId'] == widget.meetingId) {
        _onMessage((e['msg'] as Map).cast<String, dynamic>());
      } else if (e['t'] == 'meeting-typing' &&
          e['meeting'] == widget.meetingId) {
        _onTyping(e);
      } else if (e['t'] == 'changed' && e['what'] == 'meetings') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _say.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _nearBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.offset < 160;

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _load({bool jump = false}) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final stick = jump || _nearBottom;
      final j = await api.get(_base);
      if (!mounted) return;
      setState(() {
        _m = KantorMeeting.fromJson((j as Map).cast<String, dynamic>());
        _error = null;
      });
      if (stick) _toBottom();
    } catch (e) {
      if (mounted && _m == null) setState(() => _error = e);
    }
  }

  void _onMessage(Map<String, dynamic> raw) {
    final m = _m;
    if (m == null) return;
    final msg = KantorMeetingMessage.fromJson(raw);
    if (m.messages.any((x) => x.id == msg.id)) return;
    final stick = _nearBottom;
    setState(() {
      m.messages.add(msg);
      m.cost += msg.cost;
      // the speaker's live bubble becomes this saved message in the same frame
      if (msg.kind == 'bicara' &&
          m.typing?.who.toLowerCase() == msg.who.toLowerCase()) {
        m.typing = null;
      }
    });
    if (stick) _toBottom();
  }

  void _onTyping(Map<String, dynamic> e) {
    final m = _m;
    if (m == null || !m.running) return;
    final stick = _nearBottom;
    setState(() {
      m.typing = e['done'] == true ? null : KantorMeetingTyping.fromJson(e);
    });
    if (stick) _toBottom();
  }

  Future<void> _post(
    String path,
    Object body, {
    String? ok,
    bool reload = true,
  }) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final done = await kantorGuard(context, () async => api.post(path, body));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) return;
    if (ok != null) kantorToast(context, ok);
    if (reload) await _load(jump: true);
  }

  Future<void> _sendSay() async {
    final text = _say.text.trim();
    if (text.isEmpty) return;
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final done = await kantorGuard(
      context,
      () async => api.post('$_base/say', {'text': text}),
    );
    if (done) _say.clear();
  }

  Future<void> _cancel() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Bubarkan rapat?',
      message:
          'Giliran yang sedang jalan dihentikan. Percakapan sejauh ini tetap tersimpan.',
      confirmLabel: 'Bubarkan',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _post(
      '/api/offices/${Uri.encodeComponent(widget.officeId)}/meetings-cancel',
      {'id': widget.meetingId},
      ok: 'Rapat dibubarkan',
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = _m;
    final roles =
        ref.watch(kantorRolesProvider(widget.officeId)).value ??
        const <KantorRole>[];
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(m?.topic ?? 'Rapat', overflow: TextOverflow.ellipsis),
        actions: [
          if (m != null && m.running)
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('Bubarkan'),
            ),
        ],
      ),
      body: _error != null
          ? KantorErrorView(error: _error!, onRetry: () => _load(jump: true))
          : m == null
          ? const KantorLoading(count: 4)
          : Column(
              children: [
                Expanded(child: _content(context, m, roles)),
                if (m.running) _sayBar(context),
              ],
            ),
    );
  }

  KantorRole? _roleById(List<KantorRole> roles, String id) =>
      roles.where((r) => r.id == id).firstOrNull;
  KantorRole? _roleByName(List<KantorRole> roles, String name) => roles
      .where((r) => r.name.toLowerCase() == name.toLowerCase())
      .firstOrNull;

  Widget _content(
    BuildContext context,
    KantorMeeting m,
    List<KantorRole> roles,
  ) {
    final g = context.ghina;
    final parts = [
      for (final id in m.participants) _roleById(roles, id),
    ].nonNulls.toList();
    final chair = _roleById(roles, m.chair);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                m.topic,
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
            ),
            KantorStatusPill(m.status),
          ],
        ),
        const SizedBox(height: GhinaSpace.sm),
        Wrap(
          spacing: 4,
          children: [
            for (final r in parts) KantorSprite(look: r.look, size: 36),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${parts.map((r) => r.name).join(', ')} · ketua ${chair?.name ?? (m.chair.isEmpty ? '-' : m.chair)} · ${m.rounds ?? '?'} ronde · ${kantorUsd(m.cost, 3)}',
          style: GhinaType.caption.copyWith(color: g.textMuted),
        ),
        if (m.agenda.isNotEmpty) ...[
          const SizedBox(height: GhinaSpace.sm),
          Text(
            m.agenda,
            style: GhinaType.bodyS.copyWith(
              color: g.textSecondary,
              height: 1.4,
            ),
          ),
        ],
        if (m.interrupted) ...[
          const SizedBox(height: GhinaSpace.lg),
          ChunkyCard(
            tinted: GhinaColors.orange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  m.status == 'gagal'
                      ? 'Rapat berhenti: ${m.error.isEmpty ? 'tanpa keterangan' : m.error}'
                      : 'Rapat terputus karena kantor dimulai ulang.',
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Percakapan sejauh ini tersimpan, dan rapat bisa diteruskan dari giliran terakhir.',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: GhinaSpace.md),
                ChunkyButton(
                  label: 'Lanjutkan rapat',
                  loading: _busy,
                  onPressed: _busy
                      ? null
                      : () => _post(
                          '$_base/resume',
                          const {},
                          ok: 'Rapat dilanjutkan',
                        ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: GhinaSpace.lg),
        for (final msg in m.messages) _bubble(context, msg, roles),
        if (m.running && m.typing != null)
          _liveBubble(context, m.typing!, roles)
        else if (m.running)
          _typing(context, m, roles),
        if (m.status == 'selesai') ...[
          const SizedBox(height: GhinaSpace.lg),
          _minutes(context, m, roles),
          const SizedBox(height: GhinaSpace.lg),
          _continueForm(context),
        ],
        const SizedBox(height: GhinaSpace.xxl),
      ],
    );
  }

  Widget _bubble(
    BuildContext context,
    KantorMeetingMessage msg,
    List<KantorRole> roles,
  ) {
    final g = context.ghina;
    if (msg.kind == 'sistem') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: GhinaSpace.sm),
        child: Center(
          child: Text(
            msg.text,
            textAlign: TextAlign.center,
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
      );
    }
    final owner = msg.kind == 'kamu';
    final role = owner ? null : _roleByName(roles, msg.who);
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KantorSprite(
            look: owner
                ? _ownerLook
                : (role?.look ?? KantorSprite.guestLook(msg.who)),
            size: 36,
          ),
          const SizedBox(width: GhinaSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${owner ? 'Kamu' : msg.who} · ${kantorHhmm(msg.at)}${msg.cost > 0 ? ' · ${kantorUsd(msg.cost, 3)}' : ''}',
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 4),
                ChunkyCard(
                  padding: const EdgeInsets.all(GhinaSpace.md),
                  depth: GhinaDepth.sm,
                  tinted: owner ? GhinaColors.blue : null,
                  child: KantorMarkdown(msg.text, selectable: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The speaker's bubble while they write: dots until the first words, then the
  /// text flows in with a caret.
  Widget _liveBubble(
    BuildContext context,
    KantorMeetingTyping t,
    List<KantorRole> roles,
  ) {
    final g = context.ghina;
    final role = _roleByName(roles, t.who);
    final thinking = t.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KantorSprite(
            look: role?.look ?? KantorSprite.guestLook(t.who),
            size: 36,
          ),
          const SizedBox(width: GhinaSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t.who} · ${thinking ? 'sedang berpikir…' : 'sedang mengetik…'}',
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 4),
                ChunkyCard(
                  padding: const EdgeInsets.all(GhinaSpace.md),
                  depth: GhinaDepth.sm,
                  child: thinking
                      ? const _TypingDots()
                      : KantorMarkdown('${t.text} ▍'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typing(
    BuildContext context,
    KantorMeeting m,
    List<KantorRole> roles,
  ) {
    final names = [
      for (final id in m.participants) _roleById(roles, id)?.name,
    ].nonNulls.toList();
    final last = m.messages.where((x) => x.kind == 'bicara').lastOrNull;
    var label = 'Rapat berjalan…';
    if (names.isNotEmpty) {
      final i = last == null
          ? -1
          : names.indexWhere((n) => n.toLowerCase() == last.who.toLowerCase());
      if (last == null) {
        label = '${names.first} sedang bicara…';
      } else if (i >= 0) {
        label = '${names[(i + 1) % names.length]} sedang bicara…';
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GhinaSpace.sm),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: GhinaSpace.sm),
          Text(
            label,
            style: GhinaType.bodyS.copyWith(color: context.ghina.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sayBar(BuildContext context) {
    final g = context.ghina;
    return Material(
      color: g.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.md,
            GhinaSpace.sm,
            GhinaSpace.md,
            GhinaSpace.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: ChunkyTextField(
                  controller: _say,
                  hint: 'Sela rapat: tulis pendapat atau arahan',
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendSay(),
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              ChunkyIconButton(
                icon: Icons.send_rounded,
                tooltip: 'Kirim',
                onPressed: _sendSay,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _minutes(
    BuildContext context,
    KantorMeeting m,
    List<KantorRole> roles,
  ) {
    final g = context.ghina;
    final acts = m.actions;
    final allDone = acts.isNotEmpty && acts.every((a) => a.card != null);
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notulen', style: GhinaType.h2.copyWith(color: g.textPrimary)),
          if (m.summary.isNotEmpty) ...[
            const SizedBox(height: GhinaSpace.md),
            Text(
              'Ringkasan',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: 4),
            SelectableText(
              m.summary,
              style: GhinaType.body.copyWith(
                color: g.textPrimary,
                height: 1.45,
              ),
            ),
          ],
          if (m.decisions.isNotEmpty) ...[
            const SizedBox(height: GhinaSpace.md),
            Text(
              'Keputusan',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            for (final d in m.decisions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: GhinaType.body.copyWith(color: g.textPrimary),
                    ),
                    Expanded(
                      child: Text(
                        d,
                        style: GhinaType.body.copyWith(
                          color: g.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: GhinaSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tindak lanjut',
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              if (acts.isNotEmpty && !allDone)
                ChunkyButton(
                  label: 'Semua jadi kartu',
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  onPressed: _busy
                      ? null
                      : () => _post('$_base/action', {
                          'index': 'all',
                        }, ok: 'Kartu dibuat'),
                ),
            ],
          ),
          if (acts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Tidak ada tindak lanjut.',
                style: GhinaType.body.copyWith(color: g.textMuted),
              ),
            ),
          for (var i = 0; i < acts.length; i++)
            _action(context, acts[i], i, roles),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context,
    KantorMeetingAction a,
    int i,
    List<KantorRole> roles,
  ) {
    final g = context.ghina;
    final who = a.who == null
        ? null
        : (_roleById(roles, a.who!)?.name ?? a.who);
    final meta = [
      ?who,
      if (a.prio != null && a.prio!.isNotEmpty) a.prio!,
      if (a.detail != null && a.detail!.isNotEmpty) a.detail!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: GhinaSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: GhinaSpace.sm),
          if (a.card != null)
            ChunkyPill(
              label: 'Kartu ${a.card}',
              color: GhinaColors.green,
              soft: true,
              uppercase: false,
            )
          else
            ChunkyButton(
              label: 'Jadikan kartu',
              size: ChunkyButtonSize.small,
              variant: ChunkyButtonVariant.outline,
              onPressed: _busy
                  ? null
                  : () => _post('$_base/action', {
                      'index': i,
                    }, ok: 'Kartu dibuat'),
            ),
        ],
      ),
    );
  }

  Widget _continueForm(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lanjutkan rapat',
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Peserta yang sama berdiskusi lagi dengan transkrip di atas sebagai konteks, lalu ketua memperbarui notulen. Tindak lanjut yang sudah jadi kartu tetap disimpan. Biaya nyata.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            controller: _note,
            hint:
                'Pertanyaan atau arahan baru (opsional), mis. hitung ulang kalau harga naik 20%',
            minLines: 2,
            maxLines: 5,
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyChoiceChips<int>(
            options: [
              for (var i = 1; i <= 3; i++)
                ChunkyChoice(value: i, label: '+$i ronde'),
            ],
            selected: {_moreRounds},
            onChanged: (s) {
              if (s.isNotEmpty) setState(() => _moreRounds = s.first);
            },
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyButton(
            label: 'Lanjutkan rapat',
            loading: _busy,
            onPressed: _busy
                ? null
                : () async {
                    final ok = await showChunkyConfirm(
                      context,
                      title: 'Lanjutkan rapat?',
                      message:
                          'Menambah $_moreRounds ronde. Tiap giliran memakai model role-nya (biaya nyata).',
                      confirmLabel: 'Lanjutkan',
                    );
                    if (!ok || !mounted) return;
                    await _post('$_base/continue', {
                      'note': _note.text,
                      'rounds': _moreRounds,
                    }, ok: 'Rapat dilanjutkan');
                    _note.clear();
                  },
          ),
        ],
      ),
    );
  }
}

/// Three dots that pulse in turn.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.ghina.textMuted;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Opacity(
                opacity: 0.25 + 0.75 * (1 - ((_c.value * 3 - i) % 3) / 3),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
