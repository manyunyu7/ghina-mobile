import 'package:flutter/material.dart';
import '../pratinjau/pratinjau_downloads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../state/appearance_provider.dart';
import '../../../state/mascot_kind_provider.dart';
import '../../notes/widgets/speech_model_sheet.dart';
import '../../settings/pages/appearance_page.dart' show themeModeLabel;
import '../kantor_data.dart';
import '../session/chat_view_prefs.dart';
import 'kantor_daemon_settings.dart';
import 'kantor_offline_cache_tile.dart';

/// URL and token of the Kantor daemon, with a connection test.
class KantorSettingsPage extends ConsumerStatefulWidget {
  const KantorSettingsPage({super.key});

  @override
  ConsumerState<KantorSettingsPage> createState() => _KantorSettingsPageState();
}

class _KantorSettingsPageState extends ConsumerState<KantorSettingsPage> {
  final _name = TextEditingController();
  String? _profileId;
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _edge = TextEditingController();
  bool _loaded = false;
  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _edge.dispose();
    super.dispose();
  }

  KantorComplexProfile _draft() {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        _token.text.trim().isEmpty) {
      throw const KantorException(
        KantorFailure.server,
        'Isi alamat HTTP/HTTPS yang valid dan token kompleks.',
      );
    }
    final edge = _edge.text.trim();
    if (edge.isNotEmpty && kantorEdgeHeaders(edge).isEmpty) {
      throw const KantorException(
        KantorFailure.server,
        'Kunci Cloudflare harus berformat CLIENT_ID:CLIENT_SECRET.',
      );
    }
    return KantorComplexProfile(
      id: _profileId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? uri.host : _name.text.trim(),
      baseUrl: _url.text.trim().replaceFirst(RegExp(r'/+$'), ''),
      token: _token.text.trim(),
      edge: edge,
    );
  }

  Future<void> _test({bool save = false}) async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final profile = _draft();
      if (save) {
        // Validate before persisting: a typo never strands an existing chat.
        await ref
            .read(kantorComplexProfilesProvider.notifier)
            .upsert(profile, activate: true);
        ref.invalidate(kantorStateProvider);
        if (mounted) context.go('/kantor');
      } else {
        final st = await KantorApi(profile.config).get('/api/state') as Map;
        final n = (st['offices'] as List?)?.length ?? 0;
        if (mounted)
          setState(() {
            _ok = true;
            _result = 'Tersambung. $n kantor ditemukan.';
          });
      }
    } on KantorException catch (e) {
      if (mounted)
        setState(() {
          _ok = false;
          _result = e.message;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _ok = false;
          _result = 'Koneksi gagal. Periksa alamat dan token kompleks.';
        });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _edit(KantorComplexProfile? profile) {
    setState(() {
      _loaded = true;
      _profileId = profile?.id;
      _name.text = profile?.name ?? '';
      _url.text = profile?.baseUrl ?? '';
      _token.text = profile?.token ?? '';
      _edge.text = profile?.edge ?? '';
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final config = ref.watch(kantorConfigProvider);
    final profiles =
        ref.watch(kantorComplexProfilesProvider).value ??
        const <KantorComplexProfile>[];
    final active = ref.watch(kantorActiveComplexProvider);
    if (!_loaded &&
        config.hasValue &&
        (!config.value!.ready || active != null)) {
      _loaded = true;
      _url.text = config.value!.baseUrl;
      _token.text = config.value!.token;
      _edge.text = config.value!.edge;
      _profileId = active?.id;
      _name.text = active?.name ?? '';
    }
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Pengaturan Kompleks'),
        actions: const [KantorDownloadsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        children: [
          for (final profile in profiles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                profile.id == active?.id
                    ? Icons.check_circle_rounded
                    : Icons.dns_outlined,
              ),
              title: Text(profile.name),
              subtitle: Text(profile.baseUrl),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _testing ? null : () => _edit(profile),
            ),
          TextButton.icon(
            onPressed: _testing ? null : () => _edit(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tambah kompleks'),
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            label: 'Nama kompleks',
            hint: 'Mac Mini, VPS, ...',
            controller: _name,
            prefixIcon: Icons.dns_outlined,
          ),
          const SizedBox(height: GhinaSpace.lg),
          MascotSpeech(
            message:
                'Kantor berjalan di komputermu dan hanya bisa dijangkau lewat '
                'Tailscale. Nyalakan Tailscale di HP ini, lalu isi token dari '
                'pengaturan daemon Kantor.',
            mood: MascotMood.thinking,
            mascotSize: 72,
          ),
          const SizedBox(height: GhinaSpace.xl),
          ChunkyTextField(
            label: 'Alamat kompleks',
            hint: KantorConfig.defaultUrl,
            controller: _url,
            keyboardType: TextInputType.url,
            prefixIcon: Icons.link_rounded,
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyTextField(
            label: 'Token',
            hint: 'Tempel token',
            controller: _token,
            obscureText: true,
            prefixIcon: Icons.key_rounded,
            suffix: IconButton(
              tooltip: 'Tempel',
              icon: const Icon(Icons.paste_rounded),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) {
                  setState(() => _token.text = d!.text!.trim());
                }
              },
            ),
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyTextField(
            label: 'Kunci Cloudflare (opsional)',
            hint: 'CLIENT_ID:CLIENT_SECRET',
            controller: _edge,
            obscureText: true,
            prefixIcon: Icons.shield_outlined,
            suffix: IconButton(
              tooltip: 'Tempel',
              icon: const Icon(Icons.paste_rounded),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) {
                  setState(() => _edge.text = d!.text!.trim());
                }
              },
            ),
          ),
          const SizedBox(height: GhinaSpace.xl),
          ChunkyButton(
            label: 'Uji koneksi',
            loading: _testing,
            onPressed: _testing ? null : () => _test(),
          ),
          if (_result != null) ...[
            const SizedBox(height: GhinaSpace.md),
            ChunkyCard(
              tinted: _ok ? GhinaColors.green : GhinaColors.red,
              padding: const EdgeInsets.all(GhinaSpace.md),
              child: Text(
                _result!,
                style: GhinaType.body.copyWith(color: g.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: GhinaSpace.md),
          ChunkyButton(
            label: 'Simpan dan buka Kompleks',
            variant: ChunkyButtonVariant.outline,
            onPressed: _testing ? null : () => _test(save: true),
          ),
          const SizedBox(height: GhinaSpace.xl),
          const KantorDaemonSettings(),
          // Ghina has its own entry under Pengaturan; Ravel only has this page.
          if (ref.watch(kantorOnlyProvider)) ...[
            ChunkyTile(
              key: const ValueKey('kantor-settings-mascot'),
              title: 'Maskot',
              subtitle:
                  '${ref.watch(mascotKindProvider).label} · ketuk buat ganti',
              leading: const MascotView(
                size: 40,
                animate: false,
                showShadow: false,
              ),
              showChevron: true,
              onTap: () => context.push('/settings/mascot'),
            ),
            GhinaSpace.gapSm,
            ChunkyTile(
              key: const ValueKey('kantor-settings-appearance'),
              title: 'Tampilan',
              subtitle: _lookSummary(ref.watch(appearanceProvider)),
              leading: Icon(switch (ref.watch(appearanceProvider).mode) {
                ThemeMode.system => Icons.brightness_auto_rounded,
                ThemeMode.light => Icons.light_mode_rounded,
                ThemeMode.dark => Icons.dark_mode_rounded,
              }),
              showChevron: true,
              onTap: () => context.push('/settings/appearance'),
            ),
            GhinaSpace.gapSm,
          ],
          ChunkyTile(
            title: 'Tampilan chat',
            subtitle: 'Ukuran teks, wallpaper, gelembung, warna, maskot',
            leading: const Icon(Icons.text_fields_rounded),
            showChevron: true,
            onTap: () => showChatViewSheet(context),
          ),
          GhinaSpace.gapSm,
          ChunkyTile(
            title: 'Tampilan terminal',
            subtitle: 'Tema warna, font, ukuran huruf',
            leading: const Icon(Icons.terminal_rounded),
            showChevron: true,
            onTap: () =>
                showChatViewSheet(context, scope: ViewSheetScope.terminal),
          ),
          GhinaSpace.gapSm,
          const DictationOfflineTile(),
          GhinaSpace.gapSm,
          const KantorOfflineCacheTile(),
          const SizedBox(height: GhinaSpace.xl),
          Text(
            'Token disimpan terenkripsi di perangkat (Keychain / Keystore) dan '
            'tidak ikut tersinkron.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
      ),
    );
  }
}

/// "Mode: Gelap · Biru": what Ravel's "Tampilan" entry opens.
String _lookSummary(GhinaAppearance a) =>
    'Mode: ${themeModeLabel(a.mode)} · ${a.accent.label}';
