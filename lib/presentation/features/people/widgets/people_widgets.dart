import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../people_format.dart';

/// Round avatar: the vibe emoji on a tinted disc.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, this.size = 44});

  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: g.surfaceAlt),
      child: Text(
        person.vibe.emoji,
        semanticsLabel: person.vibe.label,
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}

/// A labelled on/off row ([Switch] without a ListTile, which asserts inside
/// the decorated cards and sheets).
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      toggled: value,
      label: title,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: GhinaRadii.rMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GhinaType.body
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the list: vibe emoji, name, one-line context, tags.
class PersonTile extends StatelessWidget {
  const PersonTile({super.key, required this.person, this.onTap});

  final Person person;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sub = personSubtitle(person);
    return ChunkyCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      borderRadius: GhinaRadii.rLg,
      semanticLabel: person.name,
      child: Row(
        children: [
          PersonAvatar(person: person),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (person.sensitive) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: g.textMuted,
                        semanticLabel: 'Sensitif',
                      ),
                    ],
                  ],
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                if (person.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    person.tags.map((t) => '#$t').join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(
                      color: GhinaColors.blue.base,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}

/// "Ulang tahun & tanggal penting terdekat": the next 60 days.
class UpcomingPeopleCard extends StatelessWidget {
  const UpcomingPeopleCard({
    super.key,
    required this.events,
    required this.onOpen,
    this.limit = 5,
  });

  final List<UpcomingEvent> events;
  final ValueChanged<String> onOpen;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final shown = events.take(limit).toList();
    return ChunkyCard(
      key: const ValueKey('upcoming-people'),
      tinted: GhinaColors.pink,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ulang tahun & tanggal penting terdekat',
            style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 6),
          for (final e in shown)
            InkWell(
              key: ValueKey('upcoming-${e.dateId ?? e.personId}'),
              onTap: () => onOpen(e.personId),
              borderRadius: GhinaRadii.rMd,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            upcomingTitle(e),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.body
                                .w(800)
                                .copyWith(color: g.textPrimary),
                          ),
                          Text(
                            '${formatDayMonthOf(e)} · ${upcomingDetail(e)}',
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (e.daysUntil <= 1)
                      ChunkyPill(
                        label: e.daysUntil == 0 ? 'Hari ini' : 'Besok',
                        color: GhinaColors.pink,
                      ),
                  ],
                ),
              ),
            ),
          if (events.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '+${events.length - shown.length} lainnya',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// `5 Mei` of an upcoming entry's next date (Feb 29 reads Feb 28 in a
/// non-leap year, like the notification).
String formatDayMonthOf(UpcomingEvent e) {
  final p = e.nextDate.split('-').map(int.parse).toList();
  return '${p[2]} ${monthNameId(p[1])}';
}
