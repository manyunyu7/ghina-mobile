import 'package:flutter/material.dart';

import '../../../../../domain/entities/entities.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../widgets/tx_visuals.dart';

/// "Edit baris": type, amount, accounts, category, date and note of a pending
/// row. Returns only the fields that changed, or null when dismissed.
Future<StatementRowPatch?> showStatementRowEditSheet(
  BuildContext context, {
  required StatementRow row,
  required List<Wallet> wallets,
  required List<TxCategory> categories,
  required String currency,
}) => showChunkyBottomSheet<StatementRowPatch>(
  context,
  title: 'Edit baris',
  showClose: true,
  builder: (_) => _EditForm(
    row: row,
    wallets: wallets,
    categories: categories,
    currency: currency,
  ),
);

class _EditForm extends StatefulWidget {
  const _EditForm({
    required this.row,
    required this.wallets,
    required this.categories,
    required this.currency,
  });

  final StatementRow row;
  final List<Wallet> wallets;
  final List<TxCategory> categories;
  final String currency;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late TxType _type = widget.row.type;
  late final _amount = TextEditingController(
    text: amountToInput(widget.row.amount, widget.currency),
  );
  late final _note = TextEditingController(text: widget.row.title);
  late String? _walletId = _known(widget.row.walletId);
  late String? _toWalletId = _known(widget.row.toWalletId);
  late String? _categoryId = widget.row.categoryId;
  late DateTime _date = widget.row.date;
  String? _amountError;
  String? _walletError;
  String? _toWalletError;

  String? _known(String? id) =>
      widget.wallets.any((w) => w.id == id) ? id : null;

  String? _walletName(String? id) {
    for (final w in widget.wallets) {
      if (w.id == id) return w.name;
    }
    return null;
  }

  List<TxCategory> get _categoriesForType => [
    for (final c in widget.categories)
      if (c.type ==
          (_type == TxType.income ? CategoryType.income : CategoryType.expense))
        c,
  ];

  String? get _categoryName {
    for (final c in _categoriesForType) {
      if (c.id == _categoryId) return c.name;
    }
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseAmountInput(_amount.text);
    final transfer = _type == TxType.transfer;
    setState(() {
      _amountError = amount == null || amount <= 0
          ? 'Nominal harus lebih dari 0'
          : null;
      _walletError = _walletId == null ? 'Pilih dompet dulu' : null;
      _toWalletError = !transfer
          ? null
          : _toWalletId == null
          ? 'Pilih dompet tujuan'
          : _toWalletId == _walletId
          ? 'Dompet tujuan harus beda'
          : null;
    });
    if (_amountError != null ||
        _walletError != null ||
        _toWalletError != null) {
      return;
    }
    final r = widget.row;
    final note = _note.text.trim();
    final category = transfer || _categoryName == null ? null : _categoryId;
    Navigator.of(context).pop(
      StatementRowPatch(
        date: _date == r.date ? null : _date,
        type: _type == r.type ? null : _type,
        amount: amount == r.amount ? null : amount,
        note: note.isEmpty || note == r.title ? null : note,
        walletId: _walletId == r.walletId ? null : _walletId,
        toWalletId: transfer && _toWalletId != r.toWalletId
            ? _toWalletId
            : null,
        categoryId: category != r.categoryId ? category : null,
        clearCategory: category == null && r.categoryId != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _type == TxType.transfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChunkySegmented<TxType>(
          segments: [
            for (final t in TxType.loggable)
              ChunkySegment(value: t, label: t.label, color: txSwatch(t)),
          ],
          value: _type,
          onChanged: (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 16),
        AmountField(
          key: const Key('statement-edit-amount'),
          controller: _amount,
          currency: widget.currency,
          errorText: _amountError,
        ),
        const SizedBox(height: 12),
        PickerField(
          key: const Key('statement-edit-wallet'),
          label: transfer ? 'Dari dompet' : 'Dompet',
          value: _walletName(_walletId),
          placeholder: 'Pilih dompet',
          errorText: _walletError,
          onTap: () async {
            final id = await showWalletPickerSheet(
              context,
              wallets: widget.wallets,
              currency: widget.currency,
              selectedId: _walletId,
            );
            if (id != null && id.isNotEmpty && mounted) {
              setState(() => _walletId = id);
            }
          },
        ),
        const SizedBox(height: 12),
        if (transfer)
          PickerField(
            key: const Key('statement-edit-to-wallet'),
            label: 'Ke dompet',
            value: _walletName(_toWalletId),
            placeholder: 'Pilih dompet tujuan',
            errorText: _toWalletError,
            onTap: () async {
              final id = await showWalletPickerSheet(
                context,
                wallets: widget.wallets,
                currency: widget.currency,
                selectedId: _toWalletId,
                title: 'Dompet tujuan',
              );
              if (id != null && id.isNotEmpty && mounted) {
                setState(() => _toWalletId = id);
              }
            },
          )
        else
          PickerField(
            key: const Key('statement-edit-category'),
            label: 'Kategori',
            value: _categoryName,
            placeholder: 'Tanpa kategori',
            onTap: () async {
              final id = await showCategoryPickerSheet(
                context,
                categories: _categoriesForType,
                selectedId: _categoryId,
                noneLabel: 'Tanpa kategori',
              );
              if (id != null && mounted) {
                setState(() => _categoryId = id.isEmpty ? null : id);
              }
            },
          ),
        const SizedBox(height: 12),
        DateField(
          label: 'Tanggal',
          value: _date,
          onChanged: (d) => setState(
            () => _date = DateTime(
              d.year,
              d.month,
              d.day,
              _date.hour,
              _date.minute,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const Key('statement-edit-note'),
          label: 'Catatan',
          controller: _note,
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const Key('statement-edit-submit'),
          label: 'Simpan perubahan',
          icon: Icons.check_rounded,
          size: ChunkyButtonSize.large,
          onPressed: _submit,
        ),
      ],
    );
  }
}
