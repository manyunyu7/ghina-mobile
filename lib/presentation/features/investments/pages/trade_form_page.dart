import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/fee_preset_controller.dart';
import '../investment_format.dart';
import '../widgets/invest_fields.dart';
import '../widgets/portfolio_widgets.dart';
import '../widgets/trade_row.dart';
import 'asset_detail_page.dart' show confirmDeleteTrade;

/// Record or edit a trade: buy / sell (lot ↔ lembar, price, fee presets),
/// dividend, split or a fee row, with the cash effect and a live preview of
/// the cash impact, the resulting holding and the realized P/L.
class TradeFormPage extends ConsumerStatefulWidget {
  const TradeFormPage({
    super.key,
    required this.assetId,
    this.tradeId,
    this.initialType,
  });

  final String assetId;

  /// Null = new trade.
  final String? tradeId;

  /// Preselected type (wire id) of a new trade (`?type=sell`).
  final String? initialType;

  @override
  ConsumerState<TradeFormPage> createState() => _TradeFormPageState();
}

const _newTradeId = '__new_trade__';

class _TradeFormPageState extends ConsumerState<TradeFormPage> {
  bool get _isEdit => widget.tradeId != null;

  late TradeType _type =
      TradeType.tryFromWire(widget.initialType) ?? TradeType.buy;
  bool _lots = true;
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _fee = TextEditingController();
  final _amount = TextEditingController();
  final _ratio = TextEditingController();
  final _note = TextEditingController();
  bool _feeAuto = true;
  late DateTime _date;
  bool _cash = false;
  String? _walletId;
  AssetTrade? _original;
  bool _loaded = false;
  bool _saving = false;
  bool _deleted = false;
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _date = ref.read(clockProvider).now();
    for (final c in [_qty, _price, _fee, _amount, _ratio]) {
      c.addListener(_refresh);
    }
  }

  /// Set while [_init] fills the controllers (inside build).
  bool _silent = false;

  void _refresh() {
    if (!mounted || _silent) return;
    _syncAutoFee();
    setState(() {});
  }

  /// Keeps the fee field showing the preset fee while it's automatic.
  void _syncAutoFee() {
    if (!_feeAuto || !_type.needsQuantityAndPrice) return;
    final f = ref.read(feePresetProvider).feeFor(_type, _gross);
    final text = numberToInput(f, decimals: 2);
    if (_fee.text == text) return;
    _fee.removeListener(_refresh);
    _fee.text = text;
    _fee.addListener(_refresh);
  }

  @override
  void dispose() {
    for (final c in [_qty, _price, _fee, _amount, _ratio, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _init(AssetDetail d) {
    _silent = true;
    try {
      _fill(d);
    } finally {
      _silent = false;
    }
    _syncAutoFee();
  }

  void _fill(AssetDetail d) {
    final a = d.asset;
    _lots = a.kind.usesLots;
    if (_isEdit) {
      final v = d.trades.where((t) => t.id == widget.tradeId).firstOrNull;
      if (v == null) return;
      final t = v.trade;
      _original = t;
      _type = t.type;
      _date = t.date;
      final q = t.quantity;
      _lots = a.kind.usesLots && (q == null || isWholeLots(q));
      _qty.text = q == null
          ? ''
          : numberToInput(_lots ? sharesToLots(q) : q, decimals: 8);
      _price.text = numberToInput(t.price, decimals: 4);
      _fee.text = numberToInput(t.fee, decimals: 2);
      _feeAuto = false;
      _amount.text = numberToInput(t.amount, decimals: 2);
      _ratio.text = numberToInput(t.ratio, decimals: 4);
      _note.text = t.note ?? '';
      _cash = v.transaction != null;
      _walletId = v.transaction?.walletId ?? a.walletId;
    } else {
      final p = d.view.quote.price;
      if (p != null) _price.text = numberToInput(p, decimals: 4);
      _walletId = a.walletId;
      _cash = a.walletId != null;
    }
    _loaded = true;
  }

  // ------------------------------------------------------------ parsing

  double? _num(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseNumber(c.text);

  /// Quantity in units (shares), lots converted.
  double? get _shares {
    final q = _num(_qty);
    if (q == null) return null;
    return _lots ? lotsToShares(q) : q;
  }

  double get _gross => (_shares ?? 0) * (_num(_price) ?? 0);

  double _feeValue(FeePreset preset) =>
      _feeAuto ? preset.feeFor(_type, _gross) : (_num(_fee) ?? 0);

  /// The trade as it would be saved (null when the inputs are incomplete).
  AssetTrade? _draft(Asset a, FeePreset preset) {
    final now = ref.read(clockProvider).now();
    double? q, p, amount, ratio;
    var fee = 0.0;
    switch (_type) {
      case TradeType.buy:
      case TradeType.sell:
        q = _shares;
        p = _num(_price);
        if (q == null || q <= 0 || p == null || p <= 0) return null;
        fee = _feeValue(preset);
      case TradeType.dividend:
      case TradeType.fee:
        amount = _num(_amount);
        if (amount == null || amount <= 0) return null;
      case TradeType.split:
        ratio = _num(_ratio);
        if (ratio == null || ratio <= 0 || ratio == 1) return null;
    }
    return AssetTrade(
      id: _original?.id ?? _newTradeId,
      assetId: a.id,
      type: _type,
      date: _date,
      quantity: q,
      price: p,
      fee: fee,
      amount: amount,
      ratio: ratio,
      cashTransactionId: _original?.cashTransactionId,
      createdAt: _original?.createdAt ?? now,
      updatedAt: now,
    );
  }

  // ------------------------------------------------------------ actions

  void _setType(TradeType t) {
    setState(() {
      _type = t;
      _errors.clear();
      if (!_isEdit) _feeAuto = true;
      _syncAutoFee();
    });
  }

  void _setLots(bool lots) {
    if (lots == _lots) return;
    final q = _num(_qty);
    setState(() {
      _lots = lots;
      if (q != null) {
        _qty.text = numberToInput(
          lots ? sharesToLots(q) : lotsToShares(q),
          decimals: 8,
        );
      }
    });
  }

  Future<void> _editRate(FeePreset preset) async {
    final buy = _type == TradeType.buy;
    final ctrl = TextEditingController(
      text: Fmt.number(
        (buy ? preset.buy : preset.sell) * 100,
        decimals: 3,
      ).replaceFirst(RegExp(r',?0+$'), ''),
    );
    final rate = await showChunkyBottomSheet<double>(
      context,
      title: buy ? 'Biaya beli (%)' : 'Biaya jual (%)',
      builder: (c) {
        String? error;
        return StatefulBuilder(
          builder: (c, set) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NumberField(
                key: const ValueKey('fee-rate'),
                controller: ctrl,
                label: 'Persentase dari nilai transaksi',
                decimals: 3,
                suffix: '%',
                autofocus: true,
                errorText: error,
                helperText:
                    'Termasuk pajak & pungutan broker. Diingat di HP ini.',
              ),
              const SizedBox(height: GhinaSpace.lg),
              ChunkyButton(
                key: const ValueKey('fee-rate-save'),
                label: 'Simpan',
                onPressed: () {
                  final v = parseNumber(ctrl.text);
                  if (v == null || v < 0 || v > 10) {
                    set(() => error = 'Isi antara 0 dan 10%');
                    return;
                  }
                  Navigator.of(c).pop(v / 100);
                },
              ),
              const SizedBox(height: GhinaSpace.sm),
              ChunkyButton(
                label: 'Pakai standar (beli 0,15% · jual 0,25%)',
                variant: ChunkyButtonVariant.ghost,
                onPressed: () => Navigator.of(c).pop(-1),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    if (rate == null || !mounted) return;
    final ctl = ref.read(feePresetProvider.notifier);
    if (rate < 0) {
      await ctl.reset();
    } else {
      await ctl.setRate(buy: buy, rate: rate);
    }
    setState(() {
      _feeAuto = true;
      _syncAutoFee();
    });
  }

  Future<void> _pickWallet(List<Wallet> wallets, String currency) async {
    final id = await showWalletPickerSheet(
      context,
      wallets: wallets,
      currency: currency,
      selectedId: _walletId,
      title: 'Dompet arus kas',
    );
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _walletId = id;
      _errors.remove('walletId');
    });
  }

  bool _validate() {
    _errors.clear();
    switch (_type) {
      case TradeType.buy:
      case TradeType.sell:
        final q = _shares;
        if (q == null || q <= 0) _errors['quantity'] = 'Isi jumlahnya dulu';
        final p = _num(_price);
        if (p == null || p <= 0) _errors['price'] = 'Harga harus lebih dari 0';
        if (!_feeAuto && _fee.text.trim().isNotEmpty && _num(_fee) == null) {
          _errors['fee'] = 'Angkanya belum pas';
        }
      case TradeType.dividend:
      case TradeType.fee:
        final v = _num(_amount);
        if (v == null || v <= 0) {
          _errors['amount'] = 'Nominal harus lebih dari 0';
        }
      case TradeType.split:
        final r = _num(_ratio);
        if (r == null || r <= 0 || r == 1) {
          _errors['ratio'] = 'Rasio harus lebih dari 0 dan bukan 1';
        }
    }
    if (_cash && _type != TradeType.split && _walletId == null) {
      _errors['walletId'] = 'Pilih dompet untuk mencatat arus kas';
    }
    return _errors.isEmpty;
  }

  Future<void> _save(Asset a, FeePreset preset, double realizedDelta) async {
    if (_saving) return;
    setState(_validate);
    if (_errors.isNotEmpty) return;
    final input = TradeInput(
      assetId: a.id,
      type: _type,
      date: _date,
      quantity: _type.needsQuantityAndPrice ? _shares : null,
      price: _type.needsQuantityAndPrice ? _num(_price) : null,
      fee: _type.needsQuantityAndPrice ? _feeValue(preset) : 0,
      amount: _type == TradeType.dividend || _type == TradeType.fee
          ? _num(_amount)
          : null,
      ratio: _type == TradeType.split ? _num(_ratio) : null,
      note: _note.text,
      cashEffect: _type == TradeType.split ? false : _cash,
      walletId: _cash && _type != TradeType.split ? _walletId : null,
    );
    setState(() => _saving = true);
    final r = _isEdit
        ? await ref.read(updateTradeProvider)(widget.tradeId!, input)
        : await ref.read(createTradeProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          _isEdit ? 'Transaksi diperbarui 👍' : _doneMessage(a, realizedDelta),
          icon: tradeIcon(_type),
        );
        popOr(context, '/investments/${a.id}');
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure is ValidationFailure && failure.field != null) {
            _errors[failure.field!] = failure.message;
          }
        });
        showFailureToast(context, failure);
    }
  }

  String _doneMessage(Asset a, double realized) => switch (_type) {
    TradeType.buy => 'Tercatat! ${a.symbol} makin banyak 📈',
    TradeType.sell =>
      realized > 0.5
          ? 'Terjual! Untung ${context.money(realized, currency: a.currency)} 🎉'
          : 'Penjualan ${a.symbol} tercatat 👍',
    TradeType.dividend => 'Dividen masuk! Cuan pasif 💸',
    TradeType.split => 'Stock split tercatat 👍',
    TradeType.fee => 'Biaya tercatat 👍',
  };

  Future<void> _delete(AssetDetail d) async {
    final v = d.trades.where((t) => t.id == widget.tradeId).firstOrNull;
    if (v == null) return;
    final wallets = ref.read(watchAllWalletsProvider).value ?? const [];
    final name = wallets
        .where((w) => w.id == v.transaction?.walletId)
        .firstOrNull
        ?.name;
    final ok = await confirmDeleteTrade(context, ref, d, v, walletName: name);
    if (ok && mounted) {
      setState(() => _deleted = true);
      popOr(context, '/investments/${d.asset.id}');
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchAssetDetailProvider(widget.assetId));
    final d = async.value;
    if (d == null) {
      return _scaffold(
        null,
        async.hasError
            ? ErrorRetry(
                onRetry: () =>
                    ref.invalidate(watchAssetDetailProvider(widget.assetId)),
              )
            : async.isLoading
            ? const Padding(
                padding: EdgeInsets.all(GhinaSpace.page),
                child: SkeletonList(count: 4),
              )
            : const EmptyState(
                mood: MascotMood.thinking,
                title: 'Asetnya nggak ketemu',
                message: 'Mungkin sudah dihapus di perangkat lain.',
              ),
      );
    }
    if (!_loaded) _init(d);
    if (_isEdit && _original == null) {
      return _scaffold(
        d.asset,
        const EmptyState(
          mood: MascotMood.thinking,
          title: 'Transaksinya nggak ketemu',
          message: 'Mungkin sudah dihapus di perangkat lain.',
        ),
      );
    }
    if (_deleted) return _scaffold(d.asset, const SizedBox.shrink());

    final g = context.ghina;
    final a = d.asset;
    final preset = ref.watch(feePresetProvider);
    final wallets = [
      for (final w
          in ref.watch(watchAllWalletsProvider).value ?? const <Wallet>[])
        if (!w.archived || w.id == _walletId) w,
    ];
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final sw = tradeSwatch(_type);
    final unit = a.kind.usesLots ? (_lots ? 'lot' : 'lembar') : a.unit;

    // Live preview.
    final current = [for (final t in d.trades) t.trade];
    final others = [
      for (final t in current)
        if (t.id != _original?.id) t,
    ];
    final draft = _draft(a, preset);
    final before = deriveHolding(others);
    final after = draft == null ? null : deriveHolding([...others, draft]);
    final seqError = draft == null
        ? null
        : tradeChangeError(current, draft.id, draft);
    final maxShares = sharesHeldAt(others, _date);
    final effect = draft == null ? null : tradeCashEffect(draft);
    final realizedDelta = after == null
        ? 0.0
        : after.realized - before.realized;
    final lastPrice = d.view.quote.price;

    ref.listen(feePresetProvider, (_, _) => _syncAutoFee());

    final canSave = !_saving && seqError == null;

    return _scaffold(
      a,
      Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.md,
                GhinaSpace.page,
                GhinaSpace.xl,
              ),
              children: [
                _AssetStrip(view: d.view),
                const SizedBox(height: GhinaSpace.lg),
                ChunkySegmented<TradeType>(
                  key: const ValueKey('trade-type'),
                  segments: [
                    for (final t in TradeType.values)
                      ChunkySegment(
                        value: t,
                        label: t == TradeType.split ? 'Split' : t.label,
                        color: tradeSwatch(t),
                      ),
                  ],
                  value: _type,
                  onChanged: _setType,
                ),
                const SizedBox(height: GhinaSpace.lg),
                ..._typeFields(a, preset, unit, maxShares, lastPrice),
                const SizedBox(height: GhinaSpace.lg),
                if (seqError != null)
                  ChunkyCard(
                    key: const ValueKey('trade-oversell'),
                    tinted: GhinaColors.red,
                    padding: const EdgeInsets.all(GhinaSpace.md),
                    child: Row(
                      children: [
                        const MascotView(
                          mood: MascotMood.sad,
                          size: 52,
                          animate: false,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kebanyakan nih',
                                style: GhinaType.body
                                    .w(900)
                                    .copyWith(color: GhinaColors.red.base),
                              ),
                              Text(
                                '$seqError. Maks jual ${qtyLabel(a, maxShares).main}.',
                                style: GhinaType.bodyS
                                    .w(700)
                                    .copyWith(color: g.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else if (draft != null && after != null)
                  _Preview(
                    asset: a,
                    type: _type,
                    swatch: sw,
                    effect: _cash ? effect : null,
                    wallet: _cash ? wallet : null,
                    after: after,
                    realized: _type == TradeType.sell ? realizedDelta : null,
                  ),
                const SizedBox(height: GhinaSpace.lg),
                DateField(
                  label: 'Tanggal',
                  value: _date,
                  lastDate: ref.read(clockProvider).now(),
                  onChanged: (v) => setState(() => _date = v),
                ),
                if (_type != TradeType.split) ...[
                  const SizedBox(height: GhinaSpace.lg),
                  _CashCard(
                    enabled: _cash,
                    wallet: wallet,
                    error: _errors['walletId'],
                    onToggle: (v) => setState(() {
                      _cash = v;
                      if (!v) _errors.remove('walletId');
                    }),
                    onPick: () => _pickWallet(wallets, a.currency),
                  ),
                ],
                const SizedBox(height: GhinaSpace.lg),
                ChunkyTextField(
                  key: const ValueKey('trade-note'),
                  controller: _note,
                  label: 'Catatan (opsional)',
                  hint: 'Contoh: beli pas koreksi',
                  errorText: _errors['note'],
                  maxLength: tradeNoteMax,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: GhinaSpace.lg),
                  ChunkyButton(
                    key: const ValueKey('trade-delete-button'),
                    label: 'Hapus transaksi',
                    icon: Icons.delete_rounded,
                    variant: ChunkyButtonVariant.ghost,
                    color: GhinaColors.red,
                    onPressed: _saving ? null : () => _delete(d),
                  ),
                ],
              ],
            ),
          ),
          InvestBottomBar(
            child: ChunkyButton(
              key: const ValueKey('trade-save'),
              label: _isEdit
                  ? 'Simpan perubahan'
                  : 'Simpan ${_type.label.toLowerCase()}',
              color: sw,
              loading: _saving,
              onPressed: canSave ? () => _save(a, preset, realizedDelta) : null,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _typeFields(
    Asset a,
    FeePreset preset,
    String unit,
    double maxShares,
    double? lastPrice,
  ) {
    final g = context.ghina;
    final cur = a.currency;
    final sym = GhinaMoney.symbolFor(cur);
    switch (_type) {
      case TradeType.buy:
      case TradeType.sell:
        final shares = _shares;
        final rate = _type == TradeType.buy ? preset.buy : preset.sell;
        final maxLabel = qtyLabel(a, maxShares).main;
        return [
          FieldLabel(
            'Jumlah',
            trailing: a.kind.usesLots
                ? SizedBox(
                    width: 150,
                    child: ChunkySegmented<bool>(
                      key: const ValueKey('trade-lots'),
                      height: 30,
                      segments: const [
                        ChunkySegment(value: true, label: 'Lot'),
                        ChunkySegment(value: false, label: 'Lembar'),
                      ],
                      value: _lots,
                      onChanged: _setLots,
                    ),
                  )
                : null,
          ),
          NumberField(
            key: const ValueKey('trade-qty'),
            controller: _qty,
            decimals: _lots ? 0 : 8,
            suffix: unit,
            errorText: _errors['quantity'],
            helperText: a.kind.usesLots && shares != null && shares > 0
                ? (_lots
                      ? '= ${fmtQty(shares)} lembar'
                      : '= ${fmtQty(sharesToLots(shares), maxFrac: 2)} lot'
                            '${isWholeLots(shares) ? '' : ' (odd lot)'}')
                : null,
            onChanged: (_) => _errors.remove('quantity'),
          ),
          if (_type == TradeType.sell && maxShares > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: const ValueKey('trade-max'),
                avatar: const Icon(Icons.all_inclusive_rounded, size: 16),
                label: Text('Jual semua · $maxLabel'),
                onPressed: () => setState(() {
                  final useLots = a.kind.usesLots && isWholeLots(maxShares);
                  _lots = useLots;
                  _qty.text = numberToInput(
                    useLots ? sharesToLots(maxShares) : maxShares,
                    decimals: 8,
                  );
                }),
              ),
            ),
          ],
          const SizedBox(height: GhinaSpace.lg),
          NumberField(
            key: const ValueKey('trade-price'),
            controller: _price,
            label: 'Harga per ${a.kind.usesLots ? 'lembar' : a.unit}',
            decimals: 4,
            prefix: sym,
            errorText: _errors['price'],
            onChanged: (_) => _errors.remove('price'),
          ),
          if (lastPrice != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: const ValueKey('trade-last-price'),
                avatar: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(
                  'Harga terakhir ${fmtPrice(lastPrice, currency: cur)}',
                ),
                onPressed: () =>
                    _price.text = numberToInput(lastPrice, decimals: 4),
              ),
            ),
          ],
          const SizedBox(height: GhinaSpace.lg),
          NumberField(
            key: const ValueKey('trade-fee'),
            controller: _fee,
            label: 'Biaya broker',
            decimals: 2,
            prefix: sym,
            errorText: _errors['fee'],
            onChanged: (_) {
              if (_feeAuto) setState(() => _feeAuto = false);
              _errors.remove('fee');
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const ValueKey('fee-auto'),
                selected: _feeAuto,
                label: Text('Otomatis ${fmtQty(rate * 100, maxFrac: 3)}%'),
                onSelected: (_) => setState(() {
                  _feeAuto = true;
                  _syncAutoFee();
                }),
              ),
              ChoiceChip(
                key: const ValueKey('fee-none'),
                selected: !_feeAuto && (_num(_fee) ?? 0) == 0,
                label: const Text('Tanpa biaya'),
                onSelected: (_) => setState(() {
                  _feeAuto = false;
                  _fee.text = '';
                }),
              ),
              ActionChip(
                key: const ValueKey('fee-edit-rate'),
                avatar: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Ubah %'),
                onPressed: () => _editRate(preset),
              ),
            ],
          ),
        ];
      case TradeType.dividend:
      case TradeType.fee:
        return [
          NumberField(
            key: const ValueKey('trade-amount'),
            controller: _amount,
            label: _type == TradeType.dividend
                ? 'Dividen diterima'
                : 'Nominal biaya',
            decimals: 2,
            prefix: sym,
            errorText: _errors['amount'],
            helperText: _type == TradeType.dividend
                ? 'Yang masuk ke rekening (setelah pajak). Dicatat sebagai pemasukan "Dividen".'
                : 'Contoh: biaya kustodian, materai. Mengurangi untung terealisasi.',
            onChanged: (_) => _errors.remove('amount'),
          ),
        ];
      case TradeType.split:
        return [
          NumberField(
            key: const ValueKey('trade-ratio'),
            controller: _ratio,
            label: 'Lembar baru per 1 lembar lama',
            decimals: 4,
            suffix: '×',
            errorText: _errors['ratio'],
            helperText:
                'Split 1:2 → isi 2. Reverse split 2:1 → isi 0,5. Modal tetap, jumlah lembar berubah.',
            onChanged: (_) => _errors.remove('ratio'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final r in const [2.0, 5.0, 10.0, 0.5])
                ActionChip(
                  label: Text(splitLabel(r)),
                  onPressed: () => _ratio.text = numberToInput(r, decimals: 4),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Stock split nggak menggerakkan saldo dompet.',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ];
    }
  }

  Widget _scaffold(Asset? a, Widget body) => Scaffold(
    appBar: AppBar(
      title: Text(
        _isEdit
            ? 'Edit transaksi${a == null ? '' : ' ${a.symbol}'}'
            : 'Catat${a == null ? '' : ' ${a.symbol}'}',
      ),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Tutup',
        onPressed: () => popOr(context, '/investments/${widget.assetId}'),
      ),
    ),
    body: body,
  );
}

/// Asset line at the top of the form: avatar, ticker, what you hold.
class _AssetStrip extends StatelessWidget {
  const _AssetStrip({required this.view});

  final HoldingView view;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = view.asset;
    final h = view.holding;
    final avg = h.avgPrice;
    return Row(
      children: [
        AssetAvatar(asset: a, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
              ),
              Text(
                h.isOpen
                    ? 'Punya ${qtyLabel(a, h.shares).main}'
                          '${avg == null ? '' : ' · avg ${context.money(avg, currency: a.currency)}'}'
                    : 'Belum punya',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.caption
                    .w(700)
                    .copyWith(color: g.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({
    required this.enabled,
    required this.wallet,
    required this.onToggle,
    required this.onPick,
    this.error,
  });

  final bool enabled;
  final Wallet? wallet;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPick;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: enabled ? GhinaColors.blue.base : g.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catat arus kas',
                      style: GhinaType.body
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                    Text(
                      enabled
                          ? 'Saldo dompet ikut bergerak.'
                          : 'Hanya kepemilikan yang dicatat.',
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('trade-cash'),
                value: enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            PickerField(
              key: const ValueKey('trade-wallet'),
              label: 'Dompet',
              value: wallet?.name,
              placeholder: 'Pilih dompet',
              errorText: error,
              leading: wallet == null
                  ? Icon(Icons.account_balance_rounded, color: g.textMuted)
                  : WalletAvatar(wallet: wallet!, size: 32),
              onTap: onPick,
            ),
          ],
        ],
      ),
    );
  }
}

/// Tinted summary of what the save will do.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.asset,
    required this.type,
    required this.swatch,
    required this.after,
    this.effect,
    this.wallet,
    this.realized,
  });

  final Asset asset;
  final TradeType type;
  final ChunkySwatch swatch;
  final Holding after;
  final ({TxType type, double amount})? effect;
  final Wallet? wallet;
  final double? realized;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final cur = asset.currency;
    final q = qtyLabel(asset, after.shares);
    final avg = after.avgPrice;
    return MoneyVisibility.reveal(
      child: ChunkyCard(
        key: const ValueKey('trade-preview'),
        tinted: swatch,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'HASILNYA NANTI',
              style: GhinaType.overline.copyWith(color: swatch.base),
            ),
            const SizedBox(height: 4),
            if (effect case final e?)
              InfoRow(
                label: 'Kas${wallet == null ? '' : ' ${wallet!.name}'}',
                value: MoneyText(
                  key: const ValueKey('preview-cash'),
                  text: GhinaMoney.format(
                    e.amount,
                    currency: cur,
                    showSign: true,
                  ),
                  tone: MoneyTone.neutral,
                  color: e.amount >= 0
                      ? GhinaColors.income.base
                      : g.textPrimary,
                  style: GhinaType.moneyS.copyWith(fontSize: 15),
                ),
              )
            else if (type != TradeType.split)
              InfoRow(
                label: 'Kas',
                value: Text(
                  'nggak dicatat',
                  style: GhinaType.bodyS.w(700).copyWith(color: g.textMuted),
                ),
              ),
            if (type != TradeType.dividend && type != TradeType.fee)
              InfoRow(
                label: 'Kepemilikan jadi',
                hint: q.sub,
                value: Text(
                  after.isOpen ? q.main : 'Habis terjual',
                  key: const ValueKey('preview-holding'),
                  style: GhinaType.moneyS.copyWith(
                    fontSize: 15,
                    color: g.textPrimary,
                  ),
                ),
              ),
            if (avg != null &&
                type != TradeType.dividend &&
                type != TradeType.fee)
              InfoRow(
                label: 'Harga rata-rata',
                value: Text(
                  GhinaMoney.format(avg, currency: cur),
                  key: const ValueKey('preview-avg'),
                  style: GhinaType.moneyS.copyWith(
                    fontSize: 15,
                    color: g.textPrimary,
                  ),
                ),
              ),
            if (realized case final r?)
              InfoRow(
                label: r >= 0 ? 'Untung terealisasi' : 'Rugi terealisasi',
                value: PlMoney(
                  key: const ValueKey('preview-realized'),
                  amount: r,
                  currency: cur,
                ),
              ),
            if (type == TradeType.dividend)
              InfoRow(
                label: 'Total dividen jadi',
                value: MoneyText(
                  amount: after.dividends,
                  currency: cur,
                  tone: MoneyTone.income,
                  style: GhinaType.moneyS.copyWith(fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
