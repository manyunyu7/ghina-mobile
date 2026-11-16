import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import 'kantor_feed.dart';
import 'kantor_konteks.dart';

/// Label pemilik untuk sesi agen: simpan (optimistis), form ubah label, dan
/// menu tahan-lama yang dipakai daftar agen, strip avatar, dan pencari cepat.
///
/// Endpoint server: `POST /api/sessions/:sid/label` body `{text, carry, tell}`;
/// teks kosong menghapus label.

/// Simpan label sesi [sid]. Tampilan langsung berubah lewat
/// [kantorLabelPatches]; gagal = patch dicabut (tampilan kembali) dan galat
/// dilempar ulang. Berhasil = data server dimuat ulang di latar, lalu patch
/// dilepas sehingga yang tampil kembali data segar.
///
/// [connection] = id profil koneksi lain (null atau sama dengan koneksi aktif
/// = koneksi aktif). [api] menimpa klien yang dipakai; [feed] (atau feed
/// kantor [officeId] yang sedang hidup) ikut dimuat ulang.
Future<void> kantorSaveLabel(
  ProviderContainer c, {
  required String sid,
  required String text,
  required bool carry,
  required bool tell,
  String? officeId,
  String? connection,
  KantorApi? api,
  KantorOfficeFeed? feed,
}) async {
  final active = c.read(kantorActiveComplexProvider)?.id ?? '';
  final other =
      connection != null && connection.isNotEmpty && connection != active;
  final client =
      api ??
      (other
          ? c.read(kantorComplexApiProvider(connection))
          : c.read(kantorApiProvider));
  if (client == null) {
    throw const KantorException(
      KantorFailure.unauthorized,
      'Belum terhubung ke Kantor.',
    );
  }
  final t = text.trim();
  final patch = KantorLabelPatch(
    t.isEmpty ? null : t,
    forRole: t.isNotEmpty && carry,
    tell: t.isNotEmpty && tell,
  );
  kantorLabelPatches.put(sid, patch);
  try {
    await client.post('/api/sessions/${Uri.encodeComponent(sid)}/label', {
      'text': t,
      'carry': t.isNotEmpty && carry,
      'tell': t.isNotEmpty && tell,
    });
  } catch (_) {
    kantorLabelPatches.drop(sid, patch);
    rethrow;
  }
  unawaited(
    _refresh(
      c,
      other: other ? connection : null,
      officeId: officeId,
      feed: feed,
    ).whenComplete(() => kantorLabelPatches.drop(sid, patch)),
  );
}

/// Muat ulang sumber data yang menampilkan label: state koneksi (dipakai
/// strip, pencari, Kompleks) dan feed kantor (daftar agen, judul chat).
Future<void> _refresh(
  ProviderContainer c, {
  String? other,
  String? officeId,
  KantorOfficeFeed? feed,
}) async {
  Future<void> wait<T>(ProviderListenable<Future<T>> p) async {
    // didengar selama memuat supaya provider autoDispose tidak dibuang
    final sub = c.listen(p, (_, _) {});
    try {
      await sub.read();
    } catch (_) {
    } finally {
      sub.close();
    }
  }

  final jobs = <Future<void>>[];
  try {
    if (other != null) {
      c.invalidate(kantorComplexStateProvider(other));
      jobs.add(wait(kantorComplexStateProvider(other).future));
    } else {
      c.invalidate(kantorStateProvider);
      jobs.add(wait(kantorStateProvider.future));
      final f =
          feed ??
          (officeId != null && c.exists(kantorOfficeFeedProvider(officeId))
              ? c.read(kantorOfficeFeedProvider(officeId))
              : null);
      if (f != null) jobs.add(f.load());
    }
    await Future.wait(jobs);
  } catch (_) {
    // muat ulang gagal: patch tetap dilepas, data lama tampil lagi sampai
    // event berikutnya dari server
  }
}

/// Buka form label untuk [session] dan simpan lewat [kantorSaveLabel].
Future<void> kantorEditLabel(
  BuildContext context,
  Json session, {
  String? name,
  String? officeId,
  String? connection,
  KantorApi? api,
  KantorOfficeFeed? feed,
}) {
  final c = ProviderScope.containerOf(context, listen: false);
  return showKantorLabelSheet(
    context,
    session,
    name: name,
    onSave: (text, carry, tell) => kantorSaveLabel(
      c,
      sid: '${session['sid']}',
      text: text,
      carry: carry,
      tell: tell,
      officeId: officeId ?? feed?.officeId,
      connection: connection,
      api: api,
      feed: feed,
    ),
  );
}

/// Menu tahan-lama agen: label lengkap (bila ada) dan aksi "Beri label" /
/// "Ubah label" yang membuka form.
Future<void> showKantorLabelMenu(
  BuildContext context,
  Json session, {
  required String name,
  String? officeId,
  String? connection,
  KantorOfficeFeed? feed,
}) async {
  final edit = await showChunkyBottomSheet<bool>(
    context,
    title: name,
    builder: (c) => KantorLabelMenuBody(
      session: session,
      onEdit: () => Navigator.of(c).pop(true),
    ),
  );
  if (edit != true || !context.mounted) return;
  await kantorEditLabel(
    context,
    session,
    name: name,
    officeId: officeId,
    connection: connection,
    feed: feed,
  );
}

/// Isi menu label: stiker label lengkap lalu baris aksi. Dipakai juga di
/// lembar aksi lain (mis. menu ruang obrolan) supaya tampilannya sama.
class KantorLabelMenuBody extends StatelessWidget {
  const KantorLabelMenuBody({
    super.key,
    required this.session,
    required this.onEdit,
  });

  final Json session;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kantorLabelPatches,
    builder: (context, _) {
      final g = context.ghina;
      final label = kantorLabelOf(session);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              'LABEL',
              style: GhinaType.overline.copyWith(color: g.textMuted),
            ),
            const SizedBox(height: 4),
            KeyedSubtree(
              key: const ValueKey('label-menu-full'),
              child: KantorLabelSticker(label, size: 18),
            ),
            GhinaSpace.gapSm,
          ],
          ListTile(
            key: const ValueKey('label-menu-edit'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(label == null ? 'Beri label' : 'Ubah label'),
            onTap: onEdit,
          ),
        ],
      );
    },
  );
}
