# PITIK — Paper v1.2

**Sistem IoT Kontrol Iklim Kandang Puyuh Berbasis ESP32 & Firebase**

> Status: **SIAP UJI** — Semua 6 eksperimen paper siap dijalankan.
> Threshold THI sudah diseragamkan ke nilai paper (75/80) di firmware, Flutter, dan Firebase.

---

## 1. Identitas Proyek

| Aspek | Detail |
|-------|--------|
| **Nama** | PITIK — IoT-Based Intelligent Climate Control for Quail Farming |
| **Paper Target** | ICIC Express Letters (ICIC-EL) |
| **Institusi** | BINUS University, Jakarta |
| **Developer** | Ricky Rudiansyah (Flutter), Marcellino Asanuddin (ESP32/IoT) |
| **Supervisor** | Prof. Dr. Ir. Widodo Budiharto |
| **Versi Saat Ini** | Paper v1.2 (2026-07-10) |
| **Lisensi** | MIT |

---

## 2. Arsitektur Sistem

```
┌─────────────────┐     Firebase RTDB      ┌─────────────────┐
│   ESP32         │◄──────────────────────►│  Flutter App    │
│                 │  /sensor_data (write)  │  (Android/iOS)  │
│  ● DHT22        │  /controls   (stream)  │                 │
│  ● MQ-135       │  /history    (write)   │  ● Dashboard    │
│  ● Relay Fan    │  /heartbeat  (write)   │  ● History+CSV  │
│  ● Relay Pump   │  /system_log (write)   │  ● Control      │
│  ● Nextion LCD  │  /control_log(write)   │  ● Settings     │
│  ● RTC DS1307   │  /sync_log   (write)   │                 │
└─────────────────┘                        └─────────────────┘
```

**Data Flow:**
- ESP32 membaca DHT22 & MQ135 → kirim ke `/sensor_data` setiap 5 detik (smart send: hanya jika berubah ≥ threshold)
- ESP32 Stream `/controls` real-time → baca perintah fan/pump/feed/auto_mode/threshold
- ESP32 tulis `/history/{YYYY-MM-DD}/{HH:MM}` setiap 5 menit (validasi epoch + format)
- Flutter membaca `/sensor_data` dan `/controls` via Stream → update UI real-time
- Flutter menulis perintah ke `/controls` → ESP32 menerima via Stream callback

---

## 3. Hardware

| Komponen | Pin ESP32 | Fungsi |
|----------|-----------|--------|
| DHT22 | GPIO 4 | Suhu (°C) & Kelembaban (%) |
| MQ-135 | GPIO 33 (ADC) | Gas Amonia NH₃ (indikatif, mapping linear) |
| Relay Fan | GPIO 26 | Kipas (active-LOW: LOW=ON) |
| Relay Pump | GPIO 27 | Pompa misting (active-LOW) |
| Nextion LCD | RX 16, TX 17 | Display & kontrol lokal (9600 baud) |
| RTC DS1307 | I2C (SDA 21, SCL 22) | Backup waktu (opsional — NTP primary) |

---

## 4. Software Stack

| Layer | Teknologi | Versi |
|-------|-----------|-------|
| **Firmware** | Arduino C++ (ESP32) | Core **2.0.17** (WAJIB, bukan 3.x) |
| **Mobile** | Flutter (Dart) | 3.x / Dart 3.11 |
| **Database** | Firebase Realtime Database | `asia-southeast1` |
| **Auth** | Firebase Phone Auth (OTP) | +62 Indonesia |
| **Charts** | fl_chart | 1.2.0 |
| **Persistence** | SharedPreferences | 2.x |

**Library ESP32 (Arduino Library Manager):**
| Library | Author |
|---------|--------|
| Firebase ESP32 Client | Mobizt |
| DHT sensor library | Adafruit |
| RTClib | Adafruit |

> **KENAPA Core 2.0.17:** Firebase_ESP_Client (Mobizt) tidak kompatibel dengan ESP32 Arduino Core 3.x (BearSSL linker error).

---

## 5. THI Formula & Threshold (PENTING)

### 5.1 Formula THI (Fahrenheit Scale — sesuai literatur puyuh)

```cpp
THI = (1.8 × T + 32) - (0.55 - 0.0055 × RH) × (1.8 × T - 26)
```

