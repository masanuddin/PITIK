# PITIK — Project Summary

## Identitas
- **Nama:** PITIK — IoT-Based Intelligent Climate Control System for Quail Farming
- **Institusi:** BINUS University, Jakarta
- **Developer:** Ricky Rudiansyah, Marcellino Asanuddin
- **Supervisor:** Prof. Dr. Ir. Widodo Budiharto
- **Tahun:** 2026
- **Versi:** 1.0.0

---

## Deskripsi Singkat (Elevator Pitch)
Sistem monitoring dan kontrol kandang burung puyuh berbasis IoT. Mendeteksi suhu, kelembaban, gas amonia, dan menghitung indeks THI (Temperature Humidity Index) secara real-time. ESP32 membaca sensor & mengontrol kipas/pompa/feeder otomatis, data dikirim ke Firebase cloud, ditampilkan di aplikasi Flutter mobile (Android/iOS).

---

## Hardware

| Komponen | Detail |
|---|---|
| **Microcontroller** | ESP32 DOIT DEVKIT |
| **Sensor Suhu & Kelembaban** | DHT22 (GPIO 4) |
| **Sensor Amonia** | MQ-135 (GPIO 33, analog) |
| **Aktuator Kipas** | Relay (GPIO 26) |
| **Aktuator Pompa Air** | Relay (GPIO 27, active-LOW) — untuk misting/cooling |
| **Aktuator Feeder** | Servo SG90 (GPIO 18) — auto-feeder 3x sehari |
| **Display Lokal** | Nextion LCD Touch Screen (RX 16, TX 17, 9600 baud) — menampilkan suhu, kelembaban, amonia, THI real-time langsung di kandang; dilengkapi tombol fisik untuk kontrol manual: kipas ON/OFF, pompa ON/OFF, dan beri pakan (debounce 300ms) |
| **RTC (cadangan)** | DS1307 (I2C) — backup waktu jika NTP gagal |
| **Sumber Waktu** | NTP server (GMT+7) sebagai primary |

---

## Software

| Layer | Teknologi |
|---|---|
| **Mobile App** | Flutter 3.x (Dart 3.11) — Android, iOS, Web, Desktop |
| **Cloud Backend** | Firebase Realtime Database (asia-southeast1) |
| **Authentication** | Firebase Phone Auth (OTP +62) + Anonymous Guest |
| **Local Storage** | SharedPreferences (threshold THI, preferensi) |
| **Chart Library** | fl_chart v1.2.0 |
| **Crash Reporting** | Firebase Crashlytics |
| **ESP32 Firmware** | C++ / Arduino IDE — Firebase ESP32 Client Library |
| **CI/CD** | GitHub Actions (analyze + test) |
| **Hardware Programming** | Arduino C++ (watchdog, state machine, NTP sync) |

---

## Arsitektur Data Flow

```
                                        ┌──────────────────────────────┐
                                        │        Firebase RTDB         │
                                        │  /sensor_data  /controls     │
                                        │  /history/{date}/{time}      │
                                        └──────┬──────────┬────────────┘
                     read /controls            │          │    read stream
              write /sensor_data + history     │          │    write /controls
                     ┌─────────────────────────┘          └──────────────┐
                     │                                                  │
┌──────────────┐    ┌┴──────┐                                  ┌────────┴─────┐
│ Nextion LCD  │    │ ESP32 │                                  │ Flutter App  │
│ Touch Screen │◄──▶│sensor │                                  │  Android     │
│ [27.5°C   ]  │UART│+aktor │                                  │  iOS / Web   │
│ [ 78% RH  ]  │9600│+WiFi  │                                  │  Monitor &   │
│ [ 12 ppm  ]  │    └┬──────┘                                  │  Kontrol     │
│ [ THI 74  ]  │     │                                          └──────────────┘
│ [FAN] [PUMP] │     │ read DHT22, MQ-135
│ [FEED NOW]   │     │ control Relay Kipas, Relay Pompa, Servo
└──────────────┘     │
          ┌──────────┼──────────┐
          │          │          │
     ┌────┴───┐ ┌───┴────┐ ┌───┴────┐
     │ DHT22  │ │ MQ-135 │ │ Relay  │
     │ Suhu & │ │ Amonia │ │ Kipas  │
     │ Kelemb.│ │ (NH3)  │ │ & Pompa│
     └────────┘ └────────┘ │ Servo  │
                           │ Feeder │
                           └────────┘
```

- **ESP32 → `/sensor_data`:** suhu, kelembaban, THI, amonia, status relay, online flag
- **App → `/controls`:** perintah fan ON/OFF, pump ON/OFF, feed_now trigger
- **ESP32 → `/history/{YYYY-MM-DD}/{HH:MM}`:** log 5-menit dengan 7 field (`t`, `h`, `a`, `thi`, `f`, `p`, `ts`)

