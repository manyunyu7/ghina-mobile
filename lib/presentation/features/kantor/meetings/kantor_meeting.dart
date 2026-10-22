import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// Meeting data as the daemon returns it.

final class KantorMeetingBrief {
  const KantorMeetingBrief({
    required this.id,
    required this.topic,
    required this.status,
    required this.participants,
    required this.chair,
    required this.createdAt,
    required this.cost,
  });

  factory KantorMeetingBrief.fromJson(Map<String, dynamic> j) =>
      KantorMeetingBrief(
        id: j['id'] as String? ?? '',
        topic: j['topic'] as String? ?? '',
        status: j['status'] as String? ?? '',
        participants: [
          for (final p in (j['participants'] as List?) ?? const []) '$p',
        ],
        chair: j['chair'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String topic;
  final String status;
  final List<String> participants;
  final String chair;
  final String createdAt;
  final double cost;
}

final class KantorMeetingMessage {
  const KantorMeetingMessage({
    required this.id,
    required this.who,
    required this.text,
    required this.at,
    required this.cost,
    required this.kind,
  });

  factory KantorMeetingMessage.fromJson(Map<String, dynamic> j) =>
      KantorMeetingMessage(
        id: '${j['id']}',
        who: j['who'] as String? ?? '',
        text: j['text'] as String? ?? '',
        at: j['at'] as String? ?? '',
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        kind: j['kind'] as String? ?? 'bicara',
      );

  final String id;
  final String who;
  final String text;
  final String at;
  final double cost;

  /// `bicara`, `kamu` (the owner cutting in) or `sistem`.
  final String kind;
}

/// Who is speaking right now and what they have said so far (`meeting-typing`).
/// [text] is cumulative; empty means still thinking.
final class KantorMeetingTyping {
  const KantorMeetingTyping({
    required this.who,
    required this.role,
    required this.text,
  });

  static KantorMeetingTyping? fromJson(Object? j) => j is Map
      ? KantorMeetingTyping(
          who: j['who'] as String? ?? '',
          role: j['role'] as String? ?? '',
          text: j['text'] as String? ?? '',
        )
      : null;

  final String who;
  final String role;
  final String text;
}

final class KantorMeetingAction {
  const KantorMeetingAction({
    required this.title,
    this.who,
    this.prio,
    this.detail,
    this.card,
  });

  factory KantorMeetingAction.fromJson(Map<String, dynamic> j) =>
      KantorMeetingAction(
        title: j['title'] as String? ?? '',
        who: j['who'] as String?,
        prio: j['prio'] as String?,
        detail: j['detail'] as String?,
        card: j['card'] is String && (j['card'] as String).isNotEmpty
            ? j['card'] as String
            : null,
      );

  final String title;
  final String? who;
  final String? prio;
  final String? detail;

  /// Card id once made.
  final String? card;
}

final class KantorMeeting {
  KantorMeeting({
    required this.id,
    required this.topic,
    required this.agenda,
    required this.status,
    required this.participants,
    required this.chair,
    required this.rounds,
    required this.cost,
    required this.summary,
    required this.decisions,
    required this.actions,
    required this.error,
    required this.messages,
    this.typing,
  });

  factory KantorMeeting.fromJson(Map<String, dynamic> j) => KantorMeeting(
    id: j['id'] as String? ?? '',
    topic: j['topic'] as String? ?? '',
    agenda: j['agenda'] as String? ?? '',
    status: j['status'] as String? ?? '',
    participants: [
      for (final p in (j['participants'] as List?) ?? const []) '$p',
    ],
    chair: j['chair'] as String? ?? '',
    rounds: (j['rounds'] as num?)?.toInt(),
    cost: (j['cost'] as num?)?.toDouble() ?? 0,
    summary: j['summary'] as String? ?? '',
    decisions: [for (final d in (j['decisions'] as List?) ?? const []) '$d'],
    actions: [
      for (final a in (j['actions'] as List?) ?? const [])
        if (a is Map) KantorMeetingAction.fromJson(a.cast<String, dynamic>()),
    ],
    error: j['error'] as String? ?? '',
    messages: [
      for (final m in (j['messages'] as List?) ?? const [])
        if (m is Map) KantorMeetingMessage.fromJson(m.cast<String, dynamic>()),
    ],
    typing: KantorMeetingTyping.fromJson(j['typing']),
  );

  final String id;
  final String topic;
  final String agenda;
  final String status;
  final List<String> participants;
  final String chair;
  final int? rounds;
  double cost;
  final String summary;
  final List<String> decisions;
  final List<KantorMeetingAction> actions;
  final String error;
  final List<KantorMeetingMessage> messages;

  /// The participant speaking now, null between turns.
  KantorMeetingTyping? typing;

  bool get running => status == 'berjalan';
  bool get interrupted => status == 'gagal' || status == 'terputus';
}

final kantorMeetingsProvider = FutureProvider.autoDispose
    .family<List<KantorMeetingBrief>, String>((ref, officeId) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null)
        throw const KantorException(
          KantorFailure.unauthorized,
          'Belum ada token',
        );
      final j = await api.get(
        '/api/offices/${Uri.encodeComponent(officeId)}/meetings',
      );
      return [
        for (final m in (j as List))
          if (m is Map) KantorMeetingBrief.fromJson(m.cast<String, dynamic>()),
      ];
    });

/// Estimated turns: participants x rounds + 1 minutes turn.
int kantorMeetingTurns(int participants, int rounds) =>
    participants * rounds + 1;