- **T** = suhu (°C)
- **RH** = kelembaban relatif (%)
- Hasil: rentang **70–90** untuk kondisi kandang puyuh tropis

### 5.2 Threshold Auto Climate Control

| Parameter | Nilai | Path Firebase | Arti |
|-----------|-------|---------------|------|
| `thiNormalMax` | **75.0** | `/controls/thi_normal` | THI ≥ 75 → Fan ON |
| `thiDangerMax` | **80.0** | `/controls/thi_danger` | THI ≥ 80 → Fan + Pump ON |

### 5.3 Histeresis (anti-flapping)

| Transisi | Kondisi |
|----------|---------|
| Fan OFF → ON | THI ≥ `thiNormalMax` (75) |
| Fan ON → OFF | THI ≤ `thiNormalMax - 2` (73) |
| Pump OFF → ON | THI ≥ `thiDangerMax` (80) |
| Pump ON → OFF | THI ≤ `thiDangerMax - 3` (77) |

### 5.4 Alur Sinkronisasi Threshold

```
1. Flutter Settings Screen: slider thiNormal=75, thiDanger=80
2. User tap "Sync to ESP32" → PUT /controls/thi_normal=75, /controls/thi_danger=80
3. ESP32 streamCallback terima update → thiNormalMax=75.0, thiDangerMax=80.0
4. autoClimateControl() pakai nilai baru real-time (tanpa restart)
```

> **CATATAN:** Default threshold di Flutter (settings_screen.dart) sudah diseragamkan ke 75/80 per Paper v1.2.
> Sebelumnya ada bug: Flutter default=72/78, tapi paper mensyaratkan 75/80. **Sudah diperbaiki 10 Jul 2026.**

---

## 6. Firebase RTDB Structure

### Node yang ditulis ESP32:

```
/sensor_data            ← updateNode (path tetap, smart send)
{
  temperature, humidity, ammonia, thi,
  relay_fan, relay_pump, online,
  timestamp (epoch UTC), hour, minute, device_id, seq
}

/history/YYYY-MM-DD/HH:MM  ← setJSON (1x/5 menit)
{ t, h, a, thi, f, p, ts }

/heartbeat              ← updateNode (1x/menit)
{ uptime_s, wifi_rssi, free_heap, epoch }

/connection_status      ← updateNode (transisi WiFi)
{ status, downtime_s, disconnect_count, epoch, wifi_rssi }

/system_log             ← push (1x/boot)
{ reset_reason, boot_epoch }

/control_log            ← push (transisi auto-climate)
{ event, thi, fan, pump, epoch }

/sync_log/0 .. /sync_log/9   ← setJSON (ring buffer 10 entry)
{ dir, epoch, uptime_ms }

/test_log               ← push (hanya saat test_mode=true; flag manual via Firebase Console)
{ feature, result, detail, epoch }
```

### Node yang dibaca ESP32 via Stream:

```
/controls
{
  fan: bool, pump: bool, feed_now: bool,
  auto_mode: bool,
  thi_normal: 75,    ← fan ON threshold
  thi_danger: 80     ← pump ON threshold
}
```

### Node yang ditulis Flutter:

```
/controls/fan, /controls/pump        (perintah aktuator)
/controls/feed_now                   (trigger pakan)
/controls/auto_mode                  (toggle auto climate)
/controls/thi_normal, thi_danger     (threshold sync)
/controls/fan_sent_at                (timestamp Flutter → ESP32, path terpisah)
/controls/pump_sent_at               (timestamp Flutter → ESP32, path terpisah)
```

---

## 7. Panduan Setup

### 7.1 ESP32 Firmware

1. Buka Arduino IDE → Board Manager → install **ESP32 2.0.17**
2. Install library via Library Manager:
   - Firebase ESP32 Client (Mobizt)
   - DHT sensor library (Adafruit)
   - RTClib (Adafruit)
3. Buka `esp32_pitik_paper/esp32_pitik_paper.ino`
4. Sesuaikan konfigurasi:
   ```cpp
   #define WIFI_SSID     "nama_wifi"
   #define WIFI_PASSWORD "password_wifi"
   #define DEVICE_ID     "ESP32-01"
   ```
5. Upload ke ESP32 → buka Serial Monitor (115200 baud)
6. Pastikan log: `PITIK Paper v1.2 Ready!`

