/// Small helpers shared by the Kantor wiki, notes and payroll tabs.
library;

const _months = [
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

/// "baru saja", "5 menit lalu", "2 hari lalu", else "12 Okt 2026".
String agoId(Object? iso) {
  final t = iso is String ? DateTime.tryParse(iso)?.toLocal() : null;
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  if (d.inDays < 7) return '${d.inDays} hari lalu';
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

final _taskLine = RegExp(
  r'^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])',
  multiLine: true,
);

/// How many `- [ ]` items the markdown has.
int taskCount(String src) => _taskLine.allMatches(src).length;

/// Flip the [n]th `- [ ]` item (0-based), like the web's `toggleTask`.
String toggleTask(String src, int n) {
  var i = -1;
  return src.replaceAllMapped(_taskLine, (m) {
    i++;
    if (i != n) return m[0]!;
    return '${m[1]}${m[2] == ' ' ? 'x' : ' '}${m[3]}';
  });
}

/// Same slug rule as the daemon / web (`slugify`).
String slugify(String s) {
  const from = 'àáâãäåèéêëìíîïòóôõöùúûüñç';
  const to = 'aaaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final k = from.indexOf(c);
    b.write(k >= 0 ? to[k] : c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// One diff line: `+`, `-` or ` ` plus its text.
typedef DiffOp = ({String k, String t});

/// Line diff (LCS), same as the web's history view.
List<DiffOp> lineOps(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  final n = x.length, m = y.length;
  if (n * m > 4000000) {
    return [
      for (final t in x) (k: '-', t: t),
      for (final t in y) (k: '+', t: t),
    ];
  }
  final l = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      l[i][j] = x[i] == y[j]
          ? l[i + 1][j + 1] + 1
          : (l[i + 1][j] > l[i][j + 1] ? l[i + 1][j] : l[i][j + 1]);
    }
  }
  final ops = <DiffOp>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (x[i] == y[j]) {
      ops.add((k: ' ', t: x[i]));
      i++;
      j++;
    } else if (l[i + 1][j] >= l[i][j + 1]) {
      ops.add((k: '-', t: x[i++]));
    } else {
      ops.add((k: '+', t: y[j++]));
    }
  }
  while (i < n) {
    ops.add((k: '-', t: x[i++]));
  }
  while (j < m) {
    ops.add((k: '+', t: y[j++]));
  }
  return ops;
}
