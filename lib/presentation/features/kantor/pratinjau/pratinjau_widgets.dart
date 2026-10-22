import 'package:flutter/material.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_format.dart';

/// Shared bits of the Pratinjau screens: URLs, pills, thumbnails, sheets.

/// Absolute URL for a signed `/pv/…` or `/pvt/…` path on the Kantor host.
/// No auth needed: the key is in the path.
Uri pratinjauUri(KantorApi api, String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Uri.parse(path);
  }
  final base = api.config.baseUrl.replaceAll(RegExp(r'/+$'), '');
  return Uri.parse('$base${path.startsWith('/') ? '' : '/'}$path');
}

/// Navigation prefix an HTML preview may stay in: `<base>/pv/<office>/<id>/`.
String pratinjauPrefix(KantorApi api, PratinjauFile file) {
  final segs = file.url.split('/').where((s) => s.isNotEmpty).take(3).toList();
  final base = api.config.baseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base/${segs.join('/')}/';
}

String pratinjauRoute(String office, [String? id]) =>
    '/kantor/o/${Uri.encodeComponent(office)}/pratinjau'
    '${id == null ? '' : '/${Uri.encodeComponent(id)}'}';

(String, ChunkySwatch) pratinjauStatusLook(String status) => switch (status) {
  'baru' || 'menunggu' => ('Baru', GhinaColors.orange),
  'dilihat' => ('Dilihat', GhinaColors.gray),
  'dikomentari' => ('Dikomentari', GhinaColors.purple),
  'sebagian' => ('Sebagian', GhinaColors.blue),
  'disetujui' => ('Disetujui', GhinaColors.green),
  'revisi' => ('Revisi', GhinaColors.red),
  'dipilih' => ('Dipilih', GhinaColors.green),
  'oke' => ('Oke', GhinaColors.green),
  _ => (status, GhinaColors.gray),
};

String pratinjauJenisLabel(String jenis) => switch (jenis) {
  'info' => 'Info',
  'pilihan' => 'Pilihan',
  _ => 'Persetujuan',
};

class PratinjauStatusPill extends StatelessWidget {
  const PratinjauStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = pratinjauStatusLook(status);
    return ChunkyPill(label: label, color: color, soft: true, uppercase: false);
  }
}

/// "v2" badge; hidden for v1 unless [always].
class PratinjauVersionBadge extends StatelessWidget {
  const PratinjauVersionBadge(this.version, {super.key, this.always = false});
  final int version;
  final bool always;

  @override
  Widget build(BuildContext context) => version <= 1 && !always
      ? const SizedBox.shrink()
      : ChunkyPill(
          label: 'v$version',
          color: GhinaColors.purple,
          uppercase: false,
        );
}

IconData pratinjauKindIcon(String kind) => switch (kind) {
  'html' => Icons.web_rounded,
  'image' => Icons.image_rounded,
  'pdf' => Icons.picture_as_pdf_rounded,
  'video' => Icons.movie_rounded,
  'doc' => Icons.description_rounded,
  _ => Icons.insert_drive_file_rounded,
};

String pratinjauModeLabel(String mode) => switch (mode) {
  'pilihan' => 'Pilihan',
  'bundle' => 'Halaman web',
  _ => 'Kumpulan file',
};

String pratinjauFromLine(PratinjauItem item) => [
  item.fromName ?? item.fromRole ?? 'Agen',
  if (item.fromName != null && item.fromRole != null) item.fromRole!,
  if (item.createdAt != null) kantorAgo(item.createdAt),
].join(' · ');

/// Thumbnail for a file: the daemon's thumb, else the image itself, else an
/// icon placeholder per kind.
class PratinjauThumb extends StatelessWidget {
  const PratinjauThumb({
    super.key,
    required this.api,
    required this.file,
    this.compact = false,
    this.fit = BoxFit.cover,
    this.purged = false,
  });

  /// Files cleaned up: only the thumb may load.
  final bool purged;

  final KantorApi api;
  final PratinjauFile file;
  final bool compact;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final src = purged
        ? (file.thumbState == 'gagal' ? null : file.thumb)
        : file.thumbState == 'gagal'
        ? (file.kind == 'image' && file.size < 4 * 1024 * 1024
              ? file.url
              : null)
        : file.thumb ??
              (file.kind == 'image' && file.size < 4 * 1024 * 1024
                  ? file.url
                  : null);
    final placeholder = Container(
      color: g.surfaceAlt,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(GhinaSpace.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pratinjauKindIcon(file.kind),
            size: compact ? 22 : 40,
            color: g.textMuted,
          ),
          if (!compact) ...[
            const SizedBox(height: GhinaSpace.xs),
            Text(
              file.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ),
    );
    if (src == null) return placeholder;
    final img = Image.network(
      pratinjauUri(api, src).toString(),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: compact ? 200 : 900,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (_, child, p) => p == null
          ? child
          : Container(
              color: g.surfaceAlt,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
    );
    if (file.kind != 'video') return img;
    return Stack(
      fit: StackFit.expand,
      children: [
        img,
        Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: compact ? 20 : 44,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

/// Note sheet for approve / revise / per-file revise / pick. Returns the note
/// ('' when left empty), or null when cancelled. [required] blocks an empty
/// note.
Future<String?> showPratinjauNoteSheet(
  BuildContext context, {
  required String title,
  required String action,
  String? message,
  String hint = 'Catatan untuk agen (opsional)',
  bool required = false,
  ChunkyButtonVariant variant = ChunkyButtonVariant.primary,
  String? initial,
}) => showChunkyBottomSheet<String>(
  context,
  title: title,
  builder: (c) => _NoteSheet(
    action: action,
    message: message,
    hint: hint,
    required: required,
    variant: variant,
    initial: initial,
  ),
);

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.action,
    required this.message,
    required this.hint,
    required this.required,
    required this.variant,
    required this.initial,
  });

  final String action;
  final String? message;
  final String hint;
  final bool required;
  final ChunkyButtonVariant variant;
  final String? initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _c = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[
            Text(
              widget.message!,
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: GhinaSpace.md),
          ],
          ChunkyTextField(
            controller: _c,
            hint: widget.hint,
            autofocus: widget.required,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyButton(
            label: widget.action,
            variant: widget.variant,
            expand: true,
            onPressed: widget.required && _c.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_c.text.trim()),
          ),
        ],
      ),
    );
  }
}

const pratinjauPurgedText =
    '🧹 Berkas sudah dibersihkan (gambar kecil tetap ada).';

class PratinjauPurgedHint extends StatelessWidget {
  const PratinjauPurgedHint({super.key});

  @override
  Widget build(BuildContext context) => Text(
    pratinjauPurgedText,
    style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
  );
}
