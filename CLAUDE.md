# SmartQuail / PITIK — Aplikasi Flutter

Aplikasi monitoring & kontrol iklim kandang puyuh. Aplikasi ini **klien** dari perangkat
ESP32-S3 (firmware PITIK v8.4) lewat **Firebase Realtime Database**. Firmware sudah
diuji di hardware dan menjadi **sumber kebenaran kontrak data** — aplikasi yang harus
menyesuaikan, bukan sebaliknya.

Bahasa UI: **Indonesia**. Pengguna: peternak (login no. HP + OTP) atau tamu (anonim).

---

## 1. Arsitektur sistem (ringkas)

```
DHT22 · MQ-137 · Nextion · relay kipas/pompa · servo pakan
            │
        ESP32-S3 (firmware v8.4)
            │  HTTPS (Firebase_ESP_Client, test_mode tanpa auth)
   Firebase RTDB  (asia-southeast1, project pitik-1ad2d)
            │  firebase_database (realtime listener)
     Aplikasi Flutter (repo ini)  ←  Firebase Auth (Phone OTP / Anonymous)
```

- Layar Nextion di kandang juga bisa mengontrol kipas/pompa/pakan **tanpa internet**.
  Perubahan dari Nextion disinkronkan ESP32 ke `/controls`, jadi app **harus** selalu
  mengikuti `/controls` secara realtime (jangan hanya state lokal).

---

## 2. KONTRAK DATA FIREBASE (wajib dipatuhi — sesuai firmware v8.4)

Semua path di root database (belum multi-device). Tanggal & jam memakai **WIB (UTC+7)**;
`timestamp`/`ts`/`epoch` = epoch detik **UTC**.

### `/sensor_data` — ditulis ESP32 (updateNode tiap 5 s bila berubah, keepalive 30 s)
| Field | Tipe | Keterangan |
|---|---|---|
| `sensor_ok` | bool | DHT22 valid. Jika `false`, field suhu/RH/THI **tidak dikirim** (nilai lama bisa tersisa) → tampilkan "Sensor error", jangan tampilkan angka lama sebagai valid |
| `temperature` | float | °C, 1 desimal |
| `humidity` | float | % RH |
| `thi` | float | THI = 0,8·T + (RH/100)·(T − 14,4) + 46,4 |
| `mq137_raw` | int | ADC 0–4095 amonia — **BUKAN ppm** |
| `mq137_volt` | float | tegangan AO sensor (V) |
| `ammonia_calibrated` | bool | selalu `false` sampai sensor dikalibrasi |
| `relay_fan`, `relay_pump` | bool | status relay **aktual** |
| `relays_enabled`, `feeder_enabled` | bool | saklar keamanan firmware; jika `false` perintah ON ditolak |
| `auto_mode` | bool | salinan mode yang sedang aktif |
| `online` | bool | **selalu true** — JANGAN dipakai untuk status online |
| `timestamp` | int | epoch UTC detik; `0` jika ESP32 belum dapat waktu NTP |
| `hour`, `minute` | int | WIB; `-1` jika belum NTP |
| `uptime_s`, `device_id`, `fw` | int/str | diagnostik (`fw` = "8.4") |
| `last_feed` | string | sumber pakan terakhir: `"07:00"` (jadwal), `"nextion"`, `"app"` |
| `last_feed_ts` | int | epoch UTC pakan terakhir |

> Field lama `ammonia` / `amonia` **tidak ada lagi**.

