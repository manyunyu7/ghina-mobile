import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/services/prayer_reminders.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/notifications/notification_providers.dart';
import '../../../state/prayer_reminders/prayer_reminder_providers.dart';
import '../../tasks/widgets/reminder_settings.dart'
    show BatteryTipList, showBatteryTip, showEnableInSettings;
import '../widgets/prayer_schedule_card.dart';
import '../widgets/prayer_visuals.dart';

/// Android battery-optimisation exemption (refreshed on resume).
final _batteryExemptProvider = FutureProvider.autoDispose<bool?>(
  (ref) => ref.watch(batteryOptimizationProvider).isIgnoring(),
);

bool _isAndroid(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.android;

/// "Pengaturan Reminder Sholat": master switch, today's schedule, location
/// (city / GPS), calculation method, sound, per-prayer options (pre-reminder,
/// follow-ups, time correction) and the permission / battery checks.
class PrayerReminderSettingsPage extends ConsumerStatefulWidget {
  const PrayerReminderSettingsPage({super.key});

  @override
  ConsumerState<PrayerReminderSettingsPage> createState() =>
      _PrayerReminderSettingsPageState();
}

class _PrayerReminderSettingsPageState
    extends ConsumerState<PrayerReminderSettingsPage> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () {
      ref.read(notificationPermissionProvider.notifier).refresh();
      ref.invalidate(_batteryExemptProvider);
    },
  );
  bool _locating = false;
  Prayer? _expanded;

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  PrayerReminderSettingsController get _ctl =>
      ref.read(prayerReminderSettingsProvider.notifier);

  Future<void> _setEnabled(bool on) async {
    await _ctl.setEnabled(on);
    if (!on || !mounted) return;
    final ok = await _ensurePermission();
    if (!ok || !mounted) return;
    final perm = ref.read(notificationPermissionProvider).value;
    if (_isAndroid(context) &&
        perm != null &&
        perm.granted &&
        !perm.exactAlarms) {
      await _askExactAlarms();
    }
    if (mounted) {
      showToastBadge(
        context,
        message: 'Pengingat sholat aktif 🕌',
        icon: Icons.notifications_active_rounded,
        color: GhinaColors.green,
      );
    }
  }

  /// Same flow as task/habit reminders, with sholat wording.
  Future<bool> _ensurePermission() async {
    final NotificationPermissionState perm;
    try {
      perm = await ref.read(notificationPermissionProvider.future);
    } catch (_) {
      return true;
    }
    if (perm.granted || perm.status.name == 'unsupported') {
      return true;
    }
    if (!mounted) return false;
    final go = await showChunkyConfirm(
      context,
      title: 'Boleh Ghina ngingetin sholat? 🔔',
      message:
          'Ghina perlu izin kirim notifikasi buat adzan, pengingat sebelum '
          'waktu sholat, dan pengingat susulan.',
      confirmLabel: 'Izinkan',
      cancelLabel: 'Nanti saja',
      mood: MascotMood.waving,
    );
    if (!go || !mounted) return false;
    final granted = await ref
        .read(notificationPermissionProvider.notifier)
        .request();
    if (!mounted) return granted;
    if (granted) {
      if (_isAndroid(context)) await showBatteryTip(context);
      return true;
    }
    await showEnableInSettings(context, ref);
    return false;
  }

  Future<void> _askExactAlarms() async {
    final go = await showChunkyConfirm(
      context,
      title: 'Biar adzan tepat waktu ⏰',
      message:
          'Tanpa izin "Alarm & pengingat", Android bisa menunda notifikasi '
          'beberapa menit saat HP lagi hemat daya. Izinkan sekarang?',
      confirmLabel: 'Izinkan',
      cancelLabel: 'Nanti saja',
      mood: MascotMood.thinking,
    );
    if (!go || !mounted) return;
    await ref
        .read(notificationPermissionProvider.notifier)
        .requestExactAlarms();
    ref.read(prayerReminderSyncControllerProvider.notifier).syncNow();
  }

  Future<void> _pickCity(PrayerLocation current) async {
    final city = await showChunkyBottomSheet<PrayerCity>(
      context,
      title: 'Pilih kota',
      showClose: true,
      builder: (_) => _CityPicker(selected: current),
    );
    if (city == null || !mounted) return;
    await _ctl.useCity(city);
    if (mounted) {
      showToastBadge(
        context,
        message: 'Jadwal pakai ${city.name}',
        icon: Icons.location_city_rounded,
        color: GhinaColors.blue,
      );
    }
  }

  Future<void> _useGps() async {
    if (_locating) return;
    setState(() => _locating = true);
    final LocationFix fix;
    try {
      fix = await _ctl.refreshGps(askPermission: true, force: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
    if (!mounted) return;
    switch (fix) {
      case LocationFound():
        final name = ref.read(prayerReminderSettingsProvider).value?.location;
        showToastBadge(
          context,
          message: 'Lokasi GPS dipakai: ${name?.name ?? ''}',
          icon: Icons.my_location_rounded,
          color: GhinaColors.green,
        );
      case LocationFailed(:final reason):
        await _locationFailed(reason);
    }
  }

  Future<void> _locationFailed(LocationFailure reason) async {
    final loc = ref.read(deviceLocationProvider);
    switch (reason) {
      case LocationFailure.serviceOff:
        await _settingsDialog(
          'GPS lagi mati',
          'Nyalakan lokasi (GPS) di HP dulu, lalu coba lagi.',
          loc.openLocationSettings,
        );
      case LocationFailure.deniedForever:
        await _settingsDialog(
          'Izin lokasi ditolak',
          'Buka Pengaturan → Aplikasi → Ghina → Izin → Lokasi, lalu pilih '
              '"Izinkan hanya saat aplikasi digunakan".',
          loc.openAppSettings,
        );
      case LocationFailure.denied:
        showErrorToast(context, 'Izin lokasi belum diberikan.');
      case LocationFailure.unavailable:
        showErrorToast(
          context,
          'Belum dapat lokasi. Coba lagi di tempat terbuka, ya.',
        );
      case LocationFailure.unsupported:
        showErrorToast(context, 'GPS nggak tersedia di perangkat ini.');
    }
  }

  Future<void> _settingsDialog(
    String title,
    String message,
    Future<void> Function() open,
  ) => showChunkyDialog<void>(
    context,
    builder: (c) => ChunkyDialog(
      title: title,
      message: message,
      mood: MascotMood.thinking,
      actions: [
        ChunkyButton(
          label: 'Buka pengaturan',
          icon: Icons.settings_rounded,
          onPressed: () {
            Navigator.of(c).pop();
            open();
          },
        ),
        ChunkyButton(
          label: 'Nanti saja',
          variant: ChunkyButtonVariant.ghost,
          color: GhinaColors.blue,
          onPressed: () => Navigator.of(c).pop(),
        ),
      ],
    ),
  );

  Future<void> _pickMethod(PrayerCalcMethod current) async {
    final m = await showChunkyBottomSheet<PrayerCalcMethod>(
      context,
      title: 'Metode perhitungan',
      showClose: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in PrayerCalcMethod.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChunkyTile(
                key: ValueKey('method-${m.wire}'),
                title: m.label,
                subtitle: m.description,
                tinted: m == current ? GhinaColors.green : null,
                trailing: m == current
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: GhinaColors.green.base,
                      )
                    : null,
                onTap: () => Navigator.of(c).pop(m),
              ),
            ),
        ],
      ),
    );
    if (m != null) await _ctl.setMethod(m);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(prayerReminderSettingsProvider);
    final s = async.value;
    final android = _isAndroid(context);

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Reminder Sholat')),
      body: s == null
          ? (async.hasError
                ? ErrorRetry(
                    onRetry: () =>
                        ref.invalidate(prayerReminderSettingsProvider),
                  )
                : const SkeletonList(count: 4))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.md,
                GhinaSpace.page,
                GhinaSpace.xxl,
              ),
              children: [
                ChunkyCard(
                  tinted: s.enabled ? GhinaColors.green : null,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ChunkyTile(
                    framed: false,
                    title: 'Pengingat sholat',
                    subtitle: s.enabled
                        ? 'Adzan 5 waktu + susulan sampai kamu centang'
                        : 'Semua pengingat sholat mati',
                    leading: CategoryAvatar(
                      icon: s.enabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      color: GhinaColors.green.base,
                      size: 40,
                    ),
                    trailing: Switch(
                      key: const ValueKey('prayer-reminders-enabled'),
                      value: s.enabled,
                      onChanged: _setEnabled,
                    ),
                    onTap: () => _setEnabled(!s.enabled),
                  ),
                ),
                GhinaSpace.gapMd,
                const PrayerScheduleCard(showSettingsLink: false),
                GhinaSpace.gapXl,
                const SectionHeader(
                  title: 'Lokasi & perhitungan',
                  subtitle: 'Dihitung offline di HP, tanpa internet',
                ),
                _LocationCard(
                  location: s.location,
                  locating: _locating,
                  onPickCity: () => _pickCity(s.location),
                  onUseGps: _useGps,
                ),
                GhinaSpace.gapMd,
                ChunkyCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ChunkyTile(
                    key: const ValueKey('prayer-method'),
                    framed: false,
                    title: 'Metode: ${s.method.label}',
                    subtitle: s.method.description,
                    leading: CategoryAvatar(
                      icon: Icons.calculate_rounded,
                      color: GhinaColors.purple.base,
                      size: 40,
                    ),
                    showChevron: true,
                    onTap: () => _pickMethod(s.method),
                  ),
                ),
                GhinaSpace.gapXl,
                const SectionHeader(
                  title: 'Per waktu sholat',
                  subtitle:
                      'Ketuk buat atur pengingat, susulan & koreksi waktu',
                ),
                for (final p in Prayer.fardhu)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SlotCard(
                      prayer: p,
                      slot: s.slot(p),
                      expanded: _expanded == p,
                      onToggleExpanded: () =>
                          setState(() => _expanded = _expanded == p ? null : p),
                      onChanged: (slot) => _ctl.setSlot(p, slot),
                    ),
                  ),
                GhinaSpace.gapLg,
                const SectionHeader(title: 'Suara'),
                ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ChunkyChoiceChips<PrayerReminderSound>(
                        options: [
                          for (final v in PrayerReminderSound.values)
                            ChunkyChoice(
                              value: v,
                              label: v == PrayerReminderSound.silent
                                  ? 'Senyap'
                                  : 'Bawaan',
                              icon: v == PrayerReminderSound.silent
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                            ),
                        ],
                        selected: {s.sound},
                        onChanged: (v) => _ctl.setSound(v.first),
                      ),
                      GhinaSpace.gapSm,
                      Text(
                        s.sound.label,
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                      GhinaSpace.gapSm,
                      Text(
                        'Suara adzan menyusul (biar aplikasinya tetap ringan). '
                        'Nada notifikasi juga bisa diganti di pengaturan '
                        'notifikasi HP → kanal "Reminder Sholat".',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                ),
                GhinaSpace.gapXl,
                const SectionHeader(
                  title: 'Izin & baterai',
                  subtitle: 'Biar pengingat nggak telat atau hilang',
                ),
                _PermissionsCard(
                  android: android,
                  onAskNotifications: _ensurePermission,
                  onAskExact: _askExactAlarms,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- location

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.location,
    required this.locating,
    required this.onPickCity,
    required this.onUseGps,
  });

  final PrayerLocation location;
  final bool locating;
  final VoidCallback onPickCity;
  final VoidCallback onUseGps;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final at = location.updatedAt;
    return ChunkyCard(
      key: const ValueKey('prayer-location'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(
                icon: location.isGps
                    ? Icons.my_location_rounded
                    : Icons.location_city_rounded,
                color: GhinaColors.blue.base,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.name,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    Text(
                      location.isGps
                          ? 'GPS · diperbarui tiap buka app'
                                '${at == null ? '' : ' · ${Fmt.relativeDay(at)} ${Fmt.time(at)}'}'
                          : 'Kota pilihan',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                    Text(
                      '${location.lat.toStringAsFixed(4)}, '
                      '${location.lng.toStringAsFixed(4)}',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          GhinaSpace.gapMd,
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('prayer-pick-city'),
                  label: 'Pilih kota',
                  icon: Icons.location_city_rounded,
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  uppercase: false,
                  onPressed: onPickCity,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('prayer-use-gps'),
                  label: 'Pakai lokasi GPS',
                  icon: Icons.my_location_rounded,
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.secondary,
                  uppercase: false,
                  loading: locating,
                  onPressed: locating ? null : onUseGps,
                ),
              ),
            ],
          ),
          if (location.isGps) ...[
            GhinaSpace.gapSm,
            Text(
              'Pindah kota lebih dari 20 km? Jadwal & pengingat menyesuaikan '
              'otomatis saat kamu buka Ghina. Kalau GPS gagal, dipakai lokasi '
              'terakhir.',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CityPicker extends StatefulWidget {
  const _CityPicker({required this.selected});

  final PrayerLocation selected;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final q = _q.trim().toLowerCase();
    final cities = [
      for (final c in indonesianPrayerCities)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.province.toLowerCase().contains(q))
          c,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          ChunkyTextField(
            key: const ValueKey('city-search'),
            hint: 'Cari kota atau provinsi',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) => setState(() => _q = v),
          ),
          GhinaSpace.gapMd,
          Expanded(
            child: cities.isEmpty
                ? Center(
                    child: Text(
                      'Kotanya belum ada di daftar. Coba "Pakai lokasi GPS".',
                      textAlign: TextAlign.center,
                      style: GhinaType.body.copyWith(color: g.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: cities.length,
                    itemBuilder: (_, i) {
                      final c = cities[i];
                      final sel =
                          !widget.selected.isGps &&
                          widget.selected.name == c.name;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ChunkyTile(
                          key: ValueKey('city-${c.name}'),
                          title: c.name,
                          subtitle: c.province,
                          dense: true,
                          tinted: sel ? GhinaColors.green : null,
                          trailing: sel
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: GhinaColors.green.base,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(c),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- per prayer

class _SlotCard extends ConsumerWidget {
  const _SlotCard({
    required this.prayer,
    required this.slot,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
  });

  final Prayer prayer;
  final PrayerSlotSettings slot;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<PrayerSlotSettings> onChanged;

  String _summary(DateTime? time) {
    if (!slot.enabled) return 'Mati';
    final parts = <String>[
      if (time != null) 'Adzan ${Fmt.time(time)}',
      if (slot.preEnabled) '${slot.preMinutes} mnt sebelum',
      if (slot.followUpEnabled)
        'susulan ${slot.followUpMax}× tiap ${slot.followUpInterval} mnt'
      else
        'tanpa susulan',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final style = prayerStyles[prayer]!;
    final today = startOfDay(ref.watch(clockProvider).now());
    final time = ref.watch(prayerTimesProvider(today))?[prayer];
    return ChunkyCard(
      key: ValueKey('prayer-slot-${prayer.wire}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyTile(
            framed: false,
            title: prayer.label,
            subtitle: _summary(time),
            leading: CategoryAvatar(
              icon: style.icon,
              color: style.color.base,
              size: 40,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  key: ValueKey('prayer-slot-on-${prayer.wire}'),
                  value: slot.enabled,
                  onChanged: (v) => onChanged(slot.copyWith(enabled: v)),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: g.textMuted,
                ),
              ],
            ),
            onTap: onToggleExpanded,
          ),
          AnimatedSize(
            duration: GhinaMotion.medium,
            curve: GhinaMotion.standard,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _SlotOptions(
                      prayer: prayer,
                      slot: slot,
                      time: time,
                      onChanged: onChanged,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SlotOptions extends StatelessWidget {
  const _SlotOptions({
    required this.prayer,
    required this.slot,
    required this.time,
    required this.onChanged,
  });

  final Prayer prayer;
  final PrayerSlotSettings slot;
  final DateTime? time;
  final ValueChanged<PrayerSlotSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final w = prayer.wire;
    Widget switchRow(
      String key,
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> f,
    ) => Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: ValueKey(key),
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: slot.enabled ? f : null,
        title: Text(title, style: GhinaType.body.w(800)),
        subtitle: Text(
          subtitle,
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      ),
    );

    Widget chips(
      String key,
      List<int> options,
      int value,
      String suffix,
      ValueChanged<int> f,
    ) => ChunkyChoiceChips<int>(
      key: ValueKey(key),
      scrollable: true,
      options: [
        for (final m in {...options, value}.toList()..sort())
          ChunkyChoice(value: m, label: '$m $suffix'),
      ],
      selected: {value},
      onChanged: (s) => f(s.first),
    );

    final corrected = time;
    return Opacity(
      opacity: slot.enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switchRow(
            'slot-pre-$w',
            'Pengingat sebelum waktu',
            slot.preEnabled
                ? '"${slot.preMinutes} menit lagi ${prayer.label}, siap-siap wudhu"'
                : 'Mati',
            slot.preEnabled,
            (v) => onChanged(slot.copyWith(preEnabled: v)),
          ),
          if (slot.preEnabled)
            chips(
              'slot-pre-min-$w',
              PrayerSlotSettings.preMinuteOptions,
              slot.preMinutes,
              'mnt',
              (m) => onChanged(slot.copyWith(preMinutes: m)),
            ),
          const SizedBox(height: 8),
          switchRow(
            'slot-fu-$w',
            'Pengingat susulan',
            slot.followUpEnabled
                ? 'Diingatkan lagi sampai dicentang atau waktu berikutnya masuk'
                : 'Mati',
            slot.followUpEnabled,
            (v) => onChanged(slot.copyWith(followUpEnabled: v)),
          ),
          if (slot.followUpEnabled) ...[
            const FieldLabel('Susulan pertama setelah adzan'),
            chips(
              'slot-fu-delay-$w',
              PrayerSlotSettings.delayOptions,
              slot.followUpDelay,
              'mnt',
              (m) => onChanged(slot.copyWith(followUpDelay: m)),
            ),
            const SizedBox(height: 10),
            const FieldLabel('Ulangi tiap'),
            chips(
              'slot-fu-every-$w',
              PrayerSlotSettings.intervalOptions,
              slot.followUpInterval,
              'mnt',
              (m) => onChanged(slot.copyWith(followUpInterval: m)),
            ),
            const SizedBox(height: 10),
            _StepperRow(
              key: ValueKey('slot-fu-max-$w'),
              label: 'Maksimal susulan',
              value: slot.followUpMax,
              min: 1,
              max: PrayerSlotSettings.maxFollowUps,
              format: (v) => '$v×',
              onChanged: (v) => onChanged(slot.copyWith(followUpMax: v)),
            ),
          ],
          const SizedBox(height: 10),
          _StepperRow(
            key: ValueKey('slot-offset-$w'),
            label: 'Koreksi waktu',
            hint: corrected == null
                ? 'Samakan dengan jadwal masjid dekatmu'
                : 'Jadi ${Fmt.time(corrected)} hari ini',
            value: slot.offsetMinutes,
            min: PrayerSlotSettings.minOffset,
            max: PrayerSlotSettings.maxOffset,
            format: (v) => v == 0 ? '0 mnt' : '${v > 0 ? '+' : ''}$v mnt',
            onChanged: (v) => onChanged(slot.copyWith(offsetMinutes: v)),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final int value;
  final int min;
  final int max;
  final String Function(int) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
            ],
          ),
        ),
        ChunkyIconButton(
          icon: Icons.remove_rounded,
          size: 36,
          tooltip: 'Kurangi',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 64,
          child: Text(
            format(value),
            textAlign: TextAlign.center,
            style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
          ),
        ),
        ChunkyIconButton(
          icon: Icons.add_rounded,
          size: 36,
          tooltip: 'Tambah',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- permissions

class _PermissionsCard extends ConsumerWidget {
  const _PermissionsCard({
    required this.android,
    required this.onAskNotifications,
    required this.onAskExact,
  });

  final bool android;
  final Future<bool> Function() onAskNotifications;
  final Future<void> Function() onAskExact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final perm = ref.watch(notificationPermissionProvider).value;
    final battery = ref.watch(_batteryExemptProvider).value;
    final unsupported = perm == null || perm.status.name == 'unsupported';

    Widget row({
      required Key key,
      required bool ok,
      required String title,
      required String explain,
      String? action,
      VoidCallback? onAction,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: ok ? GhinaColors.green.base : GhinaColors.orange.base,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                Text(
                  explain,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                if (action != null) ...[
                  const SizedBox(height: 6),
                  ChunkyButton(
                    label: action,
                    size: ChunkyButtonSize.small,
                    variant: ok
                        ? ChunkyButtonVariant.outline
                        : ChunkyButtonVariant.primary,
                    uppercase: false,
                    onPressed: onAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unsupported)
            Text(
              'Notifikasi terjadwal cuma jalan di aplikasi Android / iOS.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            )
          else ...[
            row(
              key: const ValueKey('perm-notifications'),
              ok: perm.granted,
              title: perm.granted
                  ? 'Izin notifikasi aktif'
                  : 'Izin notifikasi belum ada',
              explain: 'Tanpa ini, adzan & pengingat nggak bisa muncul.',
              action: perm.granted ? null : 'Izinkan notifikasi',
              onAction: perm.granted ? null : () => onAskNotifications(),
            ),
            if (android)
              row(
                key: const ValueKey('perm-exact'),
                ok: perm.exactAlarms,
                title: perm.exactAlarms
                    ? 'Alarm tepat waktu aktif'
                    : 'Alarm tepat waktu belum diizinkan',
                explain:
                    'Izin "Alarm & pengingat" bikin adzan bunyi pas di menitnya. '
                    'Tanpa izin ini, Android bisa menundanya beberapa menit.',
                action: perm.exactAlarms ? 'Cek izin' : 'Izinkan alarm',
                onAction: () => onAskExact(),
              ),
          ],
          if (android) ...[
            row(
              key: const ValueKey('perm-battery'),
              ok: battery ?? false,
              title: battery == true
                  ? 'Ghina bebas dari hemat baterai'
                  : 'Ghina masih dibatasi hemat baterai',
              explain:
                  'Mode hemat baterai bisa menahan pengingat saat HP lama '
                  'nggak disentuh. Pilih Ghina → "Jangan optimalkan" / '
                  '"Tanpa batasan".',
              action: 'Buka pengaturan baterai',
              onAction: () => ref.read(batteryOptimizationProvider).request(),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    'Pengingat suka telat? 🔋',
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                  subtitle: Text(
                    'Tips untuk HP Infinix, Tecno, Xiaomi & lainnya',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                  children: const [BatteryTipList()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
