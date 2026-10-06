# PITIK — AI Context Guide

**Last updated:** 2026-07-07 | **Codebase version:** Paper v1.1

> README ini adalah satu-satunya file yang perlu dibaca AI agent untuk memahami
> seluruh project PITIK. Setiap kali user memberi tugas baru, baca file ini
> dulu — semua konteks, struktur, keputusan arsitektur, dan issue yang diketahui
> sudah terdokumentasi di sini.

---

## 1. PROJECT OVERVIEW

| Aspek | Detail |
|-------|--------|
| **Nama** | PITIK |
| **Jenis** | IoT climate control untuk peternakan puyuh |
| **Tujuan** | Paper ilmiah ICIC Express Letters (ICIC-EL) — engineering validation |
| **BUKAN** | Bukan novel AI/ML, bukan product deployment |
| **Hardware** | ESP32, DHT22, MQ135, Relay (fan+pump), Servo (feeder), Nextion HMI, RTC DS1307 |
| **Software** | ESP32 firmware (Arduino C++), Flutter mobile app (Dart), Firebase RTDB |
| **Git repo** | `C:\Users\ASUS\Desktop\Project_Prof\SmartQuail` |
| **Branch** | `main` |

---

## 2. CURRENT STATE — Paper v1.1

### 2.1 Dua codebase utama

| Komponen | Path | File Utama | Status |
|----------|------|-----------|--------|
| **ESP32 Firmware** | `esp32_pitik_paper/` | `esp32_pitik_paper.ino` (1099 baris) | **SIAP** — semua instrumentasi untuk 6 eksperimen |
| **Flutter App** | `lib/` | 6 file dimodifikasi | **SIAP** — sent_at, autoMode, CSV export |
| **Paper LaTeX** | `C:\Users\ASUS\Downloads\smartquail_intro_relatedwork_2.tex` (747 baris) | Draft, bukan di dalam repo | Intro + Related Work + System Design + Methodology SELESAI; sisanya belum |

### 2.2 Apa yang sudah diubah dari versi sebelumnya

**ESP32 Paper v1.1** (dari v9.0 orisinal):
- NTP primary + RTC fallback (seed `settimeofday` -7 jam untuk UTC)
- Epoch Unix guard > 1.7e9 di semua field timestamp
- Validasi format date/hour di `saveHistory()`
- **Auto Climate Control** berbasis THI dengan histeresis + `autoMode` toggle
- 6 node logging: `test_log`, `connection_status`, `system_log`, `sync_log`, `control_log`, `heartbeat`
- Firebase call dipindahkan dari `streamCallback` ke `loop()` via `f2eSyncPending` flag
- Filter echo auto-control via `selfEchoFan`/`selfEchoPump` flag
- `packetSeq` global untuk data continuity
- Nextion display update (status relay + sensor)
- `esp_reset_reason()` di setup → `/system_log`
- Guard `rtcFromCompile` (baterai DS1307 mati + WiFi gagal)
- WDT safety: `esp_task_wdt_reset()` sebelum `setupFirebase()` di backoff

**Flutter Paper v1.1** (dari v1.0.0 orisinal):
- `api_service.dart`: `setFan/setPump` tulis `sent_at` di path terpisah + 2 metode baru (`setAutoMode`, `syncThresholds`)
- `control_screen.dart`: Auto Mode toggle + Test Mode toggle + parse threshold dari `/controls`
- `settings_screen.dart`: Opsi A (2 slider: 72/78) + tombol "Sync to ESP32" (disabled kalau offline)
- `dashboard_screen.dart`: Subscribe `/controls` untuk threshold dari ESP32
- `history_service.dart`: `toCsv()` static method
- `history_screen.dart`: Tombol export CSV → copy ke Clipboard (zero dependency)
- `lib/README_PAPER.md`: Dokumentasi lengkap perubahan Flutter

### 2.3 Yang TIDAK berubah

- `main.dart`, `auth_service.dart`, `sensor_data.dart`, `login_screen.dart`, `otp_screen.dart`, `splash_screen.dart`, `info_screen.dart`, semua widget (`kpi_card.dart`, `thi_gauge.dart`, `auth_widgets.dart`)
- Semua file platform (android/, ios/, web/, windows/, linux/, macos/)
- `pubspec.yaml`, `firebase.json`, `analysis_options.yaml`

---

## 3. FILE STRUCTURE (yang penting)

