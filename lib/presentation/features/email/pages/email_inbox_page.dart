import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../email_state.dart';
import '../widgets/inbox_item_card.dart';

/// "Email penting" (`/email/inbox`): mail Killa read and judged, newest
/// first, by importance. Paged ("Muat lagi" / scrolling near the end);
/// opening a mail marks it read.
class EmailImportantPage extends ConsumerStatefulWidget {
  const EmailImportantPage({super.key});

  @override
  ConsumerState<EmailImportantPage> createState() => _EmailImportantPageState();
}

class _EmailImportantPageState extends ConsumerState<EmailImportantPage> {
  static const _pageSize = 30;

  /// null = "Semua".
  EmailImportance? _filter;
  List<EmailInboxItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  /// Bumped on every reload so a late answer of an older filter is dropped.
  int _gen = 0;
  final _scroll = ScrollController();

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 300) unawaited(_more());
  }

  Set<EmailImportance> get _levels => _filter == null ? const {} : {_filter!};

  Future<void> _reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await ref.read(loadEmailInboxProvider)(
        importance: _levels,
        limit: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(loadEmailInboxProvider)(
        importance: _levels,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted || gen != _gen) return;
      final seen = {for (final i in _items) i.id};
      setState(() {
        _items = [
          ..._items,
          for (final i in page.items)
            if (!seen.contains(i.id)) i,
        ];
        _total = page.items.isEmpty ? _items.length : page.total;
      });
    } on EmailException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setFilter(EmailImportance? f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _items = const [];
      _total = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_reload());
  }

  /// Marks [item] read (optimistic) the first time it's opened.
  Future<void> _open(EmailInboxItem item) async {
    if (item.read) return;
    void set(bool read) => setState(() {
      _items = [
        for (final i in _items) i.id == item.id ? i.copyWith(read: read) : i,
      ];
    });
    set(true);
    try {
      await ref.read(markEmailReadProvider)(item.id);
      ref.invalidate(emailOverviewProvider);
    } on EmailException catch (e) {
      if (!mounted) return;
      set(false);
      showErrorToast(context, e.message);
    }
  }

  Future<void> _copyDraft(EmailInboxItem item) async {
    final draft = item.replyDraft;
    if (draft == null) return;
    await Clipboard.setData(ClipboardData(text: draft));
    if (!mounted) return;
    showOkToast(context, 'Draf balasan disalin', icon: Icons.copy_rounded);
    unawaited(_open(item));
  }

  Future<void> _openGmail(EmailInboxItem item) async {
    unawaited(_open(item));
    await openGmailLink(context, item.gmailUrl);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Email penting'),
        actions: [
          IconButton(
            key: const Key('inbox-rules'),
            tooltip: 'Aturan Killa',
            icon: const Icon(Icons.rule_rounded),
            onPressed: () => context.push('/email/rules'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              8,
            ),
            child: ChunkySegmented<EmailImportance?>(
              segments: [
                ChunkySegment(value: null, label: 'Semua', color: g.accent),
                for (final i in EmailImportance.shown)
                  ChunkySegment(
                    value: i,
                    label: '${i.emoji} ${i.label}',
                    color: emailImportanceSwatch(i),
                  ),
              ],
              value: _filter,
              onChanged: _setFilter,
            ),
          ),
          Expanded(
            child: RefreshIndicator(onRefresh: _reload, child: _body()),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingListView(hero: false, tiles: 3);
    final error = _error;
    if (error != null && _items.isEmpty) {
      return EmailErrorView(error: error, onRetry: _reload);
    }
    if (_items.isEmpty) return ScrollableFill(child: _empty());
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        4,
        GhinaSpace.page,
        32,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, n) {
        if (n == _items.length) {
          return ChunkyButton(
            key: const Key('inbox-more'),
            label: 'Muat lagi',
            variant: ChunkyButtonVariant.outline,
            size: ChunkyButtonSize.medium,
            loading: _loadingMore,
            onPressed: _loadingMore ? null : _more,
          );
        }
        final item = _items[n];
        return EmailInboxCard(
          item: item,
          onOpen: () => _open(item),
          onCopyDraft: () => _copyDraft(item),
          onOpenGmail: () => _openGmail(item),
        );
      },
    );
  }

  Widget _empty() {
    final triageOn = ref.watch(emailOverviewProvider).value?.triageOn ?? true;
    if (!triageOn) {
      return const EmptyState(
        key: Key('inbox-empty-off'),
        mood: MascotMood.thinking,
        title: 'Killa belum baca inbox kamu',
        message:
            'Nyalakan "Killa baca semua email" di kartu akun Gmail, nanti '
            'email penting muncul di sini.',
      );
    }
    return EmptyState(
      key: Key('inbox-empty-${_filter?.wire ?? 'all'}'),
      mood: MascotMood.happy,
      title: switch (_filter) {
        null => 'Belum ada email penting',
        EmailImportance.urgent => 'Nggak ada yang mendesak',
        EmailImportance.important => 'Nggak ada yang penting',
        _ => 'Belum ada info baru',
      },
      message: 'Killa cek email tiap jam. Tarik ke bawah buat muat ulang.',
    );
  }
}
