import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../controllers/screener_providers.dart';
import 'screener_common.dart';

/// "Hubungkan Stockbit": the user pastes text they copied themselves from
/// Stockbit; it is checked against Stockbit and kept only on this phone.
/// Resolves to true when a connection was made.
Future<bool> showStockbitConnectSheet(BuildContext context) async {
  final done = await showChunkyBottomSheet<bool>(
    context,
    title: 'Hubungkan Stockbit',
    showClose: true,
    builder: (_) => const StockbitConnectSheet(),
  );
  return done ?? false;
}

/// `s/d 18 Okt 2026 14.05`
String _until(DateTime t) => 's/d ${Fmt.date(t)} ${Fmt.time(t)}';

/// What the text pasted so far looks like, before anything is sent.
String? stockbitPastePreview(String text) {
  if (text.trim().isEmpty) return null;
  return switch (parseStockbitInput(text)) {
    StockbitParsed(:final tokens) => [
      if (tokens.access != null)
        'Token akses terbaca${tokens.accessExpiresAt == null ? '' : ', berlaku ${_until(tokens.accessExpiresAt!)}'}.',
      if (tokens.refresh != null)
        'Token perpanjangan terbaca${tokens.refreshExpiresAt == null ? '' : ', berlaku ${_until(tokens.refreshExpiresAt!)}'}.',
    ].join(' '),
    StockbitPending() => stockbitPendingMessage,
    StockbitUnrecognized() => 'Belum ada token yang bisa dikenali di teks ini.',
  };
}

class StockbitConnectSheet extends ConsumerStatefulWidget {
  const StockbitConnectSheet({super.key});

  @override
  ConsumerState<StockbitConnectSheet> createState() =>
      _StockbitConnectSheetState();
}

class _StockbitConnectSheetState extends ConsumerState<StockbitConnectSheet> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  StockbitTokens? _saved;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ref
          .read(stockbitSessionServiceProvider)
          .connect(_input.text);
      if (!mounted) return;
      _input.clear();
      ref.invalidate(stockbitTokensProvider);
      setState(() {
        _busy = false;
        _saved = t;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = screenerErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      _saved == null ? _paste(context) : _success(context, _saved!);

  Widget _paste(BuildContext context) {
    final g = context.ghina;
    final preview = _error == null ? stockbitPastePreview(_input.text) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tempel teks yang kamu salin sendiri dari Stockbit: token, header '
          'Authorization, "Copy as cURL", atau respons login. Disimpan di HP '
          'ini saja, dan Ghina nggak pernah menerimanya.',
          style: GhinaType.body.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          controller: _input,
          hint: 'Tempel di sini',
          minLines: 4,
          maxLines: 8,
          enabled: !_busy,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.none,
          errorText: _error,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (preview != null) ...[
          const SizedBox(height: 8),
          Text(
            preview,
            key: const ValueKey('paste-preview'),
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        ChunkyButton(
          label: 'Hubungkan',
          loading: _busy,
          uppercase: false,
          onPressed: _busy || _input.text.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }

  Widget _success(BuildContext context, StockbitTokens t) {
    final g = context.ghina;
    final auto = t.refresh != null;
    final exp = auto ? t.refreshExpiresAt : t.accessExpiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: MascotView(mood: MascotMood.happy, size: 96)),
        const SizedBox(height: 12),
        Text(
          'Mantap! Stockbit sudah terhubung.',
          textAlign: TextAlign.center,
          style: GhinaType.h3.copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          auto
              ? 'Sesi diperpanjang otomatis di HP ini${exp == null ? '' : ', ${_until(exp)}'}.'
              : 'Aktif di HP ini${exp == null ? '' : ' ${_until(exp)}'}.',
          textAlign: TextAlign.center,
          style: GhinaType.body.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          label: 'Selesai',
          uppercase: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
