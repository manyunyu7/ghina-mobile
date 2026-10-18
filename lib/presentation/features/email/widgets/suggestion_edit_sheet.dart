import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'suggestion_card.dart';

/// "Edit lalu setujui": kind, amount, wallet(s), category, date and note.
/// Returns the approval, or null when dismissed.
Future<EmailApproval?> showSuggestionEditSheet(
  BuildContext context, {
  required EmailSuggestion suggestion,
  required List<Wallet> wallets,
  required List<TxCategory> categories,
  required String currency,
}) => showChunkyBottomSheet<EmailApproval>(
  context,
  title: 'Edit sebelum disetujui',
  showClose: true,
  builder: (_) => _EditForm(
    suggestion: suggestion,
    wallets: wallets,
    categories: categories,
    currency: currency,
  ),
);

class _EditForm extends StatefulWidget {
  const _EditForm({
    required this.suggestion,
    required this.wallets,
    required this.categories,
    required this.currency,
  });

  final EmailSuggestion suggestion;
  final List<Wallet> wallets;
  final List<TxCategory> categories;
  final String currency;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late EmailSuggestionKind _kind = widget.suggestion.kind;
  late final _amount = TextEditingController(
    text: amountToInput(widget.suggestion.amount, widget.currency),
  );
  late final _note = TextEditingController(
    text: widget.suggestion.note.isNotEmpty
        ? widget.suggestion.note
        : widget.suggestion.merchant,
  );
  late String? _walletId = _known(widget.suggestion.walletId);
  String? _toWalletId;
  late String? _categoryId = widget.suggestion.categoryId;
  late DateTime _date = widget.suggestion.occurredAt;
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

  List<TxCategory> get _categoriesForKind => [
    for (final c in widget.categories)
      if (c.type ==
          (_kind == EmailSuggestionKind.income
              ? CategoryType.income
              : CategoryType.expense))
        c,
  ];

  String? get _categoryName {
    for (final c in _categoriesForKind) {
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
    final transfer = _kind == EmailSuggestionKind.transfer;
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
    final s = widget.suggestion;
    final note = _note.text.trim();
    Navigator.of(context).pop(
      EmailApproval(
        kind: _kind == s.kind ? null : _kind,
        amount: amount == s.amount ? null : amount,
        walletId: _walletId,
        toWalletId: transfer ? _toWalletId : null,
        categoryId: transfer
            ? null
            : _categoryName == null
            ? null
            : _categoryId,
        note: note == s.note ? null : note,
        occurredAt: _date == s.occurredAt ? null : _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _kind == EmailSuggestionKind.transfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChunkySegmented<EmailSuggestionKind>(
          segments: [
            for (final k in EmailSuggestionKind.values)
              ChunkySegment(
                value: k,
                label: k.label,
                color: emailKindSwatch(k),
              ),
          ],
          value: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 16),
        AmountField(
          key: const Key('email-edit-amount'),
          controller: _amount,
          currency: widget.currency,
          errorText: _amountError,
        ),
        const SizedBox(height: 12),
        PickerField(
          key: const Key('email-edit-wallet'),
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
            key: const Key('email-edit-to-wallet'),
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
            key: const Key('email-edit-category'),
            label: 'Kategori',
            value: _categoryName,
            placeholder: 'Tanpa kategori',
            onTap: () async {
              final id = await showCategoryPickerSheet(
                context,
                categories: _categoriesForKind,
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
          key: const Key('email-edit-note'),
          label: 'Catatan',
          controller: _note,
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const Key('email-edit-submit'),
          label: 'Setujui',
          icon: Icons.check_rounded,
          size: ChunkyButtonSize.large,
          onPressed: _submit,
        ),
      ],
    );
  }
}
