import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../files/kantor_files_model.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';
import '../pratinjau/pratinjau_viewers.dart';
import '../pratinjau/pratinjau_widgets.dart';
import '../widgets/kantor_states.dart';
import 'shows_data.dart';
import 'shows_file_view.dart';
import 'shows_mac.dart';
import 'shows_model.dart';

void openKantorShow(BuildContext context, KantorShow show) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => KantorShowScreen(show: show)));

/// One opened item: the agent's note on top, then the file, folder or address.
class KantorShowScreen extends ConsumerStatefulWidget {
  const KantorShowScreen({super.key, required this.show});

  final KantorShow show;

  @override
  ConsumerState<KantorShowScreen> createState() => _KantorShowScreenState();
}

class _KantorShowScreenState extends ConsumerState<KantorShowScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.show.seen)
      Future.microtask(
        () => ref.read(kantorShowsProvider.notifier).markSeen(widget.show.id),
      );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = widget.show;
    final office =
        ref.watch(kantorStateProvider).value?['offices'] as List? ?? const [];
    final officeName =
        [
          for (final o in office)
            if ((o as Map)['id'] == s.office) '${o['name']}',
        ].firstOrNull ??
        s.office;
    final body = s.isUrl
        ? _UrlBody(show: s)
        : s.isHtml
        ? _HtmlBody(show: s)
        : s.isFolder
        ? _FolderBody(
            office: s.office,
            start: s.target.replaceAll(RegExp(r'^/+|/+$'), ''),
          )
        : KantorShowFileView(office: s.office, path: s.target, lines: s.lines);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(kantorShort(s.label, 32), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Tutup item ini',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: () {
              ref.read(kantorShowsProvider.notifier).close(s.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: g.surfaceAlt,
            padding: const EdgeInsets.symmetric(
              horizontal: GhinaSpace.page,
              vertical: GhinaSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dibuka oleh ${s.who} · ${kantorAgo(s.at)} · $officeName',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
                if (s.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      s.note,
                      style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// An HTML file rendered from its signed `/sv/<id>/<key>/` path (sandboxed on
/// the daemon, relative assets included). The WebView may not leave that prefix.
class _HtmlBody extends ConsumerStatefulWidget {
  const _HtmlBody({required this.show});

  final KantorShow show;

  @override
  ConsumerState<_HtmlBody> createState() => _HtmlBodyState();
}

class _HtmlBodyState extends ConsumerState<_HtmlBody> {
  bool _source = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.show;
    final api = ref.watch(kantorApiProvider);
    final view = s.view;
    if (api == null || view == null) {
      return KantorShowFileView(office: s.office, path: s.target);
    }
    final uri = pratinjauUri(api, view);
    final segs = view.split('/').where((x) => x.isNotEmpty).take(3).join('/');
    final prefix =
        '${api.config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/$segs/';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.sm),
          child: Wrap(
            spacing: GhinaSpace.xs,
            children: [
              TextButton.icon(
                icon: Icon(
                  _source ? Icons.web_rounded : Icons.code_rounded,
                  size: 18,
                ),
                label: Text(_source ? 'Tampilkan halaman' : 'Lihat sumber'),
                onPressed: () => setState(() => _source = !_source),
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Buka di browser'),
                onPressed: () =>
                    launchUrl(uri, mode: LaunchMode.externalApplication),
              ),
            ],
          ),
        ),
        Expanded(
          child: _source
              ? KantorShowFileView(office: s.office, path: s.target)
              : PratinjauWeb(uri: uri, prefix: prefix),
        ),
      ],
    );
  }
}

/// `http://localhost:4317/...` (the Kantor itself, seen from the Mac) → the
/// in-app route for a Kantor hash route, or the same path on the app's base URL.
({String? route, Uri? url}) kantorMapLocalUrl(String target, String baseUrl) {
  final u = Uri.tryParse(target);
  final base = Uri.tryParse(baseUrl);
  if (u == null || base == null || !kantorIsLocalHost(u.host)) {
    return (route: null, url: null);
  }
  final port = u.hasPort ? u.port : 80;
  final kantorPort = base.hasPort ? base.port : 4317;
  if (port != 4317 && port != kantorPort) return (route: null, url: null);
  final frag = u.fragment;
  final m = RegExp(r'^/o/([^/?]+)(?:/([^/?]+)(?:/([^?]*))?)?').firstMatch(frag);
  if (m != null) {
    final office = m.group(1)!, tab = m.group(2), rest = m.group(3);
    final b = '/kantor/o/$office';
    if (tab == null) return (route: b, url: null);
    if (tab == 's' && rest != null && rest.isNotEmpty) {
      return (route: '$b/s/${rest.split('/').first}', url: null);
    }
    if (tab == 'pratinjau') {
      return (
        route:
            '$b/pratinjau${rest == null || rest.isEmpty ? '' : '/${rest.split('/').first}'}',
        url: null,
      );
    }
    return (route: '$b?tab=$tab', url: null);
  }
  final mapped = base.replace(
    path: u.path,
    query: u.hasQuery ? u.query : null,
    fragment: u.hasFragment ? u.fragment : null,
  );
  return (route: null, url: mapped);
}

