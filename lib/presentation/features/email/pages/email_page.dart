import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../email_state.dart';

/// "Email" (`/email`): connected Gmail accounts (read-only), connect / sync /
/// disconnect, "Killa baca semua email" per account, and the entries to
/// "Email penting" and the "Perlu dicek" review queue.
class EmailPage extends ConsumerStatefulWidget {
  const EmailPage({super.key});

  @override
  ConsumerState<EmailPage> createState() => _EmailPageState();
}

class _EmailPageState extends ConsumerState<EmailPage> {
  bool _connecting = false;
  bool _syncing = false;
  final Set<String> _removing = {};
  final Set<String> _triageBusy = {};

  Future<void> _connect() async {
    final connect = ref.read(connectGmailProvider);
    setState(() => _connecting = true);
    try {
      final account = await connect();
      if (!mounted || account == null) return;
      showOkToast(context, '${account.email} terhubung');
      invalidateEmail(ref);
      // The first read of the new inbox right away.
      await _sync(quiet: true);
    } on EmailException catch (e) {
      if (!mounted) return;
      if (e.kind == EmailErrorKind.notEnabled) {
        ref.invalidate(emailOverviewProvider);
        await showChunkyDialog<void>(
          context,
          builder: (c) => ChunkyDialog(
            mood: MascotMood.thinking,
            title: 'Fitur email belum aktif',
            message:
                'Akun kamu belum masuk daftar uji coba fitur email. Data '
                'Gmail kamu nggak disentuh sama sekali.',
            actions: [
              ChunkyButton(
                label: 'Oke',
                onPressed: () => Navigator.of(c).pop(),
              ),
            ],
          ),
        );
      } else {
        showErrorToast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// Starts a background sync on the server and returns at once; the page
  /// polls `GET accounts` while any account reports `syncing`.
  Future<void> _sync({bool quiet = false}) async {
    setState(() => _syncing = true);
    try {
      await ref.read(syncEmailProvider)(background: true);
      if (!mounted) return;
      _pendingBefore = _pendingNow;
      _watching = true;
      if (!quiet) {
        showOkToast(
          context,
          'Sinkron jalan di latar belakang. Boleh tinggal dulu ya.',
          icon: Icons.cloud_sync_rounded,
        );
      }
    } on EmailException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
      invalidateEmail(ref);
    }
  }

  // ---- background sync polling

  Timer? _poll;
  bool _watching = false;
  int _pendingBefore = 0;
  int _pendingNow = 0;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Polls every 4 s while a sync runs; when it ends, says what came in.
  void _track(EmailOverview o) {
    _pendingNow = o.accounts.fold(0, (s, a) => s + a.pendingCount);
    final running = o.accounts.any((a) => a.syncing);
    if (running) {
      _watching = true;
      _poll ??= Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) invalidateEmail(ref);
      });
      return;
    }
    _poll?.cancel();
    _poll = null;
    if (!_watching) return;
    _watching = false;
    final added = _pendingNow - _pendingBefore;
    final failed = o.accounts
        .where((a) => a.status != EmailAccountStatus.active)
        .length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (failed > 0) {
        showErrorToast(context, '$failed akun gagal disinkron. Cek statusnya.');
      } else {
        showOkToast(
          context,
          added > 0
              ? 'Sinkron selesai: $added transaksi baru perlu dicek'
              : 'Sinkron selesai, nggak ada transaksi baru',
          icon: Icons.mark_email_read_rounded,
        );
      }
    });
  }

  Future<void> _disconnect(EmailAccount a) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Putuskan ${a.email}?',
      message:
          'Ghina berhenti membaca email ini dan saran yang belum dicek '
          'dihapus. Transaksi yang sudah kamu setujui tetap aman.',
      confirmLabel: 'Putuskan',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _removing.add(a.id));
    try {
      await ref.read(disconnectEmailAccountProvider)(a.id);
      if (mounted) showOkToast(context, '${a.email} diputus');
      invalidateEmail(ref);
    } on EmailException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _removing.remove(a.id));
    }
  }

  /// "Killa baca semua email": turning it on asks first.
  Future<void> _setTriage(EmailAccount a, bool on) async {
    if (on) {
      final ok = await showChunkyConfirm(
        context,
        title: 'Killa baca semua email?',
        message:
            'Killa akan membaca inbox Utama & Update ${a.email} tiap jam '
            '(promo dan sosial dilewati), lalu:\n'
            '• Mendesak: langsung dikabari via WhatsApp\n'
            '• Penting: dikumpulkan jam 08, 12, 18, 21\n'
            '• Kode login & password nggak pernah diteruskan\n'
            '• Killa cuma baca, nggak bisa kirim email',
        confirmLabel: 'Nyalakan',
        mood: MascotMood.thinking,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _triageBusy.add(a.id));
    try {
      await ref.read(setEmailTriageProvider)(a.id, on);
      if (!mounted) return;
      showOkToast(
        context,
        on
            ? 'Killa mulai baca ${a.email}'
            : 'Killa berhenti baca semua email ${a.email}',
      );
      ref.invalidate(emailOverviewProvider);
    } on EmailException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _triageBusy.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(emailOverviewProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Email')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(emailOverviewProvider.future),
        child: switch (async) {
          AsyncData(:final value) when !value.enabled => const ScrollableFill(
            child: EmailNotEnabledView(),
          ),
          AsyncData(:final value) => _bodyTracked(value),
          AsyncError(:final error) => EmailErrorView(
            error: error,
            onRetry: () => ref.invalidate(emailOverviewProvider),
          ),
          _ => const LoadingListView(tiles: 2),
        },
      ),
    );
  }

  Widget _bodyTracked(EmailOverview o) {
    _track(o);
    return _body(o);
  }

  Widget _body(EmailOverview o) {
    final available = ref.read(connectGmailProvider).available;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        _InboxEntry(
          unread: o.inboxUnread,
          on: o.triageOn,
          onTap: () => context.push('/email/inbox'),
        ),
        const SizedBox(height: 10),
        _ReviewEntry(
          pending: o.pendingCount,
          onTap: () => context.push('/email/review'),
        ),
        const SizedBox(height: 16),
        _Explainer(since: o.since),
        const SizedBox(height: 8),
        SectionHeader(
          title: 'Akun Gmail',
          subtitle: o.accounts.isEmpty
              ? null
              : '${o.accounts.length} terhubung',
        ),
        if (o.accounts.isEmpty)
          const EmptyState(
            compact: true,
            mascotSize: 90,
            title: 'Belum ada Gmail terhubung',
            message: 'Hubungkan Gmail biar tagihan & struk masuk sendiri.',
          )
        else
          for (final a in o.accounts) ...[
            _AccountCard(
              account: a,
              busy: _removing.contains(a.id),
              triageBusy: _triageBusy.contains(a.id),
              onDisconnect: () => _disconnect(a),
              onTriage: (on) => _setTriage(a, on),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 16),
        ChunkyButton(
          key: const Key('email-connect'),
          label: o.accounts.isEmpty ? 'Hubungkan Gmail' : 'Tambah Gmail lain',
          icon: Icons.add_link_rounded,
          size: ChunkyButtonSize.large,
          loading: _connecting,
          onPressed: _connecting || !available ? null : _connect,
        ),
        if (!available) ...[
          const SizedBox(height: 8),
          Text(
            'Login Google belum diaktifkan di versi aplikasi ini.',
            textAlign: TextAlign.center,
            style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
          ),
        ],
        const SizedBox(height: 12),
        ChunkyButton(
          key: const Key('email-sync'),
          label: 'Sinkron sekarang',
          icon: Icons.sync_rounded,
          variant: ChunkyButtonVariant.outline,
          size: ChunkyButtonSize.large,
          loading: _syncing || o.accounts.any((a) => a.syncing),
          onPressed:
              _syncing || o.accounts.isEmpty || o.accounts.any((a) => a.syncing)
              ? null
              : _sync,
        ),
      ],
    );
  }
}

