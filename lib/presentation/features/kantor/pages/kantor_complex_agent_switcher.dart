import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../agents/kantor_active_agents.dart';
import '../widgets/kantor_sprite.dart';

String kantorComplexChatIdentity(String complex, String office, String sid) =>
    jsonEncode([complex, office, sid]);

const _sessionTabs = {'chat', 'terminal', 'profil', 'subagent', 'pratinjau'};
String? kantorSwitchSessionTab(String? tab) =>
    _sessionTabs.contains(tab) ? tab : null;

class KantorRecentComplexChats extends Notifier<List<String>> {
  static const _key = 'kantor.recent_complex_chats.v1';

  @override
  List<String> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key) ?? const <String>[];
      if (ref.mounted) state = {...state, ...saved}.take(12).toList();
    } catch (_) {}
  }

  Future<void> remember(String complex, String office, String sid) async {
    final key = kantorComplexChatIdentity(complex, office, sid);
    state = [key, ...state.where((entry) => entry != key)].take(12).toList();
    try {
      final snapshot = state;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, snapshot);
    } catch (_) {}
  }
}

final kantorRecentComplexChatsProvider =
    NotifierProvider<KantorRecentComplexChats, List<String>>(
      KantorRecentComplexChats.new,
    );

Future<void> showKantorComplexAgentSwitcher(
  BuildContext context, {
  String? officeId,
  String? currentSid,
  String? tab,
}) {
  final router = GoRouter.of(context);
  return showChunkyBottomSheet<void>(
    context,
    title: 'Semua agen · semua kompleks',
    showClose: true,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * .68,
      child: KantorComplexAgentPicker(
        officeId: officeId,
        currentSid: currentSid,
        tab: tab,
        onNavigate: (path) {
          Navigator.of(sheet).pop();
          router.go(path);
        },
      ),
    ),
  );
}

class KantorComplexSwitcherButton extends StatelessWidget {
  const KantorComplexSwitcherButton({
    super.key,
    this.officeId,
    this.currentSid,
    this.tab,
  });
  final String? officeId, currentSid, tab;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('all-complex-agents'),
    tooltip: 'Semua agen di semua kompleks',
    icon: const Icon(Icons.hub_outlined),
    onPressed: () => showKantorComplexAgentSwitcher(
      context,
      officeId: officeId,
      currentSid: currentSid,
      tab: tab,
    ),
  );
}

class KantorComplexAgentPicker extends ConsumerStatefulWidget {
  const KantorComplexAgentPicker({
    super.key,
    this.officeId,
    this.currentSid,
    this.tab,
    required this.onNavigate,
  });
  final String? officeId, currentSid, tab;
  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<KantorComplexAgentPicker> createState() =>
      _KantorComplexAgentPickerState();
}

