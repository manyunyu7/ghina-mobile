// Small text helpers shared by Kantor screens (ports of the web `util.js`).

String kantorAgo(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  if (t == null) return '';
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return 'baru saja';
  if (s < 3600) return '${s ~/ 60} mnt lalu';
  if (s < 86400) return '${s ~/ 3600} jam lalu';
  if (s < 86400 * 7) return '${s ~/ 86400} hari lalu';
  final l = t.toLocal();
  return '${l.day}/${l.month}';
}

String kantorUsd(Object? v, [int decimals = 2]) {
  final n = (v is num ? v : num.tryParse('$v') ?? 0).toDouble();
  final fixed = n.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '\$${parts.length > 1 ? '$whole.${parts[1]}' : whole}';
}

String kantorShort(Object? s, [int n = 38]) {
  final t = '${s ?? ''}';
  return t.length > n ? '${t.substring(0, n - 1)}…' : t;
}

/// Line shown under a session: waiting, current tool, or idle/working.
String kantorSessionLabel(Map<String, dynamic> s) {
  final w = s['waiting'];
  if (w is Map) return 'menunggu izin: ${w['tool'] ?? ''}';
  final tool = s['tool'];
  if (tool is Map) return '${tool['name'] ?? ''} ${tool['label'] ?? ''}'.trim();
  if (s['title'] == 'Sesi belum terhubung') return 'belum terhubung';
  return s['status'] == 'working' ? 'bekerja' : 'idle';
}

/// Sort key for agent lists: waiting first, then working, then the rest.
int kantorSessionRank(Map<String, dynamic> s) =>
    s['waiting'] != null ? 0 : (s['status'] == 'working' ? 1 : 2);
