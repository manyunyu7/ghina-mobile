import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// Killa's accent (a calm purple, like the web's agent pages).
const killaSwatch = GhinaColors.purple;

/// Opens an http(s) link from a reply (nothing else: no `javascript:`,
/// `file:`, intents…).
Future<void> openKillaLink(BuildContext context, String href) async {
  final uri = Uri.tryParse(href.trim());
  var ok = false;
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showErrorToast(context, 'Tautan ini nggak bisa dibuka');
  }
}

/// Markdown of an assistant reply / a `.md` workspace file. Safe:
/// `flutter_markdown_plus` never renders raw HTML, images become a small
/// placeholder (no loads from the text), only http(s) links open.
class KillaMarkdown extends StatelessWidget {
  const KillaMarkdown({
    super.key,
    required this.text,
    this.selectable = true,
    this.textColor,
  });

  final String text;
  final bool selectable;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fg = textColor ?? g.textPrimary;
    final base = GhinaType.body.copyWith(color: fg, height: 1.45);
    final mono = GhinaType.bodyS.copyWith(
      color: fg,
      fontFamily: 'monospace',
      height: 1.4,
    );
    return MarkdownBody(
      data: text,
      selectable: selectable,
      softLineBreak: true,
      onTapLink: (_, href, _) {
        if (href != null) openKillaLink(context, href);
      },
      styleSheet: MarkdownStyleSheet(
        p: base,
        h1: GhinaType.h2.w(900).copyWith(color: fg),
        h2: GhinaType.h3.w(900).copyWith(color: fg),
        h3: GhinaType.bodyL.w(900).copyWith(color: fg),
        h4: base.w(800),
        h5: base.w(800),
        h6: base.w(800),
        strong: const TextStyle(fontWeight: FontWeight.w800),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: base.copyWith(
          color: GhinaColors.blue.base,
          decoration: TextDecoration.underline,
          decorationColor: GhinaColors.blue.base,
        ),
        code: mono.copyWith(backgroundColor: g.surfaceAlt),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rMd,
          border: Border.all(color: g.border),
        ),
        listBullet: base,
        tableBody: GhinaType.bodyS.copyWith(color: fg),
        tableHead: GhinaType.bodyS.w(800).copyWith(color: fg),
        tableBorder: TableBorder.all(color: g.border),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        blockquote: base.copyWith(color: g.textSecondary),
        blockquoteDecoration: BoxDecoration(
          color: g.surfaceAlt.withValues(alpha: 0.6),
          border: Border(left: BorderSide(color: killaSwatch.base, width: 4)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: g.border, width: 2)),
        ),
        blockSpacing: 8,
      ),
      imageBuilder: (uri, title, alt) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 16, color: g.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              (alt ?? '').isEmpty ? 'gambar' : alt!,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Monospace text (code / plain files), selectable, horizontally scrollable.
class KillaMonospace extends StatelessWidget {
  const KillaMonospace({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText(
        text.isEmpty ? '(berkas kosong)' : text,
        style: GhinaType.bodyS.copyWith(
          fontFamily: 'monospace',
          color: text.isEmpty ? g.textMuted : g.textPrimary,
          height: 1.45,
        ),
      ),
    );
  }
}

