// Controls of the owner on the plan: virtual joystick, the big action button
// and the sheet shown when standing next to an agent.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'floor_panels.dart';
import 'floor_sim.dart';

/// Thumb stick. Takes its own pointers, so the plan underneath never sees the
/// drag (no pan, no pinch). Reports a vector with each axis in -1..1.
class OwnerJoystick extends StatefulWidget {
  const OwnerJoystick({super.key, required this.onChanged, this.size = 124});
  final void Function(double dx, double dy) onChanged;
  final double size;

  @override
  State<OwnerJoystick> createState() => _OwnerJoystickState();
}

class _OwnerJoystickState extends State<OwnerJoystick> {
  int? _pointer;
  Offset _knob = Offset.zero;

  double get _reach => widget.size / 2 - 24;

  void _update(Offset local) {
    var d = local - Offset(widget.size / 2, widget.size / 2);
    if (d.distance > _reach) d = d / d.distance * _reach;
    setState(() => _knob = d);
    widget.onChanged(d.dx / _reach, d.dy / _reach);
  }

  void _release() {
    _pointer = null;
    if (mounted) setState(() => _knob = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  void dispose() {
    if (_pointer != null) widget.onChanged(0, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _update(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _update(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _release();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _release();
      },
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x661F1628),
                border: Border.all(color: const Color(0x99FBF4EA), width: 2),
              ),
            ),
            Transform.translate(
              offset: _knob,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xE6F5C542),
                  border: Border.all(
                    color: const Color(0xFF1F1628),
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData ownerIcon(String id) => switch (id) {
  'coffee' => Icons.coffee_rounded,
  'water' => Icons.water_drop_rounded,
  'snack' => Icons.cookie_rounded,
  'eat' => Icons.restaurant_rounded,
  'sit' || 'sofa' => Icons.event_seat_rounded,
  'sleep' => Icons.bedtime_rounded,
  'pray' || 'wudhu' => Icons.mosque_rounded,
  'play' || 'game' => Icons.sports_esports_rounded,
  'music' => Icons.music_note_rounded,
  'exercise' || 'train' => Icons.fitness_center_rounded,
  'read' || 'wiki' => Icons.menu_book_rounded,
  'plant' => Icons.local_florist_rounded,
  'phone' => Icons.call_rounded,
  'print' => Icons.print_rounded,
  'think' => Icons.lightbulb_rounded,
  'board' => Icons.dashboard_rounded,
  'rapat' => Icons.groups_rounded,
  'agent' => Icons.waving_hand_rounded,
  'test' || 'server' => Icons.dns_rounded,
  _ => Icons.touch_app_rounded,
};

/// The big button: appears only while something is within reach.
class OwnerActionButton extends StatelessWidget {
  const OwnerActionButton({
    super.key,
    required this.target,
    required this.onPressed,
  });
  final OwnerTarget target;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final stop = target.kind == 'stop';
    return ChunkyButton(
      key: const ValueKey('owner-action'),
      label: target.label,
      icon: ownerIcon(target.aff),
      expand: false,
      variant: stop
          ? ChunkyButtonVariant.secondary
          : ChunkyButtonVariant.primary,
      onPressed: onPressed,
    );
  }
}

typedef OwnerToast = void Function(String msg, {bool bad});

/// Sheet for the agent the owner stands next to: talk, nudge, hand a card, peek.
Future<void> showOwnerAgentSheet(
  BuildContext context, {
  required KantorApi api,
  required String officeId,
  required FloorEnt agent,
  required Map<String, dynamic>? role,
  required OwnerToast toast,
  required void Function(String path) open,
}) {
  final sid = agent.sid;
  if (sid == null) return Future.value();
  final base = '/kantor/o/$officeId/s/$sid';
  return showChunkyBottomSheet<void>(
    context,
    showClose: true,
    builder: (c) => _AgentSheet(
      api: api,
      officeId: officeId,
      agent: agent,
      role: role,
      base: base,
      toast: toast,
      open: open,
    ),
  );
}

class _AgentSheet extends StatefulWidget {
  const _AgentSheet({
    required this.api,
    required this.officeId,
    required this.agent,
    required this.role,
    required this.base,
    required this.toast,
    required this.open,
  });
  final KantorApi api;
  final String officeId, base;
  final FloorEnt agent;
  final Map<String, dynamic>? role;
  final OwnerToast toast;
  final void Function(String path) open;

  @override
  State<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<_AgentSheet> {
  var _mode = 'menu'; // menu | tap | cards
  var _busy = false;
  List<Map<String, dynamic>>? _cards;

  String get _sid => widget.agent.sid!;

  void _go(String tab) {
    Navigator.of(context).pop();
    widget.open('${widget.base}?tab=$tab');
  }

  Future<void> _tap(String what) async {
    setState(() => _busy = true);
    try {
      if (what == 'lanjut') {
        await widget.api.post('/api/sessions/$_sid/action', {
          'action': 'text',
          'text': 'lanjut',
        });
      } else {
        await widget.api.post('/api/sessions/$_sid/action', {'action': 'esc'});
      }
      HapticFeedback.lightImpact();
      widget.toast(
        what == 'lanjut'
            ? 'Bilang "lanjut" ke ${widget.agent.name}'
            : '${widget.agent.name} diminta berhenti dulu',
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      widget.toast('$e', bad: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCards() async {
    setState(() => _mode = 'cards');
    try {
      final b = await widget.api.get('/api/offices/${widget.officeId}/board');
      final all = (b is Map ? b['cards'] as List? : null) ?? const [];
      final rid = widget.role?['id'];
      final list = [
        for (final x in all)
          if (x is Map<String, dynamic> &&
              ((x['col'] as num?) ?? 0) < 4 &&
              x['who'] != rid)
            x,
      ];
      if (mounted) setState(() => _cards = list);
    } on Object catch (e) {
      widget.toast('$e', bad: true);
      if (mounted) setState(() => _cards = const []);
    }
  }

  Future<void> _give(Map<String, dynamic> card) async {
    setState(() => _busy = true);
    try {
      await widget.api.patch(
        '/api/offices/${widget.officeId}/cards/${card['id']}',
        {'who': widget.role!['id']},
      );
      HapticFeedback.lightImpact();
      widget.toast('Kartu diberikan ke ${widget.agent.name}');
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      widget.toast('$e', bad: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = widget.agent;
    final title = Row(
      children: [
        FloorAvatar(look: a.look, scale: 1.8),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.name,
                style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
              ),
              Text(
                a.waiting ? 'menunggu izin' : '${a.s?['status'] ?? ''}',
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
    Widget back() => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ChunkyButton(
        label: 'Kembali',
        variant: ChunkyButtonVariant.secondary,
        onPressed: _busy ? null : () => setState(() => _mode = 'menu'),
      ),
    );
    final body = switch (_mode) {
      'tap' => [
        Text(
          'Tepuk bahu ${a.name}',
          style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 10),
        ChunkyButton(
          key: const ValueKey('tap-lanjut'),
          label: 'Lanjut',
          icon: Icons.play_arrow_rounded,
          loading: _busy,
          onPressed: _busy ? null : () => _tap('lanjut'),
        ),
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('tap-esc'),
          label: 'Berhenti dulu',
          icon: Icons.pan_tool_rounded,
          variant: ChunkyButtonVariant.secondary,
          onPressed: _busy ? null : () => _tap('esc'),
        ),
        back(),
      ],
      'cards' => [
        Text(
          'Kasih kartu ke ${a.name}',
          style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 10),
        if (_cards == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_cards!.isEmpty)
          Text(
            'Tidak ada kartu yang bisa diberikan.',
            style: GhinaType.bodyS.copyWith(color: g.textMuted),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final k in _cards!)
                  ListTile(
                    key: ValueKey('card-${k['id']}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      shortText('${k['title']}', 60),
                      style: GhinaType.bodyS
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : () => _give(k),
                  ),
              ],
            ),
          ),
        back(),
      ],
      _ => [
        ChunkyButton(
          key: const ValueKey('agent-chat'),
          label: 'Ngobrol',
          icon: Icons.chat_bubble_rounded,
          onPressed: () => _go('chat'),
        ),
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('agent-tap'),
          label: 'Tepuk bahu',
          icon: Icons.back_hand_rounded,
          variant: ChunkyButtonVariant.secondary,
          onPressed: () => setState(() => _mode = 'tap'),
        ),
        if (widget.role != null) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('agent-card'),
            label: 'Kasih kartu',
            icon: Icons.style_rounded,
            variant: ChunkyButtonVariant.secondary,
            onPressed: _loadCards,
          ),
        ],
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('agent-screen'),
          label: 'Lihat layar',
          icon: Icons.terminal_rounded,
          variant: ChunkyButtonVariant.secondary,
          onPressed: () => _go('terminal'),
        ),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [title, const SizedBox(height: 14), ...body],
    );
  }
}
