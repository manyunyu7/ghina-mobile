import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../notes/widgets/link_open.dart';
import '../people_format.dart';
import '../widgets/people_widgets.dart';
import '../widgets/person_notes_section.dart';

/// `/people/:id`: the fields table, custom fields by their definitions, tags,
/// important dates and the (online-only) notes.
class PersonDetailPage extends ConsumerWidget {
  const PersonDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(watchPersonDetailProvider(id));
    final detail = async.value;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(detail?.person.name ?? 'Orang'),
        actions: [
          if (detail != null) ...[
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => context.push('/people/$id/edit'),
            ),
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(context, ref, detail.person),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: switch (async) {
          AsyncData(:final value?) => _Body(detail: value),
          AsyncData() => ScrollableFill(
            child: EmptyState(
              title: 'Orang ini nggak ketemu',
              message: 'Mungkin sudah dihapus di perangkat lain.',
              mood: MascotMood.thinking,
              actionLabel: 'Kembali',
              onAction: () => popOr(context, '/people'),
            ),
          ),
          AsyncError() => ScrollableFill(
            child: ErrorRetry(
              onRetry: () => ref.invalidate(watchPersonDetailProvider(id)),
            ),
          ),
          _ => const LoadingListView(tiles: 3),
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Person p) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus ${p.name}?',
      message:
          'Datanya, tanggal pentingnya, dan catatannya akan dihapus dari '
          'semua perangkat.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final r = await ref.read(deletePersonProvider)(p.id);
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: '${p.name} dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        popOr(context, '/people');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final PersonDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final p = detail.person;
    final today = peopleDateKey(ref.watch(clockProvider).now());
    final info = <(String, String)>[
      if (p.fullName != null) ('Nama lengkap', p.fullName!),
      if (p.status != null) ('Status', p.status!),
      if (p.howMet != null) ('Kenal dari', p.howMet!),
      if (p.organization != null) ('Organisasi', p.organization!),
      if (p.phone != null) ('Telepon', p.phone!),
      if (p.instagram != null) ('Instagram', p.instagram!),
      if (p.email != null) ('Email', p.email!),
      if (p.address != null) ('Alamat', p.address!),
    ];
    final defKeys = {for (final d in detail.defs) d.key};
    final custom = [
      for (final d in detail.defs)
        if (p.fields[d.key] != null) (d, p.fields[d.key]!),
    ];
    // Values whose definition is hidden for this category (kept, not lost) or
    // gone: shown plainly so nothing is invisible.
    final orphans = [
      for (final e in p.fields.entries)
        if (!defKeys.contains(e.key)) e,
    ];
    final birthday = personBirthdayText(p);
    final nextBirthday = p.hasBirthday
        ? nextAnnualOccurrence(p.birthMonth!, p.birthDay!, p.birthYear, today)
        : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        40,
      ),
      children: [
        ChunkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PersonAvatar(person: p, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: GhinaType.h2.copyWith(color: g.textPrimary),
                        ),
                        if (personSubtitle(p) != null)
                          Text(
                            personSubtitle(p)!,
                            style: GhinaType.body.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChunkyPill(
                    label:
                        '${detail.category?.emoji ?? '👤'} '
                        '${detail.category?.label ?? 'Lainnya'}',
                    color: GhinaColors.blue,
                    soft: true,
                    uppercase: false,
                  ),
                  ChunkyPill(
                    label: '${p.vibe.emoji} ${p.vibe.label}',
                    color: GhinaColors.purple,
                    soft: true,
                    uppercase: false,
                  ),
                  ChunkyPill(
                    label: 'Data ${p.dataStatus.label.toLowerCase()}',
                    color: GhinaColors.gray,
                    soft: true,
                    uppercase: false,
                  ),
                ],
              ),
              if (p.summary != null && p.summary != personSubtitle(p)) ...[
                const SizedBox(height: 12),
                Text(
                  p.summary!,
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
              ],
            ],
          ),
        ),
        if (birthday != null || detail.dates.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(
            title: 'Tanggal penting',
            padding: EdgeInsets.only(top: 4, bottom: 8),
          ),
          ChunkyCard(
            key: const ValueKey('person-dates'),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                if (birthday != null)
                  _DateRow(
                    emoji: EventKind.birthday.emoji,
                    title: 'Ulang tahun',
                    detail: birthday,
                    next: nextBirthday == null
                        ? null
                        : _nextText(
                            EventKind.birthday,
                            nextBirthday.daysUntil,
                            nextBirthday.yearsSince,
                          ),
                  ),
                for (final d in detail.dates)
                  _DateRow(
                    emoji: d.kind.eventKind.emoji,
                    title: d.label,
                    detail: personDateText(d),
                    next: _nextText(
                      d.kind.eventKind,
                      nextAnnualOccurrence(
                        d.month,
                        d.day,
                        d.year,
                        today,
                      ).daysUntil,
                      nextAnnualOccurrence(
                        d.month,
                        d.day,
                        d.year,
                        today,
                      ).yearsSince,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (info.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(
            title: 'Info',
            padding: EdgeInsets.only(top: 4, bottom: 8),
          ),
          ChunkyCard(
            key: const ValueKey('person-info'),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                for (final (label, value) in info)
                  _InfoRow(label: label, child: _CopyText(value)),
              ],
            ),
          ),
        ],
        if (custom.isNotEmpty || orphans.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(
            title: 'Kolom khusus',
            padding: EdgeInsets.only(top: 4, bottom: 8),
          ),
          ChunkyCard(
            key: const ValueKey('person-fields'),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                for (final (d, v) in custom)
                  _InfoRow(
                    label: d.label,
                    child: FieldValueView(def: d, value: v),
                  ),
                for (final e in orphans)
                  _InfoRow(
                    label: prettifyKey(e.key),
                    child: _CopyText('${e.value}'),
                  ),
              ],
            ),
          ),
        ],
        if (p.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(
            title: 'Tag',
            padding: EdgeInsets.only(top: 4, bottom: 8),
          ),
          Wrap(
            key: const ValueKey('person-tags'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in p.tags)
                ChunkyPill(
                  label: '#$t',
                  color: GhinaColors.blue,
                  soft: true,
                  uppercase: false,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        PersonNotesSection(key: ValueKey('notes-${p.id}'), person: p),
      ],
    );
  }

  static String _nextText(EventKind kind, int daysUntil, int? yearsSince) {
    final when = daysUntilLabel(daysUntil);
    if (yearsSince == null || yearsSince < 0) return when;
    return kind == EventKind.birthday
        ? '$when · $yearsSince tahun'
        : '$when · tahun ke-$yearsSince';
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.emoji,
    required this.title,
    required this.detail,
    this.next,
  });

  final String emoji;
  final String title;
  final String detail;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                Text(
                  detail,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          if (next != null)
            Flexible(
              child: Text(
                next!,
                textAlign: TextAlign.end,
                style: GhinaType.caption
                    .w(800)
                    .copyWith(color: GhinaColors.pink.base),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Plain text; a tap copies it.
class _CopyText extends StatelessWidget {
  const _CopyText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return GestureDetector(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) showOkToast(context, 'Disalin', icon: Icons.copy);
      },
      child: Text(text, style: GhinaType.body.copyWith(color: g.textPrimary)),
    );
  }
}

