import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import 'kantor_actions.dart';
import 'kantor_feed.dart';

/// `session.blocker` dari daemon bila bentuknya bisa dipakai: layar terminal
/// yang menahan agen (`kind` `login` atau `prompt`). Daemon lama tidak
/// mengirim field ini: hasilnya null dan chat tidak menampilkan apa-apa.
Json? kantorBlockerOf(Object? raw) {
  if (raw is! Map) return null;
  final b = asJson(raw);
  final kind = b['kind'];
  if (kind is! String || kind.isEmpty) return null;
  return b;
}

/// Kunci pembanding dua blocker (isi sama = kartu sama).
String kantorBlockerKey(Json? b) => b == null ? '' : jsonEncode(b);

/// Kartu "agen tertahan" di chat: layar login (kode sekali pakai, tautan
/// login, tempel alamat/kode) atau layar terminal yang menunggu tombol.
/// Tombolnya mengirim `POST /api/sessions/:sid/blocker`; jawaban daemon
/// langsung mengganti isi kartu. Saat login selesai (blocker jadi null)
/// kartu hijau "✓ `<agen>` sudah login" tampil [okFor] lalu hilang.
///
/// Tanpa blocker (dan bukan dalam masa kartu sukses) widget ini kosong.
class KantorBlockerCard extends StatefulWidget {
  const KantorBlockerCard({
    super.key,
    required this.blocker,
    required this.sid,
    required this.api,
    this.who = 'Agen',
    this.padding = EdgeInsets.zero,
    this.onActed,
  });

  /// Sudah lewat [kantorBlockerOf]; hanya dari data segar (bukan cache).
  final Json? blocker;
  final String sid;
  final KantorApi? api;
  final String who;
  final EdgeInsetsGeometry padding;

  /// Dipanggil setelah daemon menerima satu aksi (mis. muat ulang transkrip).
  final VoidCallback? onActed;

  static const okFor = Duration(seconds: 3);

  @override
  State<KantorBlockerCard> createState() => _KantorBlockerCardState();
}

