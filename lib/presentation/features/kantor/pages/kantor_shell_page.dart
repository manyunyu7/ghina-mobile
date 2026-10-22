import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../agents/kantor_agents_tab.dart';
import '../archive/kantor_archive_tab.dart';
import '../board/kantor_board_tab.dart';
import '../files/kantor_files_tab.dart';
import '../floor/kantor_floor_tab.dart';
import '../kantor_data.dart';
import 'kantor_agent_switcher.dart';
import 'kantor_office_switcher.dart';
import '../meetings/kantor_meetings_tab.dart';
import '../notes/kantor_notes_tab.dart';
import '../proses/kantor_proses_page.dart';
import '../metrics/kantor_metrics_tab.dart';
import '../payroll/kantor_payroll_tab.dart';
import '../pratinjau/pratinjau_feed.dart';
import '../usage/kantor_usage_tab.dart';
import '../roles/kantor_new_agent_sheet.dart';
import '../roles/kantor_role_editor.dart';
import '../roles/kantor_roles_tab.dart';
import '../templates/kantor_templates.dart';
import '../timeline/kantor_timeline_tab.dart';
import '../widgets/kantor_inbox.dart';
import '../widgets/kantor_states.dart';
import '../shows/shows_button.dart';
import '../wiki/kantor_wiki_tab.dart';

typedef _TabBuilder = Widget Function(String officeId);

/// Tab keys (the `tab` query value), label and body. On the phone the agents,
/// wiki and files come first; the rest follows the web's order.
final _tabs = <(String, String, _TabBuilder)>[
  ('agen', 'Agen', (id) => KantorAgentsTab(officeId: id)),
  ('wiki', 'Wiki', (id) => KantorWikiTab(officeId: id)),
  ('file', 'File', (id) => KantorFilesTab(officeId: id)),
  ('pratinjau', 'Pratinjau', (id) => KantorPratinjauFeed(officeId: id)),
  ('kantor', 'Kantor', (id) => KantorFloorTab(officeId: id)),
  ('board', 'Board', (id) => KantorBoardTab(officeId: id)),
  ('timeline', 'Timeline', (id) => KantorTimelineTab(officeId: id)),
  ('rapat', 'Rapat', (id) => KantorMeetingsTab(officeId: id)),
  ('notes', 'Notes', (id) => KantorNotesTab(officeId: id)),
  ('payroll', 'Payroll', (id) => KantorPayrollTab(officeId: id)),
  ('metrik', 'Metrik', (id) => KantorMetricsTab(officeId: id)),
  ('pemakaian', 'Pemakaian', (id) => KantorUsageTab(officeId: id)),
  ('role', 'Role', (id) => KantorRolesTab(officeId: id)),
  ('arsip', 'Arsip', (id) => KantorArchiveTab(officeId: id)),
];

/// The complex has no floor, board or roles of its own.
const _complexTabs = {'notes', 'wiki', 'payroll', 'metrik', 'pemakaian'};

/// One office: a swipeable tab bar over the per-feature tab bodies. Owns the
/// Scaffold and AppBar; tabs only draw their body.
class KantorShellPage extends StatelessWidget {
  const KantorShellPage({super.key, required this.officeId, this.tab});

  final String officeId;
  final String? tab;

  @override
  Widget build(BuildContext context) =>
      // Keyed so switching office rebuilds the tab controller and bodies even
      // when the router reuses this page's element.
      _KantorShellBody(key: ValueKey(officeId), officeId: officeId, tab: tab);
}

class _KantorShellBody extends ConsumerStatefulWidget {
  const _KantorShellBody({super.key, required this.officeId, this.tab});

  final String officeId;
  final String? tab;

  @override
  ConsumerState<_KantorShellBody> createState() => _KantorShellPageState();
}

