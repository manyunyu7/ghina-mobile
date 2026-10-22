import 'dart:math' as math;

/// Character look vocabulary, a port of the web `chars.js` (same ids, so a
/// role edited on either side renders the same).
const kantorHairStyles = <String, String>{
  'short': 'Pendek',
  'long': 'Panjang',
  'ponytail': 'Kuncir kuda',
  'bob': 'Bob',
  'bun': 'Cepol',
  'pigtails': 'Kuncir dua',
  'curly': 'Keriting',
  'hijab': 'Hijab',
};
const kantorOutfits = <String, String>{
  'kemeja': 'Kemeja + celana',
  'rok': 'Blus + rok',
  'dress': 'Dress',
  'hoodie': 'Hoodie',
  'jas': 'Jas',
};
const kantorAccessories = <String, String>{
  '': 'Tanpa aksesori',
  'kacamata': 'Kacamata',
  'anting': 'Anting',
  'topi': 'Topi',
};

const kantorSwatches = [
  '#2F5D9E',
  '#2C8452',
  '#A9620F',
  '#7A3E9D',
  '#BC3B34',
  '#1C7379',
  '#55606E',
  '#C2417A',
];
const kantorSkins = ['#F1C9A5', '#D9A47C', '#B97E57', '#8D5A3B', '#E8B98F'];
const kantorHairColors = [
  '#2B1D14',
  '#5A3A22',
  '#1E1E24',
  '#7A4B2A',
  '#C9A15A',
  '#3D2B4F',
];
const kantorHijabs = [
  '#E8EEF8',
  '#2F5D9E',
  '#C2417A',
  '#2C8452',
  '#7A3E9D',
  '#F2D7DC',
  '#55606E',
  '#1F1F26',
];

const _lookKeys = [
  'color',
  'hair',
  'skin',
  'hairStyle',
  'outfit',
  'acc',
  'hijab',
  'tie',
];

/// A mutable look being edited.
final class KantorLook {
  KantorLook({
    this.color = '#2F5D9E',
    this.hair = '#2B1D14',
    this.skin = '#F1C9A5',
    this.hairStyle = 'short',
    this.outfit = 'kemeja',
    this.acc = '',
    this.hijab = '#E8EEF8',
    this.tie = false,
  });

  factory KantorLook.fromJson(Map<String, dynamic> j) {
    String s(String k, String d) {
      final v = j[k];
      return v is String && v.isNotEmpty ? v : d;
    }

    return KantorLook(
      color: s('color', kantorSwatches[0]),
      hair: s('hair', kantorHairColors[0]),
      skin: s('skin', kantorSkins[0]),
      hairStyle: s('hairStyle', 'short'),
      outfit: s('outfit', 'kemeja'),
      acc: j['acc'] is String ? j['acc'] as String : '',
      hijab: s('hijab', kantorHijabs[0]),
      tie: j['tie'] == true,
    );
  }

  String color, hair, skin, hairStyle, outfit, acc, hijab;
  bool tie;

  /// A hijab never goes with a cap.
  void normalize() {
    if (hairStyle == 'hijab' && acc == 'topi') acc = '';
  }

  void apply(KantorLook o) {
    color = o.color;
    hair = o.hair;
    skin = o.skin;
    hairStyle = o.hairStyle;
    outfit = o.outfit;
    acc = o.acc;
    hijab = o.hijab;
    tie = o.tie;
    normalize();
  }

  KantorLook copy() => KantorLook()..apply(this);

  Map<String, dynamic> toJson() => {
    for (final k in _lookKeys)
      k: switch (k) {
        'color' => color,
        'hair' => hair,
        'skin' => skin,
        'hairStyle' => hairStyle,
        'outfit' => outfit,
        'acc' => acc,
        'hijab' => hijab,
        _ => tie,
      },
  };
}

final class KantorLookTemplate {
  const KantorLookTemplate(this.name, this.look);
  final String name;
  final KantorLook Function() look;
}

KantorLook _t(
  String hairStyle,
  String outfit,
  String acc,
  String color,
  String hair,
  String skin, {
  String hijab = '#E8EEF8',
  bool tie = false,
}) => KantorLook(
  hairStyle: hairStyle,
  outfit: outfit,
  acc: acc,
  color: color,
  hair: hair,
  skin: skin,
  hijab: hijab,
  tie: tie,
);

