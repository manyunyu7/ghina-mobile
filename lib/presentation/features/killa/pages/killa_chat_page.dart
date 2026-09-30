import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_chat_controller.dart';
import '../widgets/killa_common.dart';
import '../widgets/killa_message_views.dart';

/// "Killa": chat with the personal Claude agent (`docs/killa.md`). Online
/// only. Polls the newest page every 20 s while visible and on app resume, so
/// WhatsApp-mirrored turns show up on their own.
class KillaChatPage extends ConsumerStatefulWidget {
  const KillaChatPage({super.key});

  /// Poll interval of the newest page.
  static const pollEvery = Duration(seconds: 20);

  @override
  ConsumerState<KillaChatPage> createState() => _KillaChatPageState();
}

class _KillaChatPageState extends ConsumerState<KillaChatPage>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final List<KillaOutgoingMedia> _media = [];
  Timer? _poll;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(KillaChatPage.pollEvery, (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _resumed = s == AppLifecycleState.resumed;
    if (_resumed) _tick();
  }

  /// Polls only while this page is the visible route, the app is in front
  /// and nothing is being sent.
  void _tick() {
    if (!mounted || !_resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final s = ref.read(killaChatControllerProvider);
    if (s.pending != null || s.loading || s.error != null) return;
    ref.read(killaChatControllerProvider.notifier).refreshNewest();
  }

  Future<void> _send() async {
    final s = ref.read(killaChatControllerProvider);
    if (s.pending != null) return;
    final text = _text.text;
    final media = List.of(_media);
    if (text.trim().isEmpty && media.isEmpty) return;
    HapticFeedback.lightImpact();
    _text.clear();
    setState(_media.clear);
    _jumpToBottom();
    final r = await ref
        .read(killaChatControllerProvider.notifier)
        .send(text, media);
    if (!mounted) return;
    if (r case KillaSendFailed(:final error, :final recorded)) {
      if (!recorded && error.kind != KillaErrorKind.timeout) {
        // Nothing reached the server: give the draft back.
        if (_text.text.isEmpty) _text.text = text;
        if (_media.isEmpty) setState(() => _media.addAll(media));
      }
      if (error.kind == KillaErrorKind.forbidden) return;
      showToastBadge(
        context,
        message: error.kind == KillaErrorKind.timeout
            ? 'Killa masih memproses. Balasannya muncul otomatis nanti 🙏'
            : error.message,
        icon: error.kind == KillaErrorKind.timeout
            ? Icons.hourglass_top_rounded
            : Icons.error_rounded,
        color: error.kind == KillaErrorKind.timeout
            ? GhinaColors.orange
            : GhinaColors.red,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: GhinaMotion.medium, curve: Curves.easeOut);
  }

  Future<void> _attach() async {
    final left = killaMaxMedia - _media.length;
    if (left <= 0) {
      showErrorToast(context, 'Maksimal $killaMaxMedia lampiran, ya');
      return;
    }
    final choice = await showChunkyBottomSheet<String>(
      context,
      title: 'Lampirkan',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (key, icon, label, sub) in [
            (
              'gallery',
              Icons.photo_library_rounded,
              'Foto dari galeri',
              'Dikompres jadi JPEG ≤ 2048 px',
            ),
            ('camera', Icons.photo_camera_rounded, 'Ambil foto', null),
            ('pdf', Icons.picture_as_pdf_rounded, 'Dokumen PDF', 'Maks 8 MB'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChunkyTile(
                dense: true,
                title: label,
                subtitle: sub,
                leading: Icon(icon, color: killaSwatch.base),
                onTap: () => Navigator.pop(c, key),
              ),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final picker = ref.read(killaMediaPickerProvider);
    try {
      final picked = switch (choice) {
        'camera' => [?await picker.takePhoto()],
        'pdf' => await picker.pickPdfs(max: left),
        _ => await picker.pickPhotos(max: left),
      };
      if (!mounted || picked.isEmpty) return;
      final tooBig = picked.where((m) => m.bytes.length > killaMediaMaxBytes);
      if (tooBig.isNotEmpty) {
        showErrorToast(context, '${tooBig.first.name} lebih dari 8 MB');
      }
      setState(
        () => _media.addAll(
          picked.where((m) => m.bytes.length <= killaMediaMaxBytes).take(left),
        ),
      );
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          'Belum bisa ambil file. Cek izin foto/berkas di Pengaturan HP, ya.',
        );
      }
    }
  }

  Future<void> _pickModel() async {
    final cur = ref.read(killaChatControllerProvider).model;
    final m = await showKillaModelSheet(context, cur);
    if (m != null) ref.read(killaChatControllerProvider.notifier).setModel(m);
  }

  Future<void> _newSession() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Mulai sesi baru?',
      message:
          'Killa akan mulai percakapan dari awal (riwayat tetap tersimpan di '
          'sini).',
      confirmLabel: 'Sesi baru',
      mood: MascotMood.thinking,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(killaChatControllerProvider.notifier).newSession();
      if (mounted) showOkToast(context, 'Sesi baru dimulai ✨');
    } on KillaException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    }
  }

  Future<void> _loadOlder() async {
    try {
      await ref.read(killaChatControllerProvider.notifier).loadOlder();
    } on KillaException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = ref.watch(killaChatControllerProvider);
    final locked = s.forbidden;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: killaSwatch.base,
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Killa'),
                  if (!locked)
                    Text(
                      s.pending != null
                          ? 'lagi mengetik…'
                          : 'Model: ${s.model.label}',
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!locked) ...[
            IconButton(
              tooltip: 'Pilih model',
              icon: const Icon(Icons.tune_rounded),
              onPressed: _pickModel,
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu Killa',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) =>
                  v == 'new' ? _newSession() : context.push('/killa/$v'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'new',
                  child: ListTile(
                    leading: Icon(Icons.restart_alt_rounded),
                    title: Text('Sesi baru'),
                  ),
                ),
                PopupMenuItem(
                  value: 'files',
                  child: ListTile(
                    leading: Icon(Icons.folder_rounded),
                    title: Text('Berkas'),
                  ),
                ),
                PopupMenuItem(
                  value: 'commits',
                  child: ListTile(
                    leading: Icon(Icons.commit_rounded),
                    title: Text('Commit'),
                  ),
                ),
                PopupMenuItem(
                  value: 'reminders',
                  child: ListTile(
                    leading: Icon(Icons.alarm_rounded),
                    title: Text('Pengingat Killa'),
                  ),
                ),
                PopupMenuItem(
                  value: 'usage',
                  child: ListTile(
                    leading: Icon(Icons.insights_rounded),
                    title: Text('Pemakaian'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: switch (s) {
        KillaChatState(forbidden: true) => const KillaLockedView(),
        KillaChatState(loading: true) => const Padding(
          padding: EdgeInsets.all(GhinaSpace.page),
          child: SkeletonList(count: 6),
        ),
        KillaChatState(:final error?) => KillaErrorView(
          error: error,
          onRetry: () => ref.read(killaChatControllerProvider.notifier).load(),
        ),
        _ => Column(
          children: [
            if (s.stillProcessing)
              _Banner(
                icon: Icons.hourglass_top_rounded,
                text:
                    'Killa masih memproses pesan terakhir. Balasannya muncul '
                    'otomatis di sini.',
              ),
            Expanded(child: _messages(s)),
            _Composer(
              controller: _text,
              focus: _focus,
              media: _media,
              sending: s.pending != null,
              onAttach: _attach,
              onRemove: (m) => setState(() => _media.remove(m)),
              onSend: _send,
            ),
          ],
        ),
      },
    );
  }

  Widget _messages(KillaChatState s) {
    final now = DateTime.now();
    // Reverse list: index 0 is the bottom (newest).
    final items = <Widget>[];
    if (s.pending case final p?) {
      items.add(
        KillaPendingBubbles(key: const ValueKey('pending'), pending: p),
      );
    }
    final msgs = s.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      final m = msgs[i];
      items.add(
        m.role == KillaRole.system
            ? KillaSystemDivider(key: ValueKey(m.id), message: m)
            : KillaBubble(key: ValueKey(m.id), message: m),
      );
      final prev = i > 0 ? msgs[i - 1] : null;
      if (prev == null || !isSameDay(prev.createdAt, m.createdAt)) {
        items.add(
          KillaDaySeparator(
            key: ValueKey('day-${dateKey(m.createdAt)}'),
            day: m.createdAt,
            now: now,
          ),
        );
      }
    }
    if (s.hasOlder) {
      items.add(
        Padding(
          key: const ValueKey('older'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: ChunkyButton(
              label: 'Muat pesan lama',
              variant: ChunkyButtonVariant.outline,
              size: ChunkyButtonSize.small,
              expand: false,
              icon: Icons.history_rounded,
              loading: s.loadingOlder,
              onPressed: s.loadingOlder ? null : _loadOlder,
            ),
          ),
        ),
      );
    }
    if (msgs.isEmpty && s.pending == null) {
      return ScrollableFill(
        child: EmptyState(
          mood: MascotMood.waving,
          title: 'Hai, aku Killa 👋',
          message:
              'Tanya apa aja, minta dibuatkan catatan, atau kirim foto & PDF '
              'untuk dibahas.',
          actionLabel: 'Mulai ngobrol',
          onAction: _focus.requestFocus,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(killaChatControllerProvider.notifier).refreshNewest();
      },
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: g.tint(GhinaColors.orange),
      child: Row(
        children: [
          Icon(icon, size: 18, color: GhinaColors.orange.base),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.media,
    required this.sending,
    required this.onAttach,
    required this.onRemove,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final List<KillaOutgoingMedia> media;
  final bool sending;
  final VoidCallback onAttach;
  final ValueChanged<KillaOutgoingMedia> onRemove;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      decoration: BoxDecoration(
        color: g.background,
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 14,
                  children: [
                    for (final m in media)
                      KillaMediaPreview(
                        media: m,
                        onRemove: sending ? null : () => onRemove(m),
                      ),
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Lampirkan foto / PDF',
                onPressed: sending ? null : onAttach,
                icon: Badge(
                  isLabelVisible: media.isNotEmpty,
                  label: Text('${media.length}'),
                  backgroundColor: killaSwatch.base,
                  child: const Icon(Icons.attach_file_rounded),
                ),
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey('killa-input'),
                  controller: controller,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 6,
                  maxLength: killaTextMax,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                  decoration: InputDecoration(
                    hintText: sending
                        ? 'Tunggu Killa selesai menjawab…'
                        : 'Tulis pesan ke Killa…',
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: g.surfaceAlt,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: GhinaRadii.rXl,
                      borderSide: BorderSide(color: g.border, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: GhinaRadii.rXl,
                      borderSide: BorderSide(color: g.border, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: GhinaRadii.rXl,
                      borderSide: BorderSide(color: killaSwatch.base, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, v, _) {
                  final can =
                      !sending &&
                      (v.text.trim().isNotEmpty || media.isNotEmpty);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: ChunkyIconButton(
                      key: const ValueKey('killa-send'),
                      icon: sending
                          ? Icons.hourglass_top_rounded
                          : Icons.send_rounded,
                      color: killaSwatch,
                      tooltip: 'Kirim',
                      onPressed: can ? onSend : null,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