```
C:\Users\ASUS\Desktop\Project_Prof\SmartQuail\
├── esp32_pitik_paper/          ★ FIRMWARE PAPER ★
│   ├── esp32_pitik_paper.ino   (1099 baris, Paper v1.1)
│   └── README.md                    (dokumentasi firmware)
│
├── lib/                             ★ FLUTTER APP ★
│   ├── README_PAPER.md              (dokumentasi Flutter paper)
│   ├── main.dart
│   ├── firebase_options.dart
│   ├── models/
│   │   └── sensor_data.dart
│   ├── services/
│   │   ├── api_service.dart         [MODIFIED] sent_at + 3 metode baru
│   │   ├── auth_service.dart
│   │   └── history_service.dart     [MODIFIED] +toCsv()
│   ├── screens/
│   │   ├── control_screen.dart      [MODIFIED] +autoMode
│   │   ├── dashboard_screen.dart    [MODIFIED] baca /controls
│   │   ├── history_screen.dart      [MODIFIED] +CSV export
│   │   └── settings_screen.dart     [MODIFIED] 2 slider + sync
│   └── widgets/
│       ├── kpi_card.dart
│       └── thi_gauge.dart
│
├── esp32_pitik_v9/             (firmware produksi lama — v9.1)
├── esp32_pitik.ino             (firmware root-level lama)
├── backup_codes/                    (backup kode lama)
│
├── Paper LaTeX (di luar repo!):
│   C:\Users\ASUS\Downloads\smartquail_intro_relatedwork_2.tex
```

---

## 4. HARDWARE PINOUT

| Komponen | Pin ESP32 | Catatan |
|----------|-----------|---------|
| DHT22 | GPIO 4 | Suhu & kelembaban |
| MQ-135 | GPIO 33 (ADC) | Gas amonia (mapping linear, indikatif) |
| Relay Fan | GPIO 26 | Active-LOW (LOW = ON) |
| Relay Pump | GPIO 27 | Active-LOW |
| Servo Feeder | GPIO 18 | SG90, detach after use |
| Nextion HMI | RX 16, TX 17 | Baud 9600, UART |
| RTC DS1307 | I2C (SDA 21, SCL 22) | Backup waktu |

---

## 5. FIREBASE RTDB STRUCTURE

```
/sensor_data         ← ESP32: updateNode (temperatur, humidity, ammonia, thi, relay state, online, timestamp, seq)
/controls            ← Flutter write, ESP32 Stream read (fan, pump, feed_now, auto_mode, thi_normal, thi_danger)
/controls/fan_sent_at  ← Flutter: ServerValue.timestamp (PATH TERPISAH — jangan gabung ke /fan)
/controls/pump_sent_at ← Flutter: ServerValue.timestamp (PATH TERPISAH)
/history/YYYY-MM-DD/HH:MM  ← ESP32: setJSON 1x/5 menit
/heartbeat           ← ESP32: updateNode 1x/menit (uptime_s, wifi_rssi, free_heap)
/connection_status   ← ESP32: updateNode (state-change WiFi event)
/system_log          ← ESP32: push 1x/boot (reset_reason, boot_epoch)
/control_log         ← ESP32: push (auto-climate transitions)
/sync_log/0..9       ← ESP32: setJSON ring buffer 10 entry
/test_log            ← ESP32: push (gated by test_mode flag — flag manual via Firebase Console, toggle app dihapus)
```

---

## 6. KRITIS: THI FORMULA MISMATCH — PAPER vs FIRMWARE

### ⚠️ INI ISSUE PENTING — BACA SEBELUM MENGERJAKAN APAPUN TERKAIT E3

**Firmware** menggunakan formula Celsius:
```cpp
thi = temperature - 0.55 * (1.0 - humidity / 100.0) * (temperature - 14.5);
// Contoh: T=28°C, H=70% → THI = 25.8
```

**Paper LaTeX** menggunakan formula Fahrenheit:
```latex
THI = (1.8*T + 32) - (0.55 - 0.0055*RH)*(1.8*T - 26)
% Contoh: T=28°C, H=70% → THI = 78.4
```

**Dampak:** Kedua formula menghasilkan rentang nilai yang BERBEDA:
- Formula Celsius: THI ~20-35 (untuk kondisi kandang normal)
- Formula Fahrenheit: THI ~70-90

**Firmware default thresholds:** `thiNormalMax = 72.0`, `thiDangerMax = 78.0`
Ini adalah nilai Fahrenheit-scale. Dengan formula Celsius, THI tidak akan pernah mencapai 72. **Auto-climate control TIDAK AKAN PERNAH TRIGGER.**

**Paper thresholds:** `THI_normal = 75`, `THI_danger = 80` (juga Fahrenheit-scale)

