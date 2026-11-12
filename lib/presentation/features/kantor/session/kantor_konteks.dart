import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../kantor_format.dart';
import 'kantor_feed.dart';

/// Konteks satu sesi dari server (`session.konteks`): topik, permintaan,
/// balasan terakhir, galat, berkas, kartu, cabang, dan keadaan. Semua bagian
/// boleh kosong; server lama yang tidak mengirimnya menghasilkan `null`.

String? _str(Object? v) {
  final t = '${v ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return v == null || t.isEmpty ? null : t;
}

class KantorKonteksAsk {
  const KantorKonteksAsk({required this.s, this.at, this.fromAgent = false});
  final String s;
  final String? at;
  final bool fromAgent;
}

class KantorKonteksReply {
  const KantorKonteksReply({required this.s, this.q, this.at});
  final String s;
  final String? q;
  final String? at;
}

class KantorKonteks {
  const KantorKonteks({
    required this.stateKey,
    required this.stateLabel,
    this.topic,
    this.step,
    this.percent,
    this.draftTitle,
    this.draftReady = false,
    this.draftDetails,
    this.ask,
    this.reply,
    this.err,
    this.fileNames = const [],
    this.fileCount = 0,
    this.cardTitle,
    this.branch,
    this.label,
    this.labelForRole = false,
    this.labelTell = false,
    this.auto,
  });

  final String stateKey;
  final String stateLabel;
  final String? topic;

  /// Laporan agen sendiri lewat tool `kerjaan_set`.
  final String? step;
  final int? percent;

  /// Draf laporan Claude Code ke Anthropic yang menunggu keputusan di terminal.
  final String? draftTitle;
  final bool draftReady;
  final String? draftDetails;
  final KantorKonteksAsk? ask;
  final KantorKonteksReply? reply;
  final String? err;
  final List<String> fileNames;
  final int fileCount;
  final String? cardTitle;
  final String? branch;

  /// Label dari pemilik (`konteks.label`). Kalau ada, server sudah memakainya
  /// sebagai [topic]; [auto] berisi judul otomatis yang tergeser.
  final String? label;

  /// Label disimpan per role, jadi terbawa ke shift berikutnya.
  final bool labelForRole;

  /// Agen dikabari labelnya lewat hook.
  final bool labelTell;
  final String? auto;

  /// Parsing aman: bukan Map atau tanpa `state` valid menghasilkan `null`.
  static KantorKonteks? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = asJson(raw);
    final st = j['state'] is Map
        ? asJson(j['state'])
        : const <String, dynamic>{};
    final k = _str(st['k']);
    if (k == null) return null;
    final a = j['ask'] is Map ? asJson(j['ask']) : null;
    final r = j['reply'] is Map ? asJson(j['reply']) : null;
    final f = j['files'] is Map ? asJson(j['files']) : null;
    final c = j['card'] is Map ? asJson(j['card']) : null;
    final names = f?['names'] is List
        ? [
            for (final n in f!['names'] as List)
              if (_str(n) != null) _str(n)!,
          ]
        : <String>[];
    final askS = _str(a?['s']);
    final replyS = _str(r?['s']);
    final w = j['kerjaan'] is Map ? asJson(j['kerjaan']) : null;
    final d = j['draft'] is Map ? asJson(j['draft']) : null;
    final l = j['label'] is Map ? asJson(j['label']) : null;
    final lt = _str(l?['text']);
    return KantorKonteks(
      label: lt,
      labelForRole: lt != null && l?['scope'] == 'role',
      labelTell: lt != null && l?['tell'] == true,
      auto: lt == null ? null : _str(j['auto']),
      stateKey: k,
      stateLabel: _str(st['label']) ?? k,
      topic: _str(j['topic']),
      draftTitle: _str(d?['title']),
      draftReady: d?['siap'] == true,
      draftDetails: _str(d?['details']),
      step: _str(w?['langkah']),
      percent: (w?['persen'] as num?)?.round(),
      ask: askS == null
          ? null
          : KantorKonteksAsk(
              s: askS,
              at: _str(a?['at']),
              fromAgent: a?['from'] == 'agen',
            ),
      reply: replyS == null
          ? null
          : KantorKonteksReply(s: replyS, q: _str(r?['q']), at: _str(r?['at'])),
      err: _str(j['err']),
      fileNames: names,
      fileCount: (f?['n'] as num?)?.toInt() ?? names.length,
      cardTitle: _str(c?['title']),
      branch: _str(j['branch']),
    );
  }

  static KantorKonteks? ofSession(Json? session) =>
      fromJson(session?['konteks']);

  bool get needsOwner => stateKey == 'izin' || stateKey == 'tanya';

  /// Satu baris: apa yang terjadi sekarang. Kosong kalau tak ada yang berguna.
  String detail(Json? session) {
    final w = session?['waiting'];
    switch (stateKey) {
      case 'izin':
      case 'tanya':
        final sum = w is Map ? _str(w['summary']) ?? _str(w['tool']) : null;
        return clip(sum ?? reply?.q ?? '', 80);
      case 'jalan':
        if (step != null) return clip(step!, 80);
        final tool = toolFull(session?['tool']);
        if (tool.isNotEmpty) return clip(tool, 80);
        final a = ask?.s ?? '';
        return clip(a.isNotEmpty && a != topic ? a : 'sedang berpikir', 80);
      case 'gagal':
        return clip(err ?? '', 80);
      case 'selesai':
      case 'henti':
      case 'tunggu':
      case 'kosong':
      case 'tutup':
        return clip(reply?.s ?? '', 80);
    }
    return clip(reply?.s ?? '', 80);
  }
}

