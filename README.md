<div align="center">
  <img src="assets/images/pitik.png" alt="PITIK Logo" width="120"/>

  # PITIK

  **Sistem Monitoring & Kontrol Kandang Burung Puyuh Berbasis IoT**

  [![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
  [![Firebase](https://img.shields.io/badge/Firebase-Realtime%20DB-FFCA28?style=flat-square&logo=firebase)](https://firebase.google.com)
  [![ESP32](https://img.shields.io/badge/ESP32-IoT%20Hardware-E7352C?style=flat-square&logo=espressif)](https://www.espressif.com)
  [![Dart](https://img.shields.io/badge/Dart-3.11-0175C2?style=flat-square&logo=dart)](https://dart.dev)
  [![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

  *Pantau suhu, kelembaban, dan kualitas udara kandang puyuhmu secara real-time dari mana saja.*

</div>

---

## Tentang PITIK

PITIK adalah aplikasi mobile berbasis Flutter yang terhubung langsung dengan perangkat ESP32 melalui Firebase Realtime Database. Aplikasi ini dirancang khusus untuk peternak burung puyuh agar dapat memantau dan mengontrol kondisi kandang secara remote -- mulai dari suhu, kelembaban, kadar amonia (NH₃), hingga kendali perangkat seperti kipas, pompa air, dan auto-feeder.

### Mengapa PITIK?

Burung puyuh sangat sensitif terhadap perubahan suhu dan kelembaban. THI (Temperature Humidity Index) di atas 78 dapat menyebabkan *heat stress* yang berujung pada penurunan produksi telur hingga kematian. PITIK hadir sebagai solusi monitoring cerdas yang memberikan **notifikasi real-time** dan **kontrol perangkat** untuk menjaga kondisi kandang tetap optimal.

---

## Fitur Utama

### Dashboard
- Monitoring real-time suhu, kelembaban, THI Index, dan kadar NH₃
- Status koneksi ESP32 (Online/Offline)
- Indikator zona bahaya berwarna (Normal / Warning / Danger)
- Custom THI gauge dengan animasi

### Riwayat Data
- Grafik interaktif suhu, kelembaban, dan THI Index
- Filter periode: 1 Jam, 24 Jam, 7 Hari, 30 Hari
- Zone annotation visual Normal/Warning/Danger pada grafik THI
- Statistik ringkasan (rata-rata, min, max, cooling events)

### Kontrol Perangkat
- Kontrol kipas ON/OFF manual
- Kontrol pompa air ON/OFF
- Auto-feeder trigger
- Quick Presets: Semua OFF, Kipas Saja, Full Cool
- Status real-time setiap perangkat

### Pengaturan
- Konfigurasi threshold THI (Normal, Warning, Danger) -- **tersimpan & diterapkan otomatis**
- Pengaturan notifikasi
- Manajemen akun + Logout
- Preferensi bahasa & tema

### Bantuan & Informasi
- Panduan koneksi ESP32
- Penjelasan indikator sensor
- Kebijakan Privasi

---

## Arsitektur Sistem

```
+-----------------+         +------------------+         +-----------------+
|   ESP32 Device  | --WiFi--+  Firebase RTDB   |<--------+  PITIK App |
|                 |         |                  |          |  (Flutter)      |
|  * DHT22        |         |  /sensor_data    |          |                 |
|  * MQ-135 (NH3) |         |  /controls       |          |  * Dashboard    |
|  * MOSFET PWM   |         |  /history        |          |  * History      |
|  * Relay Module |         |                  |          |  * Control      |
+-----------------+         +------------------+          +-----------------+
```

### Alur Data

```
ESP32 --write--> /sensor_data       (temperature, humidity, thi, ammonia, relay_fan, relay_pump, online)
ESP32 --write--> /history/YYYY-MM-DD/HH:MM/  (t: temp, h: hum, a: nh3, thi: thi, f: fan, p: pump)
App   --write--> /controls          (fan, pump, feed_now)  --> ESP32 reads & executes
App   --read---- /sensor_data, /history
```

---

## Struktur Project

```
SmartQuail/
├── lib/
│   ├── main.dart                    # Entry point, AuthWrapper, MainNavigation
│   ├── firebase_options.dart        # Konfigurasi Firebase
│   ├── models/
│   │   └── sensor_data.dart         # Unified SensorData model dengan fromMap()
│   ├── screens/
│   │   ├── splash_screen.dart       # Splash screen animasi
│   │   ├── login_screen.dart        # Login nomor telepon
│   │   ├── otp_screen.dart          # Verifikasi OTP
│   │   ├── dashboard_screen.dart    # Monitoring real-time
│   │   ├── history_screen.dart      # Grafik riwayat data
│   │   ├── control_screen.dart      # Kontrol perangkat manual
│   │   ├── settings_screen.dart     # Pengaturan + threshold (persist)
│   │   └── info_screen.dart         # Bantuan & kebijakan privasi
│   ├── services/
│   │   ├── api_service.dart         # Firebase CRUD + SensorData model
│   │   ├── auth_service.dart        # Firebase Auth (Phone + Anonymous)
│   │   └── history_service.dart     # History parsing & stats
│   └── widgets/
│       ├── auth_widgets.dart        # Apple-style form widgets
│       ├── kpi_card.dart            # KPI metric card widget
│       └── thi_gauge.dart           # Custom animated THI gauge
├── esp32_pitik.ino             # Arduino IDE sketch untuk ESP32
├── test/
│   ├── services/
│   │   ├── auth_service_test.dart   # 7 unit test formatPhoneNumber
│   │   └── history_service_test.dart # 6 unit test HistoryData.isValid
│   └── widget_test.dart             # 2 widget test
├── .github/workflows/
│   └── ci.yml                       # GitHub Actions CI
├── assets/
│   └── images/
│       └── pitik.png                # App logo
├── android/                         # Konfigurasi Android
├── ios/                             # Konfigurasi iOS
└── pubspec.yaml                     # Dependencies
```

---

## Tech Stack

| Layer | Teknologi |
|-------|-----------|
| **Mobile App** | Flutter 3.x + Dart 3.11 |
| **Database** | Firebase Realtime Database |
| **Autentikasi** | Firebase Authentication (Phone OTP + Anonymous) |
| **Crash Reporting** | Firebase Crashlytics |
| **Persistence** | SharedPreferences |
| **Charts** | fl_chart |
| **IoT Hardware** | ESP32 + DHT22 + MQ-135 |
| **CI/CD** | GitHub Actions |

---

## Cara Menjalankan (Flutter App)

### Prerequisites

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.11.0
- Android Studio / VS Code
- Akun Firebase

### Instalasi

1. **Clone repository**
   ```bash
   git clone https://github.com/masanuddin/SmartQuail.git
   cd SmartQuail
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Konfigurasi Firebase**
   - Buat project baru di [Firebase Console](https://console.firebase.google.com)
   - Aktifkan **Realtime Database**, **Authentication** (Phone), dan **Crashlytics**
   - Download `google-services.json` (Android) dan letakkan di `android/app/`
   - Download `GoogleService-Info.plist` (iOS) dan letakkan di `ios/Runner/`
   - Update `lib/firebase_options.dart` dengan konfigurasi projectmu

4. **Struktur Firebase RTDB**
   ```json
   {
     "sensor_data": {
       "temperature": 28.5,
       "humidity": 70.2,
       "thi": 74.1,
       "ammonia": 12.3,
       "relay_fan": false,
       "relay_pump": false,
       "online": true,
       "hour": 14,
       "minute": 30,
       "device_id": "ESP32-01"
     },
     "controls": {
       "fan": false,
       "pump": false,
       "feed_now": false
     },
      "history": {
        "2026-05-20": {
          "14:00": { "t": 28.0, "h": 65.0, "a": 15.0, "thi": 74.0, "f": 0, "p": 0, "ts": 1716199200 },
          "14:05": { "t": 28.2, "h": 64.5, "a": 14.8, "thi": 74.2, "f": 0, "p": 0, "ts": 1716199500 }
        }
      }
   }
   ```

5. **Jalankan aplikasi**
   ```bash
   flutter run
   ```

---

## Setup ESP32 (Arduino IDE)

Proyek ini memiliki **2 versi firmware ESP32**:

- **`esp32_pitik.ino` (v5)** — Versi awal, polling `/controls`, PWM fan, relay feeder
- **ESP32 v9** — Versi terbaru: stream-based controls, watchdog, exponential backoff, NTP primary (RTC opsional), Nextion LCD, servo feeder

### Hardware v5 (`esp32_pitik.ino`)

| Komponen | Pin ESP32 | Fungsi |
|----------|-----------|--------|
| DHT22 | GPIO 4 | Sensor suhu & kelembaban |
| MQ-135 | GPIO 34 (ADC) | Sensor gas amonia |
| MOSFET IRF520 | GPIO 25 (PWM) | Kontrol kecepatan kipas |
| Relay 1 | GPIO 26 | Kontrol pompa air |
| Relay 2 | GPIO 27 | Kontrol auto-feeder |

### Hardware v9 (rekomendasi terbaru)

| Komponen | Pin ESP32 | Fungsi |
|----------|-----------|--------|
| DHT22 | GPIO 4 | Sensor suhu & kelembaban |
| MQ-135 | GPIO 33 (ADC) | Sensor gas amonia |
| Relay Fan | GPIO 26 | Kontrol kipas (active-LOW) |
| Relay Pump | GPIO 27 | Kontrol pompa air (active-LOW) |
| Servo Feeder | GPIO 18 | Auto-feeder servo |
| Nextion LCD | GPIO 16 (RX), GPIO 17 (TX) | Display & kontrol lokal |
| RTC DS1307 | I2C (SDA/SCL) | Opsional — NTP sebagai primary time source |

**Perbedaan utama v9 vs v5:**
- ⚡ Stream `/controls` real-time, bukan polling
- 🛡️ Watchdog timer + exponential backoff Firebase
- 📡 Smart send: hanya kirim sensor data kalau berubah (hemat bandwidth)
- 🕐 NTP sebagai sumber waktu utama — RTC opsional (hindari kerusakan history seperti `2113-45-165`)
- 🖥️ Dukungan Nextion LCD untuk kontrol lokal
- 🍽️ Servo feeder + jadwal pakan 3x/hari otomatis

### Library Arduino IDE

Install via Library Manager:
1. **Firebase ESP32 Client** by Mobizt
2. **DHT sensor library** by Adafruit

**v9:**
1. **Firebase ESP32 Client** by Mobizt (stream)
2. **DHT sensor library** by Adafruit
3. **RTClib** by Adafruit (opsional)
4. **ESP32Servo** by Kevin Harrington

> Library `time.h` dan `esp_task_wdt.h` sudah built-in di ESP32 core.

### Konfigurasi

**v5 (`esp32_pitik.ino`):**
```cpp
#define WIFI_SSID       "nama_wifi_kamu"
#define WIFI_PASSWORD   "password_wifi_kamu"
#define FIREBASE_HOST   "pitik-1ad2d-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH   "your_database_secret"
```

**v9:**
```cpp
#define WIFI_SSID        "nama_wifi_kamu"
#define WIFI_PASSWORD    "password_wifi_kamu"
#define FIREBASE_HOST    "pitik-1ad2d-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_API_KEY "isi-web-api-key"
```
> v9 menggunakan API key + test mode auth, bukan legacy database secret.

### Alur Kerja ESP32

**v5 (polling):**
1. **Setup**: Konek WiFi -> Sync NTP -> Init Firebase -> Init sensor & aktuator
2. **Loop**: Poll `/controls` tiap iterasi -> Sensor tiap 5s -> History tiap 5 menit

**v9 (stream + smart send):**
1. **Setup**: Konek WiFi -> Sync NTP -> Init Firebase -> Start stream `/controls` -> Watchdog
2. **Loop**: Stream callback real-time `/controls` -> Sensor tiap 2s -> Smart send (kirim hanya kalau data berubah > threshold) -> History tiap 5 menit (validasi tanggal sebelum tulis) -> Reconnect exponential backoff

### Firebase Paths (ESP32)

| Path | Arah | Format Data |
|------|------|-------------|
| `/sensor_data` | ESP32 tulis | `{temperature, humidity, thi, ammonia, relay_fan, relay_pump, online, hour, minute, device_id}` |
| `/controls/fan` | ESP32 baca | `boolean` |
| `/controls/pump` | ESP32 baca | `boolean` |
| `/controls/feed_now` | ESP32 baca | `boolean` (one-shot, ESP32 reset ke false setelah eksekusi) |
| `/history/{date}/{time}` | ESP32 tulis | `{t, h, a, thi, f, p, ts}` — `ts` = epoch detik (fallback Flutter) |

**Catatan validasi history Flutter (`history_service.dart`):**
- `temperature`: 5.0 — 60.0 °C
- `humidity`: 5.0 — 100.0 %
- `thi`: -20.0 — 110.0 *(threshold rendah menerima THI dari kandang bersuhu dingin)*
- `timeKey`: format `HH:MM`. Jika rusak (RTC error), Flutter fallback ke field `ts` epoch.

---

## Changelog

### v1.1.0 (26 Jun 2026) — Fix History & ESP32 v9 Sync

| Komponen | Perubahan |
|----------|-----------|
| **Flutter** | Validasi THI: `> 40.0` → `> -20.0` — data THI rendah (22-30) tidak lagi difilter |
| **Flutter** | Fallback timeKey: jika `HH:MM` rusak (RTC error), parse dari field `ts` (epoch) |
| **ESP32 v9** | Ganti sumber waktu dari RTC DS1307 ke NTP (RTC opsional) |
| **ESP32 v9** | Tambah validasi tanggal di `saveHistory()` — cegah garbage date masuk Firebase |
| **ESP32 v9** | Tambah field `ts` (epoch timestamp) di node history sebagai fallback Flutter |
| **ESP32 v9** | Stream-based `/controls` (real-time), exponential backoff Firebase, watchdog timer |

> **Catatan:** ESP32 v9 menggunakan pin berbeda dari v5 di `esp32_pitik.ino` — cek bagian Setup ESP32 v9 di bawah.

---

## THI Index -- Panduan Zona

| Nilai THI | Status | Kondisi |
|-----------|--------|---------|
| < Normal Max | **Normal** | Kondisi optimal untuk puyuh |
| Normal Max - Warning Max | **Warning** | Perlu perhatian, aktifkan kipas |
| > Warning Max | **Danger** | Bahaya *heat stress*, tindakan segera |

> **Rumus THI:** `THI = T - 0.55 * (1 - RH/100) * (T - 14.5)`
> dimana T = suhu (°C) dan RH = kelembaban relatif (%)

> **Catatan:** Threshold Normal dan Warning dapat dikonfigurasi melalui halaman Pengaturan di aplikasi (default: Normal < 72, Warning < 78).

---

## Tim Pengembang

| Nama | Role |
|------|------|
| Ricky Rudiansyah | Mobile Developer (Flutter) |
| Marcellino Asanuddin | IoT & Hardware Engineer |
| Prof. Dr. Ir. Widodo Budiharto | Supervisor |

---

## Lisensi

Project ini menggunakan lisensi [MIT](LICENSE).

---

<div align="center">
  <sub>Dibuat dengan ❤️ untuk para peternak puyuh Indonesia</sub>
</div>