### Yang harus diputuskan:

**Opsi A — Ganti formula firmware ke Fahrenheit:**
Ganti `readSensors()` baris ~570 agar sesuai dengan paper. Threshold bisa diseragamkan.
Pro: Konsisten dengan paper. Nilai THI sesuai literatur quail (70-80).
Con: Perlu kompilasi ulang firmware.

**Opsi B — Ganti threshold ke Celsius-scale:**
Turunkan threshold firmware ke range yang masuk akal untuk formula Celsius.
Misal: `thiNormalMax = 25.0`, `thiDangerMax = 28.0`. Paper juga disesuaikan.
Pro: Formula lebih sederhana.
Con: Paper harus diupdate. Tidak konsisten dengan mayoritas literatur yang pakai Fahrenheit scale.

**Opsi C — Paper akui perbedaan formula sebagai variasi implementasi:**
Paper tetap dengan Fahrenheit formula + threshold 75/80, firmware tetap Celsius dengan threshold yang dikalibrasi ulang. Di paper, sebutkan "THI values reported in this system follow the Celsius formulation, with thresholds calibrated to match the quail-specific stress limits identified in [eltarabany2016]."

**Rekomendasi:** Opsi A — paling bersih. Ganti formula firmware, seragamkan threshold, tidak perlu revisi paper besar.

---

## 7. KNOWN ISSUES & GOTCHAS

| # | Issue | Lokasi | Dampak | Status |
|---|-------|--------|--------|--------|
| 1 | **THI formula mismatch** (Celsius vs Fahrenheit) | Firmware baris 570 vs Paper LaTeX | Auto-climate tidak akan trigger dengan threshold saat ini | **BELUM DIPUTUSKAN** |
| 2 | Paper thresholds (75/80) vs firmware defaults (72/78) tidak match | Paper Table 2, firmware baris 193-194 | Nilai numerik berbeda, perlu diseragamkan | Turunan dari #1 |
| 3 | MQ-135 mapping linear, bukan kurva kalibrasi gas | Firmware baris 578 | Nilai amonia indikatif, bukan absolut | Diterima — sudah dicatat di paper |
| 4 | Tidak ada pin feedback relay | Firmware `applyFan/applyPump` | Response time aktuator tidak terukur presisi | Diterima — asumsi <10ms |
| 5 | Clock skew antara ESP32 (UTC) dan Flutter (ServerValue.timestamp) | `sync_log` | Sync latency aproksimasi, bukan angka presisi | Diterima — sudah dicatat |
| 6 | Self-write echo flag asumsi FIFO ordering | Firmware baris 228-229 | Bisa salah atribusi di bawah concurrent commands | Diterima — sudah dicatat |
| 7 | File project Nextion (.hmi/.tft) TIDAK ADA di repo | — | Tidak bisa verifikasi nama komponen Nextion | User harus sesuaikan manual |
| 8 | ESP32 harus core 2.0.17 (bukan 3.x) | Arduino Board Manager | Library Firebase_ESP_Client (Mobizt) tidak kompatibel dg 3.x | Done — sudah didokumentasikan |
| 9 | Belum di-compile / di-test secara fisik | Seluruh codebase | Bisa ada bug compile-time yang belum ketahuan | **TODO** |

---

## 8. EKSPERIMEN PAPER — STATUS READINESS

| Eksperimen | Status | Butuh Alat Eksternal | Catatan |
|-----------|--------|---------------------|---------|
| **E1** Functional Validation | ✅ Siap | Tidak | `test_log` node (set `test_mode` manual via Console) |
| **E2** Sensor Accuracy | ✅ Siap | **Ya** — thermometer referensi | CSV export via Flutter History Screen |
| **E3** Auto Climate Control | ⚠️ **TERGANTUNG #1** | Tidak | **THI formula mismatch — threshold tidak akan trigger** |
| **E4** Communication Reliability | ✅ Siap | Tidak | `connection_status` + `packetSeq` |
| **E5** Dual Interface Sync | ✅ Siap | Tidak | `sync_log` ring buffer + `fan_sent_at` |
| **E6** Long-Term Stability | ✅ Siap | Tidak | `system_log` + `heartbeat` |

---

## 9. TUGAS UMUM YANG MUNGKIN DIMINTA USER

### A. "Audit / cek kode"
- Baca file ini → baca file kode yang relevan → laporkan temuan
- Perhatikan Issue #1 (THI formula mismatch) sebagai temuan utama