/// Label pemilik bergaya stiker kuning yang ditempel miring (gaya A di web).
class KantorLabelSticker extends StatelessWidget {
  const KantorLabelSticker(this.text, {super.key, this.maxLines, this.size});
  final String text;
  final int? maxLines;
  final double? size;

  static const paper = Color(0xFFFDE68A);
  static const edge = Color(0xFFF59E0B);
  static const ink = Color(0xFF713F12);

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.012,
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.all(Radius.circular(2)),
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, 1))],
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'PatrickHand',
          color: ink,
          fontSize: size ?? 16,
          height: 1.25,
        ),
      ),
    ),
  );
}

ChunkySwatch kantorKonteksColor(String k) => switch (k) {
  'izin' || 'tanya' => GhinaColors.orange,
  'jalan' => GhinaColors.green,
  'tunggu' => GhinaColors.blue,
  'gagal' => GhinaColors.red,
  'henti' => GhinaColors.yellow,
  'selesai' => GhinaColors.teal,
  _ => GhinaColors.gray,
};

/// Pil keadaan sesi, satu baris dan terpotong bila sempit.
class KantorKonteksPill extends StatelessWidget {
  const KantorKonteksPill({super.key, required this.konteks});
  final KantorKonteks konteks;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 170),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: ChunkyPill(
        label: konteks.stateLabel,
        color: kantorKonteksColor(konteks.stateKey),
        soft: true,
        uppercase: false,
      ),
    ),
  );
}

/// Topik (satu baris) lalu pil + detail (satu baris). Tanpa konteks, jatuh ke
/// [fallback] seperti tampilan lama.
class KantorKonteksLines extends StatelessWidget {
  const KantorKonteksLines({
    super.key,
    required this.session,
    required this.fallback,
    this.fallbackColor,
    this.showTopic = true,
  });

  final Json session;
  final String fallback;
  final Color? fallbackColor;
  final bool showTopic;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final k = KantorKonteks.ofSession(session);
    if (k == null) {
      return Text(
        fallback,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GhinaType.bodyS.copyWith(color: fallbackColor ?? g.textPrimary),
      );
    }
    final d = k.detail(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTopic && k.label != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: KantorLabelSticker(k.label!, maxLines: 2),
          )
        else if (showTopic && k.topic != null)
          Text(
            k.topic!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(flex: 0, child: KantorKonteksPill(konteks: k)),
            if (d.isNotEmpty) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ],
    );
  }
}

/// Bar konteks di atas Chat/Terminal: tertutup = pil + topik, terbuka = rincian.
class KantorKonteksBar extends StatefulWidget {
  const KantorKonteksBar({
    super.key,
    required this.session,
    this.onDraft,
    this.onLabel,
  });
  final Json session;

  /// Simpan label pemilik; teks kosong menghapus. Tanpa ini tombol ubah label
  /// tidak ditampilkan.
  final Future<void> Function(String text, bool carry, bool tell)? onLabel;

  /// `abaikan` atau `kirim`; tanpa ini tombol draf tidak ditampilkan.
  final Future<void> Function(String aksi)? onDraft;

