import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'attachment_model.dart';
import 'attachment_uploader.dart';

/// What the upload queue and the live attachment events tell the owner
/// outside the app window. Tests pass [NoUploadNotifier].
abstract class UploadNotifier {
  /// Ongoing "Mengunggah video ke Rara 45%"; the first call also starts the
  /// foreground service that keeps the upload alive with the screen off.
  Future<void> progress(UploadJob job, {required int waiting});
  Future<void> finished(UploadJob job);
  Future<void> failed(UploadJob job);

  /// The queue is empty: stop the foreground service.
  Future<void> idle();

  /// "Rara mengirim screenshot".
  Future<void> agentSent(String who, KantorAttachment a);
}

class NoUploadNotifier implements UploadNotifier {
  const NoUploadNotifier();
  @override
  Future<void> progress(UploadJob job, {required int waiting}) async {}
  @override
  Future<void> finished(UploadJob job) async {}
  @override
  Future<void> failed(UploadJob job) async {}
  @override
  Future<void> idle() async {}
  @override
  Future<void> agentSent(String who, KantorAttachment a) async {}
}

/// `flutter_local_notifications` (initialised once by the app's gateway).
/// The upload runs in the app's own isolate; the plugin's foreground service
/// (`dataSync`) only keeps that process alive and shows the progress.
class FlutterUploadNotifier implements UploadNotifier {
  FlutterUploadNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const uploadChannelId = 'kantor_upload';
  static const _agentChannelId = 'kantor_claude';
  static const _progressId = 8400001;
  static const _icon = 'ic_stat_ghina';
  static const _accent = Color(0xFF58CC02);

  bool _serviceUp = false;
  bool _channelMade = false;
  String? _lastJob;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _channel() async {
    if (_channelMade) return;
    _channelMade = true;
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        uploadChannelId,
        'Unggahan ke agen',
        description: 'Progres mengirim foto, video, dan file ke agen Kantor.',
        importance: Importance.low,
        showBadge: false,
      ),
    );
  }

  static int _idFor(String s) => 8410000 + (s.hashCode & 0x3ffff);

  AndroidNotificationDetails _progressDetails(int percent) =>
      AndroidNotificationDetails(
        uploadChannelId,
        'Unggahan ke agen',
        icon: _icon,
        color: _accent,
        ongoing: true,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: 100,
        progress: percent,
        category: AndroidNotificationCategory.progress,
        importance: Importance.low,
        priority: Priority.low,
      );

  @override
  Future<void> progress(UploadJob job, {required int waiting}) async {
    final now = DateTime.now();
    final same = _lastJob == job.id;
    if (same &&
        _serviceUp &&
        now.difference(_lastAt) < const Duration(seconds: 1)) {
      return;
    }
    _lastJob = job.id;
    _lastAt = now;
    final title = 'Mengunggah ${job.noun} ke ${job.agent} ${job.percent}%';
    final body = waiting > 0 ? '${job.name} (+$waiting antre)' : job.name;
    try {
      await _channel();
      final details = _progressDetails(job.percent);
      if (!_serviceUp && _android != null) {
        _serviceUp = true;
        await _android!.startForegroundService(
          id: _progressId,
          title: title,
          body: body,
          notificationDetails: details,
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          },
        );
      } else {
        await _plugin.show(
          id: _progressId,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(android: details),
        );
      }
    } catch (e) {
      _serviceUp = false;
      debugPrint('Kantor upload notification: $e');
    }
  }

  Future<void> _result(UploadJob job, String title, String body) async {
    try {
      await _channel();
      await _plugin.show(
        id: _idFor(job.id),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            uploadChannelId,
            'Unggahan ke agen',
            icon: _icon,
            color: _accent,
            importance: Importance.low,
            priority: Priority.low,
            autoCancel: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Kantor upload notification: $e');
    }
  }

  @override
  Future<void> finished(UploadJob job) =>
      _result(job, 'Terkirim ke ${job.agent}', '${job.name} sudah sampai.');

  @override
  Future<void> failed(UploadJob job) => _result(
    job,
    'Gagal mengunggah ${job.noun} ke ${job.agent}',
    '${job.name}: ${job.error ?? 'putus'}. Buka chat ${job.agent} lalu ketuk Coba lagi.',
  );

  @override
  Future<void> idle() async {
    _lastJob = null;
    if (!_serviceUp) return;
    _serviceUp = false;
    try {
      await _android?.stopForegroundService();
      await _plugin.cancel(id: _progressId);
    } catch (e) {
      debugPrint('Kantor upload notification: $e');
    }
  }

  @override
  Future<void> agentSent(String who, KantorAttachment a) async {
    final what = switch (a.kind) {
      AttachmentKind.image => 'screenshot',
      AttachmentKind.video => 'video',
      AttachmentKind.audio => 'audio',
      AttachmentKind.file => 'file ${a.name}',
    };
    try {
      await _plugin.show(
        id: _idFor('att${a.id}'),
        title: '$who mengirim $what',
        body: a.caption.isNotEmpty ? a.caption : a.name,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _agentChannelId,
            'Kantor Claude',
            icon: _icon,
            color: _accent,
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Kantor attachment notification: $e');
    }
  }
}
