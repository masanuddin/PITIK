# Perubahan Aplikasi PITIK — Penyesuaian ke Kontrak Firmware v8.4

**Tanggal:** 30 September 2026
**Cakupan:** folder `lib/` dan `test/` aplikasi Flutter PITIK / SmartQuail
**Acuan:** kontrak data Firebase di `CLAUDE.md` §2 (firmware ESP32 v8.4, sudah diuji di hardware)

---

## 1. Ringkasan

Aplikasi sebelumnya membaca beberapa field Firebase yang sudah tidak dikirim firmware, memakai
angka ambang yang di-hardcode, dan menentukan status online dari field yang selalu `true`.
Semua bagian itu sudah disesuaikan dengan firmware v8.4, yang menjadi sumber kebenaran.

| Indikator | Sebelum | Sesudah |
|---|---|---|
| `flutter analyze` | 90 isu (1 warning) | **No issues found** |
| `flutter test` | 1 tes gagal | **93 tes lulus** |
| File yang mengakses Firebase RTDB | 5 file (tersebar di screen) | **1 file** (`services/pitik_repository.dart`) |
| Listener realtime | 5 listener di 3 screen | **1 listener per path** (`DeviceState`) |

Aturan kerja yang tetap dipatuhi:
- Nama path dan field Firebase tidak diubah, dan tidak ada field baru.
- App tidak menulis ke `/sensor_data`, `/history`, atau `/control_log`; yang ditulis hanya `/controls`.
- `firebase_options.dart` tidak disentuh.
- Tidak ada paket baru. State management memakai `ChangeNotifier` dan `ListenableBuilder` bawaan Flutter.

---

## 2. Perubahan yang terlihat oleh pengguna

### Dashboard
- **Amonia** ditampilkan sebagai nilai ADC mentah MQ-137 (0–4095) dengan label
  *"ADC · belum dikalibrasi"*. Alert dan ambang "ppm" dihapus karena firmware belum
  mengirim ppm. Sebelumnya nilai amonia selalu 0 karena field `ammonia` sudah tidak ada.
- **Status Online/Offline** dihitung dari umur `timestamp` perangkat: offline bila
  `timestamp == 0` atau data lebih lama dari 60 detik. Status diperbarui tiap 5 detik walau
  ESP32 mati. Saat offline muncul banner *"Perangkat offline"*, dan angka-angka diredupkan
  sebagai "data terakhir".
- **Sensor error:** bila `sensor_ok == false`, suhu, kelembaban, dan THI tampil `--`, disertai
  banner *"Sensor error (DHT22)"* dan gauge bertuliskan *"SENSOR ERROR"* (sebelumnya "0.0 NORMAL").
- **Status THI** memakai ambang dari `/controls` (default firmware 72/78), bukan angka hardcode.
  Gauge berskala 50–100.
- **Banner status** menampilkan relay aktual dan mode, misalnya
  *"THI ≥ 78 · Kipas OFF · Pompa OFF · mode manual"*. Sebelumnya banner menebak
  "Pendinginan Aktif" dari nilai THI.
- **Kartu Pakan (baru):** pakan terakhir beserta sumbernya (Jadwal / Nextion / Aplikasi) dan jadwal aktif.
- **Update terakhir** memakai jam perangkat dalam WIB, misalnya *"Update: 14:05:30 WIB · 12 detik lalu"*,
  bukan jam HP.

### Kontrol
- **Satu sumber kebenaran:** switch kipas, pompa, dan mode mengikuti `/controls` secara realtime.
  Perubahan dari Nextion atau ESP32 langsung terlihat. Setelah ESP32 restart, mode otomatis
  tampil **"Manual"** karena firmware menulis `auto_mode=false`.
- **Relay aktual** tampil terpisah di bawah tiap switch (*"Relay aktual: ON/OFF"*). Bila perintah
  belum dijalankan perangkat, muncul *"menunggu perangkat…"*.
