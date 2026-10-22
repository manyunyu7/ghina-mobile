import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'wiki_markdown.dart';

const _templates = <(String, String)>[
  ('Kosong', ''),
  (
    'Runbook deploy',
    '''# Runbook deploy

## Kapan dipakai
Jelaskan situasi yang membutuhkan runbook ini.

## Prasyarat
- [ ] Branch sudah di-merge dan tes lulus
- [ ] Akses ke server / layanan tersedia

## Langkah
1. Langkah pertama
2. Langkah kedua
3. Langkah ketiga

## Verifikasi
Apa yang dicek setelah deploy selesai.

## Rollback
Cara membatalkan bila ada masalah.

## Kontak
Siapa yang dihubungi bila macet.
''',
  ),
  (
    'Keputusan (ADR)',
    '''# Keputusan: judul singkat

Status: diusulkan
Tanggal:

## Konteks
Masalah apa yang sedang dihadapi dan batasan apa yang berlaku.

## Keputusan
Apa yang diputuskan, dalam satu atau dua kalimat.

## Alternatif yang dipertimbangkan
- Opsi A: kelebihan dan kekurangan
- Opsi B: kelebihan dan kekurangan

## Konsekuensi
Apa yang jadi lebih mudah, apa yang jadi lebih sulit, dan apa yang perlu dikerjakan setelahnya.
''',
  ),
  (
    'Onboarding repo',
    '''# Onboarding repo

## Gambaran
Repo ini untuk apa dan siapa pemakainya.

## Menjalankan di lokal
```
# perintah instalasi
# perintah menjalankan
```

## Struktur folder
- `src/` — kode utama
- `tests/` — tes

## Perintah penting
- Tes:
- Lint:
- Build:

## Yang perlu diketahui
- Konvensi commit dan branch
- Hal-hal yang jangan disentuh
''',
  ),
  (
    'Panduan role',
    '''# Panduan role: nama role

## Tugas utama
Apa yang menjadi tanggung jawab role ini.

## Cara kerja
- Mulai dari kartu di board yang ditugaskan
- Catat progres di komentar kartu

## Batasan
Hal yang tidak boleh dilakukan tanpa izin.

## Serah terima
Kapan dan kepada siapa pekerjaan diserahkan.
''',
  ),
  (
    'Notulen rapat',
    '''# Notulen rapat: topik

Tanggal:
Peserta:

## Agenda
1.

## Pembahasan
-

## Keputusan
-

## Tindak lanjut
- [ ] Tugas — penanggung jawab
''',
  ),
];

/// Create or edit a wiki page. Pops with the saved slug.
class WikiEditorScreen extends ConsumerStatefulWidget {
  const WikiEditorScreen({
    super.key,
    required this.officeId,
    this.page,
    this.initialTitle,
    this.parent,
  });

  final String officeId;

  /// Existing page (full map with `body`); null = new page.
  final Map<String, dynamic>? page;
  final String? initialTitle;
  final String? parent;

  @override
  ConsumerState<WikiEditorScreen> createState() => _WikiEditorScreenState();
}

