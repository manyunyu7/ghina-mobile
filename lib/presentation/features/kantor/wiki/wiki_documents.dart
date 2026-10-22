import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';
import 'wiki_markdown.dart';

/// PDF and text/markdown attachments inside wiki pages: a preview card in the
/// page, a full-screen viewer on tap.

final _pdfExt = RegExp(r'\.pdf(?:[?#].*)?$', caseSensitive: false);
final _docExt = RegExp(
  r'\.(md|markdown|txt)(?:[?#].*)?$',
  caseSensitive: false,
);

bool isPdfUri(Uri uri) => _pdfExt.hasMatch(uri.path);
bool isDocUri(Uri uri) => _docExt.hasMatch(uri.path);

/// `/api/offices/<id>/media/…` → `<id>`.
String? officeIdOf(Uri uri) {
  final s = uri.pathSegments;
  final i = s.indexOf('offices');
  return i >= 0 && i + 1 < s.length ? s[i + 1] : null;
}

/// Downloads an own-office media path to the cache (reused when present) and
/// returns the file.
Future<File> fetchMedia(KantorApi api, Uri uri, String name) async {
  final id = uri.pathSegments.isEmpty
      ? 'x'
      : uri.pathSegments.last.replaceAll(RegExp(r'[^\w.\-]'), '_');
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'kantor_wiki', id),
  );
  await dir.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
  final file = File(p.join(dir.path, safe.isEmpty ? 'file' : safe));
  if (await file.exists() && await file.length() > 0) return file;
  await file.writeAsBytes(await api.bytes(uri.path));
  return file;
}

Future<void> _share(File f, String name, String mime) =>
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, name: name, mimeType: mime)],
      ),
    );

String _fileName(Uri uri, String? alt, String ext) {
  final a = (alt ?? '').trim();
  if (a.isEmpty) return 'dokumen.$ext';
  return a.toLowerCase().endsWith('.$ext') ? a : '$a.$ext';
}

/// Page-in-wiki card for `![nama](…/media/<id>.pdf)`: first page + page count.
class WikiPdfCard extends StatefulWidget {
  const WikiPdfCard({
    super.key,
    required this.uri,
    this.alt,
    required this.api,
  });

  final Uri uri;
  final String? alt;
  final KantorApi? api;

  @override
  State<WikiPdfCard> createState() => _WikiPdfCardState();
}

class _WikiPdfCardState extends State<WikiPdfCard> {
  File? _file;
  PdfDocument? _doc;
  bool _failed = false;

