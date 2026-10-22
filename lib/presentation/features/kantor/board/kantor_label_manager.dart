import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'kantor_board_data.dart';
import 'kantor_board_lib.dart';
import 'kantor_board_widgets.dart';

/// Create, recolor, rename and delete board labels.
Future<void> showKantorLabelManager(
  BuildContext context, {
  required String officeId,
}) => showChunkyBottomSheet<void>(
  context,
  title: 'Kelola label',
  builder: (_) => _Manager(officeId: officeId),
);

class _Manager extends ConsumerStatefulWidget {
  const _Manager({required this.officeId});
  final String officeId;

  @override
  ConsumerState<_Manager> createState() => _ManagerState();
}

class _ManagerState extends ConsumerState<_Manager> {
  final _name = TextEditingController();
  String _color = CategoryColors.palette.first;

  String get _base => '${kBase(widget.officeId)}/labels';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _do(Future<dynamic> Function(KantorApi api) f) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      await f(api);
      await ref.read(kantorBoardProvider(widget.officeId).notifier).refresh();
    } catch (e) {
      if (mounted) kToast(context, '$e', bad: true);
    }
  }

  Future<void> _rename(KLabel l) async {
    final ctl = TextEditingController(text: l.name);
    final r = await showChunkyDialog<String>(
      context,
      builder: (ctx) => ChunkyDialog(
        title: 'Ubah label',
        content: TextField(controller: ctl, autofocus: true, maxLength: 40),
        actions: [
          ChunkyButton(
            label: 'Simpan',
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (r != null && r.isNotEmpty) {
      await _do(
        (api) => api.post(_base, {'id': l.id, 'name': r, 'color': l.color}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(kantorBoardProvider(widget.officeId)).value;
    final labels = board?.labels ?? const <KLabel>[];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (labels.isEmpty) const Text('Belum ada label.'),
            for (final l in labels)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: GestureDetector(
                  onTap: () async {
                    final hex = await showChunkyBottomSheet<String>(
                      context,
                      title: 'Warna',
                      builder: (ctx) => ChunkyColorPicker(
                        selected: l.color,
                        onChanged: (v) => Navigator.of(ctx).pop(v),
                      ),
                    );
                    if (hex != null) {
                      await _do(
                        (api) => api.post(_base, {
                          'id': l.id,
                          'name': l.name,
                          'color': hex,
                        }),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: kHex(l.color),
                  ),
                ),
                title: Text(l.name, style: GhinaType.body.w(700)),
                subtitle: Text(
                  '${board?.cards.where((c) => c.labels.contains(l.id)).length ?? 0} kartu',
                ),
                onTap: () => _rename(l),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _do((api) => api.delete('$_base/${l.id}')),
                ),
              ),
            const Divider(),
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(hintText: 'Nama label baru'),
            ),
            ChunkyColorPicker(
              selected: _color,
              size: 36,
              onChanged: (v) => setState(() => _color = v),
            ),
            const SizedBox(height: 12),
            ChunkyButton(
              label: 'Tambah label',
              onPressed: () async {
                final n = _name.text.trim();
                if (n.isEmpty) return;
                await _do(
                  (api) => api.post(_base, {'name': n, 'color': _color}),
                );
                _name.clear();
              },
            ),
          ],
        ),
      ),
    );
  }
}
