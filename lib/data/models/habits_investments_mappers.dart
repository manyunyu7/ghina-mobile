/// Drift row ⇄ entity mappers of the habits and investments tables.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../datasources/local/app_database.dart';

Object? _json(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

List<String> decodeStringList(String? s) {
  final v = _json(s);
  if (v is! List) return const [];
  return List.unmodifiable([
    for (final x in v)
      if (x is String && x.isNotEmpty) x,
  ]);
}

// ---------------------------------------------------------------- habits

extension HabitRowX on HabitRow {
  Habit toEntity() => Habit(
    id: id,
    name: name,
    emoji: emoji,
    color: color,
    kind: HabitKind.fromWire(kind),
    schedule: HabitSchedule.tryParse(_json(schedule)) ?? HabitSchedule.daily,
    target: HabitTarget.tryParse(_json(target)) ?? HabitTarget.check,
    reminders: decodeStringList(reminders),
    isPrivate: isPrivate,
    why: why,
    startDate: startDate,
    archived: archived,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension HabitX on Habit {
  HabitsCompanion toCompanion() => HabitsCompanion.insert(
    id: id,
    name: name,
    emoji: Value(emoji),
    color: Value(color),
    kind: Value(kind.wire),
    schedule: Value(jsonEncode(schedule.toJson())),
    target: Value(jsonEncode(target.toJson())),
    reminders: Value(jsonEncode(reminders)),
    isPrivate: Value(isPrivate),
    why: Value(why),
    startDate: startDate,
    archived: Value(archived),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension HabitLogRowX on HabitLogRow {
  /// Null for a type this app doesn't know (newer server).
  HabitLog? toEntityOrNull() {
    final t = HabitLogType.tryFromWire(type);
    if (t == null) return null;
    return HabitLog(
      id: id,
      habitId: habitId,
      date: date,
      type: t,
      value: value,
      note: note,
      triggers: decodeStringList(triggers),
      at: at,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension HabitLogX on HabitLog {
  HabitLogsCompanion toCompanion() => HabitLogsCompanion.insert(
    id: id,
    habitId: habitId,
    date: date,
    type: type.wire,
    value: Value(value),
    note: Value(note),
    triggers: Value(jsonEncode(triggers)),
    at: Value(at),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- investments

extension AssetRowX on AssetRow {
  Asset toEntity() => Asset(
    id: id,
    kind: AssetKind.fromWire(kind),
    symbol: symbol,
    name: name,
    currency: currency,
    priceMode: PriceMode.fromWire(priceMode),
    manualPrice: manualPrice,
    manualPriceAt: manualPriceAt,
    unit: unit,
    walletId: walletId,
    archived: archived,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension AssetX on Asset {
  AssetsCompanion toCompanion() => AssetsCompanion.insert(
    id: id,
    kind: kind.wire,
    symbol: symbol,
    name: Value(name),
    currency: Value(currency),
    priceMode: Value(priceMode.wire),
    manualPrice: Value(manualPrice),
    manualPriceAt: Value(manualPriceAt),
    unit: Value(unit),
    walletId: Value(walletId),
    archived: Value(archived),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension AssetTradeRowX on AssetTradeRow {
  /// Null for a trade type this app doesn't know (newer server).
  AssetTrade? toEntityOrNull() {
    final t = TradeType.tryFromWire(type);
    if (t == null) return null;
    return AssetTrade(
      id: id,
      assetId: assetId,
      type: t,
      date: date,
      quantity: quantity,
      price: price,
      fee: fee,
      amount: amount,
      ratio: ratio,
      note: note,
      cashTransactionId: cashTransactionId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension AssetTradeX on AssetTrade {
  AssetTradesCompanion toCompanion() => AssetTradesCompanion.insert(
    id: id,
    assetId: assetId,
    type: type.wire,
    date: date,
    quantity: Value(quantity),
    price: Value(price),
    fee: Value(fee),
    amount: Value(amount),
    ratio: Value(ratio),
    note: Value(note),
    cashTransactionId: Value(cashTransactionId),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension CachedPriceRowX on CachedPriceRow {
  SecurityPrice toEntity() => SecurityPrice(
    kind: AssetKind.fromWire(kind),
    symbol: symbol,
    price: price,
    prevClose: prevClose,
    change: change,
    changePct: changePct,
    currency: currency,
    name: name,
    asOf: asOf,
    source: source,
    fetchedAt: fetchedAt,
    serverStale: stale,
    cachedAt: cachedAt,
  );
}

extension SecurityPriceX on SecurityPrice {
  CachedPricesCompanion toCompanion() => CachedPricesCompanion.insert(
    key: key,
    kind: kind.wire,
    symbol: symbol,
    price: price,
    prevClose: Value(prevClose),
    change: Value(change),
    changePct: Value(changePct),
    currency: Value(currency),
    name: Value(name),
    asOf: Value(asOf),
    source: Value(source),
    fetchedAt: Value(fetchedAt),
    stale: Value(serverStale),
    cachedAt: cachedAt,
  );
}

extension PortfolioSnapshotRowX on PortfolioSnapshotRow {
  PortfolioPoint toEntity() =>
      PortfolioPoint(date: date, value: value, cost: cost);
}
