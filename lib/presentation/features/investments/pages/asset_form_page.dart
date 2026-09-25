import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../investment_format.dart';
import '../widgets/invest_fields.dart';
import '../widgets/portfolio_widgets.dart';

/// Live ticker check state of the add-asset form.
sealed class LookupState {
  const LookupState();
}

/// Nothing typed yet / kind without market prices.
final class LookupIdle extends LookupState {
  const LookupIdle();
}

final class LookupChecking extends LookupState {
  const LookupChecking();
}

final class LookupFound extends LookupState {
  const LookupFound(this.info);
  final SymbolInfo info;
}

final class LookupNotFound extends LookupState {
  const LookupNotFound(this.symbol);
  final String symbol;
}

/// Bad format (`Kode saham tidak valid`).
final class LookupInvalid extends LookupState {
  const LookupInvalid(this.message);
  final String message;
}

/// Offline / price service down: saving is allowed, unvalidated.
final class LookupUnavailable extends LookupState {
  const LookupUnavailable();
}

/// Add or edit an asset: kind chips, ticker with live validation, manual
/// price, unit and the investment wallet (RDN).
class AssetFormPage extends ConsumerStatefulWidget {
  const AssetFormPage({super.key, this.id});

  /// Null = new asset.
  final String? id;

  @override
  ConsumerState<AssetFormPage> createState() => _AssetFormPageState();
}

class _AssetFormPageState extends ConsumerState<AssetFormPage> {
  bool get _isEdit => widget.id != null;

  AssetKind _kind = AssetKind.stock;
  final _symbol = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _unit = TextEditingController();
  bool _manual = false;
  String? _walletId;
  Asset? _original;
  bool _loaded = false;
  bool _saving = false;

  LookupState _lookup = const LookupIdle();
  Timer? _debounce;
  int _lookupSeq = 0;

  /// The name was filled from the lookup (replace it on the next lookup).
  String? _autoName;

  String? _symbolError;
  String? _nameError;
  String? _priceError;
  String? _unitError;