- **Tombol dikunci** dan alasannya ditampilkan:

  | Tombol | Dikunci bila |
  |---|---|
  | Kipas, pompa, preset | perangkat offline · `relays_enabled == false` · mode otomatis (*"Dikendalikan otomatis"*) · tamu |
  | Beri Makan | perangkat offline (*"Perangkat offline"*) · `feeder_enabled == false` · `feed_now == true` (*"Menunggu perangkat…"*) · tamu |
  | Mode otomatis | perangkat offline · tamu |

- **Pakan tertinggal:** bila `feed_now` masih `true` saat perangkat offline, app menampilkan
  peringatan bahwa perintah itu tidak akan dijalankan saat perangkat tersambung lagi.
  App tidak pernah menulis `feed_now=false` sendiri.
- **Preset** (Semua OFF / Kipas Saja / Full Cool) menulis kipas dan pompa dalam satu update atomik.
- Semua teks berbahasa Indonesia ("Feeding triggered!" diganti "Perintah pakan dikirim ke perangkat").

### Riwayat
- Field amonia `a` diganti `mq137_raw`. Ada grafik baru *"Amonia (MQ-137)"* dalam satuan ADC.
- Tanggal dan jam memakai **WIB**, tidak lagi zona waktu HP (sebelumnya bisa salah hari
  di sekitar tengah malam bagi HP di luar WIB).
- Zona warna grafik THI mengikuti ambang di `/controls`.
- Ekspor CSV memakai kolom `date,time,ts,temperature,humidity,thi,mq137_raw,fan,pump`.
- Periode "1 Jam" dan "24 Jam" kini difilter berdasarkan waktu sebenarnya.

### Pengaturan
- **Ambang THI** dibaca dari dan ditulis ke `controls/thi_normal` + `controls/thi_danger`:
  - rentang 50–100, langkah 0,5;
  - validasi *normal < bahaya*;
  - tombol *"Simpan ke Perangkat"*, *"Reset ke Default (72/78)"*, dan *"Batal"*;
  - tidak lagi disimpan lokal (default lama 75/80 dihapus).
- **Jadwal Pakan (baru):** tiga slot dengan time picker 24 jam yang menulis `feed_hour1..3` / `feed_min1..3`.
- **Kartu Perangkat:** nilai hardcode ("ESP32-01", "Connected", "2 detik") diganti data asli, yaitu
  Device ID, Firmware, Jam Perangkat (*"--:-- (belum sinkron NTP)"* bila `hour/minute == -1`),
  Uptime, status koneksi server, dan interval 5 detik.
- Status online tidak lagi memakai field `online`, yang selalu `true`.

### Mode tamu (login anonim)
- Tamu **hanya bisa melihat**. Kontrol, ambang THI, dan jadwal pakan dikunci, disertai banner
  *"Mode tamu — hanya melihat"* dan tombol *"Masuk dengan No. HP"*.
- Logout dan pengaturan lokal (notifikasi, tema, bahasa) tetap bisa dipakai.

### Tombol "Sambungkan Ulang" (tambahan)
- Letak: banner *"Perangkat offline"* di Dashboard, baris status koneksi di Kontrol (saat
  offline), dan kartu Perangkat di Pengaturan (selalu ada). Tamu juga boleh memakainya
  karena tombol ini tidak menulis apa pun ke Firebase.
- Cara kerja:
  1. Koneksi app ke Firebase diputus lalu dibuka lagi (`goOffline` → `goOnline`).
  2. Semua langganan realtime dipasang ulang.
  3. App menunggu data segar dari ESP32 hingga 15 detik.
- Hasil ditampilkan lewat snackbar:

  | Hasil | Pesan | Artinya |
  |---|---|---|
  | ✅ | *"Tersambung — perangkat online."* | Semua normal |
  | ⚠️ | *"Server tersambung, tapi perangkat belum mengirim data. Periksa daya & WiFi ESP32."* | Masalah di sisi ESP32 |
  | ❌ | *"Gagal terhubung ke server. Periksa koneksi internet HP."* | Masalah di sisi HP / jaringan |

- Status server diambil dari `.info/connected` Firebase, sehingga "HP tanpa internet" tidak
  salah dibaca sebagai "ESP32 offline". Baris *"Server (Firebase)"* di Pengaturan juga memakai status ini.
