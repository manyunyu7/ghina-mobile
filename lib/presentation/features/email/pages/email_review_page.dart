import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart' show currencyProvider;
import '../email_state.dart';
import '../widgets/suggestion_card.dart';
import '../widgets/suggestion_edit_sheet.dart';

/// "Perlu dicek" (`/email/review`): transactions suggested from finance
/// emails. Nothing is recorded until the user approves; approving creates a
/// normal transaction on the server, which arrives here with the next sync.
class EmailReviewPage extends ConsumerStatefulWidget {
  const EmailReviewPage({
    super.key,
    this.initial = EmailSuggestionStatus.pending,
  });

  final EmailSuggestionStatus initial;

  @override
  ConsumerState<EmailReviewPage> createState() => _EmailReviewPageState();
}

class _EmailReviewPageState extends ConsumerState<EmailReviewPage> {
  late EmailSuggestionStatus _status = widget.initial;

  /// `status/id` of rows decided here and not refetched yet (hidden from
  /// that tab right away).
  final Set<String> _hidden = {};

  static String _key(EmailSuggestion s) => '${s.status.wire}/${s.id}';
  final Set<String> _busy = {};

  List<Wallet> get _wallets => ref.read(watchWalletsProvider).value ?? const [];
  List<TxCategory> get _categories =>
      ref.read(watchCategoriesProvider(null)).value ?? const [];

  void _refresh() {
    invalidateEmail(ref);
  }

  Future<void> _run(String id, Future<void> Function() body) async {
    setState(() => _busy.add(id));
    try {
      await body();
    } on EmailException catch (e) {
      if (!mounted) return;
      showErrorToast(context, e.message);
      if (e.kind == EmailErrorKind.conflict ||
          e.kind == EmailErrorKind.notFound) {
        _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _approve(EmailSuggestion s, [EmailApproval? edited]) async {
    var approval = edited;
    if (approval == null) {
      // A transfer needs a destination: the edit sheet asks for it.
      if (s.kind == EmailSuggestionKind.transfer) return _edit(s);
      final guess = s.walletId;
      if (guess == null || !_wallets.any((w) => w.id == guess)) {
        final id = await showWalletPickerSheet(
          context,
          wallets: _wallets,
          currency: ref.read(currencyProvider),
          title: 'Masuk ke dompet mana?',
        );
        if (id == null || id.isEmpty || !mounted) return;
        approval = EmailApproval(walletId: id);
      } else {
        approval = const EmailApproval();
      }
    }
    final a = approval;
    await _run(s.id, () async {
      await ref.read(approveEmailSuggestionProvider)(s, a);
      if (!mounted) return;
      setState(() => _hidden.add(_key(s)));
      showOkToast(context, 'Tercatat 👍');
      _refresh();
      // Pull the new transaction onto the phone.
      unawaited(ref.read(syncNowProvider)());
    });
  }

  Future<void> _edit(EmailSuggestion s) async {
    final approval = await showSuggestionEditSheet(
      context,
      suggestion: s,
      wallets: _wallets,
      categories: _categories,
      currency: ref.read(currencyProvider),
    );
    if (approval == null || !mounted) return;
    await _approve(s, approval);
  }

  Future<void> _ignore(EmailSuggestion s) async {
    final messenger = ScaffoldMessenger.of(context);
    await _run(s.id, () async {
      await ref.read(ignoreEmailSuggestionProvider)(s.id);
      if (!mounted) return;
      setState(() => _hidden.add(_key(s)));
      _refresh();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${s.title}" diabaikan'),
          duration: const Duration(seconds: 4),
          persist: false,
          action: SnackBarAction(label: 'BATAL', onPressed: () => _undo(s)),
        ),
      );
    });
  }

  Future<void> _undo(EmailSuggestion s) => _run(s.id, () async {
    await ref.read(restoreEmailSuggestionProvider)(s.id);
    if (!mounted) return;
    setState(() => _hidden.remove(_key(s)));
    _refresh();
  });

  Future<void> _restore(EmailSuggestion s) => _run(s.id, () async {
    await ref.read(restoreEmailSuggestionProvider)(s.id);
    if (!mounted) return;
    setState(() => _hidden.add(_key(s)));
    showOkToast(context, 'Dikembalikan ke "Perlu dicek"');
    _refresh();
  });

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(emailSuggestionsProvider(_status));
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final categories =
        ref.watch(watchCategoriesProvider(null)).value ?? const <TxCategory>[];
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Perlu dicek')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              8,
            ),
            child: ChunkySegmented<EmailSuggestionStatus>(
              segments: [
                for (final s in EmailSuggestionStatus.values)
                  ChunkySegment(value: s, label: s.label, color: g.accent),
              ],
              value: _status,
              onChanged: (s) => setState(() => _status = s),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.refresh(emailSuggestionsProvider(_status).future),
              child: switch (async) {
                AsyncData(:final value) => _list(
                  [
                    for (final s in value.items)
                      if (!_hidden.contains(_key(s))) s,
                  ],
                  wallets,
                  categories,
                ),
                AsyncError(:final error) => EmailErrorView(
                  error: error,
                  onRetry: () =>
                      ref.invalidate(emailSuggestionsProvider(_status)),
                ),
                _ => const LoadingListView(hero: false, tiles: 3),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    List<EmailSuggestion> items,
    List<Wallet> wallets,
    List<TxCategory> categories,
  ) {
    if (items.isEmpty) {
      return ScrollableFill(
        child: EmptyState(
          key: Key('email-empty-${_status.wire}'),
          mood: _status == EmailSuggestionStatus.pending
              ? MascotMood.happy
              : MascotMood.sleeping,
          title: switch (_status) {
            EmailSuggestionStatus.pending => 'Semua sudah dicek',
            EmailSuggestionStatus.approved => 'Belum ada yang disetujui',
            EmailSuggestionStatus.ignored => 'Nggak ada yang diabaikan',
          },
          message: _status == EmailSuggestionStatus.pending
              ? 'Transaksi baru dari email bakal muncul di sini. Tarik ke '
                    'bawah buat cek lagi.'
              : null,
        ),
      );
    }
    String? walletName(String? id) {
      for (final w in wallets) {
        if (w.id == id) return w.name;
      }
      return null;
    }

    String? categoryName(String? id) {
      for (final c in categories) {
        if (c.id == id) return c.name;
      }
      return null;
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        4,
        GhinaSpace.page,
        32,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final s = items[i];
        return EmailSuggestionCard(
          suggestion: s,
          walletName: walletName(s.walletId),
          categoryName: categoryName(s.categoryId),
          busy: _busy.contains(s.id),
          onApprove: () => _approve(s),
          onEdit: () => _edit(s),
          onIgnore: () => _ignore(s),
          onRestore: () => _restore(s),
          onOpenGmail: () => openGmailLink(context, s.gmailUrl),
        );
      },
    );
  }
}
