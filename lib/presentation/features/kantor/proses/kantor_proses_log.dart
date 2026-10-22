import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'kantor_proses_data.dart';
import 'kantor_proses_page.dart' show kantorProcStatus;

Future<void> openKantorProcLog(
  BuildContext context, {
  required String officeId,
  required String procId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => KantorProcLogPage(officeId: officeId, procId: procId),
  ),
);

/// Live log of one process: polls `/procs/<id>/log?offset=` like the web dock,
/// follows the tail while you are at the bottom, zoomable monospace.
class KantorProcLogPage extends ConsumerStatefulWidget {
  const KantorProcLogPage({
    super.key,
    required this.officeId,
    required this.procId,
    this.interval = const Duration(milliseconds: 900),
  });

  final String officeId, procId;
  final Duration interval;

  @override
  ConsumerState<KantorProcLogPage> createState() => _LogState();
}

class _LogState extends ConsumerState<KantorProcLogPage> {
  static const _cap = 300000;
  final _scroll = ScrollController();
  Timer? _timer;
  String _text = '';
  int _offset = -1;
  bool _loaded = false, _follow = true, _busy = false;
  String? _error;
  double _size = 12, _baseSize = 12;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final atEnd = _scroll.position.maxScrollExtent - _scroll.offset < 40;
      if (atEnd != _follow) setState(() => _follow = atEnd);
    });
    _pull();
    _timer = Timer.periodic(widget.interval, (_) => _pull());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pull() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _busy) return;
    _busy = true;
    try {
      final id = Uri.encodeComponent(widget.procId);
      final r = Map<String, dynamic>.from(
        await api.get(
              '/api/offices/${Uri.encodeComponent(widget.officeId)}/procs/$id/log',
              query: _offset >= 0 ? {'offset': _offset} : null,
            )
            as Map,
      );
      if (!mounted) return;
      final from = (r['from'] as num?)?.toInt() ?? 0;
      final chunk = kantorCleanLog('${r['text'] ?? ''}');
      var next = (_offset >= 0 && from == _offset) ? _text + chunk : chunk;
      if (next.length > _cap) next = next.substring(next.length - _cap);
      final grew = next != _text;
      setState(() {
        _text = next;
        _offset = (r['next'] as num?)?.toInt() ?? _offset;
        _loaded = true;
        _error = null;
      });
      if (grew && _follow) _toEnd();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _busy = false;
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  void _zoom(double d) => setState(() => _size = (_size + d).clamp(8, 24));

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final procs = ref.watch(kantorProcsProvider(widget.officeId)).value;
    KantorProc? p;
    for (final x in procs?.procs ?? const <KantorProc>[]) {
      if (x.id == widget.procId) p = x;
    }
    final st = p == null ? null : kantorProcStatus(p);
    return Scaffold(
      backgroundColor: const Color(0xFF0E1218),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p?.name ?? 'Log', overflow: TextOverflow.ellipsis),
            if (st != null)
              Text(st.$1, style: GhinaType.caption.copyWith(color: st.$2)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Perkecil huruf',
            icon: const Icon(Icons.text_decrease_rounded),
            onPressed: () => _zoom(-1),
          ),
          IconButton(
            tooltip: 'Perbesar huruf',
            icon: const Icon(Icons.text_increase_rounded),
            onPressed: () => _zoom(1),
          ),
        ],
      ),
      floatingActionButton: _follow
          ? null
          : FloatingActionButton.small(
              tooltip: 'Ke bawah',
              onPressed: () {
                setState(() => _follow = true);
                _toEnd();
              },
              child: const Icon(Icons.vertical_align_bottom_rounded),
            ),
      body: Column(
        children: [
          if (p != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF171C25),
              padding: const EdgeInsets.symmetric(
                horizontal: GhinaSpace.md,
                vertical: 6,
              ),
              child: Text(
                '\$ ${p.cmd}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFE4A445),
                  fontFamily: 'monospace',
                  fontSize: _size,
                ),
              ),
            ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: g.surface,
              padding: const EdgeInsets.all(GhinaSpace.sm),
              child: Text(
                'Log tidak terbaca: $_error',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
          Expanded(
            child: GestureDetector(
              onScaleStart: (_) => _baseSize = _size,
              onScaleUpdate: (d) {
                if (d.pointerCount > 1) {
                  setState(() => _size = (_baseSize * d.scale).clamp(8, 24));
                }
              },
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(GhinaSpace.md),
                child: SelectableText(
                  !_loaded
                      ? 'Memuat log…'
                      : _text.isEmpty
                      ? 'Belum ada keluaran.'
                      : _text,
                  style: TextStyle(
                    color: const Color(0xFFD4DAE3),
                    fontFamily: 'monospace',
                    fontSize: _size,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
