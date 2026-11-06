# Hasil perubahan dan validasi

## Ringkasan

- Tampilan mengikuti ruang jendela dan skala teks, toolbar ponsel memakai menu
  kompak, katalog menghitung kolom secara dinamis, dan halaman yang panjang dapat
  digulir. Panel keranjang berdampingan memerlukan ruang yang cukup.
- Engsel penghalang dan postur setengah terlipat dihindari melalui sub-screen
  Flutter. Perubahan ukuran mempertahankan keranjang dalam provider.
- Checkout menolak keranjang kosong, nominal tidak valid/kurang bayar, serta
  pembayaran bersamaan. Lifecycle halaman pembayaran ditangani setelah operasi
  async. ID invoice memakai microsecond, menghindari pengulangan suffix lama
  setiap 100 detik.
- Listener pengguna tidak lagi menulis ulang akun bawaan yang sudah ada. Password
  remote yang diganti owner dipertahankan. Snapshot cache/pending-write tidak
  memicu seeding akun. Loop sebelumnya menghasilkan kehabisan thread di emulator.
- Login dan checkout menyimpan data lokal sebelum menunggu cloud. Checkout
  mengirim perubahan stok dan transaksi melalui batch di belakang; status pending
  write tidak dianggap sebagai pengakuan server.
- Cache foto Base64 memakai string penuh sebagai key dan dibatasi 8 MiB untuk
  byte hasil decoding, sehingga tidak bergantung pada collision hashCode.
- Pemeriksaan versi, banner rilis, menu unduh APK HTTPS, dan kontrol tiga fitur
  tersedia melalui `app_config/android`. Ikuti `UPDATE_APK.md` untuk aktivasi.
- Kamera/Bluetooth/lokasi menjadi hardware opsional. Permission Bluetooth Android
  12+ diminta sebelum membaca adapter pada pengaturan printer.

## File yang diubah/ditambahkan

| File | Perubahan |
| --- | --- |
| `lib/main.dart` | Provider rilis, konfigurasi awal Firestore, sub-screen foldable |
| `lib/providers/pos_provider.dart` | Validasi/pengaman checkout dan ID invoice |
| `lib/services/pos_database_service.dart` | Loop snapshot akun, persistensi login/checkout, pengakuan sinkronisasi |
| `lib/services/app_release_service.dart` | Baru: metadata rilis, fitur, pemeriksaan versi, jembatan Android |
| `lib/screens/main_wrapper_screen.dart` | Toolbar kompak, banner dan akses updater, safe area |
| `lib/screens/barista/pos_screen.dart` | Grid adaptif, breakpoint panel, keyboard/modal, fitur barcode |
| `lib/screens/barista/cart_bottom_sheet.dart` | Satu area scroll, teks membungkus, pengaman pembayaran/lifecycle |
| `lib/screens/barista/receipt_dialog.dart` | Kontrol fitur pencetakan |
| `lib/screens/dialogs/app_update_dialog.dart` | Baru: dialog rilis/unduh/error |
| `lib/screens/dialogs/printer_settings_dialog.dart` | Permission sebelum adapter, header adaptif, kontrol fitur |
| `lib/screens/owner/owner_dashboard_screen.dart` | Header dan panel membungkus pada layar sempit |
| `lib/screens/owner/stock_management_screen.dart` | Header dan scroll inventori |
| `lib/screens/owner/operational_expenses_screen.dart` | Scroll halaman dan kategori dengan teks besar |
| `lib/screens/owner/reports_screen.dart` | Teks tautan audit membungkus |
| `lib/widgets/analytics_charts.dart` | Header grafik dan tinggi empty-state adaptif |
| `lib/widgets/product_image_widget.dart` | Batas cache dan kontrol fitur gambar |
| `android/app/src/main/AndroidManifest.xml` | Hardware opsional dan aktivitas dapat di-resize |
| `android/app/src/main/kotlin/com/kafekita/pos/MainActivity.kt` | Baca versi terpasang dan buka URL HTTPS di browser |
| `test/adaptive_release_test.dart` | Baru: 26 tes regresi tambahan |
| `UPDATE_APK.md` | Baru: publikasi rilis, aturan metadata, kontrol fitur, signing |
| `VALIDATION.md` | Baru: catatan ini |

