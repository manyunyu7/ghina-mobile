# Ravel: Android khusus Kantor

Ravel dan Ghina memakai satu kode Kantor dan satu pohon route. Ravel tidak
memulai login Ghina, database keuangan, reminder sholat, Notification Listener,
watchdog atau exact alarm. Package aplikasi: `com.henryaugusta.ravel`.
Namespace Kotlin tetap `com.henryaugusta.ghina` agar bridge dikte dan widget
bisa digunakan bersama. Penyimpanan aplikasi terpisah; profil dan token Kantor
perlu diisi sendiri di Ravel, tidak disalin dari Ghina.

## Build

```sh
flutter build apk --flavor ravel --target lib/main_ravel.dart --release --target-platform android-arm64
flutter build apk --flavor ghina --target lib/main.dart --release --target-platform android-arm64
```

`default-flavor: ghina` menjaga perintah build Ghina tanpa `--flavor`.
Ravel harus memakai entry point `main_ravel.dart`. Kunci release tetap memakai
`android/key.properties` lokal, di luar Git. Verifikasi APK dengan
`apksigner verify --print-certs`; jangan membagikan kunci/password.
APK: `build/app/outputs/flutter-apk/app-ravel-release.apk`.

Versi 1.11.2 (47): unduhan pratinjau background, progres dan hasil tersimpan.
Lihat [alur unduhan dan pengujiannya](ravel-downloads.md).

## Manifest

Manifest hasil gabungan plugin berada di
`build/app/intermediates/merged_manifests/ravelRelease/processRavelReleaseManifest/AndroidManifest.xml`.
Izin akhir: INTERNET, ACCESS_NETWORK_STATE, POST_NOTIFICATIONS, RECORD_AUDIO,
FOREGROUND_SERVICE, FOREGROUND_SERVICE_DATA_SYNC, WAKE_LOCK, VIBRATE.
AndroidX menambahkan izin internal signature
`com.henryaugusta.ravel.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` untuk menjaga
receiver dinamis; ini bukan izin membaca data perangkat.

Flavor membuang lokasi, exact alarm, penyimpanan eksternal, biometrik,
Bluetooth, Notification Listener, watchdog, receiver alarm/boot dan WorkManager
short foreground service. Upload tetap memakai dataSync foreground service.
Dikte Ravel memakai mikrofon perangkat tanpa meminta akses Bluetooth.
Simpan ke galeri pada Android 9 ke bawah tidak didukung tanpa izin penyimpanan;
berbagi file melalui share sheet tetap tersedia.

## Notifikasi MVP

Keputusan kb1c085: Ravel tidak memakai endpoint backend Ghina
`/api/mobile/kantor/notices` yang membutuhkan login. Worktree
`buddget-kantor-notify` / `feat/kantor-notify-multi` sudah diperiksa dan tetap
memerlukan backend serta login tersebut.

Ravel menginisialisasi plugin sendiri untuk progres upload, lampiran dan izin
baru dari state Kantor yang segar saat aplikasi terbuka. Snapshot pertama hanya
menjadi patokan; inbox lama tidak diputar ulang. Ketukan hanya membuka halaman
Kantor untuk memuat data terkini, tidak menyetujui aksi. Target terikat alamat
kompleks; setelah ganti kompleks, notifikasi lama membuka beranda Kantor agar
tidak membuka kantor dengan ID sama di server lain. Tidak ada FCM/push saat app
ditutup. Widget menggunakan WorkManager minimal 15 menit (best effort Android)
dan refresh saat app dibuka. Setelah reboot, buka app lagi untuk memastikan
penjadwal widget aktif kembali.

## Verifikasi

```sh
flutter test test/app/ravel_app_test.dart test/presentation/features/kantor test/presentation/state/platform/dictation_controller_test.dart
flutter analyze --no-fatal-infos
```

Uji perangkat pemilik perlu koordinasi: instalasi berdampingan dengan Ghina,
profil Kantor, chat WA/Telegram, board, dikte, upload dengan layar mati,
notifikasi dan widget. Pengurangan izin tidak menjamin Play Protect tidak
memperingatkan; catat hasil pemasangan nyata tanpa menonaktifkan Play Protect.
