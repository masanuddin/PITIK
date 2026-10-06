# PITIK — Dokumentasi Lengkap Aplikasi & Firmware

**Sistem monitoring dan kontrol iklim kandang burung puyuh berbasis IoT**
(Aplikasi Flutter + ESP32-S3 + Firebase Realtime Database)

| Item | Nilai |
|---|---|
| Versi aplikasi | `1.0.0+1` (`pubspec.yaml`) |
| Firmware ESP32 | **v8.4.2** (kandidat: v8.4 + perbaikan D2 + D4) — `firmware/pitik_v8_4_d2d4/` |
| Firebase project | `pitik-1ad2d` — Realtime Database region **asia-southeast1** |
| Flutter / Dart | Flutter 3.44.3 (stable), Dart 3.12.2 (`sdk: ^3.11.0`) |
| Status kualitas | `flutter analyze`: **No issues found** · `flutter test`: **264 tes lulus** |
| Status lapangan | Diuji oleh pemilik proyek pada perangkat Android (Samsung S23 Ultra) dan dilaporkan berfungsi baik (6 Oktober 2026) |
| Tanggal dokumen | 6 Oktober 2026 |

> Dokumen ini adalah **sumber dokumentasi utama** versi terbaru. Dokumen lain:
> - `CLAUDE.md` — kontrak data Firebase (wajib dipatuhi) & aturan kerja.
> - `PERUBAHAN_APP_FIRMWARE_v8.4.md` — detail fase penyesuaian ke firmware v8.4.
> - `firmware/README.md` — ringkas cara compile firmware.
> - `PITIK_redesign/review/batch_1..4/README.md` — dokumentasi visual redesign (capture).
> - `README.md` lama sebagian sudah usang (lihat [§13](#13-catatan-dokumen-lama-yang-usang)).

---

## Daftar Isi

1. [Gambaran Sistem](#1-gambaran-sistem)
2. [Fitur Aplikasi Saat Ini](#2-fitur-aplikasi-saat-ini)
3. [Kontrak Data Firebase (ringkas)](#3-kontrak-data-firebase-ringkas)
4. [Arsitektur Kode Aplikasi](#4-arsitektur-kode-aplikasi)
5. [Riwayat Perubahan (Changelog)](#5-riwayat-perubahan-changelog)
6. [Firmware ESP32 v8.4.2](#6-firmware-esp32-v842)
7. [Pengujian & Validasi](#7-pengujian--validasi)
8. [Build & Instal APK Android](#8-build--instal-apk-android)
9. [Preview Lokal (tanpa Firebase)](#9-preview-lokal-tanpa-firebase)
10. [Keamanan & Hal yang Masih Terbuka](#10-keamanan--hal-yang-masih-terbuka)
11. [Rencana Pengembangan Berikutnya: Notifikasi](#11-rencana-pengembangan-berikutnya-notifikasi)
12. [Panduan Push ke GitHub (untuk opencode)](#12-panduan-push-ke-github-untuk-opencode)
13. [Catatan Dokumen Lama yang Usang](#13-catatan-dokumen-lama-yang-usang)

---

## 1. Gambaran Sistem

```
 DHT22 (suhu/RH) · MQ-137 (amonia, ADC) · Nextion (layar sentuh)
 Relay kipas (GPIO47) · Relay pompa (GPIO21) · Servo pakan (GPIO5)
                         │
                 ESP32-S3 — firmware v8.4.2
                         │  HTTPS (Firebase_ESP_Client mobizt 4.4.17)
         Firebase Realtime Database — pitik-1ad2d (asia-southeast1)
                         │  realtime listener (firebase_database)
              Aplikasi Flutter PITIK (repo ini)
                         │
            Firebase Auth: login No. HP (OTP) atau Tamu (anonim)
```

Prinsip utama:

- **Firmware adalah sumber kebenaran kontrak data.** Aplikasi menyesuaikan diri dengan firmware,
  bukan sebaliknya (lihat `CLAUDE.md` §2).
- Layar **Nextion** di kandang dapat mengontrol kipas/pompa/pakan **tanpa internet**; ESP32
  menyinkronkan perubahan ke `/controls`, sehingga aplikasi selalu mengikuti `/controls` secara
  realtime (tidak ada state optimistis di aplikasi).
- Aplikasi **hanya menulis ke `/controls`**. `/sensor_data`, `/history`, `/control_log` hanya
  ditulis ESP32. Aturan ini dijaga otomatis oleh `test/architecture_test.dart`.
- Waktu tanggal/jam memakai **WIB (UTC+7)**; `timestamp`/`ts`/`epoch` adalah epoch detik UTC.

---

## 2. Fitur Aplikasi Saat Ini

Bahasa UI: **Indonesia**. Tema: Material 3 dengan design token PITIK (aksen `#2F62D9`,
kontras teks sudah diverifikasi WCAG). Navigasi bawah 4 tab: **Dashboard · Riwayat · Kontrol · Pengaturan**.

### 2.1 Login & Akun
- **Login No. HP + OTP** (Firebase Phone Auth, prefix +62) atau **masuk sebagai Tamu** (anonim).
- **Tamu = hanya melihat.** Kontrol, ambang THI, dan jadwal pakan dikunci, disertai banner
  "Mode tamu — hanya melihat" dan aksi "Masuk dengan No. HP".
- Nomor HP ditampilkan **disamarkan** di Pengaturan (mis. `+62 812-••••-1234`). Badge
  "Terverifikasi" hanya untuk akun non-tamu yang benar-benar memiliki nomor HP dari Firebase Auth.

### 2.2 Dashboard
- **Baris koneksi**: "Update x lalu" + tanggal/jam WIB laporan terakhir + tombol **Sambungkan Ulang**
  dengan hasil inline (server terhubung ≠ perangkat online).
- **Status perangkat Online/Offline** dihitung dari umur `timestamp` (offline bila > 60 detik atau
  `timestamp == 0`), diperbarui tiap 5 detik dan dikoreksi `.info/serverTimeOffset`.
- **Kartu status THI** (Normal / Waspada / Bahaya) memakai ambang dari `/controls` (bukan hardcode).
  Saat data lama: "Status saat ini tidak tersedia" + status terakhir beserta waktunya.
- **KPI**: Suhu, Kelembapan, THI; **Gas Amonia (NH3) · MQ-137** sebagai nilai ADC mentah
  dengan label "belum dikalibrasi" (bukan ppm).
- **Sensor error (DHT22)** ditampilkan jelas (`--`), tidak pernah menampilkan angka lama sebagai valid.
- **Status Perangkat** (kipas/pompa terakhir diketahui), **Pakan** (terakhir + jadwal),
  **THI Monitor** (gauge skala 50–100 + teks skala penuh untuk aksesibilitas).

### 2.3 Riwayat
- Periode **1 Jam / 24 Jam / 7 Hari / 30 Hari** (data per 5 menit; 30 Hari mengambil tiap titik ke-6).
- 4 grafik (fl_chart, garis lurus tanpa smoothing): **Suhu (°C), Kelembapan (%), Indeks THI**
  (zona Normal/Waspada/Bahaya dari `/controls`), **Sensor gas MQ-137 (ADC)**.
- Ketuk grafik → **readout** tanggal/jam & nilai titik data asli.
- Statistik: rata-rata/min/maks; **Estimasi siklus pendinginan** (dihitung dari sampel, bukan jumlah pasti).
- **Salin CSV** (`date,time,ts,temperature,humidity,thi,mq137_raw,fan,pump`) — hanya aktif bila
  data yang tampil = periode terpilih.
- Keadaan lengkap: memuat, kosong (tanpa angka nol palsu), gagal + "Coba Lagi", ganti periode
  (grafik lama tetap dilabeli periodenya), respons terlambat diabaikan.

### 2.4 Kontrol
- **Mode Iklim**: switch Mode otomatis (Permintaan vs Status perangkat), ambang THI dari Pengaturan,
  penjelasan perilaku firmware (Nextion; setelah restart kembali Manual).
- **Kipas utama** dan **Pompa air / misting**: switch = **Permintaan** (`/controls`), terpisah dari
  **Status perangkat** (`/sensor_data.relay_*`, yaitu state output yang diperintahkan firmware —
  bukan sensor fisik motor).
- **Preset Cepat** atomik: "Semua mati", "Kipas saja", "Kipas + pompa".
- **Pemberi Pakan**: "Beri Pakan Sekarang", pakan terakhir, jadwal ("Ubah di Pengaturan").
- Umpan balik penulisan (tanpa klaim konfirmasi perangkat):
  | Keadaan | Teks |
  |---|---|
  | Sedang menulis | "Mengirim perintah…" (semua kontrol dikunci sementara) |
  | Tulis selesai | "Permintaan disimpan. Menunggu status perangkat." / "Permintaan pakan disimpan. Menunggu perangkat." |
  | Permintaan ≠ status perangkat | "Menunggu perubahan status perangkat." (tidak mengunci kontrol lain) |
  | Gagal | "Gagal mengirim perintah. Periksa koneksi." |
- **Aturan kunci** (tidak berubah sejak penyesuaian v8.4): offline, `relays_enabled == false`,
  mode otomatis ("Dikendalikan otomatis"), `feeder_enabled == false`, `feed_now == true`
  ("Menunggu perangkat…"), tamu. Satu perintah sekaligus; tanpa retry otomatis.

### 2.5 Pengaturan
- **Akun** (nomor disamarkan / Mode tamu).
- **Perangkat**: Nama Kandang ("Label tampilan aplikasi"), Device ID, Firmware, Jam Perangkat
  (`--:-- (belum sinkron NTP)` bila belum NTP), Uptime — saat data lama diberi konteks
  "Nilai dari laporan terakhir perangkat · {waktu}".
- **Koneksi**: Status koneksi perangkat, Server (Firebase), satu tombol Sambungkan Ulang + hasil inline.
- **Ambang THI**: "Ambang normal (kipas)" & "Ambang bahaya (pompa)" — slider 50–100 langkah 0,5,
  validasi normal < bahaya, "Reset ke Default (72/78)", "Batal", status draft
  "Tidak ada perubahan" / "Belum disimpan", tombol "Simpan perubahan".
- **Jadwal Pakan**: Pakan 1–3 via time picker sistem (24 jam), reset dengan konfirmasi.
- Umpan balik simpan: "Menyimpan perubahan…" → "Perubahan disimpan." (±5 detik) /
  "Gagal menyimpan perubahan. Periksa koneksi."; helper statis
  "Perangkat akan menggunakan pengaturan ini saat tersambung." (bukan konfirmasi perangkat).
- **Notifikasi / Bahasa / Tema**: tampil **nonaktif** dengan label "Belum tersedia"
  (placeholder; nilai SharedPreferences tetap dibaca).
- **Info**: Tentang Aplikasi, Bantuan, Kebijakan Privasi · **Keluar dari Akun** (dengan konfirmasi) ·
  footer versi.

### 2.6 Aksesibilitas & performa UI
- Diuji pada lebar 360/393 dp dan skala teks 1.0–2.0 tanpa overflow; konten terakhir tidak tertutup navigasi.
- Navigasi bawah: 1 baris bila label muat, otomatis grid 2×2 bila tidak (berdasarkan pengukuran teks).
- Semantics untuk tombol, switch, slider, status; dukungan **reduced motion** (tanpa animasi berulang).

---

## 3. Kontrak Data Firebase (ringkas)

Rincian lengkap & wajib: **`CLAUDE.md` §2**. Jangan mengubah nama path/field tanpa mengubah firmware.

| Path | Penulis | Isi utama |
|---|---|---|
| `/sensor_data` | ESP32 | `sensor_ok`, `temperature`, `humidity`, `thi`, `mq137_raw`, `mq137_volt`, `relay_fan`, `relay_pump`, `relays_enabled`, `feeder_enabled`, `auto_mode`, `timestamp`, `hour`, `minute`, `uptime_s`, `device_id`, `fw`, `last_feed`, `last_feed_ts` |
| `/controls` | App ⇄ ESP32 | `fan`, `pump`, `auto_mode`, `feed_now`, `fan_speed` (ESP32), `thi_normal`, `thi_danger`, `feed_hour1..3`, `feed_min1..3` |
| `/history/{YYYY-MM-DD}/{HH:MM}` | ESP32 (tiap 5 menit) | `t`, `h`, `thi`, `mq137_raw`, `f`, `p`, `ts` |
| `/control_log/{pushId}` | ESP32 (mode otomatis) | `event`, `thi`, `fan`, `pump`, `epoch` |

Perilaku firmware penting: boot selalu **Manual + relay OFF**; mode otomatis (cek tiap 5 detik):
kipas ON bila THI ≥ `thi_normal` (OFF ≤ normal−2), pompa ON bila THI ≥ `thi_danger` (OFF ≤ bahaya−3).

---

## 4. Arsitektur Kode Aplikasi

```
lib/
├── main.dart                 ← Firebase init → AuthWrapper → Login / MainNavigation (IndexedStack 4 tab)
├── main_preview.dart         ← ENTRYPOINT PREVIEW (data simulasi, tanpa Firebase) — bukan produksi
├── firebase_options.dart     ← konfigurasi FlutterFire (jangan diubah manual)
├── models/
│   ├── sensor_data.dart      ← /sensor_data
│   ├── controls.dart         ← /controls + FeedTime + validasi ambang/jadwal
│   ├── history_point.dart    ← /history + HistoryStats + CSV
│   └── json_parse.dart       ← parsing toleran nilai RTDB
├── services/
│   ├── pitik_repository.dart ← SATU-SATUNYA akses RTDB; tulis hanya /controls
│   ├── device_state.dart     ← ChangeNotifier: 1 langganan realtime, status online, reconnect
│   └── auth_service.dart     ← Phone OTP & anonim
├── theme/pitik_tokens.dart   ← warna, radius, spasi, tipografi, motion (design token)
├── utils/wib_time.dart       ← format & konversi waktu WIB
├── widgets/                  ← komponen: pitik_card, status_chip, metric_card, connection_row,
│                                pitik_bottom_nav, history_chart_card, thi_gauge, guest_banner, …
├── screens/                  ← dashboard, history, control, settings, login, otp, info, splash
└── preview/                  ← perangkat & repository simulasi untuk main_preview.dart
```

Alur data:

```
Firebase RTDB ─► PitikRepository ─► DeviceState (ChangeNotifier) ─► Dashboard / Riwayat / Kontrol / Pengaturan
                        ▲
Screen ── perintah ─────┘  setFan · setPump · setFanPump (atomik) · setAutoMode · triggerFeed ·
                           setThresholds · setFeedSchedule  → semuanya update() ke /controls
```

Dependensi (tanpa paket state management tambahan): `firebase_core`, `firebase_database`,
`firebase_auth`, `firebase_crashlytics`, `fl_chart`, `shared_preferences`.

---

## 5. Riwayat Perubahan (Changelog)

### Fase 1 — Penyesuaian ke kontrak firmware v8.4 (30 Sep 2026)
Detail lengkap: `PERUBAHAN_APP_FIRMWARE_v8.4.md`. Ringkasan:
- Lapisan data baru: `PitikRepository` (satu-satunya akses RTDB) + `DeviceState` + model `SensorData`,
  `Controls`, `HistoryPoint`; `api_service.dart` & `history_service.dart` dihapus.
- Amonia → `mq137_raw` (ADC, belum dikalibrasi); status online dari umur `timestamp`;
  sensor error ditangani; ambang THI & jadwal pakan dari/ke `/controls`; tamu read-only.
- Bug diperbaiki: kebocoran listener gauge THI, race condition Riwayat, key SharedPreferences
  tidak cocok, switch mode optimistis, validasi riwayat.

### Fase 2 — Tombol "Sambungkan Ulang"
- `DeviceState.reconnect()` (goOffline → goOnline → langganan ulang → tunggu data segar ≤15 detik)
  dengan hasil: perangkat online / server terhubung tapi perangkat diam / gagal ke server.
- Status server dari `.info/connected`. Tombol tidak menulis ke database (boleh untuk tamu) dan
  **tidak** membuat perangkat dianggap Online hanya karena server tersambung.

### Fase 3 — Redesign UI (Batch 1–4, semua disetujui)
- **Batch 1 — Fondasi + Dashboard + Navigasi**: design token (`lib/theme/pitik_tokens.dart`),
  komponen reusable, navigasi bawah adaptif (1 baris / grid 2×2), Dashboard baru.
- **Batch 2 — Riwayat**: 4 grafik + readout, statistik, CSV, semua keadaan muat/kosong/gagal/ganti periode.
- **Batch 3 — Kontrol**: Permintaan vs Status perangkat, umpan balik tulis tanpa klaim konfirmasi,
  preset baru ("Semua mati", "Kipas saja", "Kipas + pompa"), tombol pakan biru, satu banner offline.
- **Batch 4 — Pengaturan**: grup pengaturan rapi, nomor disamarkan, ambang THI dengan status draft,
  jadwal pakan, placeholder "Belum tersedia", copy simpan final ("Perubahan disimpan.").
- Capture review: `PITIK_redesign/review/batch_1..4/`. Preview lokal: `lib/main_preview.dart`.

### Fase 4 — Perbaikan bug kipas/pompa dari aplikasi (firmware v8.4.2)
- **Gejala:** kipas & pompa tidak menyala dari aplikasi; pakan otomatis tetap berjalan.
  Jalur lokal (Nextion/firmware) terbukti berfungsi.
- **Akar masalah:** aplikasi menulis `/controls` dengan `update()`; ESP32 menerimanya sebagai event
  **`patch` di path `/`**. Firmware v8.4 memperlakukan **semua** event di `/` sebagai snapshot
  (awal/reconnect) dan sengaja melewati `fan`, `pump`, `auto_mode` → perintah dari app diabaikan.
  (`feed_now`, ambang, jadwal tetap diproses, sehingga pakan berjalan.)
- **Perbaikan (firmware, D2):** bedakan `put "/"` (snapshot → fan/pump/auto_mode tetap tidak
  dipulihkan; boot Manual + relay OFF tetap) dari `patch "/"` (semua kunci di payload diproses,
  termasuk preset atomik). Strategi tulis Flutter (`update()`, preset atomik) **tidak diubah**.
- **D4 (telemetry):** perubahan `relay_fan`, `relay_pump`, `auto_mode`, `sensor_ok` ikut memicu
  kirim `/sensor_data` pada siklus kirim berikutnya (tanpa jaminan waktu; cadence & penundaan
  saat feeder bekerja tetap).
- **D3 (tidak digabung, butuh keputusan):** `feed_now` lama di snapshot. Lihat [§10](#10-keamanan--hal-yang-masih-terbuka).
- Validasi: self-test `static_assert` (dievaluasi compiler ESP32), uji mutasi, rekaman event
  di Firebase Emulator lokal (lihat [§7](#7-pengujian--validasi)).

### Fase 5 — Build APK & perbaikan startup Android
- **Gejala:** APK pertama tertahan di layar pembuka pada HP.
- **Akar masalah:** `android/app/google-services.json` untuk project `pitik-1ad2d` tidak memuat
  `firebase_url`, sedangkan `firebase_options.dart` memuat `databaseURL` asia-southeast1.
  `firebase_core` mendeteksi opsi berbeda dan melempar `[core/duplicate-app]` sebelum `runApp()`.
- **Perbaikan:** `google-services.json` diunduh ulang dari Firebase Console (kini memuat
  `firebase_url` yang identik dengan `firebase_options.dart`). Tidak ada perubahan kode.

### Housekeeping keamanan repo
- Kredensial firmware dipindah ke `secrets.h` (di-ignore git); tersedia `secrets.example.h`.
- `.gitignore`: `firmware/**/secrets.h`, `android/build/`.
- `README.md`: API key project lama diganti placeholder.

---

## 6. Firmware ESP32 v8.4.2

| Path | Isi |
|---|---|
| `firmware/pitik_v8_4_d2d4/pitik_v8_4_d2d4.ino` | **Firmware yang dipakai (v8.4.2 = v8.4 + D2 + D4)** |
| `firmware/pitik_v8_4_d2d4/control_stream_policy.h` (+ `_selftest.h`) | Kebijakan event stream `/controls` |
| `firmware/pitik_v8_4_d2d4/telemetry_policy.h` (+ `_selftest.h`) | Kebijakan kirim telemetry (D4) |
| `firmware/pitik_v8_4_d2d4/secrets.example.h` | Contoh kredensial (placeholder) |
| `firmware/pitik_v8_4/` | Varian D2 saja (v8.4.1) |
| `firmware/patches/D3_feed_now_snapshot.patch` | Patch terpisah, **belum disetujui** |
| `firmware/patches/D4_telemetry_state.patch` | D4 relatif terhadap D2 (sudah termasuk di v8.4.2) |
| `firmware/tools/` | Alat validasi emulator lokal (lihat §7) |

**Yang tidak berubah dari v8.4:** pin (DHT22 GPIO4, MQ-137 GPIO6, servo GPIO5, relay kipas GPIO47,
relay pompa GPIO21, Nextion RX18/TX17), polaritas relay (active-high), safety flags, boot Manual +
relay OFF, perintah Nextion 1–5, auto climate, perilaku feeder.

**Compile (Arduino IDE / arduino-cli):**
1. Salin `secrets.example.h` → `secrets.h` di folder sketch, isi Wi-Fi & API key. **Jangan commit.**
2. Board **ESP32S3 Dev Module** (core esp32 3.3.12 teruji), library *Firebase Arduino Client Library
   for ESP8266 and ESP32* (mobizt) **4.4.17**, DHT sensor library, ESP32Servo.
3. `arduino-cli compile --fqbn esp32:esp32:esp32s3 firmware/pitik_v8_4_d2d4`
   — ukuran ±1.239.612 / 1.310.720 byte (partisi default 4 MB).

**Verifikasi runtime setelah upload:** serial menampilkan `v8.4.2` dan `[Relay] Boot: semua OFF`;
`/sensor_data/fw = "8.4.2"`; tombol kipas/pompa/preset/mode di app memunculkan
`[App] Fan ON` / `[App] Pump ON` / `[App] Auto mode ON` di serial.

**Rollback:** upload sketch v8.4 lama dengan setting board yang sama. Aman dari sisi data (tidak ada
field baru/NVS), tetapi bug kipas/pompa dari app akan kembali.

---

## 7. Pengujian & Validasi

### 7.1 Aplikasi Flutter
```bash
flutter pub get
flutter analyze   # No issues found
flutter test      # 264 tes lulus
```
CI GitHub Actions (`.github/workflows/ci.yml`) menjalankan `flutter analyze` + `flutter test`
dengan Flutter 3.44.3 pada setiap push/PR ke `main`.

| Area | File tes |
|---|---|
| Model & parsing | `test/models/*_test.dart` |
| Waktu WIB | `test/utils/wib_time_test.dart` |
| State realtime, online/offline, reconnect | `test/services/device_state_test.dart` |
| Auth | `test/services/auth_service_test.dart` |
| Dashboard (+ responsif 360/393 dp × skala teks) | `test/screens/dashboard_screen_test.dart`, `dashboard_responsive_test.dart` |
| Riwayat (periode, keadaan, respons terlambat, CSV, aksesibilitas) | `test/screens/history_screen_test.dart` |
| Kontrol (aturan kunci, Permintaan vs Status, tulis/gagal, semantics) | `test/screens/control_screen_test.dart` |
| Pengaturan (ambang, jadwal, placeholder, akun, koneksi) | `test/screens/settings_screen_test.dart` |
| Navigasi bawah, token warna, widget error sensor | `test/widgets/*`, `test/theme/*` |
| Aturan arsitektur (hanya repository akses RTDB, hanya tulis `/controls`) | `test/architecture_test.dart` |

### 7.2 Firmware
- **Self-test kebijakan** (`*_selftest.h`): `static_assert` dievaluasi compiler `xtensa-esp32s3`
  setiap compile — compile gagal bila kebijakan berubah tanpa sengaja. Uji mutasi membuktikan
  regresi (mis. perilaku v8.4 lama) tertangkap.
- **Rekaman event di Firebase Emulator lokal** (`firmware/tools/verify_stream_events.mjs`, hanya
  127.0.0.1, namespace `demo-*`): snapshot awal = `put "/"`; `update()` fan/pump/preset/auto_mode =
  `patch "/"`; set anak = `put "/fan"`; reconnect = `put "/"`; payload identik tidak menghasilkan event.
  Event terekam diubah menjadi `static_assert` (`gen_policy_asserts.py`) terhadap header C++ asli.
  ```bash
  firebase emulators:start --only database --project demo-pitik --config firmware/tools/firebase.emulator.json
  node firmware/tools/verify_stream_events.mjs events.json
  python firmware/tools/gen_policy_asserts.py events.json recorded_asserts.cpp
  ```
  (Emulator butuh Java 21+.)

### 7.3 Pengujian pemilik
Pemilik proyek telah menguji aplikasi di perangkat Android (Samsung S23 Ultra) dan melaporkan
sistem berfungsi baik.

---

## 8. Build & Instal APK Android

Prasyarat: Android SDK, **JDK 17+** (Android Gradle Plugin menolak Java 11; JDK bawaan Android
Studio/JBR bisa dipakai), `android/app/google-services.json` yang memuat `firebase_url`.

```bash
# Cara standar
flutter build apk --release

# Alternatif via Gradle (melewati upload mapping Crashlytics ke Firebase)
cd android
./gradlew assembleRelease -x uploadCrashlyticsMappingFileRelease
```

Hasil: `build/app/outputs/flutter-apk/app-release.apk` (universal: arm64-v8a, armeabi-v7a, x86_64).

Catatan:
- APK saat ini ditandatangani **debug key** (cukup untuk instal manual, mis. via Google Drive;
  Play Protect dapat memberi peringatan). Rilis Play Store butuh keystore rilis dan
  `applicationId` bukan `com.example.*`.
- Bila login OTP bermasalah, daftarkan SHA-1/SHA-256 sertifikat penandatangan di
  Firebase Console → Project settings → aplikasi Android.
- **APK ini memakai Firebase produksi** — tombol Kontrol menggerakkan perangkat sungguhan.

---

## 9. Preview Lokal (tanpa Firebase)

`lib/main_preview.dart` menampilkan keempat layar asli dengan data simulasi
(tanpa Firebase/Auth/Crashlytics):

```bash
flutter run -d web-server -t lib/main_preview.dart --web-hostname 127.0.0.1 --web-port 8080
```

Parameter URL: `scenario` (online, stale, sensorError, staleSensorError, noData, reconnecting,
serverErrorFresh, serverOkStale, auto, relayMismatch, feedPending), `tab` (0–3), `history`
(ok, slow, failOthers, empty, error), `write` (ok, slow, error, noApply), `guest=1`, `scale`, `ui=0`.

---

## 10. Keamanan & Hal yang Masih Terbuka

| # | Hal | Status / Rekomendasi |
|---|---|---|
| 1 | **Firebase RTDB Rules** | Rules yang ter-deploy belum diaudit (UNKNOWN). Firmware memakai `signer.test_mode=true` (tanpa autentikasi), sehingga database efektif terbuka. Rencana: akun Firebase Auth khusus perangkat → flash firmware ber-auth → uji Rules di emulator → baru deploy Rules (urutan ini penting agar perangkat tidak terputus). |
| 2 | Pembatasan tamu | Saat ini hanya di UI; perlu ditegakkan lewat Rules (anonim hanya baca). |
| 3 | Kepemilikan perangkat | Belum ada; semua pengguna terautentikasi berbagi satu perangkat (path root). |
| 4 | TLS firmware | Library tanpa CA certificate memanggil `setInsecure()` → sertifikat server tidak diverifikasi. Rekomendasi: set root CA. |
| 5 | Kredensial di riwayat git | Password Wi-Fi asli pernah ter-commit (file firmware lama, sudah dihapus dari working tree tetapi masih di riwayat). **Rekomendasi: ganti password Wi-Fi.** Batasi Web API key di Google Cloud Console. |
| 6 | Validasi tipe nilai | Firmware menafsirkan string non-"true"/"1" sebagai `false` (mis. `pump:"yes"` mematikan pompa). Tambahkan `.validate` tipe di Rules. |
| 7 | **D3 — `feed_now` lama** | Belum digabung. Perintah pakan yang tertinggal saat ESP32 mati/stream putus saat ini **dijalankan** ketika tersambung lagi (bertentangan dengan `CLAUDE.md`). D3 akan membuangnya, tetapi juga dapat membuang perintah sah; reset tanpa syarat dapat menghapus perintah yang lebih baru. Solusi lengkap butuh kontrak baru (timestamp/ID perintah + ack). |
| 8 | Signing & App ID | Release memakai debug key, `applicationId` `com.example.pitik_app`. |
| 9 | Versi di aplikasi | "PITIK v1.0.0" masih teks tetap (belum membaca info paket). |
| 10 | Status Perangkat | `relay_fan/relay_pump` = state output yang diperintahkan, bukan umpan balik fisik (tidak ada sensor arus). |
| 11 | App Check | Belum kompatibel dengan ESP32 tanpa provider khusus; tunda sampai autentikasi perangkat ada. |

> Catatan: pengujian hardware lokal tidak membuktikan keamanan backend. Perubahan keamanan dikerjakan
> sebagai batch terpisah, tanpa deploy otomatis.

---

## 11. Rencana Pengembangan Berikutnya: Notifikasi

Saat ini **Push Notification, Suara Peringatan, Email Alert** di Pengaturan masih placeholder
("Belum tersedia"). Usulan rancangan:

### 11.1 Jenis peringatan yang diusulkan
| Peringatan | Pemicu | Catatan |
|---|---|---|
| THI Bahaya | THI ≥ `thi_danger` | Pakai histeresis (mis. reset < `thi_danger − 3`) & cooldown agar tidak spam |
| THI Waspada (opsional) | THI ≥ `thi_normal` | Bisa dimatikan per pengguna |
| Sensor error | `sensor_ok == false` > N menit | Hindari notifikasi untuk kegagalan sesaat |
| Perangkat offline | umur `timestamp` > M menit | Butuh pengecekan terjadwal di server (perangkat mati tidak mengirim apa pun) |
| Pakan | jadwal terlewat / pakan berjalan | Berdasarkan `last_feed_ts` vs jadwal |
| Amonia | setelah MQ-137 dikalibrasi | Saat ini ADC mentah — jangan beri peringatan ppm |

### 11.2 Opsi arsitektur
| Opsi | Cara kerja | Kelebihan | Kekurangan |
|---|---|---|---|
| **A. FCM + Cloud Functions (disarankan)** | Function memantau `/sensor_data` (trigger RTDB) + fungsi terjadwal untuk offline → kirim FCM ke token pengguna | Tetap jalan walau app ditutup; logika terpusat; bisa dites di emulator | Butuh paket Blaze; perlu path baru untuk token & state peringatan (perubahan kontrak) |
| B. Notifikasi lokal saja | App memantau stream & menampilkan `flutter_local_notifications` | Tanpa server | Tidak andal saat app ditutup / dibatasi baterai Android |
| C. ESP32 kirim langsung | ESP32 memanggil FCM | Tanpa server | Kredensial server di perangkat — **tidak disarankan** |

### 11.3 Langkah teknis (Opsi A)
1. **Kontrak baru (perlu persetujuan):** mis. `/users/{uid}/fcm_tokens/{token}`,
   `/users/{uid}/notif_prefs`, `/alert_state/*` (untuk cooldown/histeresis). Ditulis app/Functions,
   tidak oleh ESP32.
2. **Aplikasi:** tambah `firebase_messaging` (+ `flutter_local_notifications` untuk tampilan
   foreground), izin `POST_NOTIFICATIONS` (Android 13+), channel notifikasi, simpan/refresh token,
   ketuk notifikasi → buka tab terkait. Ubah placeholder Pengaturan menjadi kontrol nyata
   (disimpan di DB agar dihormati server, bukan hanya SharedPreferences).
3. **Cloud Functions:** evaluasi ambang dari `/controls`, histeresis + cooldown, fungsi terjadwal
   untuk offline/sensor error, kirim FCM ke pengguna yang mengaktifkan.
4. **Keamanan:** selesaikan autentikasi perangkat & Rules (§10 no. 1–3) lebih dulu, karena token
   dan preferensi pengguna adalah data pribadi.
5. **Pengujian:** unit test logika evaluasi peringatan; Firebase Emulator Suite (Database +
   Functions); uji izin notifikasi di Android 13+; uji tidak ada spam saat THI naik-turun di sekitar ambang.
6. **Copy:** Bahasa Indonesia, tanpa klaim berlebihan (mis. "THI mencapai batas bahaya (79,2). Pompa
   akan menyala bila mode otomatis aktif." — bukan "Pompa sudah menyala").

---

## 12. Panduan Push ke GitHub (untuk opencode)

Remote: `origin` → `https://github.com/masanuddin/SmartQuail.git`, branch utama `main`.
Commit terakhir di remote: `ba8ec39`. Working tree berisi banyak perubahan yang **belum di-commit**
(seluruh fase di §5).

### 12.1 WAJIB sebelum commit
1. **Pastikan file rahasia TIDAK ikut:**
   ```bash
   git check-ignore -v firmware/pitik_v8_4_d2d4/secrets.h   # harus ter-ignore
   git status --short | grep -i secrets                       # hanya secrets.example.h yang boleh muncul
   ```
   Jangan pernah `git add -f` file `secrets.h`.
2. **Pastikan artefak build tidak ikut:** `build/`, `android/build/`, `*.apk`,
   `firmware/tools/__pycache__/` (ter-ignore lewat `.gitignore`).
3. **Pindai pola kredensial** pada file yang akan di-commit (hasil yang wajar hanya
   `android/app/google-services.json` dan `lib/firebase_options.dart`, yang berisi Firebase client
   API key — memang bagian konfigurasi aplikasi):
   ```bash
   git ls-files -mo --exclude-standard -z | xargs -0 grep -lIE "AIza[0-9A-Za-z_-]{30,}" 2>/dev/null
   git ls-files -mo --exclude-standard -z | xargs -0 grep -nIE "WIFI_PASSWORD\s+\"" 2>/dev/null
   ```
   Baris `WIFI_PASSWORD` yang muncul **harus berupa placeholder** (`README.md`, `README_TERBARU.md`,
   `secrets.example.h`). Tidak boleh ada password Wi-Fi asli di file mana pun.
4. **Jalankan validasi:**
   ```bash
   flutter analyze && flutter test
   ```

### 12.2 Yang perlu di-commit
- `lib/`, `test/` (seluruh perubahan & file baru)
- `firmware/` (kecuali `secrets.h`)
- `android/` (konfigurasi, `google-services.json` terbaru, MainActivity `com/example/pitik_app/`), `ios/`, `macos/`, `linux/`, `windows/`, `web/` (perubahan rename proyek)
- `pubspec.yaml`, `.gitignore`, `.github/workflows/ci.yml`, `firebase.json`
- Dokumen: `DOKUMENTASI_PITIK.md`, `CLAUDE.md`, `PERUBAHAN_APP_FIRMWARE_v8.4.md`, `README.md`,
  `README_AI_CONTEXT.md`, `README_TERBARU.md`, `summary_pitik_konteks.md`
- `PITIK_redesign/` (ekspor desain & capture review, ±8 MB) — opsional, sesuai keputusan pemilik
- `assets/images/pitik.png`
- File terhapus (`esp32_smartquail.ino`, `esp32_smartquail_v9/`, `esp32_v9/`, `lib/services/api_service.dart`,
  `lib/services/history_service.dart`, MainActivity lama) ikut di-commit sebagai penghapusan.

### 12.3 Contoh urutan commit (disarankan beberapa commit terpisah)
```bash
git checkout -b feature/pitik-v1-redesign-firmware-v842   # atau langsung main sesuai keputusan pemilik

git add lib/models lib/services lib/utils test/models test/services test/utils test/helpers test/architecture_test.dart
git commit -m "feat(data): lapisan data sesuai kontrak firmware v8.4 (PitikRepository, DeviceState, model)"

git add lib/theme lib/widgets lib/screens lib/main.dart lib/main_preview.dart lib/preview test/screens test/widgets test/theme test/widget_test.dart assets
git commit -m "feat(ui): redesign Dashboard, Riwayat, Kontrol, Pengaturan + preview lokal"

git add firmware
git commit -m "fix(firmware): v8.4.2 — proses patch /controls dari app (D2) + telemetry state (D4)"

git add android ios macos linux windows web pubspec.yaml firebase.json .github .gitignore lib/firebase_options.dart
git commit -m "chore(app): rename ke pitik_app, google-services pitik-1ad2d dengan firebase_url"

git add DOKUMENTASI_PITIK.md CLAUDE.md PERUBAHAN_APP_FIRMWARE_v8.4.md README.md README_AI_CONTEXT.md README_TERBARU.md summary_pitik_konteks.md lib/README_PAPER.md
git commit -m "docs: dokumentasi lengkap PITIK v1.0.0 + firmware v8.4.2"

git add -A   # sisa (penghapusan file lama, PITIK_redesign bila disetujui) — periksa dulu git status!
git status
git commit -m "chore: hapus file lama & tambah aset desain"

git push -u origin <nama-branch>
```

### 12.4 Jangan dilakukan
- Commit/push `secrets.h`, keystore, file `.env`, atau APK.
- Menulis ulang riwayat git (force push) tanpa persetujuan pemilik.
- Deploy Firebase Rules / Functions sebagai bagian dari push ini.

---

## 13. Catatan Dokumen Lama yang Usang

| Dokumen | Bagian usang |
|---|---|
| `README.md` | Menjelaskan arsitektur & firmware lama (v5/v9, `api_service`), struktur project lama, changelog s/d v1.1.0. Disarankan menambahkan tautan ke dokumen ini di bagian atas. |
| `lib/README_PAPER.md` | Masih menyebut `api_service.dart`, `history_service.dart`, `fan_sent_at` yang sudah dihapus. |
| `PERUBAHAN_APP_FIRMWARE_v8.4.md` | Akurat untuk Fase 1; beberapa teks UI (mis. "Full Cool", "Beri Makan Sekarang", "Simpan ke Perangkat", snackbar reconnect) sudah diganti oleh redesign (lihat §2 & §5 dokumen ini). |
| `PITIK_redesign/review/batch_4/` | Capture dirender sebelum koreksi copy final (dicatat di README batch tersebut). |
