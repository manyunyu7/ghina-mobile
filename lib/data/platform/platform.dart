/// Device services for notes: voice recording/playback, dictation, share
/// target, microphone permission. See `README.md` in this folder.
///
/// The `create*` factories return the production implementation on Android/iOS
/// and a no-op elsewhere (including under `flutter test`).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/services/app_shortcuts.dart';
import '../../domain/services/gmail_authorizer.dart';
import '../../domain/services/launcher_icon.dart';
import '../../domain/services/audio_playback.dart';
import '../../domain/services/killa_media_picker.dart';
import '../../domain/services/microphone_permission.dart';
import '../../domain/services/notification_listener.dart';
import '../../domain/services/notification_log_export.dart';
import '../../domain/services/prayer_reminders.dart';
import '../../domain/services/share_intake.dart';
import '../../domain/services/speech_transcriber.dart';
import '../../domain/services/voice_recorder.dart';
import '../datasources/local/app_database.dart';
import 'battery_optimization_bridge.dart';
import 'channel_share_intake.dart';
import 'device_location.dart';
import 'device_microphone_permission.dart';
import 'fakes.dart';
import 'google_gmail_authorizer.dart';
import 'just_audio_playback.dart';
import 'launcher_icon_bridge.dart';
import 'killa_media_picker_impl.dart';
import 'notification_log_exporter.dart';
import 'notification_listener_bridge.dart';
import 'quick_actions_app_shortcuts.dart';
import 'record_voice_recorder.dart';
import 'stt_speech_transcriber.dart';

export 'app_info.dart';
export 'battery_optimization_bridge.dart' show NoopBatteryOptimization;
export 'launcher_icon_bridge.dart' show NoopLauncherIcon;
export 'device_location.dart' show NoopDeviceLocation;
export 'fakes.dart';
export 'google_gmail_authorizer.dart' show NoopGmailAuthorizer;
export 'notification_listener_bridge.dart'
    show NoopDeviceNotificationListener, notificationCaptureDatabase;

bool get _isTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Android or iOS device (not web, not `flutter test`).
bool get isMobileDevice =>
    !kIsWeb &&
    !_isTest &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get _isAndroid =>
    isMobileDevice && defaultTargetPlatform == TargetPlatform.android;

VoiceRecorder createVoiceRecorder() =>
    isMobileDevice ? RecordVoiceRecorder() : const NoopVoiceRecorder();

AudioPlayback createAudioPlayback() =>
    isMobileDevice ? JustAudioPlayback() : const NoopAudioPlayback();

SpeechTranscriber createSpeechTranscriber() =>
    isMobileDevice ? SttSpeechTranscriber() : const NoopSpeechTranscriber();

MicrophonePermission createMicrophonePermission() => isMobileDevice
    ? DeviceMicrophonePermission()
    : const NoopMicrophonePermission();

/// Android only (iOS share extension is out of scope for v1).
ShareIntake createShareIntake() =>
    _isAndroid ? ChannelShareIntake() : const NoopShareIntake();

/// Launcher shortcuts (Android app shortcuts / iOS quick actions).
AppShortcuts createAppShortcuts() =>
    isMobileDevice ? QuickActionsAppShortcuts() : const NoopAppShortcuts();

/// Android only: iOS can't read other apps' notifications ("Log Notifikasi"
/// is hidden there).
DeviceNotificationListener createDeviceNotificationListener() => _isAndroid
    ? FlutterDeviceNotificationListener()
    : const NoopDeviceNotificationListener();

/// Android only: the adb-pullable copy of "Log Notifikasi"
/// (tool/pull_notification_log.sh).
NotificationLogExport createNotificationLogExport(AppDatabase db) => _isAndroid
    ? NotificationLogExporter(db)
    : const NoopNotificationLogExport();

/// Reminder Sholat "Pakai lokasi GPS" (one-shot coarse fix).
DeviceLocationService createDeviceLocation() => isMobileDevice
    ? const GeolocatorDeviceLocation()
    : const NoopDeviceLocation();

/// Android battery-optimisation shortcut (Reminder Sholat).
BatteryOptimization createBatteryOptimization() =>
    _isAndroid ? BridgeBatteryOptimization() : const NoopBatteryOptimization();

/// Launcher icon = chosen mascot (Android activity-aliases).
LauncherIcon createLauncherIcon() =>
    _isAndroid ? BridgeLauncherIcon() : const NoopLauncherIcon();

/// Killa composer attachments (photos → JPEG ≤ 2048 px, PDFs).
KillaMediaPicker createKillaMediaPicker() =>
    isMobileDevice ? DeviceKillaMediaPicker() : const NoopKillaMediaPicker();

/// Email "Hubungkan Gmail" (google_sign_in `authorizeServer`).
GmailAuthorizer createGmailAuthorizer() => isMobileDevice
    ? const GoogleGmailAuthorizer()
    : const NoopGmailAuthorizer();
