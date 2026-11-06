# Pembaruan APK dan kontrol fitur Warloc

Aplikasi memeriksa rilis saat dibuka, ketika kembali aktif, dan melalui menu
**Pembaruan Aplikasi**. Jika ada versi lebih baru, banner tampil setelah login.
Unduhan dibuka di browser. Pengguna membuka APK hasil unduhan dan menyetujui
pembaruan melalui Android. Tidak ada pemasangan diam-diam.

## Mengaktifkan pembaruan

1. Gunakan proyek Firebase yang sama dengan `android/app/google-services.json`.
2. Di Firestore, buat collection `app_config`, document `android`.
3. Tambahkan field berikut dengan tipe yang sesuai. JSON di bawah adalah contoh;
   ganti URL dengan lokasi APK HTTPS milik Anda yang benar-benar sudah diunggah.

```json
{
  "versionCode": 2,
  "versionName": "1.1.0",
  "downloadUrl": "https://domain-anda.example/releases/warloc-1.1.0.apk",
  "notes": "Perbaikan bug dan tampilan adaptif.",
  "features": {
    "barcode_lookup": true,
    "product_images": true,
    "thermal_printer": true
  }
}
```

`versionCode` harus integer positif dan lebih tinggi dari APK yang terpasang.
`versionName` adalah teks untuk pengguna. `features` adalah map dengan nilai
boolean, bukan string `"true"`/`"false"`. URL HTTP, file lokal, URL dengan
username/password, atau fragment ditolak. Konfigurasi tidak valid mempertahankan
pengaturan terakhir. Dokumen yang dihapus mengembalikan default semua fitur aktif.

Gunakan tautan HTTPS yang dapat diakses browser perangkat, tanpa login Firebase
khusus aplikasi. Unggah APK dahulu, uji tautannya, baru terbitkan metadata rilis.
Jangan gunakan contoh URL di atas sebagai URL produksi.

## Kontrol fitur tanpa merilis APK

Ubah nilai `features` di Firebase Console:

| Field | Pengaruh ketika `false` |
| --- | --- |
| `barcode_lookup` | Menyembunyikan input barcode/SKU cepat di katalog |
| `product_images` | Menggunakan placeholder gambar produk, tanpa menghapus foto |
| `thermal_printer` | Menonaktifkan akses pengaturan, koneksi, dan pencetakan thermal |

Perubahan diterapkan lewat listener Firestore. Ketika offline, cache Firestore
Android tetap dapat menyediakan konfigurasi sebelumnya; perubahan baru memerlukan
koneksi. Instalasi pertama tanpa konfigurasi menggunakan semua fitur aktif.
Pemeriksaan versi yang gagal tidak menghalangi kasir. Tombol **Periksa Lagi**
menampilkan kegagalan koneksi/konfigurasi dan dapat dicoba kembali.

Switch ini mengendalikan fitur yang kodenya sudah ada di APK. Fitur dengan kode
baru tetap memerlukan APK baru. Switch bukan pengganti hak akses pengguna.

## Hak akses metadata rilis

Dokumen rilis berisi metadata publik, bukan rahasia. Aplikasi hanya membaca;
publikasi rilis dan perubahan fitur dilakukan administrator melalui Firebase
Console atau backend tepercaya. Contoh rule khusus dokumen ini:

```text
match /app_config/android {
  allow read: if true;
  allow write: if false;
}
```

Gabungkan dengan aturan proyek yang sudah ada. Rule wildcard lain yang mengizinkan
semua write tetap dapat mengizinkan perubahan metadata: penolakan spesifik tidak
membatalkan izin rule lain. Pastikan tidak ada rule luas yang membolehkan client
menulis `app_config`. Login peran lokal Warloc bukan Firebase Authentication.
Aturan cloud tidak diubah/deploy otomatis oleh perubahan kode ini.

## Menerbitkan versi berikutnya

```powershell
flutter analyze
flutter test
flutter build apk --release --build-name=1.1.0 --build-number=2
```