### `/controls` — ditulis aplikasi, didengarkan ESP32 via stream
| Field | Tipe | Penulis | Aturan |
|---|---|---|---|
| `fan` | bool | app ⇄ ESP32 | perintah kipas. ESP32 menulis balik bila ditolak / berubah dari Nextion / mode otomatis |
| `fan_speed` | int | ESP32 | 0 / 100, indikator saja |
| `pump` | bool | app ⇄ ESP32 | sama seperti `fan` |
| `feed_now` | bool | app → `true`, ESP32 → `false` | memicu pakan sekali; ESP32 selalu mereset ke `false` |
| `auto_mode` | bool | app ⇄ ESP32 | ESP32 menulis `false` saat tombol manual Nextion ditekan |
| `thi_normal` | float | app | 50–100 dan < `thi_danger` (default firmware **72**) |
| `thi_danger` | float | app | ≤ 100 dan > `thi_normal` (default firmware **78**) |
| `feed_hour1..3` | int | app | 0–23 (default 7, 12, 17) |
| `feed_min1..3` | int | app | 0–59 (default 0) |

Perilaku firmware yang harus dipahami UI:
- **Saat boot** ESP32 masuk mode **MANUAL** dengan kipas & pompa MATI, lalu menulis
  `fan=false`, `pump=false`, `auto_mode=false` (nilai lama tidak dipulihkan). Mode otomatis
  hanya aktif lagi bila user menyalakannya dari app.
- `feed_now = true` yang tertinggal saat ESP32 mati/putus **tidak** dijalankan saat ESP32
  tersambung lagi — ESP32 hanya mereset ke `false`. Jadi tombol pakan di app sebaiknya
  dinonaktifkan saat perangkat offline.
- **Mode otomatis** (dicek tiap 5 s): kipas ON bila THI ≥ `thi_normal`, OFF bila
  ≤ `thi_normal − 2`; pompa ON bila THI ≥ `thi_danger`, OFF bila ≤ `thi_danger − 3`.
  Selama `auto_mode = true`, perintah manual fan/pump **akan ditimpa**.
- Nilai di luar rentang diabaikan firmware (tidak ada pesan error ke app).

### `/history/{YYYY-MM-DD}/{HH:MM}` — ESP32, tiap 5 menit (hanya bila NTP & sensor valid)
`t` (°C), `h` (%), `thi`, `mq137_raw`, `f` (0/1 kipas), `p` (0/1 pompa), `ts` (epoch UTC).
> Field lama `a` (amonia) **tidak ada**.

### `/control_log/{pushId}` — ESP32, saat mode otomatis mengubah relay
`event` (`fan_on`|`pump_on`|`fan_pump_on`|`all_off`), `thi`, `fan`, `pump`, `epoch`.

---

## 3. Kondisi kode saat ini (lib/)

Lapisan data (satu-satunya akses RTDB ada di `services/`):
- `models/` — `SensorData` (`/sensor_data`), `Controls` + `FeedTime` (`/controls`,
  validasi ambang & jadwal), `HistoryPoint` + `HistoryStats` + CSV (`/history`),
  `json_parse.dart` (parsing toleran nilai RTDB).
- `services/pitik_repository.dart` — **satu-satunya** file yang mengimpor
  `firebase_database`; stream `/sensor_data`, `/controls`, `.info/serverTimeOffset`,
  baca `/history` (tanggal WIB), dan **tulis hanya ke `/controls`**.
- `services/device_state.dart` — `ChangeNotifier`, satu langganan realtime untuk semua
  tab; status online dari umur `timestamp` (Timer 5 s, dikoreksi serverTimeOffset);
  teks `lastUpdateText` / `lastFeedText`.
- `utils/wib_time.dart` — konversi & format waktu WIB (UTC+7), tangani `0` / `-1`.
- `test/architecture_test.dart` menjaga aturan di atas (gagal bila dilanggar).

UI:
- `main.dart` — Firebase init → `AuthWrapper` → `LoginScreen` atau `MainNavigation`
  (membuat `PitikRepository` + `DeviceState`, dioper ke 4 tab).
- `screens/dashboard_screen.dart` — data dari `DeviceState`; ambang dari `/controls`;
  sensor error / offline / pakan terakhir; amonia = ADC mentah.
- `screens/control_screen.dart` — switch mengikuti `/controls`, relay aktual terpisah;
  tombol dikunci saat offline / `relays_enabled` / `feeder_enabled` / mode otomatis /
  `feed_now`.
