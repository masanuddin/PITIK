# PITIK Flutter App — Paper v1.1

**Aplikasi mobile untuk pengambilan data eksperimen paper ICIC Express Letters.**

> Ini adalah dokumentasi perubahan Flutter app untuk mendukung firmware ESP32 Paper v1.1.
> Lihat `esp32_pitik_paper/README.md` untuk dokumentasi firmware.

---

## Perubahan dari Aplikasi Original (v1.0.0)

### Ringkasan

| # | File | Perubahan | Tujuan Paper |
|---|------|-----------|-------------|
| A | `api_service.dart` | `sent_at` timestamp di path terpisah, metode baru | Eksperimen 1, 3, 5 |
| B | `control_screen.dart` | Auto Mode toggle | Eksperimen 1, 3 |
| C | `settings_screen.dart` | 2 slider THI + tombol "Sync to ESP32" | Eksperimen 3 |
| D | `dashboard_screen.dart` | Baca threshold dari `/controls` ESP32 | Eksperimen 3 |
| E | `history_service.dart` + `history_screen.dart` | CSV export via Clipboard | Eksperimen 2 |

### A. `api_service.dart` — metode baru

```dart
// setFan/setPump — SEKARANG tulis 2 path sekaligus:
// /controls/fan         ← bool (tidak berubah)
// /controls/fan_sent_at ← ServerValue.timestamp (BARU, path terpisah)
Future<void> setFan(bool value)     // + sent_at
Future<void> setPump(bool value)    // + sent_at

// BARU:
Future<void> setAutoMode(bool value)          // /controls/auto_mode
Future<void> syncThresholds(double n, double d) // /controls/thi_normal, /controls/thi_danger
```

**Kenapa `sent_at` di path terpisah:** Jika `sent_at` digabung ke dalam node `/controls/fan`, node berubah dari `bool` jadi `object` — parser `data.boolData()` di ESP32 akan gagal. Path terpisah menjaga backward compatibility.

### B. `control_screen.dart` — toggle Auto Mode

**Auto Mode Switch:**
- Baca/tulis `/controls/auto_mode`
- ON: ESP32 mengontrol fan/pump otomatis berdasarkan THI
- OFF: Fan/pump hanya dari Flutter atau Nextion (manual)
- Menampilkan threshold aktif (thiNormal, thiDanger) dari ESP32

### C. `settings_screen.dart` — Opsi A (2 slider)

**Threshold THI — dari 3 slider ke 2 slider:**
| Slider | Default | Dikirim ke ESP32 | Arti |
|--------|---------|-----------------|------|
| Fan ON (Normal → Warning) | 72.0 | `/controls/thi_normal` | THI >= nilai ini → Fan menyala |
| Pump ON (Warning → Danger) | 78.0 | `/controls/thi_danger` | THI >= nilai ini → Fan + Pump |

**Tombol "Sync to ESP32":**
- Hanya aktif saat ESP32 online (dideteksi dari `/sensor_data/online`)
- Mengirim `thi_normal` dan `thi_danger` ke Firebase `/controls`
- ESP32 menerima via Stream dan langsung menerapkan threshold baru

### D. `dashboard_screen.dart` — threshold dari ESP32

Dashboard sekarang subscribe ke `/controls` untuk membaca `thi_normal` dan `thi_danger` langsung dari ESP32. Jika ESP32 belum mengirim threshold (misal baru boot), fallback ke SharedPreferences.

### E. History CSV Export

Tombol download di header History Screen. Menyalin seluruh data yang sedang ditampilkan ke Clipboard dalam format CSV:

```
time,temperature,humidity,ammonia,thi,fan,pump
14:00,28.5,70,12,74.1,0,0
14:05,28.7,69,12,74.3,1,0
...
```

Paste langsung ke Excel atau Notepad → simpan sebagai `.csv`. Nol dependency baru (pakai `Clipboard` dari Flutter SDK).

---

## Firebase Nodes — Flutter Side

### Ditulis oleh Flutter:

```
/controls/fan               = bool          (perintah kipas)
/controls/pump              = bool          (perintah pompa)
/controls/feed_now          = bool          (trigger feeder)
/controls/auto_mode         = bool          (toggle auto climate)
/controls/thi_normal        = double        (threshold fan — dari settings)
/controls/thi_danger        = double        (threshold pump — dari settings)
/controls/fan_sent_at       = timestamp     (kapan Flutter kirim perintah fan)
/controls/pump_sent_at      = timestamp     (kapan Flutter kirim perintah pump)
```

### Dibaca oleh Flutter:

```
/sensor_data/*              = real-time KPI (suhu, kelembaban, THI, amonia, relay status)
/controls/*                 = real-time control sync (fan, pump, auto_mode, thresholds)
/history/YYYY-MM-DD/HH:MM   = data riwayat (grafik + statistik + CSV export)
```

---

## Panduan 6 Eksperimen — dari Sisi Flutter

### Eksperimen 1 — Functional Validation

> Catatan: toggle **Test Mode** di aplikasi sudah dihapus. Jika masih memerlukan logging
> `/test_log`, set `/controls/test_mode = true` secara manual via Firebase Console.

1. Set `/controls/test_mode = true` via Firebase Console
2. Lakukan setiap fitur berulang kali:
   - Toggle fan ON/OFF dari Flutter
   - Toggle pump ON/OFF dari Flutter
   - Tekan tombol Feed
   - Cek dashboard untuk pembacaan sensor
