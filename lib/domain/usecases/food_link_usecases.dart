/// Food log ⇄ transaction links (`docs/food-transaction-link.md`): link /
/// unlink, "Catat juga sebagai pengeluaran" and "Catat juga di Food log".
library;

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'life_usecases.dart';
import 'transaction_usecases.dart';

/// Links a food log to one of the user's expenses (several logs may share
/// it), or unlinks it with `null`. Photos stay where they are: the detail
/// screens show both sides through the link.
final class LinkFoodToTransaction {
  const LinkFoodToTransaction(this._food, this._tx, this._clock);
  final FoodRepository _food;
  final TransactionRepository _tx;
  final Clock _clock;

  Future<Result<FoodLog>> call(String foodId, String? transactionId) =>
      guard(() async {
        final log = await _food.getById(foodId);
        if (log == null) {
          throw const NotFoundFailure('Catatan makan tidak ditemukan');
        }
        if (transactionId != null) {
          final t = await _tx.getById(transactionId);
          if (t == null) {
            throw const NotFoundFailure('Transaksi tidak ditemukan');
          }
          if (t.type != TxType.expense) {
            throw const ValidationFailure(
              'Cuma pengeluaran yang bisa ditautkan ke catatan makan',
              field: 'transactionId',
            );
          }
        }
        if (log.transactionId == transactionId) return log;
        final next = log.withTransaction(transactionId, _clock.now());
        await _food.save(next);
        return next;
      });
}

/// The expense part of "Catat juga sebagai pengeluaran".
final class FoodExpenseInput {
  const FoodExpenseInput({
    required this.amount,
    required this.walletId,
    this.categoryId,
    this.note,
  });

  final num amount;
  final String walletId;

  /// Usually the food category (`defaultFoodCategoryId`).
  final String? categoryId;

  /// Defaults to the food's name.
  final String? note;
}

/// Logs a meal and records what it cost as an expense at the same time,
/// linked. The expense is created first (so its validation runs before
/// anything is written); if the meal then fails, the expense is removed again
/// (an unpushed create + delete collapse in the outbox).
final class CreateFoodWithExpense {
  const CreateFoodWithExpense(this._createTx, this._createFood, this._tx);
  final CreateTransaction _createTx;
  final CreateFoodLog _createFood;
  final TransactionRepository _tx;

  Future<Result<({FoodLog food, Transaction transaction})>> call(
    FoodInput input,
    FoodExpenseInput expense, {
    String? photoPath,
  }) async {
    final note = expense.note?.trim();
    final tx = await _createTx(
      TransactionInput(
        type: TxType.expense,
        amount: expense.amount.toDouble(),
        walletId: expense.walletId,
        categoryId: expense.categoryId,
        note: note == null || note.isEmpty ? input.name.trim() : note,
        date: input.date,
      ),
    );
    final Transaction t;
    switch (tx) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        t = value;
    }
    final food = await _createFood(
      input,
      photoPath: photoPath,
      transactionId: t.id,
    );
    switch (food) {
      case Ok(:final value):
        return Ok((food: value, transaction: t));
      case Err(:final failure):
        await guard(() => _tx.delete(t.id));
        return Err(failure);
    }
  }
}

/// "Catat juga di Food log" from the transaction form: a food log at the
/// transaction's time, linked to it. The receipt photos stay on the
/// transaction (the food detail shows them through the link).
final class LogFoodForTransaction {
  const LogFoodForTransaction(this._createFood);
  final CreateFoodLog _createFood;

  Future<Result<FoodLog>> call(
    Transaction transaction, {
    required String name,
    MealType? meal,
    String? mealLabel,
    num? calories,
  }) {
    if (transaction.type != TxType.expense) {
      return Future.value(
        const Err(
          ValidationFailure(
            'Cuma pengeluaran yang bisa dicatat ke Food log',
            field: 'type',
          ),
        ),
      );
    }
    return _createFood(
      FoodInput(
        date: transaction.date,
        name: name,
        meal: meal,
        mealLabel: mealLabel,
        calories: calories,
      ),
      transactionId: transaction.id,
    );
  }
}
