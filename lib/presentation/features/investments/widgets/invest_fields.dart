import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// Grouped number input (`9.500`, `0,125`) with an optional leading symbol
/// (`Rp`) and trailing unit (`lot`, `gram`). Parse with [parseNumber].
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    this.label,
    this.hint = '0',
    this.decimals = 0,
    this.prefix,
    this.suffix,
    this.errorText,
    this.helperText,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? label;
  final String hint;
  final int decimals;
  final String? prefix;
  final String? suffix;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget tag(String t, EdgeInsets pad) => Padding(
      padding: pad,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          t,
          style: GhinaType.bodyL.w(900).copyWith(color: g.textMuted),
        ),
      ),
    );
    return ChunkyTextField(
      label: label,
      hint: hint,
      controller: controller,
      errorText: errorText,
      helperText: helperText,
      autofocus: autofocus,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
      textInputAction: TextInputAction.done,
      inputFormatters: [AmountInputFormatter(decimals: decimals)],
      suffix: suffix == null && prefix == null
          ? null
          : tag([?prefix, ?suffix].join(' '), const EdgeInsets.only(right: 14)),
    );
  }
}

/// `9.500,5` → 9500.5 (null when empty / not a number).
double? parseNumber(String text) => Fmt.parseAmount(text);

/// Text for a number field: `9.500`, `0,125` (no trailing zeros).
String numberToInput(num? v, {int decimals = 0}) {
  if (v == null || v == 0) return '';
  if (decimals == 0 || v == v.roundToDouble()) return Fmt.number(v.round());
  return Fmt.number(v, decimals: decimals).replaceFirst(RegExp(r',?0+$'), '');
}

/// Bottom bar holding the page's main CTA.
class InvestBottomBar extends StatelessWidget {
  const InvestBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.background,
        border: Border(
          top: BorderSide(color: g.border, width: GhinaDepth.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.md,
            GhinaSpace.page,
            GhinaSpace.md,
          ),
          child: child,
        ),
      ),
    );
  }
}