Dependensi, `pubspec.yaml`, `pubspec.lock`, dan `analysis_options.yaml` tidak diubah.
Workspace tidak mempunyai repository Git; perubahan diperiksa terhadap salinan
awal file. Tidak ada reset, stash, clean, atau penghapusan sumber pengguna.

## Validasi yang dijalankan dan hasil

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --reporter expanded`: **35 tes lulus**, mencakup 9 tes
  awal dan 26 tes tambahan. Log: `build/flutter-test-validation.log`.
- Ukuran widget: 320x568, 360x800, 800x360, 600x960, 1280x800 untuk kasir,
  admin, owner; engsel vertikal 1350x900; tabletop 900x1200; skala teks 1.5;
  keyboard; perubahan ukuran dan semua tab owner.
- `flutter build apk --release --no-pub --build-name=1.1.0 --build-number=2`:
  **berhasil**. Log: `build/apk-build-validation.log`.
- Emulator Android API 37 x86_64 dijalankan tanpa jendela, tanpa snapshot/save,
  read-only, dengan Wi-Fi/data dimatikan. APK dipasang memakai `adb install -r`;
  pemasangan dari build 1 ke build 2 berhasil.
- Pada APK final: login lokal berhasil, satu produk ditambahkan, checkout offline
  menghasilkan struk, aplikasi ditutup paksa dan dibuka kembali. Sesi kasir tetap
  aktif, stok produk tersimpan berubah dari 43 menjadi 42. Dialog updater membaca
  **Terpasang: 1.1.0 (2)** melalui kode native.
- Screenshot updater offline: `build/warloc-final.png`. Pesan gagal memeriksa
  pembaruan saat jaringan dimatikan merupakan hasil yang diharapkan.

## APK hasil build

- Lokasi: `build/app/outputs/flutter-apk/app-release.apk`
- Versi: `1.1.0+2`; application ID: `com.kafekita.pos`
- Minimum Android 7.0/API 24, target API 36
- ABI: armeabi-v7a, arm64-v8a, x86_64
- Ukuran: 58,926,689 byte
- SHA-256: `9FC7D56C4652BA57DBF4BE44294BF333295E5DEFBCE1971AF0A3E87E8A4B00D9`

## Risiko dan bagian yang belum tervalidasi

- Metadata rilis, URL hosting APK, dan security rules Firebase belum diterbitkan
  ke server. Unduh lalu instal dari hosting produksi dan penerapan kontrol fitur
  melalui Firestore online belum diuji end-to-end. Pengujian dilakukan offline
  agar tidak mengubah data cloud operasional.
- Build release masih memakai debug signing bawaan proyek. Signing produksi dan
  kesinambungan kunci dengan APK yang sudah tersebar perlu ditetapkan sebelum
  distribusi operasional. Jangan uninstall untuk mengatasi signature berbeda.
- Tablet/foldable fisik, Android API 24 pada perangkat nyata, variasi vendor,
  kamera, printer Bluetooth fisik, serta penolakan permission Bluetooth belum
  diverifikasi. Pengujian foldable/tablet saat ini memakai widget simulation.
- Pengujian offline native berfokus pada login, checkout, restart, dan updater.
  Sinkronisasi online antarperangkat, konflik stok bersamaan, dan seluruh operasi
  administrasi offline belum divalidasi melalui server/perangkat nyata.
- Build memberi peringatan kompatibilitas KGP pada plugin `firebase_core` untuk
  Flutter mendatang; build saat ini berhasil. Dependensi tidak dinaikkan.