class _KantorShellPageState extends ConsumerState<_KantorShellBody>
    with SingleTickerProviderStateMixin {
  late final List<(String, String, _TabBuilder)> _visible;
  late final TabController _controller;

  /// The floor (denah) owns pinch and pan, so swiping must not change tabs
  /// while it is the selected one; the tab bar still switches.
  bool _onFloor = false;

  @override
  void initState() {
    super.initState();
    _visible = widget.officeId == '_kompleks'
        ? [
            for (final t in _tabs)
              if (_complexTabs.contains(t.$1)) t,
          ]
        : _tabs;
    final start = _visible.indexWhere((t) => t.$1 == widget.tab);
    _controller = TabController(
      length: _visible.length,
      vsync: this,
      initialIndex: start < 0 ? 0 : start,
    );
    _onFloor = _isFloor(_controller.index);
    _controller.addListener(_syncSwipe);
    if (widget.officeId != '_kompleks') {
      rememberKantorOffice(widget.officeId);
      ref.invalidate(kantorLastOfficeProvider);
    }
  }

  bool _isFloor(int i) => _visible[i].$1 == 'kantor';

  void _syncSwipe() {
    final on = _isFloor(_controller.index);
    if (on != _onFloor && mounted) setState(() => _onFloor = on);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncSwipe);
    _controller.dispose();
    super.dispose();
  }

  void _openInbox(List<dynamic> items, List<dynamic> offices) {
    showChunkyBottomSheet<void>(
      context,
      title: 'Izin menunggu',
      builder: (_) =>
          KantorInboxList(items: items, offices: offices, showOffice: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final id = widget.officeId;
    final office = ref.watch(kantorOfficeProvider(id));
    final state = ref.watch(kantorStateProvider);
    final inbox = (state.value?['inbox'] as List? ?? const [])
        .where((i) => id == '_kompleks' || (i as Map)['office'] == id)
        .toList();
    final sessions = (office.value?['sessions'] as List? ?? const [])
        .where((s) => (s as Map)['status'] != 'ended')
        .toList();
    final working = sessions
        .where((s) => (s as Map)['status'] == 'working')
        .length;

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: InkWell(
          onTap: () => showKantorOfficeSwitcher(
            context,
            currentId: id,
            tab: _visible[_controller.index].$1,
          ),
          child: Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${office.value?['name'] ?? (id == '_kompleks' ? 'Kompleks' : id)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (id != '_kompleks' && office.hasValue)
                      Text(
                        sessions.isEmpty
                            ? 'tidak ada sesi'
                            : '${sessions.length} sesi · $working bekerja',
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
        actions: [
          // Ponsel sempit: maksimal ~2 ikon tetap. "Dibuka untukmu" & izin
          // hanya muncul sebagai ikon saat ada yang menunggu; selebihnya di ⋮.
          const KantorShowsButton(hideWhenIdle: true),
          if (inbox.isNotEmpty)
            IconButton(
              tooltip: 'Izin menunggu',
              onPressed: () => _openInbox(
                inbox,
                (state.value?['offices'] as List?) ?? const [],
              ),
              icon: Badge(
                label: Text('${inbox.length}'),
                child: const Icon(Icons.verified_user_outlined),
              ),
            ),
          if (id != '_kompleks')
            IconButton(
              tooltip: 'Pindah agen',
              icon: const Icon(Icons.groups_rounded),
              onPressed: () => showKantorAgentSwitcher(
                context,
                officeId: id,
                tab: _visible[_controller.index].$1,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Menu kantor',
            onSelected: (v) {
              if (v == 'agen') {
                showKantorNewAgentSheet(context, officeId: id);
              } else if (v == 'role') {
                kantorAddRole(context, id);
              } else if (v == 'proses') {
                openKantorProses(context, officeId: id);
              } else if (v == 'template') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => KantorTemplatePage(officeId: id),
                  ),
                );
              } else if (v == 'izin') {
                _openInbox(
                  inbox,
                  (state.value?['offices'] as List?) ?? const [],
                );
              } else if (v == 'dibuka') {
                showKantorShows(context);
              } else if (v == 'kompleks') {
                ref.read(kantorSkipResumeProvider.notifier).set(true);
                context.go('/kantor');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'kompleks',
                child: _menuRow(Icons.apartment_rounded, 'Kompleks'),
              ),
              PopupMenuItem(
                value: 'izin',
                child: _menuRow(
                  Icons.verified_user_outlined,
                  inbox.isEmpty
                      ? 'Izin menunggu'
                      : 'Izin menunggu (${inbox.length})',
                ),
              ),
              PopupMenuItem(
                value: 'dibuka',
                child: _menuRow(Icons.visibility_outlined, 'Dibuka untukmu'),
              ),
              if (id != '_kompleks') ...[
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'agen', child: Text('Agen baru')),
                const PopupMenuItem(value: 'role', child: Text('Tambah role')),
                const PopupMenuItem(value: 'proses', child: Text('Proses')),
                const PopupMenuItem(
                  value: 'template',
                  child: Text('Suasana kantor (template)'),
                ),
              ],
            ],
          ),
        ],
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _visible) Tab(text: t.$2)],
        ),
      ),
      body: office.when(
        data: (_) => TabBarView(
          controller: _controller,
          physics: _onFloor ? const NeverScrollableScrollPhysics() : null,
          children: [for (final t in _visible) t.$3(id)],
        ),
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kantorOfficeProvider(id)),
        ),
        loading: () => const KantorLoading(),
      ),
    );
  }
}

Widget _menuRow(IconData icon, String label) => Row(
  children: [
    Icon(icon, size: 20),
    const SizedBox(width: 12),
    Flexible(child: Text(label)),
  ],
);