/// A Killa error as a full state. `forbidden` → [KillaLockedView]; the
/// engine being off / slow / unreachable get their own friendly copy.
class KillaErrorView extends StatelessWidget {
  const KillaErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e is KillaException && e.kind == KillaErrorKind.forbidden) {
      return const KillaLockedView();
    }
    final (mood, title, message) = switch (e) {
      KillaException(kind: KillaErrorKind.engineOff) => (
        MascotMood.sleeping,
        'Killa lagi tidur 😴',
        'Mesinnya sedang nggak aktif. Coba lagi nanti, ya.',
      ),
      KillaException(kind: KillaErrorKind.timeout) => (
        MascotMood.thinking,
        'Killa kelamaan mikir',
        e.message,
      ),
      KillaException(kind: KillaErrorKind.network) => (
        MascotMood.sad,
        'Lagi offline',
        'Killa butuh internet. Sambungkan dulu, lalu coba lagi.',
      ),
      KillaException(kind: KillaErrorKind.tooLarge) => (
        MascotMood.thinking,
        'Terlalu besar',
        e.message,
      ),
      KillaException(kind: KillaErrorKind.unsupported) => (
        MascotMood.thinking,
        'Nggak bisa dibuka di sini',
        e.message,
      ),
      KillaException(kind: KillaErrorKind.notFound) => (
        MascotMood.thinking,
        'Nggak ketemu',
        e.message,
      ),
      KillaException(:final message) => (
        MascotMood.sad,
        'Ups, Killa bermasalah',
        message,
      ),
      _ => (MascotMood.sad, 'Ups, gagal memuat', 'Coba lagi, yuk.'),
    };
    return ScrollableFill(
      child: EmptyState(
        mood: mood,
        title: title,
        message: message,
        actionLabel: onRetry == null ? null : 'Coba lagi',
        onAction: onRetry,
      ),
    );
  }
}

/// Shown to accounts that aren't allowlisted (403): polite, no retry loop.
class KillaLockedView extends StatelessWidget {
  const KillaLockedView({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ScrollableFill(
      child: Padding(
        padding: const EdgeInsets.all(GhinaSpace.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const MascotView(mood: MascotMood.thinking, size: 120),
                Positioned(
                  right: -6,
                  bottom: 4,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: killaSwatch.base,
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Killa masih terkunci',
              style: GhinaType.h2.copyWith(color: g.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Killa adalah asisten pribadi yang cuma bisa dipakai akun '
              'tertentu. Akun kamu belum masuk daftar, jadi menu ini '
              'disembunyikan dulu, ya 🙏',
              style: GhinaType.body.copyWith(color: g.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ChunkyButton(
              label: 'Kembali',
              variant: ChunkyButtonVariant.outline,
              size: ChunkyButtonSize.medium,
              expand: false,
              onPressed: () => popOr(context, '/home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Display name of a model value (`"default"` → "Default", `opus` → "Opus").
String killaModelLabel(String? model) {
  final m = model ?? killaDefaultModel;
  return m.isEmpty ? m : '${m[0].toUpperCase()}${m.substring(1)}';
}

String? _killaModelHint(String model) => switch (model.toLowerCase()) {
  killaDefaultModel => 'Model bawaan engine',
  'fable' => 'Paling pintar, paling lama',
  'opus' => 'Kuat untuk tugas berat',
  'sonnet' => 'Seimbang: cepat & pintar',
  'haiku' => 'Paling cepat & hemat',
  _ => null,
};

/// "default" first, then the server's options (the active one kept even if
/// the server no longer lists it).
List<String> killaModelChoices(KillaModelSetting s) => [
  killaDefaultModel,
  for (final o in {...s.options, ?s.model})
    if (o != killaDefaultModel) o,
];

/// Picks the persisted model → the chosen value (`"default"` included), or
/// null when dismissed / unchanged.
Future<String?> showKillaModelSheet(
  BuildContext context,
  KillaModelSetting setting,
) => showChunkyBottomSheet<String>(
  context,
  title: 'Pilih model',
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Tersimpan di Killa, berlaku juga untuk chat WhatsApp.',
          style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
        ),
      ),
      for (final m in killaModelChoices(setting))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            key: ValueKey('killa-model-$m'),
            dense: true,
            title: killaModelLabel(m),
            subtitle: _killaModelHint(m),
            leading: Icon(
              m == setting.active
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: m == setting.active ? killaSwatch.base : null,
            ),
            tinted: m == setting.active ? killaSwatch : null,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(c, m == setting.active ? null : m);
            },
          ),
        ),
    ],
  ),
);