  String get _name => _fileName(widget.uri, widget.alt, 'pdf');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null || !widget.uri.path.startsWith('/api/')) {
      setState(() => _failed = true);
      return;
    }
    try {
      final f = await fetchMedia(api, widget.uri, _name);
      final d = await PdfDocument.openFile(f.path);
      if (!mounted) {
        d.dispose();
        return;
      }
      setState(() {
        _file = f;
        _doc = d;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final d = _doc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _file == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WikiPdfScreen(file: _file!, name: _name),
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 96,
                  child: d != null
                      ? PdfPageView(
                          document: d,
                          pageNumber: 1,
                          alignment: Alignment.center,
                        )
                      : Center(
                          child: _failed
                              ? Icon(Icons.picture_as_pdf, color: g.textMuted)
                              : const CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
                const SizedBox(width: GhinaSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _failed
                            ? 'PDF tidak termuat'
                            : d == null
                            ? 'Memuat PDF…'
                            : 'PDF · ${d.pages.length} halaman · ketuk untuk membuka',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen PDF: swipe/scroll pages, pinch zoom, share/save.
class WikiPdfScreen extends StatelessWidget {
  const WikiPdfScreen({super.key, required this.file, required this.name});

  final File file;
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ghina.background,
    appBar: AppBar(
      title: Text(name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Bagikan / simpan',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => _share(file, name, 'application/pdf'),
        ),
      ],
    ),
    body: PdfViewer.file(file.path),
  );
}

/// Card for `.md` / `.markdown` / `.txt` attachments: title + first lines.
class WikiDocCard extends StatefulWidget {
  const WikiDocCard({
    super.key,
    required this.uri,
    this.alt,
    required this.api,
  });

  final Uri uri;
  final String? alt;
  final KantorApi? api;

  @override
  State<WikiDocCard> createState() => _WikiDocCardState();
}

class _WikiDocCardState extends State<WikiDocCard> {
  String? _text;
  bool _failed = false;

  String get _ext =>
      _docExt.firstMatch(widget.uri.path)?[1]!.toLowerCase() ?? 'md';
  String get _name => _fileName(widget.uri, widget.alt, _ext);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null || !widget.uri.path.startsWith('/api/')) {
      setState(() => _failed = true);
      return;
    }
    try {
      final b = await api.bytes(widget.uri.path);
      if (mounted) setState(() => _text = utf8.decode(b, allowMalformed: true));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final t = _text;
    final title = t == null ? _name : docTitle(t, _name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        child: InkWell(
          borderRadius: GhinaRadii.rMd,
          onTap: t == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WikiDocScreen(
                      name: _name,
                      text: t,
                      api: widget.api,
                      officeId: officeIdOf(widget.uri),
                    ),
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined, color: g.textMuted),
                    const SizedBox(width: GhinaSpace.sm),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _failed
                      ? 'Dokumen tidak termuat'
                      : t == null
                      ? 'Memuat…'
                      : docSnippet(t),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First `# heading`, else the file name.
String docTitle(String text, String fallback) {
  final m = RegExp(
    r'^\s{0,3}#{1,4}\s+(.+?)\s*#*\s*$',
    multiLine: true,
  ).firstMatch(text);
  final t = m?[1]?.trim();
  return t == null || t.isEmpty ? fallback : t;
}

/// A few plain lines for the card (markup characters stripped).
String docSnippet(String text, {int lines = 4}) {
  final out = <String>[];
  var fence = false;
  for (final raw in text.replaceAll('\r', '').split('\n')) {
    final l = raw.trim();
    if (l.startsWith('```')) {
      fence = !fence;
      continue;
    }
    if (fence || l.isEmpty || RegExp(r'^[-*_|:\s]+$').hasMatch(l)) continue;
    if (RegExp(r'^#{1,4}\s').hasMatch(l) && out.isEmpty) {
      continue; // title is shown above
    }
    out.add(
      l
          .replaceFirst(RegExp(r'^(#{1,4}|>|[-*]|\d+[.)])\s+'), '')
          .replaceAll(RegExp(r'[*_`]'), '')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
    if (out.length >= lines) break;
  }
  return out.isEmpty ? '(kosong)' : out.join('\n');
}

/// Full-screen document: rendered with the wiki renderer (raw HTML is never
/// interpreted, only http(s) links open), "Lihat sumber" for the raw text,
/// "Jadikan halaman wiki" to import it as a new page.
class WikiDocScreen extends StatefulWidget {
  const WikiDocScreen({
    super.key,
    required this.name,
    required this.text,
    this.api,
    this.officeId,
  });

  final String name;
  final String text;
  final KantorApi? api;
  final String? officeId;

  @override
  State<WikiDocScreen> createState() => _WikiDocScreenState();
}

class _WikiDocScreenState extends State<WikiDocScreen> {
  bool _raw = false;
  bool _busy = false;

  bool get _isText => widget.name.toLowerCase().endsWith('.txt');

  Future<void> _import() async {
    final api = widget.api, office = widget.officeId;
    if (api == null || office == null) return;
    setState(() => _busy = true);
    try {
      final title = docTitle(
        widget.text,
        widget.name.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), ''),
      );
      await api.post('/api/offices/${Uri.encodeComponent(office)}/wiki', {
        'title': title,
        'body': widget.text,
        'msg': 'Diimpor dari ${widget.name}',
      });
      if (mounted) kantorToast(context, 'Halaman "$title" dibuat');
    } on KantorException catch (e) {
      if (mounted) kantorToast(context, e.message, bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final dir = await getTemporaryDirectory();
    final f = File(
      p.join(dir.path, widget.name.replaceAll(RegExp(r'[^\w.\- ]'), '_')),
    );
    await f.writeAsString(widget.text);
    await _share(f, widget.name, 'text/markdown');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final showRaw = _raw || _isText;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_isText)
            IconButton(
              tooltip: _raw ? 'Tampilan rapi' : 'Lihat sumber',
              icon: Icon(_raw ? Icons.article_rounded : Icons.code_rounded),
              onPressed: () => setState(() => _raw = !_raw),
            ),
          IconButton(
            tooltip: 'Bagikan / simpan',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _download,
          ),
          if (widget.api != null && widget.officeId != null)
            IconButton(
              tooltip: 'Jadikan halaman wiki',
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.note_add_outlined),
              onPressed: _busy ? null : _import,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        child: showRaw
            ? SelectableText(
                widget.text,
                style: GhinaType.caption.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                  color: g.textPrimary,
                ),
              )
            : WikiMarkdown(text: widget.text, api: widget.api),
      ),
    );
  }
}