class _KantorComplexAgentPickerState
    extends ConsumerState<KantorComplexAgentPicker> {
  String _query = '';
  String? _opening;
  String? _error;

  Future<void> _open(KantorComplexProfile profile, KantorAgentRef agent) async {
    if (_opening != null) return;
    setState(() {
      _opening = kantorComplexChatIdentity(
        profile.id,
        agent.officeId,
        agent.sid,
      );
      _error = null;
    });
    try {
      // Probe first: a failed destination must never disconnect the old chat.
      await ref.read(kantorConfigProvider.notifier).activate(profile.id);
      if (!mounted) return;
      unawaited(
        ref
            .read(kantorRecentComplexChatsProvider.notifier)
            .remember(profile.id, agent.officeId, agent.sid),
      );
      widget.onNavigate(
        kantorAgentPath(
          agent.officeId,
          agent.sid,
          tab: kantorSwitchSessionTab(widget.tab),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Tidak bisa membuka ' +
            profile.name +
            '. Periksa koneksi lalu coba lagi.',
      );
      ref.invalidate(kantorComplexStateProvider(profile.id));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(kantorComplexProfilesProvider);
    final active = ref.watch(kantorActiveComplexProvider);
    final recent = ref.watch(kantorRecentComplexChatsProvider);
    final q = _query.trim().toLowerCase();
    final loaded = <(KantorComplexProfile, KantorAgentRef)>[];
    final groups = <Widget>[];
    for (final profile in profiles.value ?? const <KantorComplexProfile>[]) {
      final async = ref.watch(kantorComplexStateProvider(profile.id));
      final all = async.value == null
          ? <KantorAgentRef>[]
          : kantorActiveAgents(async.value!);
      final matches = all
          .where(
            (a) => (profile.name + ' ' + a.haystack).toLowerCase().contains(q),
          )
          .toList();
      loaded.addAll(matches.map((a) => (profile, a)));
      if (q.isNotEmpty &&
          matches.isEmpty &&
          async.hasValue &&
          !profile.name.toLowerCase().contains(q))
        continue;
      final waiting = all.where((a) => a.waiting).length;
      groups.add(
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: GhinaType.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (active?.id == profile.id || waiting > 0)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (active?.id == profile.id)
                            Text('Aktif', style: GhinaType.caption),
                          if (waiting > 0)
                            Text(
                              waiting.toString() + ' menunggu kamu',
                              style: GhinaType.caption.copyWith(
                                color: GhinaColors.orange.edge,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang ' + profile.name,
                onPressed: _opening != null
                    ? null
                    : () => ref.invalidate(
                        kantorComplexStateProvider(profile.id),
                      ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ),
      );
      groups.add(
        Text(
          profile.baseUrl,
          style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      if (async.isLoading) {
        groups.add(
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        );
      } else if (async.hasError) {
        groups.add(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_off_outlined),
            title: const Text('Tidak terhubung'),
            subtitle: const Text('Periksa server atau koneksi kompleks ini.'),
            trailing: TextButton(
              onPressed: _opening != null
                  ? null
                  : () =>
                        ref.invalidate(kantorComplexStateProvider(profile.id)),
              child: const Text('Coba lagi'),
            ),
          ),
        );
      } else if (matches.isEmpty) {
        groups.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              q.isEmpty ? 'Belum ada agen aktif' : 'Tidak ada agen yang cocok',
            ),
          ),
        );
      } else {
        final offices = <String, List<KantorAgentRef>>{};
        for (final a in matches) {
          offices.putIfAbsent(a.officeId, () => []).add(a);
        }
        for (final agents in offices.values) {
          groups.add(
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                agents.first.office['name'].toString(),
                style: GhinaType.overline.copyWith(
                  color: context.ghina.textSecondary,
                ),
              ),
            ),
          );
          for (final a in agents) {
            groups.add(_row(profile, a, active?.id));
          }
        }
      }
    }
    final recentRows = <Widget>[];
    for (final identity in recent) {
      for (final (profile, agent) in loaded) {
        if (kantorComplexChatIdentity(profile.id, agent.officeId, agent.sid) ==
            identity) {
          recentRows.add(_row(profile, agent, active?.id, showComplex: true));
        }
      }
      if (recentRows.length >= 4) break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          hint: 'Cari agen, kantor, atau kompleks…',
          prefixIcon: Icons.search_rounded,
          onChanged: (v) => setState(() => _query = v),
        ),
        if (_opening != null) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: GhinaColors.red.base)),
          ),
        Expanded(
          child: ListView(
            children: [
              if (profiles.isLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (profiles.hasError)
                ListTile(
                  title: const Text('Daftar kompleks tidak bisa dibuka'),
                  trailing: TextButton(
                    onPressed: () =>
                        ref.invalidate(kantorComplexProfilesProvider),
                    child: const Text('Coba lagi'),
                  ),
                ),
              if (recentRows.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                  child: Text('TERAKHIR DIBUKA'),
                ),
                ...recentRows,
              ],
              ...groups,
              if (profiles.hasValue && (profiles.value?.isEmpty ?? true))
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Tambahkan koneksi kompleks di Pengaturan Kantor.',
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    KantorComplexProfile profile,
    KantorAgentRef agent,
    String? activeId, {
    bool showComplex = false,
  }) {
    final identity = kantorComplexChatIdentity(
      profile.id,
      agent.officeId,
      agent.sid,
    );
    final current =
        activeId == profile.id &&
        widget.officeId == agent.officeId &&
        widget.currentSid == agent.sid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ChunkyTile(
        key: ValueKey((showComplex ? 'recent-' : 'agent-') + identity),
        leading: KantorSprite(look: agent.look, size: 36),
        title: agent.name,
        subtitle: [
          if (showComplex)
            profile.name + ' / ' + agent.office['name'].toString(),
          agent.waiting && agent.session['waiting'] is! Map
              ? 'Menunggu kamu'
              : agent.doing,
        ].join(' · '),
        trailing: _opening == identity
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : current
            ? const Icon(Icons.check_rounded)
            : agent.waiting
            ? Tooltip(
                message: 'Menunggu kamu',
                child: Icon(
                  Icons.mark_chat_unread_outlined,
                  size: 20,
                  color: GhinaColors.orange.base,
                  semanticLabel: 'Menunggu kamu',
                ),
              )
            : null,
        onTap: _opening != null ? null : () => _open(profile, agent),
      ),
    );
  }
}
