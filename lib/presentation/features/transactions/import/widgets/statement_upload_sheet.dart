import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../di/di.dart';
import '../../../../../domain/entities/entities.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../state/killa_access_provider.dart';
import '../../../../state/session_controller.dart' show currencyProvider;
import '../statement_state.dart';

/// "Unggah PDF": the picked file, the statement's account (optional) and, only
/// when the server says the PDF is locked, its password. Uploads on "Unggah"
/// and returns the created import, or null when dismissed.
Future<StatementImport?> showStatementUploadSheet(
  BuildContext context, {
  required String fileName,
  required Uint8List bytes,
}) => showChunkyBottomSheet<StatementImport>(
  context,
  title: 'Impor mutasi',
  showClose: true,
  builder: (_) => _UploadForm(fileName: fileName, bytes: bytes),
);

class _UploadForm extends ConsumerStatefulWidget {
  const _UploadForm({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;

  @override
  ConsumerState<_UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends ConsumerState<_UploadForm> {
  final _password = TextEditingController();
  String? _walletId;
  bool _askPassword = false;
  String? _passwordError;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String? _walletName(List<Wallet> wallets) {
    for (final w in wallets) {
      if (w.id == _walletId) return w.name;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _password.text;
    if (_askPassword && password.isEmpty) {
      setState(() => _passwordError = 'Isi password-nya dulu');
      return;
    }
    setState(() {
      _busy = true;
      _passwordError = null;
    });
    try {
      final created = await ref
          .read(statementRepositoryProvider)
          .upload(
            StatementUpload(
              name: widget.fileName,
              bytes: widget.bytes,
              walletId: _walletId,
              password: _askPassword ? password : null,
            ),
          );
      ref.read(killaAccessProvider.notifier).markAllowed();
      if (mounted) Navigator.of(context).pop(created);
    } on StatementException catch (e) {
      if (!mounted) return;
      switch (e.kind) {
        case StatementErrorKind.passwordRequired:
          setState(() {
            _askPassword = true;
            _busy = false;
          });
        case StatementErrorKind.passwordWrong:
          setState(() {
            _askPassword = true;
            _passwordError = e.message;
            _busy = false;
          });
        case StatementErrorKind.forbidden:
          ref.read(killaAccessProvider.notifier).markForbidden();
          Navigator.of(context).pop();
          showErrorToast(context, e.message);
        default:
          setState(() => _busy = false);
          showErrorToast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChunkyTile(
          key: const Key('statement-upload-file'),
          dense: true,
          leading: CategoryAvatar(
            icon: Icons.picture_as_pdf_rounded,
            color: GhinaColors.red.base,
            size: 40,
            soft: true,
          ),
          title: widget.fileName,
          subtitle: fileSizeLabel(widget.bytes.length),
        ),
        const SizedBox(height: 12),
        PickerField(
          key: const Key('statement-upload-wallet'),
          label: 'Rekening yang mana?',
          value: _walletName(wallets),
          placeholder: 'Biar Killa yang tebak',
          onTap: () async {
            final id = await showWalletPickerSheet(
              context,
              wallets: wallets,
              currency: ref.read(currencyProvider),
              selectedId: _walletId,
              title: 'Rekening mutasi ini',
              noneLabel: 'Biar Killa yang tebak',
            );
            if (id != null && mounted) {
              setState(() => _walletId = id.isEmpty ? null : id);
            }
          },
        ),
        if (_askPassword) ...[
          const SizedBox(height: 12),
          ChunkyTextField(
            key: const Key('statement-upload-password'),
            label: 'Password PDF',
            controller: _password,
            obscureText: true,
            autofocus: true,
            errorText: _passwordError,
            helperText:
                'PDF ini dikunci. Masukkan password-nya — tidak '
                'disimpan.',
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Killa bakal baca mutasinya, lalu kamu cek dulu sebelum disimpan.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          key: const Key('statement-upload-submit'),
          label: _busy ? 'Mengunggah…' : 'Unggah',
          icon: Icons.upload_rounded,
          size: ChunkyButtonSize.large,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
