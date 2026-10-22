import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// Shared Kantor office data for the Roles, Meetings, Archive and Files tabs.

String _s(Object? v, [String d = '']) => v is String ? v : d;

/// A permanent office employee. [look] is the raw map [KantorSprite] reads.
final class KantorRole {
  const KantorRole({
    required this.id,
    required this.name,
    required this.title,
    required this.model,
    required this.room,
    required this.persona,
    required this.skills,
    required this.notes,
    required this.isManager,
    required this.archived,
    required this.look,
    this.budget,
    this.reportsTo,
    this.engine = 'claude',
    this.effort = '',
  });

  factory KantorRole.fromJson(Map<String, dynamic> j) => KantorRole(
    id: _s(j['id']),
    name: _s(j['name']),
    title: _s(j['title']),
    model: _s(j['model'], 'sonnet'),
    room: _s(j['room']),
    persona: _s(j['persona']),
    skills: [
      for (final s in (j['skills'] as List?) ?? const [])
        if (s is String) s,
    ],
    notes: _s(j['notes']),
    isManager: j['isMgr'] == true,
    archived: j['archived'] == true,
    look: j,
    budget: j['budget'] is num ? (j['budget'] as num).toDouble() : null,
    reportsTo: j['reportsTo'] is String ? j['reportsTo'] as String : null,
    engine: _s(j['engine']) == 'codex' ? 'codex' : 'claude',
    effort: _s(j['effort']),
  );

  final String id;
  final String name;
  final String title;
  final String model;
  final String room;
  final String persona;
  final List<String> skills;
  final String notes;
  final bool isManager;
  final bool archived;
  final Map<String, dynamic> look;
  final double? budget;
  final String? reportsTo;

  /// `claude` (bawaan, juga untuk server lama) atau `codex`.
  final String engine;
  final String effort;
  bool get isCodex => engine == 'codex';

  /// Model untuk tampilan; role Codex tanpa model memakai bawaan Codex.
  String get modelText => isCodex
      ? [
          model.isEmpty ? 'Bawaan Codex' : model,
          if (effort.isNotEmpty) effort,
        ].join(' · ')
      : kantorModelName(model);
}

final class KantorRoom {
  const KantorRoom({
    required this.id,
    required this.name,
    required this.kind,
    this.path,
    this.frozen = false,
  });

  factory KantorRoom.fromJson(Map<String, dynamic> j) => KantorRoom(
    id: _s(j['id']),
    name: _s(j['name'], _s(j['id'])),
    kind: _s(j['kind']),
    path: j['path'] is String ? j['path'] as String : null,
    frozen: j['frozen'] == true || j['kind'] == 'beku',
  );

  final String id;
  final String name;
  final String kind;
  final String? path;
  final bool frozen;

  /// Rooms with no desk (shared spaces) cannot host a role.
  static const noDesk = ['lobby', 'openplan', 'toilet', 'booth', 'musik'];
  bool get hasDesk => !noDesk.contains(kind);
}

/// A live session as the office reports it (`status`: starting, working,
/// idle, waiting, ended).
final class KantorSessionInfo {
  const KantorSessionInfo({
    required this.sid,
    required this.role,
    required this.status,
    required this.title,
  });

  factory KantorSessionInfo.fromJson(Map<String, dynamic> j) =>
      KantorSessionInfo(
        sid: _s(j['sid']),
        role: j['role'] is String ? j['role'] as String : null,
        status: _s(j['status']),
        title: _s(j['title']),
      );

  final String sid;
  final String? role;
  final String status;
  final String title;
}

/// Office detail: rooms and live sessions (roles come from [kantorRolesProvider],
/// which also lists archived ones).
final class KantorOffice {
  const KantorOffice({
    required this.id,
    required this.name,
    required this.rooms,
    required this.sessions,
  });

  factory KantorOffice.fromJson(Map<String, dynamic> j) => KantorOffice(
    id: _s(j['id']),
    name: _s(j['name']),
    rooms: [
      for (final r in ((j['plan'] as Map?)?['rooms'] as List?) ?? const [])
        if (r is Map<String, dynamic>) KantorRoom.fromJson(r),
    ],
    sessions: [
      for (final s in (j['sessions'] as List?) ?? const [])
        if (s is Map<String, dynamic>) KantorSessionInfo.fromJson(s),
    ],
  );

  final String id;
  final String name;
  final List<KantorRoom> rooms;
  final List<KantorSessionInfo> sessions;

  String roomName(String? id) {
    for (final r in rooms) {
      if (r.id == id) return r.name;
    }
    return id ?? '';
  }

  List<KantorSessionInfo> liveSessionsOf(String roleId) => [
    for (final s in sessions)
      if (s.role == roleId && s.status != 'ended') s,
  ];
}

final kantorOfficeProvider = FutureProvider.autoDispose
    .family<KantorOffice, String>((ref, officeId) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null)
        throw const KantorException(
          KantorFailure.unauthorized,
          'Belum ada token',
        );
      final j = await api.get('/api/offices/${Uri.encodeComponent(officeId)}');
      return KantorOffice.fromJson((j as Map).cast<String, dynamic>());
    });

/// Every role of the office, archived ones included.
final kantorRolesProvider = FutureProvider.autoDispose
    .family<List<KantorRole>, String>((ref, officeId) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null)
        throw const KantorException(
          KantorFailure.unauthorized,
          'Belum ada token',
        );
      final j = await api.get(
        '/api/offices/${Uri.encodeComponent(officeId)}/roles',
      );
      return [
        for (final r in (j as List))
          if (r is Map) KantorRole.fromJson(r.cast<String, dynamic>()),
      ];
    });

/// Model ids offered when creating a role.
const kantorModelOptions = <(String, String)>[
  ('sonnet', 'Sonnet 5.5, kerja utama'),
  ('opus', 'Opus 5.5, perencanaan'),
  ('haiku', 'Haiku 5.5, tugas kecil'),
  ('fable', 'Fable 5.1, paling kuat'),
];

String kantorModelName(String id) => switch (id) {
  'opus' => 'Opus 5.5',
  'sonnet' => 'Sonnet 5.5',
  'haiku' => 'Haiku 5.5',
  'fable' => 'Fable 5.1',
  _ => id,
};

String kantorUsd(num? v, [int digits = 2]) =>
    '\$${(v ?? 0).toStringAsFixed(digits)}';

/// Indonesian short date + time, e.g. "21 Okt 14.05".
String kantorWhen(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${m[d.month - 1]} ${two(d.hour)}.${two(d.minute)}';
}

String kantorHhmm(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}.${two(d.minute)}';
}

/// "5 mnt lalu" style relative time.
String kantorAgo(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return 'baru saja';
  if (s < 3600) return '${s ~/ 60} mnt lalu';
  if (s < 86400) return '${s ~/ 3600} jam lalu';
  return '${s ~/ 86400} hari lalu';
}

/// Message for any failure, for toasts.
String kantorErrorText(Object e) =>
    e is KantorException ? e.message : 'Gagal: $e';
