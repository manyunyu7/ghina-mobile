import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';

/// Friendly failure view for any Kantor call. [onRetry] shows a retry button.
class KantorErrorView extends StatelessWidget {
  const KantorErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final kind = error is KantorException
        ? (error as KantorException).kind
        : KantorFailure.server;
    final (title, message) = switch (kind) {
      KantorFailure.unreachable => (
        'Kantor tidak terjangkau',
        'Nyalakan Tailscale di HP ini, lalu pastikan Mac kantor menyala dan tidak tidur.',
      ),
      KantorFailure.unauthorized => (
        'Token ditolak',
        'Token Kantor salah atau sudah diganti. Periksa di pengaturan Kantor.',
      ),
      KantorFailure.notFound => (
        'Tidak ditemukan',
        'Data yang diminta tidak ada.',
      ),
      KantorFailure.server => (
        'Kantor menolak permintaan',
        error is KantorException
            ? (error as KantorException).message
            : '$error',
      ),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MascotView(
              mood: kind == KantorFailure.unreachable
                  ? MascotMood.sleeping
                  : MascotMood.sad,
              size: 96,
            ),
            const SizedBox(height: GhinaSpace.lg),
            Text(
              title,
              style: GhinaType.h3.copyWith(color: context.ghina.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GhinaSpace.sm),
            Text(
              message,
              style: GhinaType.body.copyWith(
                color: context.ghina.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GhinaSpace.xl),
            if (kind == KantorFailure.unreachable) ...[
              ChunkyButton(
                label: 'Buka Tailscale',
                variant: ChunkyButtonVariant.secondary,
                expand: true,
                onPressed: _openTailscale,
              ),
              const SizedBox(height: GhinaSpace.sm),
            ],
            if (kind == KantorFailure.unauthorized)
              ChunkyButton(
                label: 'Pengaturan Kantor',
                expand: true,
                onPressed: () => context.push('/kantor/settings'),
              ),
            if (onRetry != null && kind != KantorFailure.unauthorized)
              ChunkyButton(
                label: 'Coba lagi',
                variant: ChunkyButtonVariant.outline,
                expand: true,
                onPressed: onRetry,
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openTailscale() async {
    for (final uri in [
      Uri.parse('tailscale://'),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=com.tailscale.ipn',
      ),
    ]) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }
}

/// Skeleton placeholder while a Kantor call is in flight.
class KantorLoading extends StatelessWidget {
  const KantorLoading({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(GhinaSpace.page),
    child: SkeletonList(count: count),
  );
}