/// One-tap looks, same set as the web "Template karakter".
final kantorLookTemplates = <KantorLookTemplate>[
  KantorLookTemplate(
    'Hijab biru',
    () => _t(
      'hijab',
      'dress',
      '',
      '#7A3E9D',
      '#2B1D14',
      '#D9A47C',
      hijab: '#2F5D9E',
    ),
  ),
  KantorLookTemplate(
    'Hijab pastel',
    () => _t(
      'hijab',
      'jas',
      'kacamata',
      '#55606E',
      '#2B1D14',
      '#F1C9A5',
      hijab: '#F2D7DC',
    ),
  ),
  KantorLookTemplate(
    'Rambut panjang',
    () => _t('long', 'kemeja', 'anting', '#C2417A', '#2B1D14', '#E8B98F'),
  ),
  KantorLookTemplate(
    'Kuncir kuda',
    () => _t('ponytail', 'rok', '', '#1C7379', '#5A3A22', '#F1C9A5'),
  ),
  KantorLookTemplate(
    'Bob',
    () => _t('bob', 'jas', 'anting', '#BC3B34', '#1E1E24', '#D9A47C'),
  ),
  KantorLookTemplate(
    'Cepol',
    () => _t('bun', 'dress', '', '#2C8452', '#3D2B4F', '#B97E57'),
  ),
  KantorLookTemplate(
    'Kuncir dua',
    () => _t('pigtails', 'hoodie', '', '#C2417A', '#C9A15A', '#F1C9A5'),
  ),
  KantorLookTemplate(
    'Keriting',
    () => _t('curly', 'rok', 'kacamata', '#A9620F', '#2B1D14', '#8D5A3B'),
  ),
  KantorLookTemplate(
    'Rok kantor',
    () => _t('long', 'rok', 'anting', '#2F5D9E', '#7A4B2A', '#D9A47C'),
  ),
  KantorLookTemplate(
    'Sporty',
    () => _t('ponytail', 'hoodie', 'topi', '#BC3B34', '#1E1E24', '#E8B98F'),
  ),
  KantorLookTemplate(
    'Berkacamata',
    () => _t('short', 'kemeja', 'kacamata', '#2F5D9E', '#1E1E24', '#E8B98F'),
  ),
  KantorLookTemplate(
    'Hoodie',
    () => _t('short', 'hoodie', '', '#55606E', '#7A4B2A', '#B97E57'),
  ),
  KantorLookTemplate(
    'Manager berdasi',
    () => _t('short', 'jas', '', '#2F5D9E', '#2B1D14', '#D9A47C', tie: true),
  ),
  KantorLookTemplate(
    'Klasik',
    () => _t('short', 'kemeja', '', '#2C8452', '#5A3A22', '#F1C9A5'),
  ),
  KantorLookTemplate(
    'Bertopi',
    () => _t('short', 'kemeja', 'topi', '#A9620F', '#7A4B2A', '#8D5A3B'),
  ),
];

/// A balanced random look: about half feminine, hijab never with a cap.
KantorLook kantorRandomLook([math.Random? rng]) {
  final r = rng ?? math.Random();
  T pick<T>(List<T> a) => a[r.nextInt(a.length)];
  T weighted<T>(List<(T, double)> pairs) {
    var t = pairs.fold<double>(0, (s, p) => s + p.$2) * r.nextDouble();
    for (final p in pairs) {
      t -= p.$2;
      if (t < 0) return p.$1;
    }
    return pairs.first.$1;
  }

  final fem = r.nextBool();
  final hairStyle = fem
      ? weighted([
          ('long', 3.0),
          ('ponytail', 3.0),
          ('bob', 3.0),
          ('bun', 2.0),
          ('pigtails', 2.0),
          ('curly', 2.0),
          ('hijab', 2.2),
          ('short', .6),
        ])
      : weighted([('short', 8.0), ('curly', 1.0)]);
  final outfit = fem
      ? weighted([
          ('rok', 3.0),
          ('dress', 3.0),
          ('jas', 2.0),
          ('kemeja', 2.0),
          ('hoodie', 1.5),
        ])
      : weighted([('kemeja', 5.0), ('hoodie', 2.0), ('jas', 2.0)]);
  final acc = weighted(
    fem
        ? [('', 4.0), ('anting', 3.0), ('kacamata', 2.0), ('topi', 1.0)]
        : [('', 5.0), ('kacamata', 2.5), ('topi', 1.5)],
  );
  final color = pick(kantorSwatches);
  final tie =
      !fem &&
      (outfit == 'jas'
          ? r.nextDouble() < .7
          : outfit == 'kemeja' && r.nextDouble() < .3);
  return KantorLook(
    hairStyle: hairStyle,
    outfit: outfit,
    acc: acc,
    color: color,
    skin: pick(kantorSkins),
    hair: pick(kantorHairColors),
    hijab: pick([
      for (final h in kantorHijabs)
        if (h.toLowerCase() != color.toLowerCase()) h,
    ]),
    tie: tie,
  )..normalize();
}
