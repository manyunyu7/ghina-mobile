# Unduhan pratinjau Ravel

Versi 1.11.2 (47) menambahkan tombol **Unduh asli**, **Unduh semua**, dan
halaman **Unduhan** di detail/feed/fullscreen, menu kartu chat, serta pengaturan
kompleks. Halaman menampilkan progres byte/persen, antrean, menunggu koneksi,
selesai/gagal, filter status, batal/coba lagi, serta buka dan bagikan berkas.
Tombol Simpan yang lama tetap berarti bookmark pratinjau, bukan unduh.

Versi 1.11.3 (48) membuat akses ini terlihat langsung: tombol unduh di kartu
feed/tab agen dan bubble chat, panel **Unduhan** di atas tab Pratinjau kantor
dan agen, serta bar progres/persen/byte saat transfer aktif. Panel tetap ada
ketika feed kosong atau server gagal dimuat. Ketuk **Lihat semua** untuk riwayat,
batal/coba lagi, buka dan bagikan. Progres diperbarui juga setelah app kembali
dari background, dan timer tampilan dihentikan saat app tidak aktif.

Tes tab kantor dan tab agen memeriksa bar progres tanpa membuka detail, termasuk
layar sempit dengan teks diperbesar. Probe `tool/kantor_preview_download_probe.dart`
memakai tab agen sebenarnya dan fixture lokal untuk verifikasi visual Android.
Uji Android 15 menunjukkan progres 1% lalu 15% langsung di tab setelah tombol
**Unduh asli** pada kartu ditekan. Seluruh 401 tes Ravel/Kantor lulus (1 skip).

Transfer menggunakan Android DownloadManager, terpisah dari proses Flutter.
Menutup halaman/aplikasi tidak membatalkan transfer. Daftar ID dan metadata
bertahan ketika proses aplikasi mati dan tidak bergantung pada kompleks aktif.
Unduhan aktif dengan URL yang sama tidak dibuat ganda. Nama tujuan unik sehingga
unduhan baru tidak menimpa berkas yang sudah selesai.

Android 10+ menyimpan di `Download/Ravel`; versi lama memakai direktori unduhan
aplikasi tanpa meminta izin penyimpanan luas. Lokasi ditampilkan di tiap hasil.
Android menangani koneksi ulang dan notifikasi progres/selesai. Roaming dimatikan;
data seluler biasa boleh dipakai. Tidak menambah foreground service aplikasi.
Ini tidak menjanjikan transfer ketika perangkat mati atau Download Manager
dinonaktifkan. Batal menghapus transfer parsial; hasil selesai tidak memiliki
aksi hapus di dalam Ravel.

URL berasal dari berkas asli pratinjau (`/pv/...`), bukan thumbnail atau rendition
video. Host harus sama dengan kompleks aktif dan tidak boleh berisi user-info.
Link bertanda tangan diteruskan tanpa header bearer atau token akun. Bridge tidak
mengembalikan URL ke daftar UI dan tidak mencetaknya pada pesan galat. FileProvider
tidak diekspor dan hanya memberi izin baca sementara ke berkas hasil unduhan,
dengan nama asli saat dibagikan. HTTP diizinkan pada flavor Ravel untuk daemon
LAN/tailnet yang dikonfigurasi pemilik.

Unduh semua membuat transfer terpisah untuk setiap berkas yang tercantum.
HTML diunduh sebagai berkas asli; ini bukan ekspor ZIP situs offline beserta
seluruh aset. iOS tidak ditargetkan oleh bridge Android ini dan mendapat pesan
bahwa fitur memerlukan aplikasi Android terbaru.

Implementasi mengikuti [kontrak DownloadManager Android](https://developer.android.com/reference/android/app/DownloadManager)
dan [pengaturan tujuan/notifikasi Request](https://developer.android.com/reference/android/app/DownloadManager.Request).

## Pengujian

Tes unit/widget memeriksa validasi alamat tanpa bearer, ukuran tidak diketahui,
progres/status galat, buka ulang daftar, batal/retry/open/share, keadaan kosong
dan bridge gagal, serta unduh semua dan penolakan host asing.

```sh
flutter test test/presentation/features/kantor/kantor_downloads_test.dart
flutter test test/app/ravel_app_test.dart test/presentation/features/kantor
```

Probe native harus berjalan pada emulator terisolasi, tanpa akun/data pemilik:

```sh
python3 -u tool/kantor_download_fixture.py
# di terminal lain, setelah emulator Android berjalan sebagai emulator-5554:
flutter build apk --debug --flavor ravel --target tool/kantor_download_probe.dart --target-platform android-arm64
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-ravel-debug.apk
python3 -u tool/kantor_download_e2e.py
```

Probe memakai fixture HTTP lambat 8 MiB dan 404 di `10.0.2.2:18376`. Ia memeriksa
batal, gagal/coba ulang dan deduplikasi. Skrip host mematikan proses Ravel ketika
byte pertama diterima dan mematikan layar. Seluruh hasil wajib cocok SHA256
fixture sementara proses Ravel tetap mati; setelah dibuka kembali, status lengkap
harus muncul. Run ID default `2` memerlukan emulator yang belum menjalankan probe
tersebut; jangan menghapus data perangkat pemilik untuk mengulang tes.

Hasil Android 15 Pixel 7a: seluruh tahap lulus, termasuk hash
`7d212b9c884f5c77896de960ae17cc341cda43b14d6a971f34ca29ebd4badf7f`.
Share sheet Android menampilkan nama asli `background-test-2.bin` melalui
FileProvider. Tidak menekan tujuan share eksternal.

## Rilis

```sh
flutter build apk --release --flavor ravel --target lib/main_ravel.dart --target-platform android-arm64
```

APK berada di `build/app/outputs/flutter-apk/app-ravel-release.apk`. Periksa versi,
package `com.henryaugusta.ravel`, sertifikat release, dan manifest sebelum dikirim.
Ponsel USB pemilik tidak dipasang atau diubah oleh pengujian emulator.