class _WikiEditorScreenState extends ConsumerState<WikiEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final _msg = TextEditingController();
  late final String _title0;
  late final String _body0;
  bool _preview = false;
  bool _saving = false;
  int _uploading = 0;
  int _tpl = 0;

  bool get _isNew => widget.page == null;
  String get _base => '/api/offices/${Uri.encodeComponent(widget.officeId)}';
  bool get _dirty => _title.text != _title0 || _body.text != _body0;

  @override
  void initState() {
    super.initState();
    _title0 = _isNew ? '' : (widget.page!['title'] as String? ?? '');
    _body0 = _isNew ? '' : (widget.page!['body'] as String? ?? '');
    _title = TextEditingController(
      text: widget.page?['title'] as String? ?? widget.initialTitle ?? '',
    );
    _body = TextEditingController(text: _body0);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _msg.dispose();
    super.dispose();
  }

  void _toast(String m, {bool bad = true}) => showToastBadge(
    context,
    message: m,
    icon: bad ? Icons.error_outline : Icons.check_circle_outline,
  );

  void _insert(String text) {
    final sel = _body.selection;
    final v = _body.text;
    final a = sel.isValid ? sel.start : v.length;
    final b = sel.isValid ? sel.end : v.length;
    _body.value = TextEditingValue(
      text: v.replaceRange(a, b, text),
      selection: TextSelection.collapsed(offset: a + text.length),
    );
  }

  String _safe(String n) => n.replaceAll(RegExp(r'[\[\]()\n]'), ' ').trim();

  Future<void> _upload(Uint8List bytes, String name) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final label = _safe(name.isEmpty ? 'berkas' : name);
    final mark = '⏳ Mengunggah $label…';
    setState(() => _uploading++);
    _insert(
      '${_body.text.isNotEmpty && !_body.text.endsWith('\n') ? '\n' : ''}$mark\n',
    );
    var out = '';
    try {
      final r = await api.post(
        '$_base/media?name=${Uri.encodeQueryComponent(name)}',
        bytes,
      );
      if (r is Map && r['url'] is String) {
        final n = _safe('${r['name'] ?? label}');
        out = r['image'] == true
            ? '![${n.replaceAll(RegExp(r'\.[a-z0-9]+$', caseSensitive: false), '')}](${r['url']})'
            : '[📎 $n](${r['url']})';
      }
    } on KantorException catch (e) {
      if (mounted) _toast('Gagal mengunggah $label: ${e.message}');
    }
    if (!mounted) return;
    setState(() => _uploading--);
    final t = _body.text;
    final i = t.indexOf(mark);
    if (i >= 0) {
      final tail = out.isEmpty ? '$mark\n' : mark;
      final next = t.replaceFirst(tail, out);
      final pos = _body.selection.isValid ? _body.selection.start : next.length;
      _body.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: pos.clamp(0, next.length)),
      );
    }
  }

  Future<void> _attach() async {
    final how = await showChunkyBottomSheet<String>(
      context,
      title: 'Lampirkan',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyTile(
            title: 'Foto dari galeri',
            leading: const Icon(Icons.photo_outlined),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          ChunkyTile(
            title: 'Ambil foto',
            leading: const Icon(Icons.photo_camera_outlined),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
          ChunkyTile(
            title: 'Berkas',
            leading: const Icon(Icons.attach_file),
            onTap: () => Navigator.pop(c, 'file'),
          ),
        ],
      ),
    );
    if (how == null) return;
    try {
      if (how == 'file') {
        final files = await FilePicker.pickFiles();
        for (final f in files) {
          await _upload(await f.readAsBytes(), f.name);
        }
      } else {
        final x = await ImagePicker().pickImage(
          source: how == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2000,
          imageQuality: 85,
        );
        if (x != null) await _upload(await x.readAsBytes(), x.name);
      }
    } catch (e) {
      if (mounted) _toast('Tidak bisa mengambil berkas.');
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('Judul wajib diisi.');
      return;
    }
    if (_uploading > 0) {
      _toast('Tunggu unggahan selesai dulu.');
      return;
    }
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      final p = await api.post('$_base/wiki', {
        'title': title,
        'body': _body.text,
        if (_msg.text.trim().isNotEmpty) 'msg': _msg.text.trim(),
        if (!_isNew) 'prevSlug': widget.page!['slug'],
        if (_isNew && widget.parent != null) 'parent': widget.parent,
      });
      if (!mounted) return;
      _toast('Halaman disimpan.', bad: false);
      _body0Saved = true;
      Navigator.of(context).pop(p is Map ? p['slug'] : null);
    } on KantorException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(e.message);
      }
    }
  }

  bool _body0Saved = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final api = ref.watch(kantorApiProvider);
    return PopScope(
      canPop: !_dirty || _body0Saved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showChunkyConfirm(
          context,
          title: 'Perubahan belum disimpan',
          message: 'Kalau keluar sekarang, perubahan di halaman ini hilang.',
          confirmLabel: 'Buang',
          cancelLabel: 'Lanjut menyunting',
          destructive: true,
        );
        if (discard && context.mounted) {
          setState(() => _body0Saved = true);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: g.background,
        appBar: AppBar(
          title: Text(_isNew ? 'Halaman baru' : 'Ubah halaman'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Simpan'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(GhinaSpace.page),
          children: [
            if (_isNew && widget.initialTitle == null) ...[
              Text(
                'Mulai dari',
                style: GhinaType.overline.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: GhinaSpace.sm),
              Wrap(
                spacing: GhinaSpace.sm,
                runSpacing: GhinaSpace.sm,
                children: [
                  for (var i = 0; i < _templates.length; i++)
                    ChunkyChip(
                      label: _templates[i].$1,
                      selected: _tpl == i,
                      onTap: () {
                        if (_body.text.isNotEmpty &&
                            _body.text != _templates[_tpl].$2) {
                          _toast('Isi sudah ditulis, template tidak menimpa.');
                          return;
                        }
                        setState(() => _tpl = i);
                        _body.text = _templates[i].$2;
                      },
                    ),
                ],
              ),
              const SizedBox(height: GhinaSpace.lg),
            ],
            if (_isNew && widget.parent != null)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                child: Text(
                  'Sub-halaman dari ${widget.parent}',
                  style: GhinaType.bodyS.copyWith(color: g.textMuted),
                ),
              ),
            ChunkyTextField(
              label: 'Judul',
              hint: 'Judul halaman',
              controller: _title,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: GhinaSpace.lg),
            Row(
              children: [
                Expanded(
                  child: ChunkySegmented<bool>(
                    segments: const [
                      ChunkySegment(value: false, label: 'Tulis'),
                      ChunkySegment(value: true, label: 'Pratinjau'),
                    ],
                    value: _preview,
                    onChanged: (v) => setState(() => _preview = v),
                  ),
                ),
                const SizedBox(width: GhinaSpace.sm),
                IconButton(
                  tooltip: 'Lampirkan',
                  onPressed: _attach,
                  icon: _uploading > 0
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                ),
              ],
            ),
            const SizedBox(height: GhinaSpace.sm),
            if (!_preview) ...[
              _Toolbar(onInsert: _insert, controller: _body),
              ChunkyTextField(
                hint:
                    'Tulis dengan markdown. Tautkan halaman lain dengan [[Judul]].',
                controller: _body,
                maxLines: null,
                minLines: 14,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
            ] else
              Container(
                constraints: const BoxConstraints(minHeight: 240),
                padding: const EdgeInsets.all(GhinaSpace.md),
                decoration: BoxDecoration(
                  border: Border.all(color: g.border, width: 2),
                  borderRadius: GhinaRadii.rMd,
                ),
                child: _body.text.trim().isEmpty
                    ? Text(
                        'Pratinjau muncul di sini.',
                        style: GhinaType.body.copyWith(color: g.textMuted),
                      )
                    : WikiMarkdown(text: _body.text, api: api),
              ),
            const SizedBox(height: GhinaSpace.lg),
            ChunkyTextField(
              label: 'Ringkasan perubahan',
              hint: 'Opsional, mis. menambah langkah rollback',
              controller: _msg,
            ),
            const SizedBox(height: GhinaSpace.xl),
            ChunkyButton(
              label: 'Simpan',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onInsert, required this.controller});
  final void Function(String) onInsert;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    Widget b(String label, String text) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(label: Text(label), onPressed: () => onInsert(text)),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          b('Judul', '\n## '),
          b('Centang', '\n- [ ] '),
          b('Daftar', '\n- '),
          b('Tebal', '****'),
          b('Kode', '``'),
          b('[[Wiki]]', '[[]]'),
        ],
      ),
    );
  }
}