### 7.2 Flutter App

```bash
cd SmartQuail
flutter pub get
flutter run
```

**Firebase sudah dikonfigurasi** di `lib/firebase_options.dart` dan `android/app/google-services.json` (tidak perlu setup ulang kecuali ganti project).

### 7.3 Firebase Database (opsional — sudah ada)

Rules default (`public` untuk testing):
```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

---

## 8. Panduan 6 Eksperimen Paper

| # | Eksperimen | Firebase Node | Cara | Durasi |
|---|-----------|---------------|------|--------|
| **E1** | Functional Validation | `test_log` | Set test_mode=true manual via Console → jalankan semua fitur → hitung pass/fail | ~1 jam |
| **E2** | Sensor Accuracy | `sensor_data` + `history` | Bandingkan DHT22 vs thermometer referensi → ekspor CSV → hitung MAE/MAPE/RMSE | ~2 jam |
| **E3** | Auto Climate Control | `control_log` | auto_mode=ON → panaskan DHT22 → amati transisi fan/pump | ~1 jam |
| **E4** | Communication Reliability | `connection_status` + `heartbeat` | Matikan WiFi → catat downtime → amati reconnect | ~30 menit |
| **E5** | Dual Interface Sync | `sync_log` + `fan_sent_at` | Kirim perintah dari Flutter & Nextion → ukur delay antar interface | ~1 jam |
| **E6** | Long-Term Stability | `system_log` + `heartbeat` | Jalankan 3-7 hari → cek uptime, restart, memory | 3-7 hari |

> Detail lengkap setiap eksperimen: lihat `esp32_pitik_paper/README.md` § Panduan 6 Eksperimen.

---

## 9. Struktur File Project

```
SmartQuail/
├── README_TERBARU.md                        ← FILE INI
├── README_AI_CONTEXT.md                     ← Konteks untuk AI agent
├── esp32_pitik_paper/                  ★ FIRMWARE PAPER ★
│   ├── esp32_pitik_paper.ino           Firmware ESP32 Paper v1.2
│   └── README.md                            Dokumentasi firmware
├── lib/                                     ★ FLUTTER APP ★
│   ├── main.dart                            Entry point + Auth + Navigation
│   ├── firebase_options.dart                Konfigurasi Firebase
│   ├── README_PAPER.md                      Dokumen perubahan Flutter
│   ├── models/
│   │   └── sensor_data.dart                 Model SensorData
│   ├── services/
│   │   ├── api_service.dart                 Firebase CRUD + syncThresholds
│   │   ├── auth_service.dart                Firebase Auth (Phone OTP)
│   │   └── history_service.dart             History + CSV export
│   ├── screens/
│   │   ├── dashboard_screen.dart            Monitoring real-time
│   │   ├── history_screen.dart              Grafik + CSV export
│   │   ├── control_screen.dart              Kontrol + Auto/Test Mode
│   │   ├── settings_screen.dart             Threshold slider + Sync
│   │   ├── info_screen.dart                 Bantuan & Kebijakan
│   │   └── ... (login, otp, splash)
│   └── widgets/
│       ├── kpi_card.dart / thi_gauge.dart   Komponen UI
│       └── auth_widgets.dart                Form widget
├── esp32_pitik_v9/                     Firmware v9 lama (arsip)
├── PITIK_firmware_v1.2/                Firmware hybrid (arsip)
├── esp32_pitik.ino                     Firmware root-level lama
├── android/                                 Platform Android
│   └── app/google-services.json             Firebase config Android
├── pubspec.yaml                             Dependencies Flutter
└── firebase.json                            FlutterFire CLI config
```

---

## 10. Pinout Lengkap

```
ESP32 Dev Module
┌──────────────────────────────────────────┐
│                                          │
│  GPIO 4   ─── DHT22 (DATA)               │
│  GPIO 33  ─── MQ-135 (AOUT)              │
│  GPIO 26  ─── Relay Fan   (active-LOW)   │
│  GPIO 27  ─── Relay Pump  (active-LOW)   │
│  GPIO 16  ─── Nextion RX                 │
│  GPIO 17  ─── Nextion TX                 │
│  SDA 21   ─── RTC DS1307 SDA             │
│  SCL 22   ─── RTC DS1307 SCL             │
│  5V       ─── DHT22 VCC, MQ-135 VCC      │
│  GND      ─── Common Ground              │
│                                          │
└──────────────────────────────────────────┘
```

---

## 11. Warna Brand & Design System

| Nama | Hex | Kegunaan |
|------|-----|----------|
| Normal Green | `#34C759` | THI normal, online status, sukses |
| Warning Orange | `#FF9500` | THI warning |
| Danger Red | `#FF3B30` | THI danger, error, logout |
| Primary Blue | `#007AFF` | Accent iOS, tombol utama |
| Background | `#F5F5F7` | Latar abu-abu terang |
| Text Primary | `#1D1D1F` | Teks utama |
| Text Secondary | `#8E8E93` | Label, teks abu-abu |

