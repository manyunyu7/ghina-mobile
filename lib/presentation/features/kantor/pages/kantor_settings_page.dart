import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../session/chat_view_prefs.dart';
import 'kantor_daemon_settings.dart';

/// URL and token of the Kantor daemon, with a connection test.
class KantorSettingsPage extends ConsumerStatefulWidget {
  const KantorSettingsPage({super.key});

  @override
  ConsumerState<KantorSettingsPage> createState() => _KantorSettingsPageState();
}

class _KantorSettingsPageState extends ConsumerState<KantorSettingsPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _loaded = false;
  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(kantorConfigProvider.notifier)
        .save(baseUrl: _url.text, token: _token.text);
    ref.invalidate(kantorStateProvider);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      await _save();
      final api = ref.read(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Isi token dulu.',
        );
      }
      final st = await api.get('/api/state') as Map;
      final n = (st['offices'] as List?)?.length ?? 0;
      setState(() {
        _ok = true;
        _result = 'Tersambung. $n kantor ditemukan.';
      });
    } on KantorException catch (e) {
      setState(() {
        _ok = false;
        _result = e.message;
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _result = 'Gagal: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final config = ref.watch(kantorConfigProvider);
    if (!_loaded && config.hasValue) {
      _loaded = true;
      _url.text = config.value!.baseUrl;
      _token.text = config.value!.token;
    }
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Pengaturan Kantor')),
      body: ListView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        children: [
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
            label: 'Alamat Kantor',
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
          const SizedBox(height: GhinaSpace.xl),
          ChunkyButton(
            label: 'Uji koneksi',
            loading: _testing,
            onPressed: _testing ? null : _test,
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
            onPressed: _testing
                ? null
                : () async {
                    await _save();
                    if (context.mounted) context.go('/kantor');
                  },
          ),
          const SizedBox(height: GhinaSpace.xl),
          const KantorDaemonSettings(),
          ChunkyTile(
            title: 'Tampilan chat',
            subtitle: 'Ukuran teks, kerapatan, kartu tool',
            leading: const Icon(Icons.text_fields_rounded),
            showChevron: true,
            onTap: () => showChatViewSheet(context),
          ),
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
