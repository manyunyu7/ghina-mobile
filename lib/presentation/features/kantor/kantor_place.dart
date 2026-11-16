import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../di/kantor_providers.dart';

/// Where the owner last was inside one complex: an office with its tab and,
/// when a session was open, that session with its tab (chat, terminal, ...).
/// Holds ids only, never a token. Stored per complex profile id.
class KantorPlace {
  const KantorPlace({
    required this.office,
    this.tab,
    this.sid,
    this.sessionTab,
  });

  final String office;
  final String? tab;
  final String? sid;
  final String? sessionTab;

  /// At an office tab (no session open).
  factory KantorPlace.atOffice(String office, String? tab) =>
      KantorPlace(office: office, tab: _clean(tab));

  /// Inside a session. The office tab is kept when it is the same office.
  factory KantorPlace.atSession(
    KantorPlace? previous,
    String office,
    String sid,
    String? sessionTab,
  ) => KantorPlace(
    office: office,
    tab: previous?.office == office ? previous?.tab : null,
    sid: sid,
    sessionTab: _clean(sessionTab),
  );

  /// The same office and tab, after leaving the session.
  KantorPlace withoutSession() => KantorPlace(office: office, tab: tab);

  Map<String, dynamic> toJson() => {
    'office': office,
    if (tab != null) 'tab': tab,
    if (sid != null) 'sid': sid,
    if (sessionTab != null) 'sessionTab': sessionTab,
  };

  static KantorPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final office = raw['office'];
    if (office is! String || office.isEmpty) return null;
    final sid = raw['sid'];
    return KantorPlace(
      office: office,
      tab: _clean(raw['tab']),
      sid: sid is String && sid.isNotEmpty ? sid : null,
      sessionTab: _clean(raw['sessionTab']),
    );
  }

  static String? _clean(Object? v) =>
      v is String && RegExp(r'^[a-z]{1,20}$').hasMatch(v) ? v : null;

  @override
  bool operator ==(Object other) =>
      other is KantorPlace &&
      other.office == office &&
      other.tab == tab &&
      other.sid == sid &&
      other.sessionTab == sessionTab;

  @override
  int get hashCode => Object.hash(office, tab, sid, sessionTab);
}

/// Pure: the routes to open for [place] given the daemon's `/api/state`, outer
/// route first (the office, then the session on top of it). Falls back to the
/// nearest level that still exists: session gone -> the office and its tab;
/// office gone or no place -> empty (the complex page).
List<String> kantorResumePaths(KantorPlace? place, Map<String, dynamic> state) {
  if (place == null) return const [];
  Map? office;
  for (final o in state['offices'] as List? ?? const []) {
    if (o is Map && o['id'] == place.office) office = o;
  }
  if (office == null) return const [];
  final base = '/kantor/o/${Uri.encodeComponent(place.office)}';
  final paths = <String>[place.tab == null ? base : '$base?tab=${place.tab}'];
  final sid = place.sid;
  if (sid != null) {
    final live = (office['sessions'] as List? ?? const []).any(
      (s) => s is Map && s['sid'] == sid && s['status'] != 'ended',
    );
    if (live) {
      paths.add(
        '$base/s/${Uri.encodeComponent(sid)}'
        '${place.sessionTab == null ? '' : '?tab=${place.sessionTab}'}',
      );
    }
  }
  return paths;
}

/// Persistence of [KantorPlace] per complex profile id.
class KantorPlaceStore {
  static const _prefix = 'kantor.place.v1.';
  static Future<void> _queue = Future.value();

  static Future<KantorPlace?> load(String profileId) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        '$_prefix$profileId',
      );
      return raw == null ? null : KantorPlace.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Read-modify-write, serialized so quick successive page opens cannot
  /// overwrite each other.
  static Future<void> update(
    String profileId,
    KantorPlace? Function(KantorPlace? previous) change,
  ) => _queue = _queue.then((_) async {
    try {
      final next = change(await load(profileId));
      if (next == null) return;
      await (await SharedPreferences.getInstance()).setString(
        '$_prefix$profileId',
        jsonEncode(next.toJson()),
      );
    } catch (_) {}
  });
}

/// The saved place of one complex profile (null when none or unreadable).
final kantorSavedPlaceProvider = FutureProvider.autoDispose
    .family<KantorPlace?, String>(
      (ref, profileId) => KantorPlaceStore.load(profileId),
    );

/// Records the office tab being viewed in the active complex.
void rememberKantorOfficePlace(WidgetRef ref, String office, String? tab) {
  final id = ref.read(kantorActiveComplexProvider)?.id;
  if (id == null) return;
  KantorPlaceStore.update(id, (_) => KantorPlace.atOffice(office, tab));
}

/// Records the session (and its tab) being viewed in the active complex.
void rememberKantorSessionPlace(
  WidgetRef ref,
  String office,
  String sid,
  String? sessionTab,
) {
  final id = ref.read(kantorActiveComplexProvider)?.id;
  if (id == null) return;
  KantorPlaceStore.update(
    id,
    (prev) => KantorPlace.atSession(prev, office, sid, sessionTab),
  );
}

/// The owner backed out of a session: next time, land on its office instead.
void forgetKantorSessionPlace(WidgetRef ref) {
  final id = ref.read(kantorActiveComplexProvider)?.id;
  if (id == null) return;
  KantorPlaceStore.update(id, (prev) => prev?.withoutSession());
}
