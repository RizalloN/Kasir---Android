# ☕ Warloc POS & Business Management (Android)

Aplikasi Kasir (Point of Sale) modern, responsif, dan adaptif berbasis **Flutter** dengan arsitektur **Offline-First**, **Keystore-Encrypted Storage**, **Role-Based Access Control (RBAC)**, serta integrasi **Real-Time Cloud Sync Firebase**.

---

## 🌟 Fitur Utama

### 1. 🛡️ Multi-Tier Role-Based Access Control (RBAC)
- **Kasir / Barista (`warloc.kasir`)**:
  - Transaksi kasir cepat, katalog menu & pencarian produk/hiburan.
  - Fitur **Open Bill (Simpan Tagihan)** & Resume Tagihan pelanggan.
  - Mode pembayaran **Tunai (Cash)** dan **QRIS**.
  - Cetak struk termal ESC/POS 58mm via Bluetooth/USB & preview receipt digital.
- **Admin (`warloc.admin`)**:
  - Seluruh kapabilitas kasir.
  - Manajemen inventori & stok barang, penyesuaian harga jual & HPP.
  - Fitur Batch Import produk menu baru.
- **Owner (`warloc.owner`)**:
  - Akses penuh ke seluruh fitur kasir dan manajemen.
  - **Executive Dashboard & Analytics**:
    - Ringkasan omset harian, laba kotor, laba bersih (setelah beban operasional).
    - Komparasi analitik **MTD (Month-to-Date)** dan **MTM (Month-to-Month)**.
    - Grafik interaktif: Timeseries tren penjualan, Donut chart komposisi kategori, dan Bar chart pendapatan.
  - **Pengeluaran Operasional (OPEX)**:
    - Pencatatan dan monitoring biaya listrik, air, kantong plastik, sedotan, ATK, dan lain-lain.
    - Batch input pengeluaran operasional.
  - **Kelola Profil & Pengguna**:
    - Tambah, nonaktifkan, dan ubah role pengguna.
    - Manajemen keamanan password berbasis salted PBKDF2 hash.

### 2. 📱 UI/UX Adaptif (Phone, Tablet, Desktop)
- Tata letak responsif untuk berbagai ukuran layar (layar HP, tablet kasir, maupun mode foldable).
- Navigasi tab adaptif (Sidebar pada tablet/desktop, Navigation Bar pada HP).

### 3. 🔄 Arsitektur Offline-First & Keamanan Data
- **Offline Resilience**: Kasir dapat tetap beroperasi memproses transaksi saat internet terputus. Data tersimpan aman di database lokal.
- **Cloud Auto-Sync**: Transaksi tersinkronisasi otomatis saat koneksi internet kembali aktif.
- **Enkripsi Lokal**: Kredensial dan data sensitif dilindungi dengan Android Keystore (`SecurePreferences`).
- **Data Protection**: Konfigurasi sensitif (Firebase credentials, keystores) diisolasi dan diabaikan dari version control.

---

## 📂 Struktur Proyek

```
lib/
├── main.dart                                # Entry point aplikasi & inisialisasi layanan
├── models/
│   ├── user_role.dart                       # Role: Kasir, Admin, Owner
│   ├── user_profile.dart                    # Profil pengguna & hashing PBKDF2
│   ├── product.dart                         # Model produk, HPP, stok & kategori
│   ├── cart_item.dart                       # Item keranjang transaksi
│   ├── open_bill.dart                       # Model Open Bill (tagihan tersimpan)
│   ├── operational_expense.dart             # Model biaya operasional (listrik, air, dsb.)
│   └── transaction.dart                     # Model transaksi kasir & status sinkronisasi
├── providers/
│   └── pos_provider.dart                    # Central State Management & Business Logic
├── services/
│   ├── pos_database_service.dart            # Storage lokal & sinkronisasi Firestore
│   ├── secure_preferences.dart              # Enkripsi preferensi berbasis Keystore
│   ├── thermal_printer_service.dart         # Integrasi printer termal Bluetooth/USB
│   └── app_release_service.dart             # Cek versi & pembaruan rilis APK
├── screens/
│   ├── main_wrapper_screen.dart             # Shell navigasi utama & status koneksi
│   ├── auth/                                # Layanan autentikasi login & ganti password
│   ├── barista/                             # Layanan kasir, keranjang, dan struk
│   ├── owner/                               # Dashboard analitik, stok, laporan, OPEX & users
│   └── dialogs/                             # Dialog modal (batch insert, printer, update, dll.)
├── theme/
│   └── app_theme.dart                       # Tema visual Warm Espresso & Slate Dark
├── utils/
│   └── currency_formatter.dart              # Format Rupiah & tanggal lokal
└── widgets/                                 # Komponen UI (Charts, Logo, Access Denied, dll.)
```

---

## 🚀 Setup & Panduan Menjalankan

### 1. Konfigurasi Firebase (`google-services.json`)
Demi keamanan, file kredensial Firebase asli tidak disertakan dalam repositori.

1. Salin template konfigurasi:
   ```powershell
   copy android\app\google-services.json.example android\app\google-services.json
   ```
2. Buka `android\app\google-services.json` dan ganti nilai placeholder dengan konfigurasi Firebase project Anda dari [Firebase Console](https://console.firebase.google.com/).

### 2. Mengambil Dependensi
```powershell
flutter pub get
```

### 3. Menjalankan Pengujian (Testing)
```powershell
flutter test
```

### 4. Menjalankan Aplikasi
```powershell
flutter run
```

### 5. Meng-compile ke File `.apk` (Release)
```powershell
flutter build apk --release
```
Hasil file APK release berada di:
`build/app/outputs/flutter-apk/app-release.apk`