class _KantorBlockerCardState extends State<KantorBlockerCard> {
  Json? _shown;
  bool _ok = false;
  Timer? _okTimer;
  Timer? _tick;
  String? _busy;
  String? _err;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _shown = widget.blocker;
    _syncTick();
  }

  @override
  void didUpdateWidget(KantorBlockerCard old) {
    super.didUpdateWidget(old);
    if (kantorBlockerKey(widget.blocker) != kantorBlockerKey(old.blocker)) {
      _show(widget.blocker);
    }
  }

  @override
  void dispose() {
    _okTimer?.cancel();
    _tick?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// Ganti isi kartu; login yang selesai memberi kartu sukses sebentar.
  void _show(Json? next) {
    final prev = _shown;
    if (kantorBlockerKey(prev) == kantorBlockerKey(next)) return;
    if (prev != null && next == null && prev['kind'] == 'login') {
      _ok = true;
      _okTimer?.cancel();
      _okTimer = Timer(KantorBlockerCard.okFor, () {
        if (mounted) setState(() => _ok = false);
      });
    } else if (next != null) {
      _ok = false;
      _okTimer?.cancel();
    }
    if (asJson(prev?['input'])['id'] != asJson(next?['input'])['id']) {
      _input.clear();
    }
    _shown = next;
    _err = null;
    _syncTick();
  }

  DateTime? get _expires {
    final b = _shown;
    if (b == null || b['code'] == null) return null;
    final e = b['expiresAt'];
    return e is String ? DateTime.tryParse(e) : null;
  }

  /// Hitung mundur kode: detak tiap detik hanya selama kode masih berlaku.
  void _syncTick() {
    final exp = _expires;
    final live = exp != null && exp.isAfter(DateTime.now());
    if (!live) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final e = _expires;
        if (e == null || !e.isAfter(DateTime.now())) {
          _tick?.cancel();
          _tick = null;
        }
        setState(() {});
      });
    }
  }

  Future<void> _send(String action, {String? value}) async {
    final api = widget.api;
    if (api == null || _busy != null) return;
    setState(() {
      _busy = action;
      _err = null;
    });
    try {
      final r = await KantorActions(
        api,
      ).blocker(widget.sid, action, value: value);
      if (!mounted) return;
      setState(() {
        _busy = null;
        if (r != null && r.containsKey('blocker')) {
          _show(kantorBlockerOf(r['blocker']));
        }
      });
      widget.onActed?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _err = clip(
          e is KantorException ? e.message : 'Gagal mengirim ke agen.',
          140,
        );
      });
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    try {
      if (uri != null) {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      ok = false;
    }
    if (ok || !mounted) return;
    // tidak ada browser yang mau membuka: alamatnya disalin saja
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      setState(() => _err = 'Browser tidak terbuka. Alamat login disalin.');
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Kode disalin'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (!mounted) return;
    if (t.isEmpty) {
      setState(() => _err = 'Clipboard kosong.');
      return;
    }
    _input.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
    setState(() => _err = null);
  }

  @override
  Widget build(BuildContext context) {
    final b = _shown;
    Widget? card;
    if (b != null) {
      card = _card(context, b);
    } else if (_ok) {
      card = _okCard(context);
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.bottomCenter,
      child: card == null
          ? const SizedBox(width: double.infinity)
          : Padding(padding: widget.padding, child: card),
    );
  }

  Widget _okCard(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      key: const ValueKey('blocker-ok'),
      tinted: GhinaColors.green,
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          '✓ ${widget.who} sudah login',
          style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Json b) {
    final g = context.ghina;
    final login = b['kind'] == 'login';
    final title = '${b['title'] ?? ''}'.trim();
    final detail = '${b['detail'] ?? ''}'.trim();
    final url = '${b['url'] ?? ''}'.trim();
    final code = '${b['code'] ?? ''}'.trim();
    final input = b['input'] is Map ? asJson(b['input']) : null;
    final actions = [
      for (final a in asJsonList(b['actions']))
        if ('${a['id'] ?? ''}'.isNotEmpty) a,
    ];
    final busy = _busy != null;
    final pillSwatch = login ? GhinaColors.yellow : GhinaColors.blue;

    final children = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: pillSwatch.tint(g.brightness),
            borderRadius: GhinaRadii.rPill,
          ),
          child: Text(
            login ? 'Perlu login' : 'Menunggu di terminal',
            style: GhinaType.caption
                .w(800)
                .copyWith(
                  color: login ? const Color(0xFF9A6B00) : pillSwatch.base,
                ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        title.isEmpty
            ? (login
                  ? '${widget.who} perlu login'
                  : '${widget.who} menunggu di terminal')
            : title,
        style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
      ),
      if (detail.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(detail, style: GhinaType.caption.copyWith(color: g.textSecondary)),
      ],
    ];

    if (code.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: GhinaSpace.md),
          child: CustomPaint(
            painter: _DashedBox(
              color: GhinaColors.yellow.base,
              fill: GhinaColors.yellow.tint(g.brightness),
            ),
            child: Container(
              key: const ValueKey('blocker-code'),
              width: double.infinity,
              padding: const EdgeInsets.all(GhinaSpace.md),
              alignment: Alignment.center,
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Menlo', 'Courier'],
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: g.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    } else if (url.isNotEmpty || input != null || actions.isNotEmpty) {
      children.add(const SizedBox(height: GhinaSpace.sm));
    }

    if (url.isNotEmpty || code.isNotEmpty) {
      final open = url.isEmpty
          ? null
          : ChunkyButton(
              key: const ValueKey('blocker-open'),
              label: 'Buka halaman login ↗',
              variant: ChunkyButtonVariant.secondary,
              size: ChunkyButtonSize.small,
              uppercase: false,
              onPressed: () => _open(url),
            );
      final copy = code.isEmpty
          ? null
          : ChunkyButton(
              key: const ValueKey('blocker-copy'),
              label: 'Salin kode',
              variant: ChunkyButtonVariant.outline,
              size: ChunkyButtonSize.small,
              uppercase: false,
              expand: open == null,
              onPressed: () => _copy(code),
            );
      children.add(
        Row(
          children: [
            if (open != null) Expanded(child: open),
            if (open != null && copy != null)
              const SizedBox(width: GhinaSpace.sm),
            if (copy != null) open == null ? Expanded(child: copy) : copy,
          ],
        ),
      );
    }

    final exp = _expires;
    if (code.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: GhinaSpace.sm),
          child: Text(
            _countdown(exp),
            key: const ValueKey('blocker-countdown'),
            style: GhinaType.caption.copyWith(
              color: exp != null && !exp.isAfter(DateTime.now())
                  ? GhinaColors.red.base
                  : g.textMuted,
            ),
          ),
        ),
      );
    }

    if (input != null) {
      final id = '${input['id'] ?? 'code'}';
      final label = '${input['label'] ?? ''}'.trim();
      final hint = '${input['placeholder'] ?? ''}'.trim();
      if (url.isNotEmpty || code.isNotEmpty) {
        children.add(const SizedBox(height: GhinaSpace.sm));
      }
      if (label.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label,
              style: GhinaType.caption.w(700).copyWith(color: g.textSecondary),
            ),
          ),
        );
      }
      children.add(
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('blocker-input'),
                controller: _input,
                enabled: !busy,
                minLines: 1,
                maxLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: id == 'callback'
                    ? TextInputType.url
                    : TextInputType.visiblePassword,
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint.isEmpty
                      ? (id == 'callback'
                            ? 'Tempel alamat dari browser'
                            : 'Tempel kode dari halaman login')
                      : hint,
                  filled: true,
                  fillColor: g.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: GhinaRadii.rMd,
                    borderSide: BorderSide(color: g.border, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: GhinaRadii.rMd,
                    borderSide: BorderSide(color: g.border, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('blocker-paste'),
              tooltip: 'Tempel dari clipboard',
              onPressed: busy ? null : _paste,
              icon: const Icon(Icons.content_paste_rounded),
            ),
          ],
        ),
      );
      children.add(const SizedBox(height: GhinaSpace.sm));
      children.add(
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (context, v, _) => ChunkyButton(
            key: const ValueKey('blocker-send'),
            label: id == 'callback' ? 'Kirim ke ${widget.who}' : 'Kirim kode',
            size: ChunkyButtonSize.small,
            uppercase: false,
            expand: true,
            loading: _busy == id,
            onPressed: busy || v.text.trim().isEmpty
                ? null
                : () => _send(id, value: v.text.trim()),
          ),
        ),
      );
    }

    if (actions.isNotEmpty) {
      children.add(const SizedBox(height: GhinaSpace.sm));
      Widget btn(Json a, {bool? expand}) {
        final id = '${a['id']}';
        return ChunkyButton(
          key: ValueKey('blocker-act-$id'),
          label: '${a['label'] ?? id}',
          variant: a['primary'] == true
              ? ChunkyButtonVariant.primary
              : ChunkyButtonVariant.outline,
          color: a['primary'] == true ? GhinaColors.green : null,
          size: ChunkyButtonSize.small,
          uppercase: false,
          expand: expand ?? false,
          loading: _busy == id,
          onPressed: busy ? null : () => _send(id),
        );
      }

      children.add(
        actions.length <= 2
            ? Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: GhinaSpace.sm),
                    Expanded(child: btn(actions[i], expand: true)),
                  ],
                ],
              )
            : Wrap(
                spacing: GhinaSpace.sm,
                runSpacing: GhinaSpace.sm,
                children: [for (final a in actions) btn(a)],
              ),
      );
    }

    if (_err != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: GhinaSpace.sm),
          child: Text(
            _err!,
            key: const ValueKey('blocker-error'),
            style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
          ),
        ),
      );
    }

    return ChunkyCard(
      key: const ValueKey('blocker-card'),
      tinted: login ? GhinaColors.yellow : null,
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  String _countdown(DateTime? exp) {
    const tail = ' · kartu hilang sendiri setelah berhasil';
    if (exp == null) return 'Masukkan kode ini di halaman login$tail';
    final left = exp.difference(DateTime.now());
    if (left.inSeconds <= 0) return 'Kode sudah kedaluwarsa. Minta kode baru.';
    final m = left.inMinutes;
    final s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return 'Kode berlaku $m:$s lagi$tail';
  }
}

/// Kotak kuning bergaris putus-putus untuk kode sekali pakai.
class _DashedBox extends CustomPainter {
  const _DashedBox({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(GhinaRadii.md),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect.deflate(0.75));
    for (final PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), stroke);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color || old.fill != fill;
}
