// Number guards for charts: a NaN / Infinity (a division by zero upstream)
// makes `round()` / `ceil()` throw and fl_chart paint garbage, which shows up
// as the grey error screen in release.

/// [v], or [fallback] when it is NaN / Infinity.
double finite(double v, [double fallback = 0]) => v.isFinite ? v : fallback;

/// [v] when it is a finite number >= 0, else 0 (bar heights, pie values).
double nonNegative(double v) => v.isFinite && v > 0 ? v : 0;

/// An axis interval that is never 0, negative, NaN or Infinity.
double safeInterval(double v, [double fallback = 1]) =>
    v.isFinite && v > 0 ? v : fallback;