/// "Email penting": what Killa found in the inbox, with the unread count.
class _InboxEntry extends StatelessWidget {
  const _InboxEntry({
    required this.unread,
    required this.on,
    required this.onTap,
  });

  final int unread;

  /// Any account has "Killa baca semua email" on.
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    const sw = GhinaColors.orange;
    return ChunkyCard(
      key: const Key('email-inbox-entry'),
      tinted: unread > 0 ? sw : null,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          CategoryAvatar(
            icon: Icons.mark_email_unread_rounded,
            color: sw.base,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email penting',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  unread > 0
                      ? '$unread email belum dibaca, sudah diringkas Killa'
                      : on
                      ? 'Nggak ada email baru yang perlu perhatian'
                      : 'Nyalakan "Killa baca semua email" di akun di bawah',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          if (unread > 0) ChunkyPill(label: '$unread', color: sw),
          Icon(Icons.chevron_right_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}

class _ReviewEntry extends StatelessWidget {
  const _ReviewEntry({required this.pending, required this.onTap});

  final int pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final accent = g.accent;
    return ChunkyCard(
      key: const Key('email-review-entry'),
      tinted: pending > 0 ? accent : null,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          CategoryAvatar(
            icon: Icons.fact_check_rounded,
            color: accent.base,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perlu dicek',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  pending > 0
                      ? '$pending transaksi dari email menunggu persetujuan'
                      : 'Semua sudah dicek. Mantap!',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          if (pending > 0) ChunkyPill(label: '$pending', color: accent),
          Icon(Icons.chevron_right_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({this.since});

  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: g.accent.base),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
    return ChunkyCard(
      key: const Key('email-explainer'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cara kerjanya',
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
          point(
            Icons.visibility_rounded,
            'Hanya baca (read-only). Ghina nggak bisa kirim, hapus, atau '
            'ubah email kamu.',
          ),
          point(
            Icons.filter_alt_rounded,
            'Cuma email dari pengirim keuangan: bank, kartu kredit, e-wallet, '
            'marketplace, tiket.',
          ),
          point(
            Icons.verified_user_rounded,
            'Nggak ada yang dicatat sebelum kamu setujui di "Perlu dicek".',
          ),
          if (since != null)
            point(
              Icons.history_rounded,
              'Email yang dibaca mulai ${Fmt.dateLong(since!)}.',
            ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.busy,
    required this.triageBusy,
    required this.onDisconnect,
    required this.onTriage,
  });

  final EmailAccount account;
  final bool busy;
  final bool triageBusy;
  final VoidCallback onDisconnect;
  final ValueChanged<bool> onTriage;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = account;
    return ChunkyCard(
      key: Key('email-account-${a.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Divider(height: 20, color: g.border),
          ),
          _TriageSwitch(account: a, busy: triageBusy, onChanged: onTriage),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final g = context.ghina;
    final a = account;
    final (statusLabel, statusColor) = switch (a.status) {
      EmailAccountStatus.active => ('Aktif', GhinaColors.green),
      EmailAccountStatus.error => ('Error', GhinaColors.orange),
      EmailAccountStatus.revoked => ('Akses dicabut', GhinaColors.red),
    };
    final last = a.lastSyncAt;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryAvatar(
          icon: Icons.mail_rounded,
          color: GhinaColors.red.base,
          size: 40,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChunkyPill(
                    label: statusLabel,
                    color: statusColor,
                    soft: true,
                    uppercase: false,
                  ),
                  if (a.pendingCount > 0)
                    ChunkyPill(
                      label: '${a.pendingCount} perlu dicek',
                      color: g.accent,
                      soft: true,
                      uppercase: false,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                a.syncing
                    ? 'Lagi menyinkron di latar belakang…'
                    : last == null
                    ? 'Belum pernah disinkron'
                    : 'Sinkron terakhir ${Fmt.relativeDay(last)} '
                          '${Fmt.time(last)}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              if (a.status != EmailAccountStatus.active &&
                  a.lastError != null) ...[
                const SizedBox(height: 2),
                Text(
                  a.status == EmailAccountStatus.revoked
                      ? 'Akses Gmail dicabut. Hubungkan lagi akun ini.'
                      : a.lastError!,
                  style: GhinaType.caption.copyWith(
                    color: GhinaColors.orange.base,
                  ),
                ),
              ],
            ],
          ),
        ),
        busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: Key('email-disconnect-${a.id}'),
                tooltip: 'Putuskan',
                icon: Icon(Icons.link_off_rounded, color: g.textMuted),
                onPressed: onDisconnect,
              ),
      ],
    );
  }
}

/// "Killa baca semua email" with its short explainer.
class _TriageSwitch extends StatelessWidget {
  const _TriageSwitch({
    required this.account,
    required this.busy,
    required this.onChanged,
  });

  final EmailAccount account;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final on = account.triage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: g.accent.base),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Killa baca semua email',
                style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Switch(
                key: Key('email-triage-${account.id}'),
                value: on,
                onChanged: onChanged,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            on
                ? 'Aktif. Inbox Utama & Update dibaca tiap jam, promo '
                      'dilewati. Mendesak langsung ke WhatsApp; penting '
                      'dikumpulkan jam 08, 12, 18, 21. Kode & password nggak '
                      'pernah diteruskan, dan Killa nggak bisa kirim email.'
                : 'Bukan cuma email keuangan: Killa ringkas yang penting '
                      '(denda, tagihan, keamanan akun, tenggat) dan kabari '
                      'kamu via WhatsApp. Promo dilewati, kode & password '
                      'nggak pernah diteruskan, Killa nggak bisa kirim email.',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ),
      ],
    );
  }
}
