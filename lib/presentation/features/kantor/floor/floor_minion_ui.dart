// Magang controls: the settings sheet (count, auto, "Usir semua") and the sheet
// for one tapped Magang ("Usir"). The simulation is floor_minions.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'floor_owner_ui.dart' show OwnerToast;
import 'floor_panels.dart';
import 'floor_sim.dart';

/// Sends one Magang away: they say goodbye and walk to the lift right now; the
/// daemon stores it and tells the other devices.
Future<void> usirMinion({
  required KantorApi api,
  required String officeId,
  required FloorSim sim,
  required FloorEnt minion,
  required OwnerToast toast,
}) async {
  final name = minion.name;
  sim.minionLeave(minion.id);
  try {
    await api.post(
      '/api/offices/$officeId/minions/${Uri.encodeComponent(minion.id)}/usir',
    );
    toast('$name diusir');
  } on Object catch (e) {
    toast('$e', bad: true);
  }
}

/// Tapped a Magang: who they are and the one thing you can do with them.
Future<void> showMinionSheet(
  BuildContext context, {
  required FloorEnt minion,
  required String actionLabel,
  required VoidCallback onUsir,
}) {
  return showChunkyBottomSheet<void>(
    context,
    showClose: true,
    builder: (c) {
      final g = c.ghina;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              FloorAvatar(look: minion.look, scale: 1.8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      minion.name,
                      style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
                    ),
                    Text(
                      'Magang · bukan agen, tidak memakai token',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ChunkyButton(
            key: const ValueKey('minion-usir'),
            label: actionLabel,
            icon: Icons.logout_rounded,
            onPressed: () {
              Navigator.of(c).pop();
              onUsir();
            },
          ),
        ],
      );
    },
  );
}

/// Office menu: how many Magang, auto mode, send everyone home.
Future<void> showMinionSettings(
  BuildContext context, {
  required KantorApi api,
  required String officeId,
  required Map<String, dynamic>? view,
  required FloorSim? sim,
  required void Function(Map<String, dynamic> view) onView,
  required OwnerToast toast,
}) {
  return showChunkyBottomSheet<void>(
    context,
    showClose: true,
    builder: (c) => _MinionSettings(
      api: api,
      officeId: officeId,
      view: view,
      sim: sim,
      onView: onView,
      toast: toast,
    ),
  );
}

class _MinionSettings extends StatefulWidget {
  const _MinionSettings({
    required this.api,
    required this.officeId,
    required this.view,
    required this.sim,
    required this.onView,
    required this.toast,
  });
  final KantorApi api;
  final String officeId;
  final Map<String, dynamic>? view;
  final FloorSim? sim;
  final void Function(Map<String, dynamic>) onView;
  final OwnerToast toast;

  @override
  State<_MinionSettings> createState() => _MinionSettingsState();
}

class _MinionSettingsState extends State<_MinionSettings> {
  late double _count = ((widget.view?['count'] as num?) ?? 6).toDouble();
  late bool _auto = widget.view?['auto'] == true;
  var _busy = false;

  Future<void> _put(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.put(
        '/api/offices/${widget.officeId}/minions',
        body,
      );
      if (r is Map<String, dynamic>) {
        widget.onView(r);
        _count = ((r['count'] as num?) ?? _count).toDouble();
        _auto = r['auto'] == true;
      }
    } on Object catch (e) {
      widget.toast('$e', bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final max = ((widget.view?['max'] as num?) ?? 30).toDouble();
    final here = widget.sim?.minionCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Magang',
          style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Karyawan magang tidak memanggil model apa pun: murni ramai-ramai. '
          'Mereka mengalah ke agen dan ke kamu.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Jumlah',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('minion-count'),
                min: 0,
                max: max,
                divisions: max.round(),
                value: _count.clamp(0, max),
                label: '${_count.round()}',
                onChanged: _busy ? null : (v) => setState(() => _count = v),
                onChangeEnd: (v) => _put({'count': v.round()}),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${_count.round()}',
                textAlign: TextAlign.end,
                style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
              ),
            ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey('minion-auto'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Otomatis',
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
          subtitle: Text(
            'Sepi saat malam, berkurang saat banyak agen bekerja'
            '${_auto && here != null ? ' · $here di kantor sekarang' : ''}',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          value: _auto,
          onChanged: _busy ? null : (v) => _put({'auto': v}),
        ),
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('minion-usir-semua'),
          label: 'Usir semua',
          icon: Icons.logout_rounded,
          variant: ChunkyButtonVariant.secondary,
          onPressed: _busy || _count.round() == 0
              ? null
              : () async {
                  HapticFeedback.lightImpact();
                  await _put({'usirSemua': true});
                  if (mounted) widget.toast('Semua Magang pulang');
                },
        ),
      ],
    );
  }
}
