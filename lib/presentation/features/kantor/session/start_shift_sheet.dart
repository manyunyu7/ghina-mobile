import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import 'kantor_actions.dart';
import 'kantor_feed.dart';

const _perms = <(String, String)>[
  ('', 'Default kantor'),
  ('default', 'Selalu tanya'),
  ('acceptEdits', 'Edit file otomatis'),
  ('auto', 'Auto'),
  ('plan', 'Hanya merencanakan'),
];

/// "Mulai shift" for a role off duty (web `startShiftDialog`). Returns the new
/// session id, or null when cancelled or failed.
Future<String?> showStartShiftSheet(
  BuildContext context, {
  required KantorOfficeFeed feed,
  required KantorActions? actions,
  required Json role,
}) {
  return showChunkyBottomSheet<String>(
    context,
    title: 'Mulai shift ${role['name']}',
    builder: (c) => _ShiftForm(feed: feed, actions: actions, role: role),
  );
}

class _ShiftForm extends StatefulWidget {
  const _ShiftForm({
    required this.feed,
    required this.actions,
    required this.role,
  });

  final KantorOfficeFeed feed;
  final KantorActions? actions;
  final Json role;

  @override
  State<_ShiftForm> createState() => _ShiftFormState();
}

class _ShiftFormState extends State<_ShiftForm> {
  final _task = TextEditingController();
  String _perm = '';
  late KantorEngineSel _eng = KantorEngineSel.initial(widget.role);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sid = await widget.actions?.startShift(
        widget.feed.officeId,
        '${widget.role['id']}',
        task: _task.text,
        permissionMode: _eng.codex ? null : _perm,
        extra: _eng.body(widget.role),
      );
      if (mounted) Navigator.of(context).pop(sid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.role['title'] ?? ''} - ${kantorIsCodex(widget.role) ? (('${widget.role['model'] ?? ''}').isEmpty ? 'Codex' : '${widget.role['model']}') : modelLabel(widget.role['model'])}',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          GhinaSpace.gapMd,
          ChunkyTextField(
            label: 'Tugas pertama (opsional)',
            hint: 'mis. perbaiki bug login lalu jalankan tes',
            controller: _task,
            minLines: 2,
            maxLines: 4,
            enabled: !_busy,
          ),
          GhinaSpace.gapMd,
          KantorEngineFields(
            role: widget.role,
            onChanged: (s) => setState(() => _eng = s),
          ),
          if (!_eng.codex) ...[
            GhinaSpace.gapMd,
            Text(
              'MODE IZIN',
              style: GhinaType.overline.copyWith(color: g.textSecondary),
            ),
            GhinaSpace.gapSm,
            ChunkyChoiceChips<String>(
              options: [
                for (final p in _perms) ChunkyChoice(value: p.$1, label: p.$2),
              ],
              selected: {_perm},
              onChanged: (s) =>
                  setState(() => _perm = s.isEmpty ? '' : s.first),
            ),
          ],
          if (_error != null) ...[
            GhinaSpace.gapSm,
            Text(
              _error!,
              style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
            ),
          ],
          GhinaSpace.gapLg,
          ChunkyButton(
            label: 'Mulai shift',
            loading: _busy,
            onPressed: _busy ? null : _go,
          ),
        ],
      ),
    );
  }
}
