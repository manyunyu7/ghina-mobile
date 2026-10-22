import '../../../design_system/design_system.dart';

/// Helpers + the phone-side series store for "Performa PC".
/// Contract: FRONTEND-CONTRACT "Performa PC (sysmon)".

double? sysNum(Object? v) => v is num ? v.toDouble() : null;
Map sysMap(Object? v) => v is Map ? v : const {};
List sysList(Object? v) => v is List ? v : const [];

String _dec(double x, int d) => x.toStringAsFixed(d).replaceAll('.', ',');

/// "18,4 GB" (binary units, Indonesian decimal comma).
String sysmonBytes(Object? v, {bool rate = false}) {
  final n = sysNum(v);
  if (n == null) return '–';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var x = n.abs(), u = 0;
  while (x >= 1024 && u < units.length - 1) {
    x /= 1024;
    u++;
  }
  final s = u == 0 || x >= 100 ? _dec(x, 0) : _dec(x, 1);
  return '${n < 0 ? '-' : ''}$s ${units[u]}${rate ? '/dtk' : ''}';
}

String sysmonPct(Object? v, {int d = 0}) {
  final n = sysNum(v);
  return n == null ? '–' : '${_dec(n, d)}%';
}

String sysmonFixed(Object? v, [int d = 1]) {
  final n = sysNum(v);
  return n == null ? '–' : _dec(n, d);
}

/// 12.345 style thousands separator.
String sysmonInt(Object? v) {
  final n = sysNum(v);
  if (n == null) return '–';
  final s = n.round().abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String sysmonUptime(Object? sec) {
  final s = sysNum(sec)?.toInt() ?? 0;
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  if (d > 0) return '$d hari $h jam';
  if (h > 0) return '$h jam $m mnt';
  return '$m mnt';
}

String sysmonMinutes(Object? min) {
  final m = sysNum(min)?.toInt();
  if (m == null) return '–';
  return m >= 60 ? '${m ~/ 60} j ${m % 60} m' : '$m mnt';
}

String sysmonClock(int ms, {bool seconds = false}) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}${seconds ? ':${two(d.second)}' : ''}';
}

String sysmonAgo(int ms) {
  final s = DateTime.now().millisecondsSinceEpoch - ms;
  if (s < 60e3) return 'barusan';
  if (s < 3600e3) return '${s ~/ 60000} mnt lalu';
  if (s < 86400e3) return '${s ~/ 3600000} jam lalu';
  return '${s ~/ 86400000} hari lalu';
}

ChunkySwatch sysmonColor(double p) => p >= 90
    ? GhinaColors.red
    : p >= 75
    ? GhinaColors.orange
    : p >= 50
    ? GhinaColors.yellow
    : GhinaColors.green;

ChunkySwatch sysmonLevelColor(Object? level) => switch (level) {
  'bad' || 'buruk' || 'kritis' => GhinaColors.red,
  'warn' || 'waspada' || 'dibatasi' => GhinaColors.orange,
  'ok' || 'baik' || 'normal' => GhinaColors.green,
  _ => GhinaColors.blue,
};

ChunkySwatch sysmonScoreColor(double s) => s >= 80
    ? GhinaColors.green
    : s >= 55
    ? GhinaColors.orange
    : GhinaColors.red;

/// Chart time ranges.
enum SysRange {
  m5('5m', 5),
  m15('15m', 15),
  h1('1j', 60),
  h24('24j', 1440);

  const SysRange(this.label, this.min);
  final String label;
  final int min;
}

/// Parallel time series: `t` (ms) + named value lists (null = no sample).
class SysSeries {
  SysSeries([this.cap = 800]);
  final int cap;
  final t = <int>[];
  final s = <String, List<double?>>{};
  int step = 5;

  bool get isEmpty => t.isEmpty;
  List<double?> operator [](String k) => s[k] ?? const [];

  void fill(Map h) {
    t.clear();
    s.clear();
    step = sysNum(h['step'])?.toInt() ?? 5;
    final ts = sysList(h['t']);
    for (final e in h.entries) {
      if (e.key == 't' || e.value is! List) continue;
      s['${e.key}'] = [for (final v in e.value as List) sysNum(v)];
    }
    for (final x in ts) {
      t.add(sysNum(x)?.toInt() ?? 0);
    }
    for (final l in s.values) {
      while (l.length < t.length) {
        l.add(null);
      }
    }
  }

