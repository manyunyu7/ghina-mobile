import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_format.dart';
import '../roles/kantor_ui.dart';
import 'pratinjau_widgets.dart';

/// Owner actions on a pratinjau item, shared by the feed card, the detail
/// page and the session-chat bubble: buttons per `jenis`, reactions, the
/// neutral menu (simpan / nanti dulu / arsipkan) and the comment list.

const pratinjauEmojis = ['👍', '❤️', '🔥', '🤔'];

/// Runs [action]; on success refreshes the feeds and returns the new item.
Future<PratinjauItem?> pratinjauDo(
  BuildContext context,
  WidgetRef ref,
  Future<PratinjauItem> Function(KantorApi api) action, [
  String? done,
]) async {
  final api = ref.read(kantorApiProvider);
  if (api == null) return null;
  PratinjauItem? out;
  final ok = await kantorGuard(context, () async {
    out = await action(api);
    ref.invalidate(kantorPratinjauFeedProvider);
    ref.invalidate(kantorPratinjauSessionProvider);
  });
  if (ok && done != null && context.mounted) kantorToast(context, done);
  return ok ? out : null;
}

Future<PratinjauItem?> pratinjauApprove(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it,
) async {
  final note = await showPratinjauNoteSheet(
    context,
    title: 'Setujui',
    action: 'Setujui',
    message: it.files.length > 1
        ? 'Semua ${it.files.length} file ditandai oke.'
        : null,
  );
  if (note == null || !context.mounted) return null;
  return pratinjauDo(
    context,
    ref,
    (api) => api.pratinjauSetujui(it.office, it.id, catatan: note),
    'Pratinjau disetujui',
  );
}

Future<PratinjauItem?> pratinjauRevise(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it,
) async {
  final note = await showPratinjauNoteSheet(
    context,
    title: 'Minta revisi',
    action: 'Kirim revisi',
    hint: 'Apa yang perlu diubah?',
    required: true,
    variant: ChunkyButtonVariant.danger,
  );
  if (note == null || note.isEmpty || !context.mounted) return null;
  return pratinjauDo(
    context,
    ref,
    (api) => api.pratinjauRevisi(it.office, it.id, note),
    'Permintaan revisi terkirim',
  );
}

Future<PratinjauItem?> pratinjauPick(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it,
  PratinjauFile f,
) async {
  final note = await showPratinjauNoteSheet(
    context,
    title: 'Pilih ${f.name}?',
    action: 'Pilih yang ini',
  );
  if (note == null || !context.mounted) return null;
  return pratinjauDo(
    context,
    ref,
    (api) => api.pratinjauPilih(it.office, it.id, f.id, catatan: note),
    '${f.name} dipilih',
  );
}