- `screens/history_screen.dart` — `PitikRepository.fetchHistory`, zona THI dari `/controls`.
- `screens/settings_screen.dart` — ambang THI (draft → simpan ke `/controls`), jadwal
  pakan (time picker), status perangkat; notifikasi/tema/bahasa masih dummy.
- `services/auth_service.dart`, `screens/login_screen.dart`, `otp_screen.dart` — Phone OTP
  (+62) & tamu (anonim).

Paket (pubspec): firebase_core ^4.4.0, firebase_database ^12.1.3, firebase_auth ^6.1.4,
firebase_crashlytics ^5.0.7, fl_chart ^1.2.0, shared_preferences ^2.3.0. Dart SDK ^3.11.
Tema: Material 3, warna utama `#007AFF`, gaya iOS, latar `#F5F5F7`.

---

## 4. Masalah yang harus diperbaiki (urut prioritas)

1. **Amonia** — ganti ke `mq137_raw` (ADC) + tampilkan label "ADC · belum dikalibrasi"
   selama `ammonia_calibrated == false`. Nonaktifkan alert/ambang ppm sampai kalibrasi.
   Terapkan di Dashboard, Kontrol, dan Riwayat (`history_service` field `mq137_raw`).
2. **Status online** — hitung dari umur `timestamp`: offline bila
   `now_utc − timestamp > 60 s` atau `timestamp == 0`. Perbarui tiap beberapa detik
   (Timer), karena kalau ESP32 mati tidak ada event baru.
3. **Sensor error** — bila `sensor_ok == false`, tampilkan "Sensor error" / "--".
4. **Ambang THI** — Pengaturan membaca & menulis `controls/thi_normal` dan
   `controls/thi_danger` (hanya 2 ambang; hapus ambang ketiga). Validasi normal < danger,
   rentang 50–100. Dashboard & gauge memakai nilai ini, bukan hardcode.
5. **Jadwal pakan** — UI untuk `feed_hour1..3` / `feed_min1..3` (time picker) +
   tampilkan `last_feed` dan `last_feed_ts`.
6. **Kontrol** — satu sumber kebenaran: tombol mengikuti `/controls` (`fan`, `pump`,
   `auto_mode`); tampilkan status aktual dari `/sensor_data.relay_fan/relay_pump`
   sebagai indikator terpisah. Nonaktifkan tombol bila `relays_enabled == false`
   (pakan: `feeder_enabled`). Saat mode otomatis ON, beri keterangan
   "dikendalikan otomatis". Tombol pakan: disable sampai `feed_now` kembali `false`.
7. **Lapisan data** — pindahkan semua akses RTDB ke `services/` (satu kelas repository
   + model `SensorData`, `Controls`, `HistoryPoint`), screen hanya konsumsi stream.
   Batalkan semua `StreamSubscription` di `dispose()`.
8. **Tamu (anonim)** — tentukan: tamu hanya boleh melihat (disarankan) → sembunyikan /
   nonaktifkan kontrol & pengaturan untuk `isAnonymous`.
9. Rapikan: hapus impor ke `lib/backup`, tangani `hour/minute == -1`, tangani
   `timestamp == 0` di tampilan jam.

---

## 5. Aturan kerja

- **Jangan mengubah nama path / field Firebase.** Kalau butuh field baru, tanyakan dulu
  (harus ditambahkan juga di firmware ESP32).
- Jangan menulis ke `/sensor_data`, `/history`, `/control_log` dari app (hanya ESP32).
- Jangan menambah paket state management besar tanpa alasan; `StreamBuilder` /
  `ChangeNotifier` cukup.
- Pertahankan gaya visual yang ada; teks UI Bahasa Indonesia.
- Kerjakan per langkah prioritas di atas, jalankan `flutter analyze` setelah tiap
  langkah, dan ringkas file yang diubah.
- Jangan commit kredensial; `firebase_options.dart` sudah ada, jangan diubah.