### B. "Perbaiki bug / tambah fitur / ganti kode"
- **Selalu cek Issue #1 dulu** — jika terkait E3/THI/auto-climate, tanyakan keputusan Opsi A/B/C
- Firmware: edit `esp32_pitik_paper/esp32_pitik_paper.ino` (1099 baris)
- Flutter: edit file di `lib/` (api_service, control_screen, settings_screen, dashboard_screen, history_service, history_screen)
- JANGAN push ke GitHub kecuali user minta eksplisit

### C. "Buat / edit paper LaTeX"
- File di `C:\Users\ASUS\Downloads\smartquail_intro_relatedwork_2.tex` (747 baris)
- Style: IEEE/ICIC engineering paper, formal academic English
- Referensi TIDAK BOLEH difabrikasi — hanya pakai yang sudah ada di file
- JANGAN klaim data eksperimen yang belum dijalankan (Results masih kosong)
- Threshold THI di paper (75/80) mungkin perlu diupdate tergantung keputusan Issue #1

### D. "Update README / dokumentasi"
- Update file ini (`README_AI_CONTEXT.md`) jika ada perubahan signifikan
- ESP32: `esp32_pitik_paper/README.md`
- Flutter: `lib/README_PAPER.md`

### E. "Jelaskan cara kerja X"
- Firmware ESP32: baca file `.ino` + `esp32_pitik_paper/README.md`
- Flutter: baca `lib/README_PAPER.md` + file Dart terkait
- Firebase: lihat Section 5 di atas

---

## 10. DEPENDENCIES & ENVIRONMENT

### ESP32
```
Board: ESP32 Dev Module
Core:  2.0.17 (WAJIB — bukan 3.x)
Libraries:
  - Firebase ESP32 Client by Mobizt
  - DHT sensor library by Adafruit
  - RTClib by Adafruit
  - ESP32Servo by Kevin Harrington
```

### Flutter
```
SDK:   ^3.11.0
Key packages:
  - firebase_core: ^4.4.0
  - firebase_database: ^12.1.3
  - firebase_auth: ^6.1.4
  - fl_chart: ^1.2.0
  - shared_preferences: ^2.3.0
Platform: Android (primary), iOS, Web, Desktop
```

### Firebase
```
Project: pitik-1ad2d
Region:  asia-southeast1
RTDB URL: pitik-1ad2d-default-rtdb.asia-southeast1.firebasedatabase.app
```

---

## 11. KONVENSI KODE

- **ESP32:** Arduino C++, komentar campur Indonesia-Inggris, snake_case, `logMsg()` untuk semua log
- **Flutter:** Dart 3.x, komentar Indonesia, camelCase, widget-based
- **Komunikasi ESP32 ↔ Flutter:** Firebase RTDB Stream (bukan polling, bukan MQTT)
- **Timestamp internal:** UTC (epoch Unix), tampilan: WIB (GMT+7)
- **Jangan tambah dependency baru** di Flutter tanpa diskusi — pakai yang sudah ada

---

## 12. REFERENSI PAPER (sudah ada di .tex)

Semua referensi di file `.tex` adalah **referensi nyata dengan DOI** — jangan difabrikasi. Jika user minta tambah referensi, minta user yang provide; AI hanya boleh menyusun ulang, paraphrase, atau sintesis dari referensi yang sudah diberikan.

Referensi kunci (sudah di-paraphrase di Related Work):
- `eltarabany2016` — THI thresholds quail (75 moderate, 80 high stress)
- `ciftci2025` — quail egg-laying & hatching under THI stress
- `oliveiracastro2023` — thermal comfort thresholds 68.4-76.2
- `flores2025`, `delshi2025` — ESP32 environmental monitoring
- `sebald2024` — dual-interface HMI design for farm equipment
- `mutiara2025` — sensor fusion IoT livestock
- `permana2026` — bidirectional sync literature review (notes gap)
- `kostarev2022` — quail farm microclimate control
- `wardihani2025` — edge-cloud sync in agriculture

---

## 13. NEXT STEPS (rekomendasi untuk user)

1. **[KRITIS]** Putuskan Issue #1 — THI formula (Opsi A/B/C). Tanpa ini E3 tidak bisa dijalankan.
2. Compile ESP32 firmware di core 2.0.17 — pastikan tidak ada error
3. Compile Flutter app — pastikan tidak ada error
4. Uji skenario RTC kosong (opsional)
5. Jalankan E6 dulu (long-term, 3-7 hari) — bisa paralel dengan eksperimen lain
6. Siapkan thermometer referensi untuk E2
7. Lengkapi paper LaTeX: Section 5-8 (Experimental Setup, Results, Discussion, Conclusion)
