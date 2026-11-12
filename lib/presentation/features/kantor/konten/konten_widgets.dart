import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'konten_data.dart';
import 'konten_model.dart';

/// Gambar dari kantor dengan header auth; mengganti dirinya dengan penanda
/// kalau berkas hilang atau belum ada.
class KontenImage extends StatelessWidget {
  const KontenImage({
    super.key,
    required this.repo,
    required this.url,
    this.fit = BoxFit.cover,
  });

  final KontenRepo repo;
  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final placeholder = Container(
      color: g.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: g.textMuted),
    );
    final u = url;
    if (u == null || u.isEmpty) return placeholder;
    return Image.network(
      repo.uri(u).toString(),
      headers: repo.headers,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (_, child, prog) => prog == null ? child : placeholder,
    );
  }
}

/// Warna pil per tahap.
ChunkySwatch kontenStageColor(String tahap) => switch (tahap) {
  'review' => GhinaColors.orange,
  'revisi' => GhinaColors.red,
  'siap' => GhinaColors.blue,
  'terjadwal' => GhinaColors.purple,
  'tayang' => GhinaColors.green,
  'arsip' => GhinaColors.gray,
  _ => GhinaColors.teal,
};

String kontenStageName(KontenItem i) =>
    i.tahapNama.isNotEmpty ? i.tahapNama : i.tahap;

class KontenStagePill extends StatelessWidget {
  const KontenStagePill(this.item, {super.key});
  final KontenItem item;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: kontenStageName(item),
    color: kontenStageColor(item.tahap),
    soft: true,
  );
}

const _bulan = [
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
const _hari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// "Sen, 3 Nov".
String kontenDateLabel(DateTime d) =>
    '${_hari[d.weekday - 1]}, ${d.day} ${_bulan[d.month - 1]}';

/// Keadaan kosong ramah, termasuk untuk server lama yang belum punya Konten.
class KontenEmpty extends StatelessWidget {
  const KontenEmpty({super.key, required this.title, this.message});
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: GhinaSpace.xl),
      EmptyState(title: title, message: message, mascotSize: 100),
    ],
  );
}

const kontenUnsupportedTitle = 'Konten belum aktif di kantor ini';
const kontenUnsupportedMessage =
    'Server kantor belum punya fitur Konten. Setelah diperbarui, isinya muncul di sini.';

/// Status posting per platform: hijau sudah tayang, abu-abu belum.
class KontenPlatformBadges extends StatelessWidget {
  const KontenPlatformBadges(this.item, {super.key});
  final KontenItem item;

  static const _short = {
    'instagram': 'IG',
    'threads': 'TH',
    'tiktok': 'TT',
    'youtube': 'YT',
  };

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final p in item.targets)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: item.platforms.containsKey(p)
                  ? GhinaColors.green.base.withValues(alpha: .18)
                  : g.surfaceAlt,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _short[p] ?? p,
              style: GhinaType.caption
                  .w(800)
                  .copyWith(
                    fontSize: 10,
                    color: item.platforms.containsKey(p)
                        ? GhinaColors.green.edge
                        : g.textMuted,
                  ),
            ),
          ),
      ],
    );
  }
}