- **Batasan:** tombol ini memulihkan koneksi **aplikasi**. Aplikasi tidak terhubung langsung
  ke ESP32, jadi ESP32 yang mati atau putus WiFi tidak bisa dinyalakan dari tombol ini.

### Bantuan
- Teks THI, amonia, kontrol, dan troubleshooting diperbarui sesuai perilaku firmware v8.4,
  termasuk petunjuk tombol "Sambungkan Ulang".

---

## 3. Arsitektur baru (lapisan data)

```
lib/
├── models/
│   ├── sensor_data.dart     ← /sensor_data (ditulis ulang sesuai v8.4)
│   ├── controls.dart        ← /controls + FeedTime + validasi ambang & jadwal   [baru]
│   ├── history_point.dart   ← /history + HistoryStats + CSV                     [baru]
│   └── json_parse.dart      ← parsing toleran nilai RTDB                         [baru]
├── services/
│   ├── pitik_repository.dart ← SATU-SATUNYA akses RTDB; tulis hanya ke /controls [baru]
│   ├── device_state.dart     ← 1 langganan realtime + status online (Timer 5 s) [baru]
│   └── auth_service.dart
├── utils/
│   └── wib_time.dart         ← waktu WIB, format "x detik lalu", durasi         [baru]
├── widgets/
│   ├── guest_banner.dart     ← banner mode tamu                                 [baru]
│   └── reconnect_button.dart ← tombol "Sambungkan Ulang"                        [baru]
└── screens/ ...              ← hanya membaca DeviceState & memanggil repository
```

Alur data:

```
Firebase RTDB ──► PitikRepository ──► DeviceState (ChangeNotifier) ──► Dashboard / Kontrol / Pengaturan / Riwayat
                        ▲
Screen ── perintah ─────┘  (setFan, setPump, setFanPump, setAutoMode, triggerFeed,
                            setThresholds, setFeedSchedule → hanya /controls)
```

- Status online memakai `.info/serverTimeOffset`, sehingga jam HP yang meleset tidak membuat status salah.
- Semua langganan dan Timer dibatalkan di `dispose()`, termasuk saat logout.

---

## 4. Daftar file

### File baru
| File | Isi |
|---|---|
| `lib/models/controls.dart` | Model `/controls`, `FeedTime`, `ThiLevel`, validasi |
| `lib/models/history_point.dart` | Model `/history`, statistik, ekspor CSV |
| `lib/models/json_parse.dart` | Helper parsing nilai RTDB |
| `lib/services/pitik_repository.dart` | Akses RTDB tunggal |
| `lib/services/device_state.dart` | State realtime + status online |
| `lib/utils/wib_time.dart` | Utilitas waktu WIB |
| `lib/widgets/guest_banner.dart` | Banner mode tamu |
| `lib/widgets/reconnect_button.dart` | Tombol "Sambungkan Ulang" |

### File diubah
| File | Perubahan utama |
|---|---|
| `lib/main.dart` | Membuat `PitikRepository` + `DeviceState`; meneruskan status tamu ke tab |
| `lib/models/sensor_data.dart` | Ditulis ulang: `sensor_ok`, `mq137_*`, `timestamp`, flag keamanan, pakan terakhir |
| `lib/screens/dashboard_screen.dart` | Amonia ADC, online, sensor error, ambang dari `/controls`, kartu Pakan |
| `lib/screens/control_screen.dart` | Ditulis ulang: satu sumber kebenaran, relay aktual, aturan kunci, mode tamu |
| `lib/screens/history_screen.dart` | Pakai repository, WIB, grafik amonia, zona THI dinamis, cegah race condition |
| `lib/screens/settings_screen.dart` | Ambang THI ke `/controls`, jadwal pakan, kartu Perangkat asli, mode tamu |
| `lib/screens/info_screen.dart` | Teks bantuan disesuaikan dengan firmware v8.4 |
| `lib/widgets/thi_gauge.dart` | Nilai boleh kosong (`--`); **perbaikan kebocoran listener animasi** |
| `lib/widgets/kpi_card.dart` | Badge netral/kustom (mis. "Sensor error", "ADC · belum dikalibrasi") |
| `lib/widgets/auth_widgets.dart` | Migrasi API keyboard yang deprecated (widget OTP yang tidak dipakai) |
| `lib/services/auth_service.dart` | `print` → `debugPrint` |
| `lib/screens/splash_screen.dart` | `withOpacity` → `withValues` (tanpa perubahan tampilan) |
| `CLAUDE.md` | §3 "Kondisi kode saat ini" diperbarui |