String pratinjauClock(double s) {
  final d = Duration(milliseconds: (s * 1000).round());
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Comment on the item, a file ([file]) or a moment of a video ([t]).
Future<PratinjauItem?> pratinjauComment(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it, {
  PratinjauFile? file,
  double? t,
}) async {
  final where = [
    if (file != null) file.name,
    if (t != null) 'di ${pratinjauClock(t)}',
  ].join(' ');
  final text = await showPratinjauNoteSheet(
    context,
    title: where.isEmpty ? 'Komentar' : 'Komentar · $where',
    action: 'Kirim komentar',
    hint: 'Tulis komentar untuk agen',
    required: true,
  );
  if (text == null || text.isEmpty || !context.mounted) return null;
  return pratinjauDo(
    context,
    ref,
    (api) =>
        api.pratinjauKomentar(it.office, it.id, text, file: file?.id, t: t),
    'Komentar terkirim',
  );
}

Future<PratinjauItem?> pratinjauSeen(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it,
) => pratinjauDo(
  context,
  ref,
  (api) => api.pratinjauLihat(it.office, it.id),
  'Ditandai sudah dilihat',
);

Future<PratinjauItem?> pratinjauReact(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it,
  String emoji,
) => pratinjauDo(
  context,
  ref,
  (api) => api.pratinjauReaksi(it.office, it.id, emoji),
);

/// "Nanti dulu" choices; null = cancelled, `(null, true)` = clear.
Future<PratinjauItem?> pratinjauSnooze(
  BuildContext context,
  WidgetRef ref,
  PratinjauItem it,
) async {
  final now = DateTime.now();
  DateTime at(DateTime d, int h) => DateTime(d.year, d.month, d.day, h);
  var tonight = at(now, 20);
  if (!tonight.isAfter(now)) tonight = tonight.add(const Duration(days: 1));
  final tomorrow = at(now.add(const Duration(days: 1)), 9);
  final nextWeek = at(now.add(const Duration(days: 7)), 9);
  final options = <(String, DateTime?)>[
    ('1 jam lagi', now.add(const Duration(hours: 1))),
    ('Nanti malam 20:00', tonight),
    ('Besok 09:00', tomorrow),
    ('Minggu depan', nextWeek),
    if (it.snoozed || it.snoozedUntil != null)
      ('Tampilkan lagi sekarang', null),
  ];
  final picked = await showChunkyBottomSheet<(String, DateTime?)>(
    context,
    title: 'Nanti dulu',
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in options)
          ListTile(
            leading: Icon(
              o.$2 == null ? Icons.alarm_off_rounded : Icons.snooze_rounded,
            ),
            title: Text(o.$1),
            onTap: () => Navigator.of(c).pop(o),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return null;
  final until = picked.$2;
  return pratinjauDo(
    context,
    ref,
    (api) => api.pratinjauTanda(
      it.office,
      it.id,
      snoozedUntil: until,
      clearSnooze: until == null,
    ),
    until == null
        ? 'Ditampilkan lagi'
        : 'Disembunyikan sampai ${picked.$1.toLowerCase()}',
  );
}

String _when(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '-';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

/// ⋯ menu: 📌 Simpan/Lepas, ⏸ Nanti dulu, 🗂 Arsipkan/Kembalikan.
class PratinjauMenuButton extends ConsumerWidget {
  const PratinjauMenuButton({
    super.key,
    required this.item,
    this.onItem,
    this.extra = const [],
    this.onExtra,
  });

  final PratinjauItem item;
  final ValueChanged<PratinjauItem>? onItem;

  /// Extra entries (value, label) placed first.
  final List<(String, String)> extra;
  final ValueChanged<String>? onExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final it = item;
    return PopupMenuButton<String>(
      tooltip: 'Menu pratinjau',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) async {
        PratinjauItem? next;
        switch (v) {
          case 'pin':
            next = await pratinjauDo(
              context,
              ref,
              (api) => api.pratinjauTanda(it.office, it.id, pinned: !it.pinned),
              it.pinned ? 'Dilepas dari simpanan' : 'Disimpan',
            );
          case 'snooze':
            next = await pratinjauSnooze(context, ref, it);
          case 'arsip':
            next = await pratinjauDo(
              context,
              ref,
              (api) =>
                  api.pratinjauTanda(it.office, it.id, archived: !it.archived),
              it.archived ? 'Dikembalikan dari arsip' : 'Diarsipkan',
            );
          default:
            onExtra?.call(v);
        }
        if (next != null) onItem?.call(next);
      },
      itemBuilder: (_) => [
        for (final (v, label) in extra)
          PopupMenuItem(value: v, child: Text(label)),
        PopupMenuItem(
          value: 'pin',
          child: Text(it.pinned ? '📌 Lepas simpanan' : '📌 Simpan'),
        ),
        PopupMenuItem(
          value: 'snooze',
          child: Text(
            it.snoozed
                ? '⏸ Nanti dulu (sampai ${_when(it.snoozedUntil)})'
                : '⏸ Nanti dulu',
          ),
        ),
        PopupMenuItem(
          value: 'arsip',
          child: Text(it.archived ? '🗂 Kembalikan' : '🗂 Arsipkan'),
        ),
      ],
    );
  }
}

/// 👍 ❤️ 🔥 🤔, highlighted when set.
class PratinjauReactions extends ConsumerWidget {
  const PratinjauReactions({super.key, required this.item, this.onItem});
  final PratinjauItem item;
  final ValueChanged<PratinjauItem>? onItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in pratinjauEmojis)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              borderRadius: GhinaRadii.rSm,
              onTap: () async {
                final next = await pratinjauReact(context, ref, item, e);
                if (next != null) onItem?.call(next);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: GhinaRadii.rSm,
                  color: item.reactions.containsKey(e)
                      ? g.highlight.base.withValues(alpha: 0.18)
                      : null,
                  border: Border.all(
                    color: item.reactions.containsKey(e)
                        ? g.highlight.base
                        : g.border,
                  ),
                ),
                child: Text(e, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Main buttons per `jenis`:
/// persetujuan → Setujui · Revisi · Komentar; info → 👀 Sudah lihat ·
/// Komentar; pilihan → ⭐ Pilih ([file], else opens [onOpen]) · Komentar.
class PratinjauActionBar extends ConsumerStatefulWidget {
  const PratinjauActionBar({
    super.key,
    required this.item,
    this.onItem,
    this.file,
    this.onOpen,
    this.compact = false,
    this.trailing,
  });

  final PratinjauItem item;
  final ValueChanged<PratinjauItem>? onItem;

  /// File in view (detail page): comments attach to it, ⭐ Pilih picks it.
  final PratinjauFile? file;

  /// Called by ⭐ Pilih when no [file] is given (choose in the detail page).
  final VoidCallback? onOpen;
  final bool compact;
  final Widget? trailing;

  @override
  ConsumerState<PratinjauActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<PratinjauActionBar> {
  bool _busy = false;

  Future<void> _go(Future<PratinjauItem?> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    final next = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    if (next != null) widget.onItem?.call(next);
  }

  Widget _btn(
    String label,
    IconData? icon,
    VoidCallback? onTap, {
    ChunkyButtonVariant variant = ChunkyButtonVariant.secondary,
  }) => ChunkyButton(
    label: label,
    icon: icon,
    size: widget.compact ? ChunkyButtonSize.small : ChunkyButtonSize.medium,
    variant: variant,
    onPressed: _busy ? null : onTap,
  );

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final f = widget.file;
    final buttons = <Widget>[
      if (it.isPilihan)
        if (f != null)
          _btn(
            it.picked == f.id ? 'Dipilih' : '⭐ Pilih',
            it.picked == f.id ? Icons.check_rounded : null,
            it.picked == f.id
                ? null
                : () => _go(() => pratinjauPick(context, ref, it, f)),
            variant: ChunkyButtonVariant.primary,
          )
        else
          _btn(
            '⭐ Pilih',
            null,
            widget.onOpen,
            variant: ChunkyButtonVariant.primary,
          )
      else if (it.isInfo)
        _btn(
          it.seenAt != null ? '👀 Sudah dilihat' : '👀 Sudah lihat',
          null,
          it.seenAt != null
              ? null
              : () => _go(() => pratinjauSeen(context, ref, it)),
          variant: ChunkyButtonVariant.primary,
        )
      else ...[
        _btn(
          'Setujui',
          Icons.check_rounded,
          it.status == 'disetujui'
              ? null
              : () => _go(() => pratinjauApprove(context, ref, it)),
          variant: ChunkyButtonVariant.primary,
        ),
        _btn(
          'Revisi',
          Icons.edit_rounded,
          () => _go(() => pratinjauRevise(context, ref, it)),
          variant: ChunkyButtonVariant.outline,
        ),
      ],
      _btn(
        widget.compact ? '💬' : 'Komentar',
        widget.compact ? null : Icons.chat_bubble_outline_rounded,
        () => _go(() => pratinjauComment(context, ref, it, file: f)),
        variant: ChunkyButtonVariant.outline,
      ),
    ];
    return Wrap(
      spacing: GhinaSpace.xs,
      runSpacing: GhinaSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [...buttons, ?widget.trailing],
    );
  }
}

/// Owner comments, newest last. Tapping a timed one calls [onSeek].
class PratinjauComments extends StatelessWidget {
  const PratinjauComments({super.key, required this.item, this.onSeek});
  final PratinjauItem item;
  final void Function(PratinjauComment c)? onSeek;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (item.comments.isEmpty) return const SizedBox.shrink();
    String? fileName(String? id) =>
        item.files.where((f) => f.id == id).firstOrNull?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Komentar (${item.comments.length})',
          style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
        ),
        for (final c in item.comments)
          InkWell(
            onTap: c.t != null && onSeek != null ? () => onSeek!(c) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (fileName(c.file) != null || c.t != null)
                      TextSpan(
                        text:
                            '${[?fileName(c.file), if (c.t != null) '⏱ ${pratinjauClock(c.t!)}'].join(' · ')}  ',
                        style: TextStyle(
                          color: g.highlight.base,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    TextSpan(text: c.text),
                    if (c.at != null)
                      TextSpan(
                        text: '  · ${kantorAgo(c.at)}',
                        style: TextStyle(color: g.textMuted),
                      ),
                  ],
                ),
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}