3. ESP32 otomatis mencatat pass/fail ke `/test_log`
4. Setelah selesai, set `/controls/test_mode = false` untuk hemat kuota
5. Hitung Success Rate = pass / total × 100%

### Eksperimen 2 — Sensor Accuracy

1. Biarkan sistem berjalan normal, catat waktu mulai (WIB)
2. Baca thermometer referensi manual setiap 5 menit
3. Data DHT22 otomatis tersimpan di `/history`
4. **Ekspor CSV:** buka History Screen → pilih periode → tekan tombol download
5. Paste CSV ke Excel → gabung dengan data referensi manual → hitung MAE/MAPE/RMSE

### Eksperimen 3 — Auto Climate Control

1. Buka **Control Screen** → pastikan **Auto Mode** = ON
2. Buka **Settings Screen** → atur threshold → tekan **Sync to ESP32**
3. Artifisial naikkan suhu (lampu pemanas dekat DHT22)
4. Amati:
   - Dashboard: status banner berubah Normal → Warning → Danger
   - Control Screen: relayFan/relayPump berubah sesuai threshold
   - Serial Monitor ESP32: log `[AUTO] THI=... → Fan ON`
5. Data transisi otomatis di `/control_log`
6. Decision accuracy = total transisi benar / total transisi × 100%

### Eksperimen 4 — Communication Reliability

1. Biarkan sistem jalan normal
2. Flutter tidak perlu interaksi khusus
3. ESP32 mencatat disconnect/reconnect otomatis di `/connection_status`
4. Cek `/heartbeat` untuk gap uptime
5. Cek field `seq` di `/sensor_data` untuk data continuity

### Eksperimen 5 — Dual Interface Synchronization

1. Kirim perintah dari **Control Screen** (toggle fan/pump)
2. Flutter mencatat `sent_at` di `/controls/fan_sent_at`
3. ESP32 mencatat receipt di `/sync_log/{n}`
4. ESP32 mencatat eksekusi di `/sensor_data/relay_fan`
5. Hitung delay = selisih epoch antar node
6. Bidirectional consistency = apakah state di semua interface sama pada waktu yang sama

### Eksperimen 6 — Long-Term Stability

1. Tidak perlu interaksi Flutter khusus
2. Biarkan sistem jalan 3-7 hari
3. ESP32 mencatat:
   - `/system_log` — setiap boot + reset reason
   - `/heartbeat` — uptime, RSSI, free heap setiap 1 menit
   - `/connection_status` — total disconnect count
4. Dashboard dan History Screen tetap bisa dibuka untuk monitoring

---

## Struktur File

```
lib/
├── main.dart                     (tidak berubah)
├── firebase_options.dart         (tidak berubah)
├── models/
│   └── sensor_data.dart          (tidak berubah)
├── services/
│   ├── api_service.dart          [PAPER v1.1] +5 metode, sent_at di path terpisah
│   ├── auth_service.dart         (tidak berubah)
│   └── history_service.dart      [PAPER v1.1] +toCsv() static method
├── screens/
│   ├── control_screen.dart       [PAPER v1.1] +autoMode toggle
│   ├── dashboard_screen.dart     [PAPER v1.1] baca threshold dari /controls
│   ├── history_screen.dart       [PAPER v1.1] +tombol CSV export
│   ├── settings_screen.dart      [PAPER v1.1] Opsi A (2 slider) + sync button
│   ├── info_screen.dart          (tidak berubah)
│   ├── login_screen.dart         (tidak berubah)
│   ├── otp_screen.dart           (tidak berubah)
│   └── splash_screen.dart        (tidak berubah)
├── widgets/
│   ├── auth_widgets.dart         (tidak berubah)
│   ├── kpi_card.dart             (tidak berubah)
│   └── thi_gauge.dart            (tidak berubah)
└── README_PAPER.md               [BARU] dokumentasi ini
```

---

## Catatan Metodologi untuk Paper

1. **`sent_at` path terpisah:** Timestamp perintah Flutter dicatat di `/controls/{key}_sent_at` (server-side timestamp via `ServerValue.timestamp`), bukan di dalam node kontrol. Ini menjaga parsing `boolData()` ESP32 tetap berfungsi.

2. **Threshold sync:** Threshold THI diatur dari Flutter Settings Screen, dikirim ke ESP32 via Firebase Stream, dan diterapkan real-time oleh `autoClimateControl()`. Threshold yang sama juga ditampilkan di Dashboard dan Control Screen.

3. **CSV export:** Data history diekspor via Clipboard copy — pengguna paste ke Excel untuk analisis MAE/MAPE/RMSE. Tidak ada modifikasi data; format CSV mencakup time, temperature, humidity, ammonia, THI, fan, pump.

4. **Test mode:** Fitur logging pass/fail di-gate oleh flag `testMode` (default `false`). Karena toggle app dihapus, flag diset manual via Firebase Console. Saat nonaktif, ESP32 tidak menulis ke `/test_log` (hemat kuota Firebase).

5. **Auto mode:** Saat `autoMode=OFF`, ESP32 tidak menyentuh relay — semua kontrol manual dari Flutter/Nextion. Saat `autoMode=ON`, auto-climate aktif, tapi perintah manual dari Flutter/Nextion tetap diproses (auto akan overrule dalam ≤5 detik jika THI di bawah threshold).