  @override
  void initState() {
    super.initState();
    _loaded = !_isEdit;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _symbol.dispose();
    _name.dispose();
    _price.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _loadFrom(Asset a) {
    _original = a;
    _kind = a.kind;
    _symbol.text = a.symbol;
    _name.text = a.name ?? '';
    _manual = a.isManual;
    _price.text = numberToInput(a.manualPrice, decimals: 4);
    _unit.text = a.unit == a.kind.defaultUnit ? '' : a.unit;
    _walletId = a.walletId;
    _loaded = true;
  }

  bool get _canLookup => _kind.supportsAutoPrice && !_manual;
  bool get _isManual => !_kind.supportsAutoPrice || _manual;

  void _onSymbolChanged(String _) {
    _debounce?.cancel();
    if (_symbolError != null) setState(() => _symbolError = null);
    if (!_canLookup) return;
    final raw = _symbol.text.trim();
    // Unchanged ticker while editing: nothing to check.
    if (_isEdit && raw.toUpperCase() == _original?.symbol.toUpperCase()) {
      setState(() => _lookup = const LookupIdle());
      return;
    }
    if (raw.length < 2) {
      setState(() => _lookup = const LookupIdle());
      return;
    }
    try {
      requireAssetSymbol(_kind, raw);
    } on ValidationFailure catch (f) {
      setState(() => _lookup = LookupInvalid(f.message));
      return;
    }
    setState(() => _lookup = const LookupChecking());
    _debounce = Timer(const Duration(milliseconds: 500), _runLookup);
  }

  Future<void> _runLookup() async {
    final seq = ++_lookupSeq;
    final kind = _kind;
    final raw = _symbol.text.trim();
    final r = await ref.read(lookupSymbolProvider)(kind, raw);
    if (!mounted || seq != _lookupSeq || kind != _kind) return;
    setState(() {
      switch (r) {
        case Ok(:final value?):
          _lookup = LookupFound(value);
          final n = value.name ?? value.price?.name;
          if (n != null &&
              n.isNotEmpty &&
              (_name.text.trim().isEmpty || _name.text == _autoName)) {
            _name.text = n;
            _autoName = n;
          }
        case Ok():
          _lookup = LookupNotFound(requireSymbolOrRaw(kind, raw));
        case Err(:final failure) when failure is ValidationFailure:
          _lookup = LookupInvalid(failure.message);
        case Err():
          _lookup = const LookupUnavailable();
      }
    });
  }

  static String requireSymbolOrRaw(AssetKind kind, String raw) {
    try {
      return requireAssetSymbol(kind, raw);
    } catch (_) {
      return raw.toUpperCase();
    }
  }

  void _setKind(AssetKind k) {
    if (k == _kind) return;
    _debounce?.cancel();
    _lookupSeq++;
    setState(() {
      _kind = k;
      _manual = false;
      _lookup = const LookupIdle();
      _symbolError = null;
      if (_name.text == _autoName) {
        _name.clear();
        _autoName = null;
      }
    });
    if (_symbol.text.trim().isNotEmpty) _onSymbolChanged(_symbol.text);
  }

  bool get _blocked =>
      _canLookup &&
      (_lookup is LookupChecking ||
          _lookup is LookupNotFound ||
          _lookup is LookupInvalid);

  Future<void> _pickWallet(List<Wallet> wallets, String currency) async {
    final sorted = [
      ...wallets.where((w) => w.type == WalletType.investment),
      ...wallets.where((w) => w.type != WalletType.investment),
    ];
    final id = await showWalletPickerSheet(
      context,
      wallets: sorted,
      currency: currency,
      selectedId: _walletId,
      title: 'Dompet investasi (RDN)',
      noneLabel: 'Tanpa dompet',
    );
    if (id == null || !mounted) return;
    setState(() => _walletId = id.isEmpty ? null : id);
  }

  Future<void> _save() async {
    if (_saving || _blocked) return;
    final price = _price.text.trim().isEmpty ? null : parseNumber(_price.text);
    setState(() {
      _symbolError = _symbol.text.trim().isEmpty ? 'Kode wajib diisi' : null;
      _priceError = _isManual && _price.text.trim().isNotEmpty && price == null
          ? 'Angkanya belum pas'
          : null;
    });
    if (_symbolError != null || _priceError != null) return;
    final input = AssetInput(
      kind: _kind,
      symbol: _symbol.text,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      currency: _original?.currency ?? ref.read(currencyProvider),
      priceMode: _isManual ? PriceMode.manual : PriceMode.auto,
      manualPrice: _isManual ? price : null,
      unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      walletId: _walletId,
    );
    setState(() => _saving = true);
    final r = _isEdit
        ? await ref.read(updateAssetProvider)(widget.id!, input)
        : await ref.read(createAssetProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        if (_isEdit) {
          showOkToast(context, '${value.symbol} diperbarui 👍');
          popOr(context, '/investments/${value.id}');
        } else {
          showOkToast(
            context,
            '${value.symbol} masuk portofolio! Catat pembeliannya, yuk 🎉',
          );
          context.pushReplacement('/investments/${value.id}');
        }
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure is ValidationFailure) {
            switch (failure.field) {
              case 'symbol':
                _symbolError = failure.message;
              case 'name':
                _nameError = failure.message;
              case 'manualPrice':
                _priceError = failure.message;
              case 'unit':
                _unitError = failure.message;
            }
          }
        });
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_loaded) {
      final async = ref.watch(watchAssetDetailProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _loadFrom(value.asset);
        case AsyncData():
          return _scaffold(
            const EmptyState(
              mood: MascotMood.thinking,
              title: 'Asetnya nggak ketemu',
              message: 'Mungkin sudah dihapus di perangkat lain.',
            ),
          );
        case AsyncError():
          return _scaffold(
            ErrorRetry(
              onRetry: () =>
                  ref.invalidate(watchAssetDetailProvider(widget.id!)),
            ),
          );
        default:
          return _scaffold(
            const Padding(
              padding: EdgeInsets.all(GhinaSpace.page),
              child: SkeletonList(count: 4),
            ),
          );
      }
    }
    final g = context.ghina;
    final currency = ref.watch(currencyProvider);
    final wallets = [
      for (final w
          in ref.watch(watchAllWalletsProvider).value ?? const <Wallet>[])
        if (!w.archived || w.id == _walletId) w,
    ];
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final symbolLabel = switch (_kind) {
      AssetKind.stock => 'Kode saham',
      AssetKind.crypto => 'Kode kripto',
      _ => 'Kode',
    };
    final symbolHint = switch (_kind) {
      AssetKind.stock => 'BBCA',
      AssetKind.crypto => 'BTC',
      AssetKind.gold => 'ANTAM',
      AssetKind.fund => 'SUCORINVEST-MM',
      AssetKind.bond => 'ORI025',
      AssetKind.other => 'Kode singkat',
    };

    return _scaffold(
      Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.lg,
                GhinaSpace.page,
                GhinaSpace.xl,
              ),
              children: [
                const FieldLabel('Jenis aset'),
                if (_isEdit)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ChunkyPill(
                      label: _kind.label,
                      icon: kindIcon(_kind),
                      color: kindSwatch(_kind),
                    ),
                  )
                else
                  ChunkyChoiceChips<AssetKind>(
                    key: const ValueKey('asset-kind'),
                    options: [
                      for (final k in AssetKind.values)
                        ChunkyChoice(
                          value: k,
                          label: k.label,
                          icon: kindIcon(k),
                          color: kindSwatch(k),
                        ),
                    ],
                    selected: {_kind},
                    onChanged: (s) {
                      if (s.isNotEmpty) _setKind(s.first);
                    },
                  ),
                const SizedBox(height: GhinaSpace.lg),
                ChunkyTextField(
                  key: const ValueKey('asset-symbol'),
                  controller: _symbol,
                  label: symbolLabel,
                  hint: symbolHint,
                  errorText: _symbolError,
                  maxLength: _kind.supportsAutoPrice ? 15 : assetSymbolMax,
                  textCapitalization: _kind.supportsAutoPrice
                      ? TextCapitalization.characters
                      : TextCapitalization.none,
                  textInputAction: TextInputAction.next,
                  prefixIcon: kindIcon(_kind),
                  onChanged: _onSymbolChanged,
                ),
                if (_canLookup) ...[
                  const SizedBox(height: 6),
                  LookupHint(state: _lookup, kind: _kind),
                ],
                const SizedBox(height: GhinaSpace.lg),
                ChunkyTextField(
                  key: const ValueKey('asset-name'),
                  controller: _name,
                  label: 'Nama (opsional)',
                  hint: _kind.supportsAutoPrice
                      ? 'Terisi otomatis'
                      : 'Contoh: Emas Antam',
                  errorText: _nameError,
                  maxLength: assetNameMax,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                const SizedBox(height: GhinaSpace.lg),
                if (_kind.supportsAutoPrice)
                  ChunkyCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(
                          _manual
                              ? Icons.edit_note_rounded
                              : Icons.bolt_rounded,
                          color: _manual
                              ? GhinaColors.orange.base
                              : GhinaColors.green.base,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Harga manual',
                                style: GhinaType.body
                                    .w(800)
                                    .copyWith(color: g.textPrimary),
                              ),
                              Text(
                                _manual
                                    ? 'Kamu yang memperbarui harganya sendiri.'
                                    : 'Harga pasar diambil otomatis.',
                                style: GhinaType.caption.copyWith(
                                  color: g.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          key: const ValueKey('asset-manual'),
                          value: _manual,
                          onChanged: (v) => setState(() {
                            _manual = v;
                            if (!v) _onSymbolChanged(_symbol.text);
                          }),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '${_kind.label} nggak punya harga pasar otomatis — perbarui harganya sendiri kapan aja.',
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                if (_isManual) ...[
                  const SizedBox(height: GhinaSpace.lg),
                  NumberField(
                    key: const ValueKey('asset-price'),
                    controller: _price,
                    label: 'Harga per ${_unitLabel()} (opsional)',
                    decimals: 4,
                    prefix: GhinaMoney.symbolFor(currency),
                    errorText: _priceError,
                    helperText: 'Contoh: NAB reksa dana, harga emas per gram.',
                    onChanged: (_) {
                      if (_priceError != null) {
                        setState(() => _priceError = null);
                      }
                    },
                  ),
                ],
                const SizedBox(height: GhinaSpace.lg),
                ChunkyTextField(
                  key: const ValueKey('asset-unit'),
                  controller: _unit,
                  label: 'Satuan',
                  hint: _kind.defaultUnit,
                  errorText: _unitError,
                  maxLength: assetUnitMax,
                  textCapitalization: TextCapitalization.none,
                  onChanged: (_) => setState(() => _unitError = null),
                ),
                const SizedBox(height: GhinaSpace.lg),
                PickerField(
                  key: const ValueKey('asset-wallet'),
                  label: 'Dompet investasi / RDN (opsional)',
                  value: wallet?.name,
                  placeholder: 'Tanpa dompet',
                  leading: wallet == null
                      ? Icon(Icons.account_balance_rounded, color: g.textMuted)
                      : WalletAvatar(wallet: wallet, size: 32),
                  onTap: () => _pickWallet(wallets, currency),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'Kalau diisi, beli/jual otomatis memotong/menambah saldo dompet ini.',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          InvestBottomBar(
            child: ChunkyButton(
              key: const ValueKey('asset-save'),
              label: _isEdit ? 'Simpan perubahan' : 'Tambah aset',
              loading: _saving,
              color: GhinaColors.purple,
              onPressed: _saving || _blocked ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  String _unitLabel() {
    final u = _unit.text.trim();
    return u.isEmpty ? _kind.defaultUnit : u;
  }

  Widget _scaffold(Widget body) => Scaffold(
    appBar: AppBar(
      title: Text(_isEdit ? 'Edit aset' : 'Aset baru'),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Tutup',
        onPressed: () => popOr(context, '/investments'),
      ),
    ),
    body: body,
  );
}

/// One line under the ticker: checking / found (name · price) / not found /
/// invalid / offline.
class LookupHint extends StatelessWidget {
  const LookupHint({super.key, required this.state, required this.kind});

  final LookupState state;
  final AssetKind kind;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final (IconData icon, Color color, String text, Key key) = switch (state) {
      LookupIdle() => (
        Icons.search_rounded,
        g.textMuted,
        'Kode dicek otomatis ke data pasar.',
        const ValueKey('lookup-idle'),
      ),
      LookupChecking() => (
        Icons.hourglass_top_rounded,
        g.textSecondary,
        'Mengecek kode…',
        const ValueKey('lookup-checking'),
      ),
      LookupFound(:final info) => (
        Icons.check_circle_rounded,
        GhinaColors.green.base,
        [
          info.symbol,
          if ((info.name ?? info.price?.name) case final n? when n.isNotEmpty)
            n,
          if (info.price case final p?) fmtPrice(p.price, currency: p.currency),
        ].join(' · '),
        const ValueKey('lookup-ok'),
      ),
      LookupNotFound(:final symbol) => (
        Icons.error_rounded,
        GhinaColors.red.base,
        'Kode $symbol nggak ketemu${kind == AssetKind.stock ? ' di BEI' : ''}. Cek lagi ejaannya, ya.',
        const ValueKey('lookup-missing'),
      ),
      LookupInvalid(:final message) => (
        Icons.error_rounded,
        GhinaColors.red.base,
        message,
        const ValueKey('lookup-invalid'),
      ),
      LookupUnavailable() => (
        Icons.cloud_off_rounded,
        GhinaColors.orange.base,
        'Lagi offline — kode belum tervalidasi. Tetap bisa disimpan, harganya menyusul.',
        const ValueKey('lookup-offline'),
      ),
    };
    return Padding(
      key: key,
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GhinaType.caption.w(800).copyWith(color: color),
            ),
          ),
          if (state is LookupFound &&
              (state as LookupFound).info.price?.serverStale == true)
            const StaleBadge(),
        ],
      ),
    );
  }
}