---

## 12. Known Issues & Keterbatasan

| # | Issue | Dampak | Status |
|---|-------|--------|--------|
| 1 | MQ-135 mapping linear (`map(0,4095,0,100)`), bukan kurva kalibrasi | NH₃ indikatif, bukan absolut | Diterima — dicatat di paper |
| 2 | Tidak ada pin feedback relay | Response time aktuator tidak presisi | Diterima — asumsi <10ms |
| 3 | Clock skew ESP32 ↔ Flutter | Sync latency aproksimasi | Diterima — dicatat di paper |
| 4 | Self-write echo flag asumsi FIFO | Bisa salah atribusi di concurrent commands | Diterima — volume perintah rendah |
| 5 | ESP32 harus core 2.0.17 (bukan 3.x) | Tidak bisa pakai core terbaru | Keterbatasan library Mobizt |
| 6 | File Nextion .HMI tidak ada di repo | Tidak bisa verifikasi nama komponen | User sesuaikan manual |

---

## 13. Changelog

### Paper v1.2 (10 Jul 2026) — Threshold Fix

| Komponen | Perubahan |
|----------|-----------|
| **Flutter** | Default `thiNormal` 72.0 → **75.0**, `thiDanger` 78.0 → **80.0** di 3 lokasi (`settings_screen.dart`: inisialisasi, SharedPreferences fallback, tombol Reset) |
| **Firebase** | `/controls/thi_normal` 72 → **75**, `/controls/thi_danger` 78 → **80** (via REST API PUT, stored as number) |
| **Firmware** | Default `thiNormalMax=75.0`, `thiDangerMax=80.0` sudah benar sejak v1.1 — tidak berubah |
| **Paper** | Threshold Table 2: 75/80 — tetap sesuai literatur Eltarabany (2016) |

### Paper v1.1 (26 Jun 2026) — Instrumentasi Lengkap

- NTP primary + RTC fallback + seed systime
- Auto Climate Control berbasis THI dengan histeresis
- 6 node logging: test_log, connection_status, system_log, sync_log, control_log, heartbeat
- Flutter: autoMode toggle, CSV export, threshold sync
- Stream `/controls` real-time (bukan polling)
- Watchdog + exponential backoff
- Validasi format date/hour di saveHistory()

---

## 14. Referensi Paper

| Ref | Topik | DOI |
|-----|-------|-----|
| Eltarabany (2016) | THI thresholds quail (75 moderate, 80 high stress) | `10.1007/s00484-016-1175-2` |
| Çiftçi (2025) | Quail egg-laying & hatching under THI stress | — |
| Oliveira & Castro (2023) | Thermal comfort thresholds 68.4–76.2 | — |
| Flores (2025) | ESP32 environmental monitoring | — |
| Del Shi (2025) | ESP32 sensor integration | — |
| Sebald (2024) | Dual-interface HMI for farm equipment | — |
| Mutiara (2025) | Sensor fusion IoT livestock | — |
| Permana (2026) | Bidirectional sync literature review | — |

---

## 15. Tim

| Nama | Role | Kontak |
|------|------|--------|
| **Ricky Rudiansyah** | Mobile Developer (Flutter, Firebase) | — |
| **Marcellino Asanuddin** | IoT & Hardware Engineer (ESP32, Sensor) | — |
| **Prof. Dr. Ir. Widodo Budiharto** | Supervisor | BINUS University |

---

<div align="center">
  <sub>PITIK v1.2 — BINUS University © 2026</sub>
</div>