### File dihapus
| File | Alasan |
|---|---|
| `lib/services/api_service.dart` | Tidak dipakai; menulis field di luar kontrak (`fan_sent_at`, `pump_sent_at`) |
| `lib/services/history_service.dart` | Diganti `PitikRepository` + `HistoryPoint`; membaca field lama `a` |
| `test/services/history_service_test.dart` | Ikut dihapus bersama kode yang dites |

---

## 5. Bug lain yang ikut diperbaiki

1. **Kebocoran listener di gauge THI.** Tiap perubahan nilai menambah listener animasi baru
   yang tidak pernah dilepas. Setelah beberapa jam, satu frame animasi memicu ratusan `setState`.
2. **Race condition di Riwayat.** Bila periode diganti cepat, respons lama bisa menimpa data periode baru.
3. **Key SharedPreferences tidak cocok.** Dashboard membaca `thiWarning`, sedangkan Pengaturan menulis
   `thiDanger`. Sekarang ambang sepenuhnya dari `/controls`.
4. **Switch mode otomatis optimistis.** Tampilan bisa berbeda dengan kondisi firmware. Sekarang
   tampilan hanya mengikuti `/controls`.
5. **Validasi riwayat.** THI bernilai 0 sebelumnya dianggap valid; sekarang ditolak.

---

## 6. Pengujian

Jalankan dari root proyek:

```bash
flutter analyze   # No issues found
flutter test      # 93 tes lulus
```

| File tes | Yang diuji |
|---|---|
| `test/models/*_test.dart` | Parsing `/sensor_data`, `/controls`, `/history`; validasi; field lama diabaikan |
| `test/utils/wib_time_test.dart` | Konversi WIB, pergantian hari, `0` / `-1`, format durasi |
| `test/services/device_state_test.dart` | Online/offline 60 s, koreksi jam server, mode kembali Manual, teks update & pakan |
| `test/screens/dashboard_screen_test.dart` | Ambang dinamis, banner relay aktual, sensor error, offline, kartu pakan |
| `test/screens/control_screen_test.dart` | Manual/otomatis, offline, `feed_now`, flag keamanan, preset, relay aktual, tamu |
| `test/screens/settings_screen_test.dart` | Simpan ambang, mode tamu, time picker, kartu Perangkat, NTP belum sinkron |
| `test/widgets/sensor_error_widgets_test.dart` | Gauge & KPI saat data tidak tersedia |
| `test/architecture_test.dart` | Hanya repository yang mengakses RTDB, hanya menulis `/controls`, tidak ada field lama |

> Catatan teknis: di widget test, `StreamController.close()` tidak dipanggil karena membuat tes
> menggantung di lingkungan FakeAsync. Helper tes ada di `test/helpers/fakes.dart`.

---

## 7. Hal yang masih terbuka

| # | Hal | Keterangan |
|---|---|---|
| 1 | **Firebase RTDB Rules** | Pembatasan tamu baru di UI. Database masih *test mode*, jadi siapa pun yang tahu URL-nya tetap bisa menulis. Menutupnya butuh autentikasi di ESP32, sehingga perlu keputusan bersama tim firmware. |
| 2 | Mode otomatis saat offline | Switch mode otomatis ikut dikunci saat offline. Perlu konfirmasi apakah perilaku ini diinginkan. |
| 3 | Sambung ulang stream | Sudah bisa **manual** lewat tombol "Sambungkan Ulang". Sambung ulang otomatis (tanpa tombol) belum ada. |
| 4 | `lib/README_PAPER.md` | Dokumen ini masih menjelaskan `api_service.dart`, `history_service.dart`, dan `fan_sent_at`, yang sudah dihapus. |
| 5 | Pengaturan dummy | Notifikasi, tema, bahasa, dan "Nama Kandang" masih dummy (tidak berpengaruh ke perangkat). |
