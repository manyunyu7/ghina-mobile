import 'dart:convert';

import '../../presentation/features/kantor/kantor_format.dart';

/// One agent line on the home-screen widget.
final class KantorWidgetAgent {
  const KantorWidgetAgent({
    required this.name,
    required this.action,
    required this.waiting,
    required this.route,
  });

  final String name;
  final String action;
  final bool waiting;

  /// Where tapping the row goes (`/kantor/o/<office>/s/<sid>`).
  final String route;

  Map<String, dynamic> toJson() => {
    'name': name,
    'action': action,
    'waiting': waiting,
    'route': route,
  };
}

/// What the Android widget shows, distilled from `GET /api/state`. Serialised
/// to one JSON string (read by `KantorWidgetProvider.kt`): keep the keys in sync.
final class KantorWidgetSummary {
  const KantorWidgetSummary({
    required this.waiting,
    required this.working,
    required this.idle,
    required this.agents,
    required this.updatedAt,
  });

  /// Sessions asking for a permission.
  final int waiting;
  final int working;
  final int idle;

  /// The top agents: waiting first, then working, then idle.
  final List<KantorWidgetAgent> agents;
  final DateTime updatedAt;

  static const maxAgents = 3;

  factory KantorWidgetSummary.fromState(
    Map<String, dynamic> state, {
    required DateTime now,
  }) {
    final rows = <(Map<String, dynamic>, Map<String, dynamic>)>[];
    for (final o in (state['offices'] as List? ?? const [])) {
      if (o is! Map) continue;
      final office = Map<String, dynamic>.from(o);
      for (final s in (office['sessions'] as List? ?? const [])) {
        if (s is! Map || s['status'] == 'ended') continue;
        rows.add((office, Map<String, dynamic>.from(s)));
      }
    }
    // Stable: ties keep the daemon's order.
    final ranked = [for (var i = 0; i < rows.length; i++) (i, rows[i])]
      ..sort((a, b) {
        final r = kantorSessionRank(
          a.$2.$2,
        ).compareTo(kantorSessionRank(b.$2.$2));
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });

    var waiting = 0, working = 0, idle = 0;
    for (final (_, s) in rows) {
      if (s['waiting'] != null) {
        waiting++;
      } else if (s['status'] == 'working') {
        working++;
      } else {
        idle++;
      }
    }

    return KantorWidgetSummary(
      waiting: waiting,
      working: working,
      idle: idle,
      updatedAt: now,
      agents: [
        for (final (_, (office, s)) in ranked.take(maxAgents))
          KantorWidgetAgent(
            name: _agentName(office, s),
            action: kantorShort(kantorSessionLabel(s), 40),
            waiting: s['waiting'] != null,
            route:
                '/kantor/o/${Uri.encodeComponent('${office['id']}')}'
                '/s/${Uri.encodeComponent('${s['sid']}')}',
          ),
      ],
    );
  }

  static String _agentName(
    Map<String, dynamic> office,
    Map<String, dynamic> s,
  ) {
    final look = s['look'];
    final name = look is Map ? '${look['name'] ?? ''}'.trim() : '';
    if (name.isNotEmpty) return kantorShort(name, 20);
    final title = '${s['title'] ?? ''}'.trim();
    if (title.isNotEmpty && title != 'Sesi belum terhubung') {
      return kantorShort(title, 20);
    }
    return kantorShort('${office['name'] ?? 'Agen'}', 20);
  }

  Map<String, dynamic> toJson() => {
    'ok': true,
    'waiting': waiting,
    'working': working,
    'idle': idle,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'agents': [for (final a in agents) a.toJson()],
  };

  String encode() => jsonEncode(toJson());

  /// The widget payload when the office cannot be reached: the last good
  /// numbers (when there are any) marked stale, so the widget can say
  /// "Tidak terhubung" and still show when it last knew.
  static String encodeOffline({String? previous, required DateTime now}) {
    Map<String, dynamic> base = {};
    if (previous != null) {
      try {
        final d = jsonDecode(previous);
        if (d is Map<String, dynamic>) base = d;
      } catch (_) {}
    }
    return jsonEncode({
      ...base,
      'ok': false,
      'checkedAt': now.millisecondsSinceEpoch,
    });
  }
}
