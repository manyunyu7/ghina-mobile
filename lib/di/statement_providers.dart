/// Composition root: statement import ("Impor mutasi",
/// `/api/mobile/statements`) — online-only, not in sync. Tests override
/// [statementRepositoryProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/statement_repository_impl.dart';
import '../domain/repositories/statement_repository.dart';
import 'core_providers.dart';

final statementRepositoryProvider = Provider<StatementRepository>(
  (ref) => ApiStatementRepository(ref.watch(apiClientProvider)),
);