/// Addresses on the Mac (localhost, LAN) cannot be reached from the phone,
/// except the Kantor itself (mapped to the app's Kantor address or route).
class _UrlBody extends ConsumerWidget {
  const _UrlBody({required this.show});

  final KantorShow show;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final api = ref.watch(kantorApiProvider);
    final mapped = api == null
        ? (route: null, url: null)
        : kantorMapLocalUrl(show.target, api.config.baseUrl);
    if (mapped.route != null || mapped.url != null) {
      return ListView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        children: [
          SelectableText(
            show.target,
            style: GhinaType.bodyL.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: GhinaSpace.sm),
          Text(
            'Halaman Kantor; dibuka lewat alamat Kantor yang dipakai aplikasi.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: GhinaSpace.lg),
          Wrap(
            spacing: GhinaSpace.sm,
            runSpacing: GhinaSpace.sm,
            children: [
              ChunkyButton(
                label: mapped.route != null
                    ? 'Buka di aplikasi'
                    : 'Buka di browser',
                size: ChunkyButtonSize.small,
                icon: Icons.open_in_new_rounded,
                onPressed: () => mapped.route != null
                    ? context.push(mapped.route!)
                    : launchUrl(
                        mapped.url!,
                        mode: LaunchMode.externalApplication,
                      ),
              ),
              ChunkyButton(
                label: 'Salin',
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.secondary,
                onPressed: () =>
                    kantorCopy(context, show.target, 'Alamat disalin'),
              ),
            ],
          ),
        ],
      );
    }
    final local = show.isLocalUrl;
    return ListView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        SelectableText(
          show.target,
          style: GhinaType.bodyL.copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: GhinaSpace.sm),
        Text(
          local
              ? 'Alamat ini hanya hidup di Mac, jadi tidak bisa dibuka dari HP. '
                    '"Buka di Mac" membuka folder kantor di Mac (alamatnya sendiri tidak bisa dibukakan dari sini).'
              : 'Alamat web biasa; dibuka di browser HP.',
          style: GhinaType.caption.copyWith(color: g.textMuted),
        ),
        const SizedBox(height: GhinaSpace.lg),
        Wrap(
          spacing: GhinaSpace.sm,
          runSpacing: GhinaSpace.sm,
          children: [
            if (local)
              ChunkyButton(
                label: 'Buka di Mac',
                size: ChunkyButtonSize.small,
                icon: Icons.laptop_mac_rounded,
                onPressed: () => kantorOpenOnMac(context, ref, show.office, ''),
              )
            else
              ChunkyButton(
                label: 'Buka di browser',
                size: ChunkyButtonSize.small,
                icon: Icons.open_in_new_rounded,
                onPressed: () => launchUrl(
                  Uri.parse(show.target),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ChunkyButton(
              label: 'Salin',
              size: ChunkyButtonSize.small,
              variant: ChunkyButtonVariant.secondary,
              onPressed: () =>
                  kantorCopy(context, show.target, 'Alamat disalin'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A small folder browser; files open in [KantorShowFileView].
class _FolderBody extends ConsumerStatefulWidget {
  const _FolderBody({required this.office, required this.start});

  final String office;
  final String start;

  @override
  ConsumerState<_FolderBody> createState() => _FolderBodyState();
}

class _FolderBodyState extends ConsumerState<_FolderBody> {
  late String _dir = widget.start;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final key = (office: widget.office, path: _dir, all: false);
    final folder = ref.watch(kantorFolderProvider(key));
    final up = _dir.contains('/')
        ? _dir.substring(0, _dir.lastIndexOf('/'))
        : '';
    return Column(
      children: [
        KantorMacActions(office: widget.office, path: _dir),
        Expanded(
          child: folder.when(
            error: (e, _) => KantorErrorView(
              error: e,
              onRetry: () => ref.invalidate(kantorFolderProvider(key)),
            ),
            loading: () => const KantorLoading(count: 4),
            data: (f) {
              final es = [...f.entries]
                ..sort(
                  (a, b) => a.dir == b.dir
                      ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                      : (a.dir ? -1 : 1),
                );
              return ListView(
                children: [
                  if (_dir.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.arrow_upward_rounded),
                      title: Text(
                        '/$_dir',
                        style: TextStyle(color: g.textSecondary),
                      ),
                      onTap: () => setState(() => _dir = up),
                    ),
                  if (es.isEmpty)
                    const EmptyState(title: 'Folder kosong', compact: true),
                  for (final e in es)
                    ListTile(
                      leading: Icon(
                        e.dir
                            ? Icons.folder_rounded
                            : Icons.description_outlined,
                      ),
                      title: Text(e.name, overflow: TextOverflow.ellipsis),
                      subtitle: e.dir ? null : Text(kantorFileSize(e.size)),
                      onTap: e.dir
                          ? () => setState(() => _dir = e.path)
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: Text(
                                      e.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  body: KantorShowFileView(
                                    office: widget.office,
                                    path: e.path,
                                  ),
                                ),
                              ),
                            ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
