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

  /// Konteks sesi, dengan label yang baru disimpan pemilik
  /// ([kantorLabelPatches]) bila data segar server belum memuatnya.
  static KantorKonteks? ofSession(Json? session) {
    final k = fromJson(session?['konteks']);
    if (k == null || session == null) return k;
    final p = kantorLabelPatches.of('${session['sid']}');
    return p == null ? k : k._withLabel(p);
  }

  /// Salinan dengan label [p]: label menjadi topik dan judul otomatis
  /// tergeser ke [auto], seperti yang dilakukan server.
  KantorKonteks _withLabel(KantorLabelPatch p) {
    final auto0 = label != null ? auto : topic;
    final text = p.text;
    return KantorKonteks(
      stateKey: stateKey,
      stateLabel: stateLabel,
      topic: text ?? auto0,
      step: step,
      percent: percent,
      draftTitle: draftTitle,
      draftReady: draftReady,
      draftDetails: draftDetails,
      ask: ask,
      reply: reply,
      err: err,
      fileNames: fileNames,
      fileCount: fileCount,
      cardTitle: cardTitle,
      branch: branch,
      label: text,
      labelForRole: text != null && p.forRole,
      labelTell: text != null && p.tell,
      auto: text == null ? null : auto0,
    );
  }

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

/// Label yang baru disimpan pemilik ([text] null = dihapus).
@immutable
class KantorLabelPatch {
  KantorLabelPatch(this.text, {this.forRole = false, this.tell = false})
    : at = DateTime.now();
  final String? text;
  final bool forRole;
  final bool tell;
  final DateTime at;
}

/// Tampilan optimistis label: dipasang saat pemilik menyimpan label, dilepas
/// begitu data segar dari server tiba (atau gagal disimpan). Hanya untuk
/// tampilan; status dan izin tetap dari server. Disimpan global (bukan
/// provider) supaya widget tanpa ProviderScope pun ikut memakainya.
class KantorLabelPatches extends ChangeNotifier {
  /// Patch yang tertinggal (mis. muat ulang gagal) tidak dipakai lagi.
  static const maxAge = Duration(seconds: 45);

  final _bySid = <String, KantorLabelPatch>{};

  KantorLabelPatch? of(String sid) {
    final p = _bySid[sid];
    if (p == null) return null;
    return DateTime.now().difference(p.at) > maxAge ? null : p;
  }

  void put(String sid, KantorLabelPatch p) {
    _bySid[sid] = p;
    notifyListeners();
  }

  /// Lepas patch [sid]; bila [only] diberikan, hanya bila patch itu masih
  /// yang terpasang (simpanan yang lebih baru tidak ikut terlepas).
  void drop(String sid, [KantorLabelPatch? only]) {
    final p = _bySid[sid];
    if (p == null || (only != null && !identical(p, only))) return;
    _bySid.remove(sid);
    notifyListeners();
  }

  @visibleForTesting
  void clear() {
    _bySid.clear();
    notifyListeners();
  }
}

final kantorLabelPatches = KantorLabelPatches();

/// Label pemilik untuk [session] (sudah termasuk patch optimistis), atau null.
String? kantorLabelOf(Json? session) => KantorKonteks.ofSession(session)?.label;

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

/// Stiker label [session] yang ikut berubah saat label disimpan
/// (optimistis); tanpa label tidak menampilkan apa pun ([empty]).
class KantorSessionLabel extends StatelessWidget {
  const KantorSessionLabel({
    super.key,
    required this.session,
    this.maxLines = 2,
    this.size,
    this.onTap,
    this.padding = const EdgeInsets.only(top: 2, bottom: 2),
    this.empty = const SizedBox.shrink(),
  });

  final Json session;
  final int? maxLines;
  final double? size;
  final EdgeInsets padding;

  /// Ketuk stiker (mis. membuka form ubah label).
  final VoidCallback? onTap;

  /// Ditampilkan bila sesi tidak berlabel.
  final Widget empty;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kantorLabelPatches,
    builder: (context, _) {
      final l = kantorLabelOf(session);
      if (l == null) return empty;
      final sticker = Padding(
        padding: padding,
        child: KantorLabelSticker(l, maxLines: maxLines, size: size),
      );
      if (onTap == null) return sticker;
      return Semantics(
        button: true,
        label: 'Label: $l. Ketuk untuk mengubah',
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('label-sticker-${session['sid']}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: sticker,
        ),
      );
    },
  );
}

