import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';
import '../widgets/kantor_sprite.dart';

enum KantorHitKind { office, agent, session }

/// One search result; [path] is the route that opens it.
class KantorHit {
  const KantorHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.path,
    this.look,
  });

  final KantorHitKind kind;
  final String title;
  final String subtitle;
  final String path;
  final Map<String, dynamic>? look;
}

String _officePath(Object? id) => '/kantor/o/${Uri.encodeComponent('$id')}';
String _sessionPath(Object? office, Object? sid) =>
    '${_officePath(office)}/s/${Uri.encodeComponent('$sid')}';

/// Offices, the agents (by name, job title or what they are doing) and
/// sessions, across every office, from `/api/state` and the recently ended
/// list. Empty [query] gives no hits.
List<KantorHit> kantorSearch(
  Map<String, dynamic> state,
  String query, {
  List<dynamic> ended = const [],
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  bool has(Iterable<Object?> parts) =>
      parts.any((p) => '$p'.toLowerCase().contains(q));
  final offices = <KantorHit>[];
  final agents = <KantorHit>[];
  final sessions = <KantorHit>[];
  for (final raw in state['offices'] as List? ?? const []) {
    final o = Map<String, dynamic>.from(raw as Map);
    final name = '${o['name']}';
    if (has([name, o['style'], '${o['root'] ?? ''}'.split('/').last])) {
      offices.add(
        KantorHit(
          kind: KantorHitKind.office,
          title: name,
          subtitle: '${o['style'] ?? 'Kantor'}',
          path: _officePath(o['id']),
        ),
      );
    }
    for (final sr in o['sessions'] as List? ?? const []) {
      final s = Map<String, dynamic>.from(sr as Map);
      if (s['status'] == 'ended') continue;
      final look = s['look'] is Map
          ? Map<String, dynamic>.from(s['look'] as Map)
          : null;
      final who = '${look?['name'] ?? ''}';
      final job = '${look?['title'] ?? s['role'] ?? ''}';
      final doing = kantorSessionLabel(s);
      if (!has([who, job, s['title'], doing])) continue;
      final hit = KantorHit(
        kind: who.isNotEmpty ? KantorHitKind.agent : KantorHitKind.session,
        title: who.isNotEmpty ? who : kantorShort(doing, 40),
        subtitle: [
          '${o['name']}',
          if (job.isNotEmpty && who.isNotEmpty) job,
          if (who.isNotEmpty) kantorShort(doing, 40),
        ].join(' · '),
        path: _sessionPath(o['id'], s['sid']),
        look: look ?? KantorSprite.guestLook('${s['sid']}'),
      );
      (who.isNotEmpty ? agents : sessions).add(hit);
    }
  }
  for (final raw in ended) {
    final x = Map<String, dynamic>.from(raw as Map);
    final title = x['title'] != null && x['title'] != 'Sesi belum terhubung'
        ? '${x['title']}'
        : '${x['first_prompt'] ?? 'Sesi tanpa judul'}';
    if (!has([title, x['first_prompt'], x['office_name']])) continue;
    sessions.add(
      KantorHit(
        kind: KantorHitKind.session,
        title: kantorShort(title, 40),
        subtitle:
            '${x['office_name'] ?? ''} · ditutup ${kantorAgo(x['ended_at'])}',
        path: _sessionPath(x['office'], x['sid']),
        look: KantorSprite.guestLook('${x['sid']}'),
      ),
    );
  }
  return [...offices, ...agents, ...sessions];
}

/// Full-screen search over the whole complex. Opened from the 🔍 in the
/// Kompleks app bar or the bar at the top of its list.
class KantorSearchPage extends ConsumerStatefulWidget {
  const KantorSearchPage({super.key});

  @override
  ConsumerState<KantorSearchPage> createState() => _KantorSearchPageState();
}

class _KantorSearchPageState extends ConsumerState<KantorSearchPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final state = ref.watch(kantorStateProvider).value ?? const {};
    final ended = ref.watch(kantorEndedProvider).value ?? const [];
    final hits = kantorSearch(state, _q, ended: ended);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Cari kantor, agen, atau sesi…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: _q.trim().isEmpty
          ? Center(
              child: Text(
                'Ketik nama kantor, agen, atau isi sesi.',
                style: GhinaType.body.copyWith(color: g.textMuted),
              ),
            )
          : hits.isEmpty
          ? const EmptyState(title: 'Tidak ada hasil', compact: true)
          : ListView(
              padding: const EdgeInsets.all(GhinaSpace.page),
              children: [
                for (final h in hits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                    child: ChunkyTile(
                      leading: h.look != null
                          ? KantorSprite(look: h.look!, size: 32)
                          : const Icon(Icons.apartment_rounded),
                      title: h.title,
                      subtitle: h.subtitle,
                      showChevron: true,
                      onTap: () => context.push(h.path),
                    ),
                  ),
              ],
            ),
    );
  }
}
