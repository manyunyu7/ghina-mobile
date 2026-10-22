import '../../../../di/di.dart';
import 'kantor_feed.dart';

/// One row of Claude Code's own `/model` picker, as the daemon read it off the screen.
class KantorModelChoice {
  const KantorModelChoice({
    required this.index,
    required this.label,
    this.desc = '',
    this.current = false,
  });

  factory KantorModelChoice.fromJson(Map<dynamic, dynamic> j) =>
      KantorModelChoice(
        index: (j['index'] as num?)?.toInt() ?? 0,
        label: '${j['label'] ?? ''}',
        desc: '${j['desc'] ?? ''}',
        current: j['current'] == true,
      );

  final int index;
  final String label;
  final String desc;
  final bool current;
}

/// Writes to the daemon shared by the agents tab and the session page.
/// Every call throws a [KantorException].
class KantorActions {
  const KantorActions(this.api);
  final KantorApi api;

  Future<void> decide(String inboxId, String behavior) =>
      api.post('/api/inbox/$inboxId', {'behavior': behavior});

  Future<void> sendText(String sid, String text) =>
      api.post('/api/sessions/$sid/action', {'action': 'text', 'text': text});

  /// `esc`, `stop-all`, `compact`, `clear`, `exit`, `kill`.
  /// True when the daemon actually did something; false when the session was idle and there was
  /// nothing to stop (Esc on an idle prompt would only open Claude Code's rewind menu).
  Future<bool> action(String sid, String action) async {
    final r = await api.post('/api/sessions/$sid/action', {'action': action});
    return !(r is Map && r['idle'] == true);
  }

  Future<void> setMode(String sid, String mode) =>
      api.post('/api/sessions/$sid/mode', {'mode': mode});

  /// Opens `/model` in the session's terminal and returns the choices Claude Code offers.
  /// Leaves the picker open until [selectModel] or [cancelModelPicker] (the daemon closes it after a minute).
  Future<List<KantorModelChoice>> openModelPicker(String sid) async {
    final r = await api.post('/api/sessions/$sid/model/open');
    final list = r is Map ? r['options'] : null;
    return [
      if (list is List)
        for (final o in list)
          if (o is Map) KantorModelChoice.fromJson(o),
    ];
  }

  /// Picks a choice for this session only; returns the model name Claude Code confirmed.
  Future<String> selectModel(String sid, int index) async {
    final r = await api.post('/api/sessions/$sid/model/select', {
      'index': index,
    });
    return r is Map ? '${r['model'] ?? ''}' : '';
  }

  Future<void> cancelModelPicker(String sid) =>
      api.post('/api/sessions/$sid/model/cancel');

  /// Answers a held AskUserQuestion through the hook: choices, free text and
  /// notes per question (`[{q, choice | choices, text, note}]`).
  Future<void> submitAsk(String inboxId, List<Json> answers) =>
      api.post('/api/inbox/$inboxId/answer', {'answers': answers});

  /// Fallback once the question moved to the terminal: type the option number.
  Future<void> answerAsk(Json item, int n) async {
    if (item['held'] == true) {
      await decide('${item['id']}', 'allow');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    await sendText('${item['sid']}', '$n');
  }

  /// `GET /api/codex/models` (mesin Codex): katalog model, effort, dan default.
  Future<Map<dynamic, dynamic>> codexModels() async {
    final r = await api.get('/api/codex/models');
    return r is Map ? r : const {};
  }

  /// Ganti model/effort/mode sesi Codex yang sedang idle (409 bila sibuk).
  Future<void> codexSettings(
    String sid, {
    String? model,
    String? effort,
    String? mode,
  }) => api.post('/api/sessions/$sid/codex/settings', {
    'model': ?model,
    'effort': ?effort,
    'mode': ?mode,
  });

  /// Starts a shift for a role without a session; returns the new sid.
  Future<String?> startShift(
    String officeId,
    String roleId, {
    String? task,
    String? permissionMode,
    Map<String, dynamic>? extra,
  }) async {
    final r = await api.post('/api/offices/$officeId/roles/$roleId/start', {
      if (task != null && task.trim().isNotEmpty) 'task': task.trim(),
      if (permissionMode != null && permissionMode.isNotEmpty)
        'permissionMode': permissionMode,
      ...?extra,
    });
    return r is Map ? r['sid'] as String? : null;
  }
}
