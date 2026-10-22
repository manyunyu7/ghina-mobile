/// Logic of the "Kantor baru" wizard, kept free of widgets: the presets, the
/// folder-name rule and the spec the daemon's `/api/wizard/*` expects. Mirrors
/// `web/js/wizard.js` in the kantor-claude repo.
library;

const kantorManagerNames = [
  'Bu Ratna',
  'Pak Hendra',
  'Bu Sari',
  'Pak Bima',
  'Bu Laras',
  'Pak Danu',
];

const kantorModels = [
  ('opus', 'Opus 5.5'),
  ('sonnet', 'Sonnet 5.5'),
  ('haiku', 'Haiku 5.5'),
  ('fable', 'Fable 5.1'),
];

/// Permission modes a shift can start with ('' = follow Claude's own setting).
const kantorPermModes = [
  ('', 'Ikuti pengaturan Claude'),
  ('default', 'Selalu tanya'),
  ('acceptEdits', 'Edit file otomatis (acceptEdits)'),
  ('auto', 'Auto mode'),
  ('plan', 'Hanya merencanakan (plan)'),
  ('bypassPermissions', 'Lewati semua izin'),
];

const kantorSubSuggestions = ['api', 'web', 'mobile', 'admin', 'docs', 'infra'];

class KantorRolePreset {
  const KantorRolePreset({
    required this.key,
    required this.name,
    required this.title,
    required this.model,
    required this.like,
    required this.persona,
    required this.skills,
  });

  final String key, name, title, model, persona;

  /// Matched against room folder names to pick the room this role sits in.
  final RegExp like;
  final List<String> skills;
}

final kantorPresets = [
  KantorRolePreset(
    key: 'generalis',
    name: 'Tari',
    title: 'Generalis',
    model: 'sonnet',
    like: RegExp('.'),
    persona:
        'Serba bisa dan cepat belajar. Membaca CLAUDE.md dan wiki kantor sebelum mulai.',
    skills: const [],
  ),
  KantorRolePreset(
    key: 'frontend',
    name: 'Dimas',
    title: 'Frontend',
    model: 'sonnet',
    like: RegExp('web|front|ui|admin|site|app'),
    persona:
        'Peduli detail tampilan dan aksesibilitas. Selalu cek hasilnya di browser sebelum bilang selesai.',
    skills: const ['frontend', 'css', 'aksesibilitas'],
  ),
  KantorRolePreset(
    key: 'backend',
    name: 'Arya',
    title: 'Backend',
    model: 'sonnet',
    like: RegExp('api|back|server|service|core'),
    persona:
        'Teliti soal data dan kontrak API. Menulis tes untuk setiap perubahan logika.',
    skills: const ['backend', 'database', 'testing'],
  ),
  KantorRolePreset(
    key: 'mobile',
    name: 'Wulan',
    title: 'Mobile',
    model: 'sonnet',
    like: RegExp('mobile|android|ios|flutter|app'),
    persona:
        'Memikirkan pengguna di HP dengan sinyal jelek. Rapi soal versi rilis.',
    skills: const ['mobile', 'rilis'],
  ),
  KantorRolePreset(
    key: 'qa',
    name: 'Seno',
    title: 'QA',
    model: 'haiku',
    like: RegExp('test|qa'),
    persona:
        'Skeptis. Menganggap fitur rusak sampai terbukti sebaliknya, dan menulis temuan sebagai komentar kartu.',
    skills: const ['review', 'testing'],
  ),
  KantorRolePreset(
    key: 'devops',
    name: 'Raka',
    title: 'DevOps',
    model: 'sonnet',
    like: RegExp('infra|deploy|ops|docker'),
    persona:
        'Hati-hati di server. Tidak pernah restart atau mengubah config produksi tanpa persetujuan.',
    skills: const ['devops', 'deploy'],
  ),
  KantorRolePreset(
    key: 'docs',
    name: 'Lintang',
    title: 'Dokumentasi',
    model: 'haiku',
    like: RegExp('docs|doc|wiki'),
    persona: 'Menulis jelas dan ringkas. Menjaga wiki kantor sesuai kode.',
    skills: const ['dokumentasi'],
  ),
];

const kantorManagerPersona =
    'Teliti dan tenang. Memecah permintaan jadi kartu di board, menunjuk role yang tepat, dan mereview hasilnya sebelum dianggap selesai.';

/// Folder name from a project name: lowercase, `[a-z0-9._-]`, max 60.
String kantorSlugDir(String s) {
  final t = s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return t.length > 60 ? t.substring(0, 60) : t;
}

String kantorTilde(String p) => p.replaceFirst(RegExp(r'^/Users/[^/]+'), '~');

/// One person of the new team, in the shape `wizard/preview` and `create` read.
Map<String, dynamic> kantorTeamMember(
  KantorRolePreset p,
  List<Map<String, dynamic>> rooms,
) {
  final room = rooms.firstWhere(
    (r) => p.like.hasMatch('${r['path'] ?? ''} ${r['name']}'.toLowerCase()),
    orElse: () => rooms.isEmpty ? const {} : rooms.first,
  );
  return {
    'key': p.key,
    'name': p.name,
    'title': p.title,
    'model': p.model,
    'persona': p.persona,
    'skills': p.skills,
    'room': room['id'] ?? '',
  };
}

Map<String, dynamic> kantorManagerMember(String name) => {
  'key': 'manager',
  'isMgr': true,
  'name': name,
  'title': 'Manager',
  'model': 'opus',
  'persona': kantorManagerPersona,
  'skills': ['delegasi', 'review'],
};