  void add(int at, Map<String, double?> v) {
    if (t.isNotEmpty && at <= t.last) return;
    t.add(at);
    for (final k in {...s.keys, ...v.keys}) {
      final l = s.putIfAbsent(
        k,
        () => List<double?>.filled(t.length - 1, null, growable: true),
      );
      l.add(v[k]);
    }
    if (t.length > cap) {
      t.removeAt(0);
      for (final l in s.values) {
        if (l.isNotEmpty) l.removeAt(0);
      }
    }
  }

  /// Copy restricted to the last [min] minutes.
  SysSeries window(int min) {
    final out = SysSeries(cap)..step = step;
    if (t.isEmpty) return out;
    final from = t.last - min * 60000;
    var i = 0;
    while (i < t.length && t[i] < from) {
      i++;
    }
    out.t.addAll(t.sublist(i));
    for (final e in s.entries) {
      out.s[e.key] = e.value.length > i ? e.value.sublist(i) : <double?>[];
    }
    return out;
  }

  int get coreCount =>
      s.keys.where((k) => RegExp(r'^c\d+$').hasMatch(k)).length;
}

/// Everything the snapshot exposes, as a live point for [SysSeries].
Map<String, double?> sysPointFromSnapshot(Map s) {
  final cpu = sysMap(s['cpu']), mem = sysMap(s['mem']);
  final net = sysMap(s['net']), dio = sysMap(s['diskio']);
  final load = sysList(s['load']);
  final cores = sysList(cpu['cores']);
  return {
    'cpu': sysNum(cpu['total']),
    'user': sysNum(cpu['user']),
    'sys': sysNum(cpu['sys']),
    'ram': sysNum(mem['pct']),
    'swap': _mb(sysMap(mem['swap'])['used']),
    'comp': _mb(mem['compressed']),
    'rx': sysNum(net['rx']),
    'tx': sysNum(net['tx']),
    'dr': sysNum(dio['read']),
    'dw': sysNum(dio['write']),
    'gpu': sysNum(sysMap(s['gpu'])['util']),
    'batt': sysNum(sysMap(s['battery'])['pct']),
    'agents': sysNum(sysMap(s['agents'])['cpu']),
    'load': load.isEmpty ? null : sysNum(load.first),
    'score': sysNum(sysMap(s['health'])['score']),
    for (var i = 0; i < cores.length; i++) 'c$i': sysNum(cores[i]),
  };
}

double? _mb(Object? b) {
  final n = sysNum(b);
  return n == null ? null : n / 1048576;
}

/// Merges a `{t:'sysmon'}` live event into the last snapshot.
Map<String, dynamic> sysMergeLive(Map<String, dynamic> s, Map e) {
  final mem = Map<String, dynamic>.from(sysMap(s['mem']));
  final em = sysMap(e['mem']);
  for (final k in [
    'pct',
    'used',
    'total',
    'app',
    'wired',
    'compressed',
    'cached',
    'pressure',
    'rates',
  ]) {
    if (em.containsKey(k)) mem[k] = em[k];
  }
  if (em['swapUsed'] != null && mem['swap'] is Map) {
    mem['swap'] = {...(mem['swap'] as Map), 'used': em['swapUsed']};
  }
  if (sysNum(mem['total']) != null && sysNum(mem['used']) != null) {
    mem['free'] = sysNum(mem['total'])! - sysNum(mem['used'])!;
  }
  final split = sysMap(e['split']);
  return {
    ...s,
    'at': e['at'],
    'cpu': {
      ...sysMap(s['cpu']),
      'total': e['cpu'],
      'cores': e['cores'],
      ...split,
    },
    'load': e['load'] ?? s['load'],
    'mem': mem,
    if (e['net'] != null) 'net': {...sysMap(s['net']), ...sysMap(e['net'])},
    if (e['disk'] != null)
      'diskio': {...sysMap(s['diskio']), ...sysMap(e['disk'])},
    if (e['gpu'] != null) 'gpu': {...sysMap(s['gpu']), ...sysMap(e['gpu'])},
    if (e['batt'] != null && s['battery'] != null)
      'battery': {...sysMap(s['battery']), ...sysMap(e['batt'])},
    if (e['agents'] != null)
      'agents': {...sysMap(s['agents']), ...sysMap(e['agents'])},
    if (e['health'] != null)
      'health': {...sysMap(s['health']), ...sysMap(e['health'])},
    if (e['top'] != null) 'top': e['top'],
    'alerts': e['alerts'] ?? s['alerts'],
  };
}

const sysmonHistorySeries =
    'cpu,user,sys,ram,swap,comp,rx,tx,dr,dw,gpu,batt,agents,load,score,cores';
