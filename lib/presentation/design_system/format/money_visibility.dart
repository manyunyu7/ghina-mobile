import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'money_format.dart';

/// Balance privacy ("sembunyikan saldo") for everything below it.
///
/// The app root places one of these (fed by `balancePrivacyProvider`); every
/// [MoneyText] and every `context.money(...)` string reads it and renders
/// `Rp •••••` while [hidden]. Design-system widgets stay Riverpod-free: they
/// toggle through [onToggle].
///
/// ```dart
/// Text(context.money(250000));                // Rp 250.000 / Rp •••••
/// MoneyVisibility.reveal(child: amountForm);  // always visible (typing)
/// MoneyPeek(child: balanceCard);              // long-press to peek
/// const MoneyVisibilityToggle();              // eye button
/// ```
class MoneyVisibility extends InheritedWidget {
  const MoneyVisibility({
    super.key,
    required this.hidden,
    this.onToggle,
    this.peeking = false,
    required super.child,
  });

  /// Force-visible subtree (forms where the user types an amount).
  static Widget reveal({required Widget child}) => Builder(
    builder: (context) {
      final parent = maybeOf(context);
      return MoneyVisibility(
        hidden: false,
        onToggle: parent?.onToggle,
        child: child,
      );
    },
  );

  /// Amounts are masked below this widget.
  final bool hidden;

  /// Flips the persisted preference (null when there is no controller, e.g.
  /// in isolated widget tests).
  final VoidCallback? onToggle;

  /// True inside a [MoneyPeek] that is currently being held.
  final bool peeking;

  static MoneyVisibility? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyVisibility>();

  /// Whether money is masked at [context] (false without an ancestor).
  static bool hiddenOf(BuildContext context) =>
      maybeOf(context)?.hidden ?? false;

  @override
  bool updateShouldNotify(MoneyVisibility old) =>
      old.hidden != hidden ||
      old.peeking != peeking ||
      old.onToggle != onToggle;
}

/// Masked-aware formatting for screens that build money strings by hand.
extension MoneyVisibilityContext on BuildContext {
  /// True when amounts should be masked here.
  bool get moneyHidden => MoneyVisibility.hiddenOf(this);

  /// [GhinaMoney.format], or `Rp •••••` when balances are hidden.
  String money(
    num amount, {
    String currency = 'IDR',
    bool showSign = false,
    bool compact = false,
  }) => moneyHidden
      ? GhinaMoney.masked(currency, compact: compact)
      : GhinaMoney.format(
          amount,
          currency: currency,
          showSign: showSign,
          compact: compact,
        );
}

/// Long-press anywhere in [child] to reveal hidden amounts while held.
/// No-op when amounts are already visible.
class MoneyPeek extends StatefulWidget {
  const MoneyPeek({super.key, required this.child});

  final Widget child;

  @override
  State<MoneyPeek> createState() => _MoneyPeekState();
}

class _MoneyPeekState extends State<MoneyPeek> {
  bool _peeking = false;

  void _set(bool v) {
    if (_peeking == v) return;
    if (v) HapticFeedback.mediumImpact();
    setState(() => _peeking = v);
  }

  @override
  Widget build(BuildContext context) {
    final parent = MoneyVisibility.maybeOf(context);
    if (parent == null) return widget.child;
    // Same tree shape either way so children keep their state on toggle.
    final canPeek = parent.hidden || _peeking;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: canPeek ? (_) => _set(true) : null,
      onLongPressEnd: canPeek ? (_) => _set(false) : null,
      onLongPressCancel: canPeek ? () => _set(false) : null,
      child: MoneyVisibility(
        hidden: parent.hidden && !_peeking,
        peeking: _peeking,
        onToggle: parent.onToggle,
        child: widget.child,
      ),
    );
  }
}

/// Eye button that flips balance privacy (with haptic + icon morph).
/// Renders nothing when no [MoneyVisibility] controller is above it.
class MoneyVisibilityToggle extends StatelessWidget {
  const MoneyVisibilityToggle({super.key, this.color, this.size = 22});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = MoneyVisibility.maybeOf(context);
    final toggle = v?.onToggle;
    if (v == null || toggle == null) return const SizedBox.shrink();
    // While peeking, the icon still reflects the saved preference.
    final hidden = v.hidden || v.peeking;
    return IconButton(
      tooltip: hidden ? 'Tampilkan saldo' : 'Sembunyikan saldo',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        HapticFeedback.selectionClick();
        toggle();
      },
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: Tween(
            begin: 0.6,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          key: ValueKey(hidden),
          size: size,
          color: color ?? Theme.of(context).iconTheme.color,
        ),
      ),
    );
  }
}