  @override
  State<KantorKonteksBar> createState() => _KantorKonteksBarState();
}

class _KantorKonteksBarState extends State<KantorKonteksBar> {
  bool _open = false;

  Future<void> _decideDraft(KantorKonteks k, String aksi) async {
    if (aksi == 'kirim') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Kirim laporan ini ke Anthropic?'),
          content: SingleChildScrollView(
            child: Text(k.draftDetails ?? k.draftTitle ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Kirim'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.onDraft?.call(aksi);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _draftRow(BuildContext context, KantorKonteks k) => Padding(
    key: const ValueKey('konteks-draft'),
    padding: const EdgeInsets.symmetric(
      horizontal: GhinaSpace.md,
      vertical: GhinaSpace.xs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Draf laporan ke Anthropic: ${k.draftTitle}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: GhinaColors.orange.edge),
          ),
        ),
        if (k.draftReady && widget.onDraft != null) ...[
          TextButton(
            onPressed: () => _decideDraft(k, 'abaikan'),
            child: const Text('Abaikan'),
          ),
          TextButton(
            onPressed: () => _decideDraft(k, 'kirim'),
            child: const Text('Kirim'),
          ),
        ],
      ],
    ),
  );

  Widget _section(
    BuildContext context,
    String title,
    String body, {
    bool strong = false,
  }) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(top: GhinaSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GhinaType.overline.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: strong
                ? GhinaType.bodyS
                      .w(800)
                      .copyWith(color: GhinaColors.orange.edge)
                : GhinaType.bodyS.copyWith(color: g.textPrimary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = KantorKonteks.ofSession(widget.session);
    if (k == null) return const SizedBox.shrink();
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final g = context.ghina;
    final ask = k.ask;
    final ago = kantorAgo(ask?.at);
    final replyAgo = kantorAgo(k.reply?.at);
    final maxH = MediaQuery.sizeOf(context).height * 0.4;
    return Material(
      color: g.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (k.draftTitle != null) _draftRow(context, k),
          InkWell(
            key: const ValueKey('konteks-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GhinaSpace.md,
                vertical: GhinaSpace.xs,
              ),
              child: Row(
                children: [
                  KantorKonteksPill(konteks: k),
                  const SizedBox(width: GhinaSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (k.label != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: KantorLabelSticker(
                              k.label!,
                              maxLines: _open ? null : 2,
                            ),
                          )
                        else
                          Text(
                            k.topic ?? k.detail(widget.session),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.bodyS.w(700),
                          ),
                        if (!_open &&
                            k.topic != null &&
                            k.detail(widget.session).isNotEmpty)
                          Text(
                            k.detail(widget.session),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.onLabel != null)
                    IconButton(
                      key: const ValueKey('konteks-label'),
                      tooltip: k.label != null
                          ? 'Ubah label sesi ini'
                          : 'Beri label sesi ini',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: k.label != null
                            ? GhinaColors.orange.edge
                            : g.textMuted,
                      ),
                      onPressed: () => showKantorLabelSheet(
                        context,
                        konteks: k,
                        name:
                            '${asJson(widget.session['look'] ?? {})['name'] ?? 'sesi ini'}',
                        canCarry: _str(widget.session['role']) != null,
                        onSave: widget.onLabel!,
                      ),
                    ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: g.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                key: const ValueKey('konteks-detail'),
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.md,
                  0,
                  GhinaSpace.md,
                  GhinaSpace.sm,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (k.label != null)
                        _section(
                          context,
                          'Label kamu',
                          '${k.labelForRole ? 'Ikut role, terbawa ke shift berikutnya' : 'Untuk sesi ini saja'}${k.labelTell ? ' · agen sudah dikabari' : ''}',
                        ),
                      if (k.auto != null)
                        _section(context, 'Judul otomatis', k.auto!),
                      if (k.reply?.q != null)
                        _section(
                          context,
                          'Dia nanya',
                          k.reply!.q!,
                          strong: true,
                        ),
                      if (ask != null)
                        _section(
                          context,
                          ask.fromAgent ? 'Diminta agen' : 'Kamu minta',
                          ago.isEmpty ? ask.s : '${ask.s} ($ago)',
                        ),
                      if (k.reply != null)
                        _section(
                          context,
                          'Terakhir dia bilang',
                          replyAgo.isEmpty
                              ? k.reply!.s
                              : '${k.reply!.s} ($replyAgo)',
                        ),
                      if (k.err != null) _section(context, 'Galat', k.err!),
                      if (k.cardTitle != null)
                        _section(context, 'Kartu', k.cardTitle!),
                      if (k.fileCount > 0)
                        _section(
                          context,
                          'Berkas diubah (${k.fileCount})',
                          k.fileNames.join(', '),
                        ),
                      if (k.branch != null)
                        _section(context, 'Cabang', k.branch!),
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// Subtitle satu baris untuk daftar berbasis teks: "topik · keadaan: detail".
/// Tanpa konteks, memakai [fallback] apa adanya.
String kantorKonteksSubtitle(Json? session, String fallback) {
  final k = KantorKonteks.ofSession(session);
  if (k == null) return fallback;
  final d = k.detail(session);
  return [
    if (k.topic != null) k.topic!,
    d.isEmpty ? k.stateLabel : '${k.stateLabel}: $d',
  ].join(' · ');
}

/// Form label pemilik (web `labelFormHTML`). Opsi "bawa ke sesi berikutnya"
/// hanya untuk sesi ber-role.
Future<void> showKantorLabelSheet(
  BuildContext context, {
  required KantorKonteks konteks,
  required String name,
  required bool canCarry,
  required Future<void> Function(String text, bool carry, bool tell) onSave,
}) {
  return showChunkyBottomSheet<void>(
    context,
    title: konteks.label != null ? 'Ubah label' : 'Beri label',
    builder: (c) => _LabelForm(
      konteks: konteks,
      name: name,
      canCarry: canCarry,
      onSave: onSave,
    ),
  );
}

class _LabelForm extends StatefulWidget {
  const _LabelForm({
    required this.konteks,
    required this.name,
    required this.canCarry,
    required this.onSave,
  });

  final KantorKonteks konteks;
  final String name;
  final bool canCarry;
  final Future<void> Function(String text, bool carry, bool tell) onSave;

  @override
  State<_LabelForm> createState() => _LabelFormState();
}

class _LabelFormState extends State<_LabelForm> {
  late final _text = TextEditingController(text: widget.konteks.label ?? '');
  late bool _carry = widget.konteks.labelForRole;
  late bool _tell = widget.konteks.labelTell;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(String text) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(text.trim(), widget.canCarry && _carry, _tell);
      if (!mounted) return;
      final m = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      m?.showSnackBar(
        SnackBar(
          content: Text(
            text.trim().isEmpty ? 'Label dihapus' : 'Label disimpan',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final k = widget.konteks;
    final auto = k.label != null ? k.auto : k.topic;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChunkyTextField(
            key: const ValueKey('label-text'),
            label: 'Label untuk ${widget.name}',
            hint: 'mis. SEO gapeka, jadwal KA',
            controller: _text,
            maxLength: 240,
            minLines: 1,
            maxLines: 4,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: _busy ? null : _save,
          ),
          if (auto != null) ...[
            GhinaSpace.gapXs,
            Text(
              'Judul otomatis sekarang: $auto',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
          GhinaSpace.gapSm,
          if (widget.canCarry)
            SwitchListTile(
              key: const ValueKey('label-carry'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Bawa ke sesi berikutnya agen ini'),
              value: _carry,
              onChanged: _busy ? null : (v) => setState(() => _carry = v),
            ),
          SwitchListTile(
            key: const ValueKey('label-tell'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Kabari agennya'),
            subtitle: const Text('Disampaikan sekali di prompt berikutnya'),
            value: _tell,
            onChanged: _busy ? null : (v) => setState(() => _tell = v),
          ),
          if (_error != null) ...[
            GhinaSpace.gapSm,
            Text(
              _error!,
              style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
            ),
          ],
          GhinaSpace.gapMd,
          ChunkyButton(
            key: const ValueKey('label-save'),
            label: 'Simpan label',
            loading: _busy,
            onPressed: _busy ? null : () => _save(_text.text),
          ),
          if (k.label != null) ...[
            GhinaSpace.gapSm,
            ChunkyButton(
              key: const ValueKey('label-delete'),
              label: 'Hapus label',
              variant: ChunkyButtonVariant.ghost,
              onPressed: _busy ? null : () => _save(''),
            ),
          ],
        ],
      ),
    );
  }
}