/// Pojok kertas kuning terlipat, ditempel di avatar agen yang berlabel.
class KantorLabelCorner extends StatelessWidget {
  const KantorLabelCorner({super.key, this.size = 13});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _CornerPainter());
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, fold = w * .42;
    // kertas: persegi dengan pojok kanan bawah terlipat
    final paper = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - fold)
      ..lineTo(w - fold, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawShadow(paper, KantorLabelSticker.edge, 1, false);
    canvas.drawPath(paper, Paint()..color = KantorLabelSticker.paper);
    canvas.drawPath(
      Path()
        ..moveTo(w, h - fold)
        ..lineTo(w - fold, h - fold)
        ..lineTo(w - fold, h)
        ..close(),
      Paint()..color = KantorLabelSticker.edge,
    );
    canvas.drawPath(
      paper,
      Paint()
        ..color = KantorLabelSticker.edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kantorLabelPatches,
    builder: (context, _) => _lines(context),
  );

  Widget _lines(BuildContext context) {
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kantorLabelPatches,
    builder: (context, _) => _bar(context),
  );

  Widget _bar(BuildContext context) {
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
                        widget.session,
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
/// Tanpa konteks, memakai [fallback] apa adanya. [withLabel] false: topik
/// dilewati bila itu label pemilik (labelnya sudah tampil sebagai stiker).
String kantorKonteksSubtitle(
  Json? session,
  String fallback, {
  bool withLabel = true,
}) {
  final k = KantorKonteks.ofSession(session);
  if (k == null) return fallback;
  final d = k.detail(session);
  return [
    if (k.topic != null && (withLabel || k.label == null)) k.topic!,
    d.isEmpty ? k.stateLabel : '${k.stateLabel}: $d',
  ].join(' · ');
}

/// Form label pemilik untuk [session] (web `labelFormHTML`): kolom teks,
/// "Bawa ke sesi berikutnya agen ini" (hanya sesi ber-role), "Kabari
/// agennya", lalu Simpan / Hapus label / Batal. [onSave] menerima teks yang
/// sudah dirapikan; teks kosong = hapus. [name] menimpa nama agen di judul
/// kolom (default `look.name` sesi).
Future<void> showKantorLabelSheet(
  BuildContext context,
  Json session, {
  required Future<void> Function(String text, bool carry, bool tell) onSave,
  String? name,
}) {
  final konteks =
      KantorKonteks.ofSession(session) ??
      const KantorKonteks(stateKey: '', stateLabel: '');
  final look = session['look'];
  return showChunkyBottomSheet<void>(
    context,
    title: konteks.label != null ? 'Ubah label' : 'Beri label',
    builder: (c) => _LabelForm(
      konteks: konteks,
      name:
          name ??
          (look is Map && _str(look['name']) != null
              ? _str(look['name'])!
              : 'sesi ini'),
      canCarry: _str(session['role']) != null,
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
    final clear = text.trim().isEmpty;
    try {
      // hapus label: opsi ikut dimatikan, sama seperti web
      await widget.onSave(
        text.trim(),
        !clear && widget.canCarry && _carry,
        !clear && _tell,
      );
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
        showToastBadge(
          context,
          message: clear ? 'Label gagal dihapus' : 'Label gagal disimpan',
          icon: Icons.error_outline_rounded,
          color: GhinaColors.red,
          tag: 'kantor-label',
        );
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
          GhinaSpace.gapSm,
          Row(
            children: [
              if (k.label != null) ...[
                Expanded(
                  child: ChunkyButton(
                    key: const ValueKey('label-delete'),
                    label: 'Hapus label',
                    variant: ChunkyButtonVariant.ghost,
                    onPressed: _busy ? null : () => _save(''),
                  ),
                ),
                const SizedBox(width: GhinaSpace.sm),
              ],
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('label-cancel'),
                  label: 'Batal',
                  variant: ChunkyButtonVariant.ghost,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
