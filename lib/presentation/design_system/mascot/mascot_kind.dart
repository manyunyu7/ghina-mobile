import 'package:flutter/widgets.dart';

/// Which mascot the user picked. Every [MascotView] without an explicit
/// `kind` paints the one from the nearest [MascotChoice].
enum MascotKind {
  pohon(
    'pohon',
    'Pohon Uang',
    'Maskot asli Ghina: daunnya makin rimbun tiap tabunganmu nambah, '
        'koinnya jatuh pas target tercapai.',
  ),
  ayam(
    'ayam',
    'Celengan Ayam',
    'Celengan tanah liat bentuk ayam. Perutnya makin penuh kalau kamu rajin '
        'nabung, pas banget buat fitur tabungan.',
  ),
  kucing(
    'kucing',
    'Kucing Oren',
    'Si oren yang suka nyindir halus: "Jajan kopi lagi?" Paling cocok buat '
        'pengingat yang lucu tapi nempel.',
  ),
  kapibara(
    'kapibara',
    'Kapibara',
    'Tenang banget, nggak gampang panik. Cocok buat bikin orang betah ngecek '
        'keuangan tanpa stres.',
  ),
  loko(
    'loko',
    'Lokomotif Mungil',
    'Bikin keuanganmu tetap "on track". Nomor 168 di dadanya nyambung ke '
        'dunia 168Railway.',
  ),
  bibit(
    'bibit',
    'Bibit',
    'Mulai dari tunas kecil, daunnya tumbuh ikut level dan streak. Progres '
        'kelihatan, bukan cuma angka.',
  ),
  koin(
    'koin',
    'Koin',
    'Sekeping rupiah yang punya kaki. Langsung kebaca "ini app duit" dan '
        'gampang dijadiin stiker.',
  ),
  hantu(
    'hantu',
    'Burung Hantu',
    'Si bijak berkacamata. Pas buat analitik, laporan bulanan, dan Killa '
        'waktu ngasih saran.',
  ),
  kura(
    'kura',
    'Kura-kura',
    'Pelan tapi pasti. Simbol nabung konsisten, cocok buat target jangka '
        'panjang dan investasi.',
  ),
  dompet(
    'dompet',
    'Dompet',
    'Dompet kulit yang jalan-jalan. Kartunya nyembul dikit, uangnya ikut '
        'senyum kalau kamu hemat.',
  ),
  beluga(
    'beluga',
    'Beluga',
    'Paus putih yang kalem dengan dahi bulat besar. Pas jadi suara Killa: '
        'ngobrol pelan, nggak pernah bikin panik.',
  ),
  hiuPaus(
    'hiupaus',
    'Hiu Paus',
    'Raksasa yang lembut. Badannya besar tapi santai, cocok nemenin target '
        'tabungan jangka panjang yang nominalnya gede.',
  ),
  komodo(
    'komodo',
    'Komodo',
    'Asli Indonesia, tangguh, dan galak sama pengeluaran nggak penting. '
        'Penjaga budget yang anti boros.',
  ),
  orangutan(
    'orangutan',
    'Orangutan',
    'Santai dan suka bantu. Lengannya panjang, siap ngeraih tugas yang '
        'numpuk satu per satu.',
  ),
  cendrawasih(
    'cendrawasih',
    'Cendrawasih',
    'Burung surga dari Papua. Bulunya mekar tiap kamu capai target, pas buat '
        'momen rayakan pencapaian.',
  );

  const MascotKind(this.id, this.label, this.pitch);

  /// Stable id for storage (never rename).
  final String id;

  /// Indonesian display name.
  final String label;

  /// One-line pitch shown in the picker.
  final String pitch;

  /// The default (and the original look): the money tree.
  static const fallback = MascotKind.pohon;

  /// Unknown / null ids fall back to [fallback].
  static MascotKind fromId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return fallback;
  }
}

/// The mascot every [MascotView] below paints (unless it has an explicit
/// `kind`). The app root places one, fed by the saved preference; the design
/// system stays Riverpod-free.
///
/// ```dart
/// MascotChoice(kind: MascotKind.kucing, child: app);
/// MascotChoice.of(context); // MascotKind.pohon without an ancestor
/// ```
class MascotChoice extends InheritedWidget {
  const MascotChoice({super.key, required this.kind, required super.child});

  final MascotKind kind;

  static MascotKind of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotChoice>()?.kind ??
      MascotKind.fallback;

  @override
  bool updateShouldNotify(MascotChoice old) => old.kind != kind;
}