/// A custom-field value rendered by its definition's type (yes/no icon, link,
/// formatted date, option pill, number, long text…).
class FieldValueView extends StatelessWidget {
  const FieldValueView({super.key, required this.def, required this.value});

  final PersonFieldDef def;
  final FieldValue value;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final text = formatFieldValue(def, value);
    switch (def.type) {
      case PersonFieldType.boolean:
        final yes = value == true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              yes ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18,
              color: yes ? GhinaColors.green.base : g.textMuted,
            ),
            const SizedBox(width: 6),
            Text(text, style: GhinaType.body.copyWith(color: g.textPrimary)),
          ],
        );
      case PersonFieldType.url:
        return GestureDetector(
          onTap: () => openLink(context, '$value'),
          child: Text(
            text,
            style: GhinaType.body.copyWith(
              color: GhinaColors.blue.base,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      case PersonFieldType.select:
        return Align(
          alignment: Alignment.centerLeft,
          child: ChunkyPill(
            label: text,
            color: GhinaColors.purple,
            soft: true,
            uppercase: false,
          ),
        );
      case PersonFieldType.email:
      case PersonFieldType.phone:
        return _CopyText(text);
      case PersonFieldType.number:
      case PersonFieldType.date:
      case PersonFieldType.text:
      case PersonFieldType.longtext:
        return Text(text, style: GhinaType.body.copyWith(color: g.textPrimary));
    }
  }
}