**Komunikasi ESP32 ↔ Nextion LCD (Serial UART):**
```
┌──────────┐  Serial UART (9600 baud)  ┌──────────────┐
│  ESP32   │◄─────────────────────────▶│ Nextion LCD  │
│          │  ESP kirim: T, RH, NH3,   │  Touch Screen│
│          │  THI, status kipas/pompa  │              │
│          │  Nextion kirim: tombol    │ [ 27.5°C  ]  │
│          │  FAN/PUMP/FEED ditekan    │ [  78% RH ]  │
└──────────┘                           │ [ 12 ppm  ]  │
                                       │ [ THI 74  ]  │
                                       │ [FAN][PUMP]  │
                                       │ [FEED NOW]   │
                                       └──────────────┘
```

---

## Fitur Utama

1. **Dashboard Real-Time** — KPI cards (suhu, kelembaban, THI, amonia), THI gauge animasi semi-circular, status banner (Normal/Warning/Bahaya)
2. **Kontrol Jarak Jauh** — Toggle kipas & pompa, auto-feeder trigger, quick presets (Semua OFF / Kipas Saja / Full Cool)
3. **Riwayat & Analitik** — Grafik interaktif (fl_chart) untuk 1 jam / 24 jam / 7 hari / 30 hari, statistik rata-rata, min/max, cooling events, THI zone annotation
4. **Konfigurasi Threshold THI** — Slider di settings untuk atur batas Normal, Warning, Danger; disimpan lokal
5. **ESP32 Smart Logic (v9):**
   - Watchdog 10 detik (auto-restart jika hang)
   - Exponential backoff reconnect (1s → 60s max)
   - Smart send: hanya kirim data saat nilai berubah signifikan (±0.3°C, ±1% RH, ±1ppm)
   - NTP primary + RTC fallback → cegah corrupt timestamp
   - `onDisconnect` auto-offline: set `online: false` saat putus
   - Non-blocking feeder (state machine, bukan `delay()`)
   - Scheduled auto-feeding: 07:00, 12:00, 17:00 (configurable)
   - Nextion LCD Touch Screen: menampilkan data sensor real-time (suhu, kelembaban, amonia, THI) langsung di kandang tanpa perlu buka HP; tombol fisik FAN ON/OFF, PUMP ON/OFF, FEED NOW dengan debounce 300ms; kontrol dua arah — perubahan dari app atau Nextion langsung disinkronkan ke Firebase
6. **Auth System** — Login via SMS OTP (+62 Indonesia) atau mode tamu (anonymous)
7. **Alert Amonia** — Notifikasi in-app saat NH3 > 50 ppm
8. **Multi-platform** — Android (full), iOS/web/desktop (scaffolding ready)

---

## Rumus THI (Temperature Humidity Index)
```
THI = T - 0.55 × (1 - RH/100) × (T - 14.5)
```
- **T** = suhu (°C), **RH** = kelembaban relatif (%)
- **Normal:** THI < 72 | **Warning:** THI 72–78 | **Bahaya:** THI > 78

---

## Screenshot/Visual Aplikasi (untuk poster)

| Screen | Visual Utama |
|---|---|
| **Splash** | Logo PITIK + animasi fade/scale + loading indicator |
| **Login** | Phone input Apple-style + OTP 6-digit + "Lanjut sebagai Tamu" |
| **Dashboard** | 4 KPI cards grid, status banner warna, THI semi-circular gauge, relay indicator |
| **History** | 3 line charts (suhu, RH, THI) + zone annotation hijau/kuning/merah + statistik card |
| **Control** | Toggle switch fan/pump, chip sensor monitor, auto-feeder button, quick presets |
| **Settings** | User card, threshold slider, notification toggle, about dialog |

---

## Warna Brand / Design System

| Nama | Hex | Kegunaan |
|---|---|---|
| Primary Blue | `#007AFF` | iOS system blue, accent |
| Normal Green | `#34C759` | THI normal, online status |
| Warning Orange | `#FF9500` | THI warning, feeder button |
| Danger Red | `#FF3B30` | THI bahaya, error, logout |
| THI Purple | `#5856D6` | THI index gauge & chart |
| Background | `#F5F5F7` | Apple light gray background |
| Text | `#1D1D1F` | Primary text near-black |
| Secondary Text | `#8E8E93` | Labels, gray text |

**Desain:** Apple iOS Human Interface style, Material 3, rounded corners (radius 12–16), elevation shadows tipis.

---

## Status Saat Ini

| Platform | Status |
|---|---|
| **Android** | Full production-ready |
| **iOS** | Menunggu `GoogleService-Info.plist` |
| **Web** | Scaffolding ada, belum dikonfigurasi penuh |
| **Windows** | Scaffolding ada |
| **Linux** | Scaffolding ada |
| **macOS** | Scaffolding ada |
| **ESP32** | v9 firmware production-grade |