Naikkan `--build-number` pada setiap rilis berikutnya; samakan dengan `versionCode`
di Firestore. APK universal pada `build/app/outputs/flutter-apk/app-release.apk`
memuat ABI armv7, arm64, dan x86_64. APK yang diverifikasi saat perubahan ini memakai
minimum Android 7.0/API 24 dan target API 36. Minimum SDK perlu diperiksa kembali
setelah pembaruan plugin karena plugin juga dapat membatasi versi Android.

Pertahankan application ID `com.kafekita.pos` dan kunci penandatanganan yang sama
dengan instalasi lama. Android menolak pembaruan dengan signature yang berbeda.
**Konfigurasi proyek saat ini masih memakai debug signing untuk build release.**
Simpan kunci yang dipakai instalasi sekarang dan tetapkan signing produksi sebelum
distribusi produksi. Perubahan ini tidak membuat/mengganti keystore secara otomatis.
Mengganti kunci tanpa jalur migrasi dapat membuat APK tidak dapat memperbarui
instalasi lama. Jangan menyuruh kasir uninstall untuk mengatasi signature berbeda:
uninstall dapat menghapus transaksi lokal yang belum tersinkron.

APK lama yang belum memiliki pemeriksa pembaruan memerlukan satu pemasangan manual
ke versi yang memuat fitur ini. Setelah itu rilis selanjutnya dapat ditemukan lewat
banner/menu pembaruan.

## Tampilan dan verifikasi perangkat

Toolbar kompak menggunakan menu overflow. Katalog menghitung kolom dari ruang
tersedia dan skala teks. Panel keranjang berdampingan muncul jika lebar dan tinggi
mencukupi; jendela sempit memakai keranjang modal. Checkout menggunakan satu area
scroll agar kontrol tetap dapat dijangkau pada keyboard dan landscape.

`DisplayFeatureSubScreen` menempatkan aplikasi di area layar yang tidak melintasi
engsel penghalang atau lipatan setengah terbuka. Pada postur tersebut aplikasi
memakai satu sisi yang aman; ini belum merupakan workspace dua layar terpisah.
Foldable terbuka tanpa penghalang menggunakan seluruh ruang layar yang tersedia.
Kamera, Bluetooth, dan lokasi ditandai sebagai hardware opsional. Kemampuan cetak
tetap memerlukan Bluetooth dan printer yang kompatibel; izin Android 12+ diminta
sebelum membaca adapter Bluetooth.

Tes widget mencakup beberapa ukuran smartphone/tablet, tiga peran, engsel vertikal
dan horizontal, perubahan ukuran, teks besar, keyboard, checkout bersamaan, serta
metadata/tautan pembaruan. Pengujian perangkat fisik dan instalasi upgrade dari
APK yang diterbitkan server tetap perlu dilakukan sebelum rilis operasional.

Perbaikan sinkronisasi pengguna juga mencegah listener menulis ulang akun bawaan
setiap snapshot. Hanya akun yang belum ada berdasarkan ID dan username yang
diusulkan untuk dibuat. Snapshot cache/pending-write tidak memicu pembuatan akun;
kredensial akun remote yang sudah ada dipertahankan. Ini mengatasi loop write
yang menyebabkan kehabisan thread pada pengujian Android offline.
Login menyimpan perubahan pengguna dan sesi secara lokal tanpa menunggu balasan
cloud. Checkout juga menyimpan transaksi dan stok lokal lebih dahulu; batch
sinkronisasi cloud berjalan di belakang. Transaksi tetap berstatus tertunda sampai
ada pengakuan server, dan kegagalan sinkronisasi tidak membatalkan bukti lokal.

Acuan: [Flutter adaptive UI](https://docs.flutter.dev/ui/adaptive-responsive),
[display features](https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html),
[Android app signing](https://source.android.com/docs/security/features/apksigning),
[Firestore offline cache](https://firebase.google.com/docs/firestore/manage-data/enable-offline),
dan [overlapping security rules](https://firebase.google.com/docs/rules/rules-behavior).
