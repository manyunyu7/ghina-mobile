import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/services/prayer_reminders.dart';

/// One-shot coarse location for Reminder Sholat (`geolocator`). Never tracks:
/// one fix when the user picks "Pakai lokasi GPS" and at most one per app open.
class GeolocatorDeviceLocation implements DeviceLocationService {
  const GeolocatorDeviceLocation();

  @override
  Future<LocationFix> current({bool askPermission = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFailed(LocationFailure.serviceOff);
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && askPermission) {
        perm = await Geolocator.requestPermission();
      }
      switch (perm) {
        case LocationPermission.denied:
          return const LocationFailed(LocationFailure.denied);
        case LocationPermission.deniedForever:
          return const LocationFailed(LocationFailure.deniedForever);
        case LocationPermission.unableToDetermine:
          return const LocationFailed(LocationFailure.unavailable);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 15),
          ),
        );
        return LocationFound(p.latitude, p.longitude);
      } catch (e) {
        // Offline / indoors / timeout: the OS's last fix is good enough for
        // prayer times (a few km barely move them).
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return LocationFound(last.latitude, last.longitude);
        debugPrint('GPS fix failed: $e');
        return const LocationFailed(LocationFailure.unavailable);
      }
    } catch (e) {
      debugPrint('Location failed: $e');
      return const LocationFailed(LocationFailure.unavailable);
    }
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  @override
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }
}

/// Tests / desktop.
class NoopDeviceLocation implements DeviceLocationService {
  const NoopDeviceLocation();

  @override
  Future<LocationFix> current({bool askPermission = false}) async =>
      const LocationFailed(LocationFailure.unsupported);

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}
