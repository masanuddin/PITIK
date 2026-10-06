// ============================================================
//  PITIK / SmartQuail v8.4.1 — ESP32-S3 (varian DHT22)
//  v8.4.1: stream /controls membedakan snapshot (put "/") dari update
//        sebagian (patch "/"). Perintah fan/pump/auto_mode dari app
//        (Flutter update(), termasuk preset atomik) kini dijalankan.
//        Snapshot tetap TIDAK memulihkan fan/pump/auto_mode (boot Manual).
//        Kebijakan: control_stream_policy.h (+ self-test static_assert).
//  v8.4: boot SELALU mode MANUAL + semua relay OFF (auto_mode tidak dipulihkan dari Firebase);
//        relay dikunci OFF di baris pertama setup(). Mode otomatis aktif lagi hanya dari app.
//  v8.3a: relay ACTIVE HIGH, DHT22 GPIO4, MQ-137 GPIO6, Nextion RX GPIO18
//  v8.3: relay tidak berkedip/ON saat boot, fan/pump TIDAK dipulihkan dari Firebase saat boot,
//        tombol Nextion kipas/pompa otomatis pindah ke mode MANUAL, log debug Nextion.
//  v8.2: sensor suhu/kelembapan SHT3X diganti DHT22, data di GPIO8
//  v8.1: tampilan Nextion desain v2 (dash/ctrl/set), kirim hanya saat berubah
//  Disesuaikan dengan: PITIK_Hardware_Source_of_Truth.md
//
//  Board   : ESP32S3 Dev Module (Arduino-ESP32 core 2.x atau 3.x)
//  Library : Firebase Arduino Client Library for ESP8266 and ESP32 (mobizt)
//            DHT sensor library (Adafruit) + Adafruit Unified Sensor
//            ESP32Servo
//
//  Perubahan dari v7:
//   - Sensor suhu/RH: DHT22 di GPIO4
//   - MQ-135 -> MQ-137 (GPIO6, lewat pembagi tegangan 10k/20k)
//   - RTC DS1307 DIHAPUS -> waktu hanya dari NTP
//   - Relay onboard: Fan GPIO47, Pump GPIO21 (polaritas bisa diatur)
//   - AutoFeeder GPIO5 (servo), dikunci sampai aktuator dikonfirmasi
//   - Nextion pakai HardwareSerial(1): RX GPIO18, TX GPIO17 (GPIO16 di shield rusak)
//   - Stream Firebase thread-safe (callback jalan di task lain)
//   - Semua tulis ke Firebase ditunda selama feeder bekerja
//   - Rumus THI diganti ke skala ~70-an agar cocok dengan ambang 72/78
// ============================================================

#include <WiFi.h>
#include <time.h>
#include <math.h>
#include <esp_task_wdt.h>
#include <Firebase_ESP_Client.h>
#include <DHT.h>
#include <ESP32Servo.h>
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>
#include "control_stream_policy.h"
#include "control_stream_policy_selftest.h"   // static_assert: gagal compile bila kebijakan berubah

// ============================================================
// KONFIGURASI JARINGAN
// (Jangan unggah file ini ke tempat publik — berisi password & API key)
// ============================================================
// Kredensial dipindah ke secrets.h (tidak di-commit) — lihat secrets.example.h.
// Mendefinisikan: WIFI_SSID, WIFI_PASSWORD, FIREBASE_API_KEY.
#include "secrets.h"
#define FIREBASE_HOST    "pitik-1ad2d-default-rtdb.asia-southeast1.firebasedatabase.app"
#define DEVICE_ID        "ESP32-01"
#define FW_VERSION       "8.4.1"

// ============================================================
// PIN — SESUAI DOKUMEN. Jangan diubah tanpa update dokumen.
// ============================================================
#define MQ137_AO_PIN     6    // ADC1 — dipindah dari GPIO4 (30-09-2026)
#define AUTOFEEDER_PIN   5
#define DHT_PIN          4    // DHT22 DATA (30-09-2026)
#define DHT_TYPE     DHT22
#define NEXTION_RX_PIN  18    // ke TX Nextion (GPIO16 di shield rusak, dipindah 30-09-2026)
#define NEXTION_TX_PIN  17    // ke RX Nextion
#define PUMP_RELAY_PIN  21    // Relay 2 onboard
#define FAN_RELAY_PIN   47    // Relay 1 onboard
#define NEXTION_BAUD  9600


// ============================================================
// SAKLAR KEAMANAN — baca sebelum mengubah!
// ============================================================
// 1) Uji relay TANPA beban dulu. Setelah polaritas pasti, set true.
#define ENABLE_RELAY_OUTPUTS true
// 2) true = relay nyala saat pin LOW; false = relay nyala saat pin HIGH.
#define RELAY_ACTIVE_LOW     false   // DIUJI 30-09-2026: shield ini ACTIVE HIGH (pin HIGH = relay ON)
// 3) true HANYA jika aktuator feeder = servo dengan catu daya terpisah.
//    Motor DC/stepper butuh driver & kode lain — jangan aktifkan.
#define ENABLE_SERVO_FEEDER  true

// Pembagi tegangan MQ-137: AO -> 10k -> GPIO6 -> 20k -> GND
// V_AO = V_pin * (10k + 20k) / 20k = V_pin * 1.5
#define MQ137_DIVIDER_RATIO  1.5f

// Cetak setiap byte yang diterima dari Nextion ke Serial Monitor (1 = aktif).
#define NEXTION_DEBUG        1

// ============================================================
// TIMING
// ============================================================
#define SENSOR_INTERVAL        2500UL   // DHT22 butuh >= 2 s antar-baca
#define FIREBASE_SEND_INTERVAL 5000UL
#define KEEPALIVE_INTERVAL     30000UL
#define HISTORY_INTERVAL       300000UL
#define WIFI_RETRY_INTERVAL    30000UL
#define AUTO_CHECK_INTERVAL    5000UL
#define NEXTION_COOLDOWN       300UL
#define STREAM_BACKOFF_MIN     1000UL
#define STREAM_BACKOFF_MAX     60000UL
#define FB_TIMEOUT_MS          8000     // < WDT agar request lambat tidak me-reset
#define WDT_TIMEOUT_S          30

// ============================================================
// FEEDER
// ============================================================
#define SERVO_CLOSED_ANGLE 90
#define SERVO_OPEN_ANGLE    0
#define FEEDER_SETTLE_MS  100UL
#define FEEDER_HOLD_MS   2000UL
#define FEEDER_CLOSE_MS   500UL

// ============================================================
// WAKTU (WIB, tanpa RTC)
// ============================================================
#define TZ_OFFSET_SEC   (7 * 3600)
#define EPOCH_VALID_MIN 1700000000L

// ============================================================
// AUTO CLIMATE — histeresis
// Fan : ON >= thiNormal,  OFF <= thiNormal - 2
// Pump: ON >= thiDanger,  OFF <= thiDanger - 3
// ============================================================
#define FAN_DEADBAND  2.0f
#define PUMP_DEADBAND 3.0f

#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
  #define WDT_CORE3
#endif

// ============================================================
// PATH FIREBASE
// ============================================================
#define PATH_SENSOR        "sensor_data"
#define PATH_CONTROLS      "controls"
#define PATH_HISTORY       "history"
#define PATH_CTRL_LOG      "control_log"
#define PATH_CTRL_FAN      "controls/fan"
#define PATH_CTRL_FANSPEED "controls/fan_speed"
#define PATH_CTRL_PUMP     "controls/pump"
#define PATH_CTRL_FEEDNOW  "controls/feed_now"
#define PATH_LAST_FEED     "sensor_data/last_feed"
#define PATH_LAST_FEED_TS  "sensor_data/last_feed_ts"

// ============================================================
// OBJEK
// ============================================================
DHT            dht(DHT_PIN, DHT_TYPE);
HardwareSerial nextionSerial(1);
Servo          feederServo;
FirebaseData   fbdo;
FirebaseData   stream;
FirebaseAuth   auth;
FirebaseConfig config;

// ============================================================
// STATE — SENSOR
// ============================================================
float temperature = NAN, humidity = NAN, thi = NAN;
int   dhtFailCount = 0;     // gagal baca berturut-turut
bool  sensorValid = false;
int   mq137Raw    = -1;      // ADC mentah 0..4095 — BUKAN ppm
float mq137Volt   = NAN;     // tegangan AO sebenarnya (sebelum pembagi)

// ============================================================
// STATE — AKTUATOR & KONTROL
// ============================================================
bool  fanState     = false;
bool  pumpState    = false;
bool  autoMode     = false;  // v8.4: boot SELALU MANUAL (semua OFF sampai user menekan tombol / mengaktifkan otomatis)
float thiNormalMax = 72.0f;
float thiDangerMax = 78.0f;

// ============================================================
// STATE — WAKTU
// ============================================================
bool   timeValid = false;
int    currentHour = 0, currentMinute = 0, currentSecond = 0;
String currentDate = "";

// ============================================================
// STATE — JADWAL FEEDER
// ============================================================
int    feedHour[3] = {7, 12, 17};
int    feedMin[3]  = {0, 0, 0};
bool   fedToday[3] = {false, false, false};
String lastFeedResetDate = "";

enum FeedState { FEED_IDLE, FEED_OPENING, FEED_HOLDING, FEED_CLOSING };
FeedState     feedState    = FEED_IDLE;
bool          isFeeding    = false;
unsigned long feedTimer    = 0;
String        feederSource = "manual";

// ============================================================
// STATE — KONEKSI & TIMING
// ============================================================
bool wifiConnected     = false;
bool firebaseConnected = false;
bool fbBegun           = false;
bool streamStarted     = false;
int  firebaseErrors    = 0;

unsigned long streamBackoff  = STREAM_BACKOFF_MIN;
unsigned long lastStreamTry  = 0;
unsigned long lastWifiRetry  = 0;
unsigned long lastSensorRead = 0;
unsigned long lastFbSend     = 0;
unsigned long lastHistory    = 0;
unsigned long lastFanCmd     = 0;
unsigned long lastPumpCmd    = 0;

// ============================================================
// ANTREAN TULIS KE FIREBASE
// Semua penulisan dilakukan di loop() lewat syncToFirebase(),
// dan DITUNDA selama feeder bekerja agar timing servo tidak molor.
// ============================================================
bool syncFan          = false;
bool syncPump         = false;
bool syncAuto         = false;
bool syncFeedNowReset = false;
bool syncLastFeed     = false;

struct CtrlLogEntry {
  bool        pending;
  const char *event;
  float       thi;
  bool        fan;
  bool        pump;
  long        epoch;
};
CtrlLogEntry ctrlLog = {};

// ============================================================
// PERINTAH DARI STREAM (ditulis task stream, dibaca loop)
// ============================================================
struct PendingCtl {
  bool  hasFan, fan;
  bool  hasPump, pump;
  bool  feedNow;
  bool  hasAuto, autoMode;
  bool  hasThiN; float thiN;
  bool  hasThiD; float thiD;
  bool  hasFeedH[3]; int feedH[3];
  bool  hasFeedM[3]; int feedM[3];
};
PendingCtl   pend   = {};

// Nilai dari Firebase yang sudah dinormalisasi.
// Didefinisikan di atas agar prototype otomatis Arduino IDE mengenal tipe ini.
struct Val { bool ok; bool b; int i; float f; };
portMUX_TYPE ctlMux = portMUX_INITIALIZER_UNLOCKED;

// ============================================================
// LOGGING
// ============================================================
void logMsg(const String &m) {
  if (timeValid)
    Serial.printf("[%02d:%02d:%02d] %s\n", currentHour, currentMinute, currentSecond, m.c_str());
  else
    Serial.printf("[+%lus] %s\n", millis() / 1000UL, m.c_str());
}

// ============================================================
// NEXTION — desain v2 (3 halaman: dash / ctrl / set)
// Semua komponen dinamis di HMI memakai vscope = global, sehingga
// bisa ditulis dari halaman mana pun dengan prefix nama halaman
// (mis. "dash.t0.txt") dan nilainya tetap saat pindah halaman.
// Hanya nilai yang BERUBAH yang dikirim (cache) agar UART 9600 tidak macet.
// ============================================================
void nextionSend(const String &cmd) {
  nextionSerial.print(cmd);
  nextionSerial.write(0xFF);
  nextionSerial.write(0xFF);
  nextionSerial.write(0xFF);
}

struct NxCache { const char *obj; String val; };
NxCache nxCache[40];
int     nxCacheN = 0;

// Kirim "obj=val" hanya bila berbeda dari yang terakhir dikirim.
void nxSet(const char *obj, const String &val, bool force) {
  int i = 0;
  for (; i < nxCacheN; i++) if (strcmp(nxCache[i].obj, obj) == 0) break;
  if (i < nxCacheN) {
    if (!force && nxCache[i].val == val) return;
    nxCache[i].val = val;
  } else if (nxCacheN < (int)(sizeof(nxCache) / sizeof(nxCache[0]))) {
    nxCache[nxCacheN++] = { obj, val };
  }
  nextionSend(String(obj) + "=" + val);
}
void nxTxt(const char *obj, const String &s) { nxSet(obj, "\"" + s + "\"", false); }
void nxNum(const char *obj, int v, bool force) { nxSet(obj, String(v), force); }

// Kosongkan cache (mis. tiap 60 dtk) agar layar yang di-reset sendiri terisi ulang.
void nxInvalidate() { nxCacheN = 0; }

// Dual-state button: bt0 = kipas, bt1 = pompa, bt2 = pakan (val 0/1).
void nextionUpdateButtons(bool force) {
  nxNum("ctrl.bt0.val", fanState  ? 1 : 0, force);
  nxNum("ctrl.bt1.val", pumpState ? 1 : 0, force);
  nxNum("ctrl.bt2.val", isFeeding ? 1 : 0, force);
}

String fmt2(int v) { return (v < 10 ? "0" : "") + String(v); }

// Dipanggil dari readSensors() tiap 2 s.
void nextionUpdateSensor() {
  static unsigned long lastFlush = 0;
  if (millis() - lastFlush >= 60000UL) { lastFlush = millis(); nxInvalidate(); }

  // --- Dashboard: nilai sensor (satuan sudah tergambar di latar) ---
  nxTxt("dash.t0.txt",   sensorValid ? String(temperature, 1) : String("--"));
  nxTxt("dash.h0.txt",   sensorValid ? String(humidity, 0)    : String("--"));
  nxTxt("dash.thi0.txt", sensorValid ? String(thi, 1)         : String("--"));
  nxTxt("dash.tThi.txt", sensorValid ? String(thi, 1)         : String("--"));
  nxTxt("dash.nh3.txt",  String(mq137Raw));   // ADC mentah, BUKAN ppm

  // --- Banner status: picc 0 = hijau, 1 = oranye, 2 = merah ---
  int    lvl;
  String st;
  if (!sensorValid) {
    lvl = 1; st = "SENSOR ERROR - cek DHT22";
  } else if (thi >= thiDangerMax) {
    lvl = 2; st = String("BAHAYA - pompa ") + (pumpState ? "menyala" : "mati");
  } else if (thi >= thiNormalMax) {
    lvl = 1; st = String("WASPADA - kipas ") + (fanState ? "menyala" : "mati");
  } else {
    lvl = 0; st = (fanState || pumpState) ? "NORMAL - pendinginan berjalan" : "NORMAL - standby";
  }
  // tStat menutupi seluruh banner (x16..668) & tThi (668..784): keduanya ikut berganti warna.
  // 9 spasi di depan = ruang untuk titik status di gambar latar.
  nxNum("dash.tStat.picc", lvl, false);
  nxNum("dash.tThi.picc",  lvl, false);
  nxTxt("dash.tStat.txt", "         " + st);

  // --- Header di tiap halaman ---
  String net = !wifiConnected ? "Offline" : (firebaseConnected ? "Online" : "Wi-Fi");
  String jam = timeValid ? fmt2(currentHour) + ":" + fmt2(currentMinute) : String("--:--");
  nxTxt("dash.tWifi.txt", net);  nxTxt("dash.tJam.txt", jam);
  nxTxt("ctrl.tWifi.txt", net);  nxTxt("ctrl.tJam.txt", jam);
  nxTxt("set.tWifi.txt",  net);  nxTxt("set.tJam.txt",  jam);

  // --- Halaman Kontrol ---
  nxTxt("ctrl.tMode.txt", autoMode ? "OTOMATIS" : "MANUAL");
  String lock;
  if (!ENABLE_RELAY_OUTPUTS && !ENABLE_SERVO_FEEDER) lock = "Relay & feeder dikunci firmware";
  else if (!ENABLE_RELAY_OUTPUTS) lock = "Relay dikunci firmware";
  else if (!ENABLE_SERVO_FEEDER)  lock = "Feeder dikunci firmware";
  else lock = autoMode ? "Manual bisa ditimpa mode otomatis" : "Semua aktuator aktif";
  nxTxt("ctrl.tLock.txt", lock);
  nextionUpdateButtons(false);

  // --- Halaman Setting (hanya tampil) ---
  nxTxt("set.tTn.txt",    String(thiNormalMax, 1));
  nxTxt("set.tTd.txt",    String(thiDangerMax, 1));
  nxTxt("set.tMode2.txt", autoMode ? "Otomatis" : "Manual");
  nxTxt("set.tF1.txt",    fmt2(feedHour[0]) + ":" + fmt2(feedMin[0]) + (fedToday[0] ? " OK" : ""));
  nxTxt("set.tF2.txt",    fmt2(feedHour[1]) + ":" + fmt2(feedMin[1]) + (fedToday[1] ? " OK" : ""));
  nxTxt("set.tF3.txt",    fmt2(feedHour[2]) + ":" + fmt2(feedMin[2]) + (fedToday[2] ? " OK" : ""));
  nxTxt("set.tSsid.txt",  wifiConnected ? String(WiFi.SSID() + " (" + String(WiFi.RSSI()) + " dBm)") : String("Tidak terhubung"));
  nxTxt("set.tIp.txt",    wifiConnected ? WiFi.localIP().toString() : String("-"));
  nxTxt("set.tCloud.txt", firebaseConnected ? "Terhubung" : "Terputus");
  nxTxt("set.tFw.txt",    "v" FW_VERSION);
  unsigned long up = millis() / 60000UL;
  nxTxt("set.tUp.txt",    String(up / 1440UL) + "h " + String((up / 60UL) % 24UL) + "j " + String(up % 60UL) + "m");
  nxTxt("set.tLock2.txt", String(ENABLE_RELAY_OUTPUTS ? "Aktif" : "Dikunci") + " / " +
                          (ENABLE_SERVO_FEEDER ? "Aktif" : "Dikunci"));
}

// ============================================================
// RELAY
// ============================================================
void writeRelay(uint8_t pin, bool on) {
  if (!ENABLE_RELAY_OUTPUTS) return;
  digitalWrite(pin, (on != RELAY_ACTIVE_LOW) ? HIGH : LOW);
}

// Hanya hardware + tampilan. Return false jika ditolak pengaman.
bool applyFan(bool on) {
  if (on && !ENABLE_RELAY_OUTPUTS) {
    logMsg("[Safety] Fan ON ditolak: ENABLE_RELAY_OUTPUTS = false");
    return false;
  }
  fanState = on;
  writeRelay(FAN_RELAY_PIN, on);
  nextionUpdateButtons(false);
  return true;
}

bool applyPump(bool on) {
  if (on && !ENABLE_RELAY_OUTPUTS) {
    logMsg("[Safety] Pump ON ditolak: ENABLE_RELAY_OUTPUTS = false");
    return false;
  }
  pumpState = on;
  writeRelay(PUMP_RELAY_PIN, on);
  nextionUpdateButtons(false);
  return true;
}

// Perubahan dari sumber lokal (Nextion / auto): apply + antre sync ke Firebase.
void setFan(bool on) {
  if (on == fanState) return;
  if (applyFan(on)) {
    logMsg(String("[Fan] ") + (on ? "ON" : "OFF"));
    syncFan = true;
  }
}

void setPump(bool on) {
  if (on == pumpState) return;
  if (applyPump(on)) {
    logMsg(String("[Pump] ") + (on ? "ON" : "OFF"));
    syncPump = true;
  }
}

// ============================================================
// FEEDER — NON-BLOCKING
// idle 90° -> buka 0° -> tahan -> tutup 90° -> detach
// ============================================================
bool startFeeder(const String &source) {
  if (!ENABLE_SERVO_FEEDER) {
    logMsg("[Safety] Feed ditolak: ENABLE_SERVO_FEEDER = false");
    return false;
  }
  if (isFeeding) return false;
  isFeeding    = true;
  feederSource = source;
  feederServo.attach(AUTOFEEDER_PIN, 500, 2400);
  feedState = FEED_OPENING;
  feedTimer = millis();
  logMsg("[Feeder] Aktivasi (" + source + ")");
  return true;
}

void updateFeeder() {
  if (!isFeeding) return;
  unsigned long now = millis();
  switch (feedState) {
    case FEED_OPENING:
      if (now - feedTimer >= FEEDER_SETTLE_MS) {
        feederServo.write(SERVO_OPEN_ANGLE);
        feedState = FEED_HOLDING;
        feedTimer = now;
      }
      break;
    case FEED_HOLDING:
      if (now - feedTimer >= FEEDER_HOLD_MS) {
        feederServo.write(SERVO_CLOSED_ANGLE);
        feedState = FEED_CLOSING;
        feedTimer = now;
      }
      break;
    case FEED_CLOSING:
      if (now - feedTimer >= FEEDER_CLOSE_MS) {
        feederServo.detach();
        feedState    = FEED_IDLE;
        isFeeding    = false;
        syncLastFeed = true;
        nextionUpdateButtons(false);
        logMsg("[Feeder] Selesai");
      }
      break;
    default:
      break;
  }
}

void checkFeederSchedule() {
  if (!timeValid || !ENABLE_SERVO_FEEDER) return;

  if (currentDate != lastFeedResetDate) {
    for (int i = 0; i < 3; i++) fedToday[i] = false;
    lastFeedResetDate = currentDate;
  }

  for (int i = 0; i < 3; i++) {
    if (fedToday[i]) continue;
    if (currentHour != feedHour[i] || currentMinute != feedMin[i]) continue;
    char label[8];
    snprintf(label, sizeof(label), "%02d:%02d", feedHour[i], feedMin[i]);
    // Jika feeder sedang sibuk, dicoba lagi di iterasi berikutnya (masih menit yang sama).
    if (startFeeder(label)) {
      fedToday[i] = true;
      logMsg("[Feeder] Jadwal " + String(i + 1));
    }
  }
}

// ============================================================
// NEXTION — PERINTAH 1 KARAKTER (dikirim event Touch Release di HMI)
// 1=FAN ON  2=FAN OFF  3=PUMP ON  4=PUMP OFF  5=FEED
// Catatan: matikan "Send Component ID" di Nextion Editor agar
// byte touch-event tidak terbaca sebagai perintah.
// ============================================================
// Tombol manual di Nextion = pengguna ingin kendali manual.
// Matikan mode otomatis agar tidak ditimpa Auto Climate dalam 5 detik.
void nextionTakeManual() {
  if (!autoMode) return;
  autoMode = false;
  syncAuto = true;
  logMsg("[Nextion] Tombol manual ditekan -> mode MANUAL (auto_mode = false)");
}

void readNextionCommands() {
  bool touched = false;
  while (nextionSerial.available()) {
    uint8_t c = nextionSerial.read();
#if NEXTION_DEBUG
    Serial.printf("[NX RX] 0x%02X '%c'\n", c, (c >= 32 && c < 127) ? c : '.');
#endif
    unsigned long now = millis();
    switch (c) {
      case '1':
        if (now - lastFanCmd >= NEXTION_COOLDOWN)  { lastFanCmd = now;  nextionTakeManual(); setFan(true);  }
        touched = true; break;
      case '2':
        if (now - lastFanCmd >= NEXTION_COOLDOWN)  { lastFanCmd = now;  nextionTakeManual(); setFan(false); }
        touched = true; break;
      case '3':
        if (now - lastPumpCmd >= NEXTION_COOLDOWN) { lastPumpCmd = now; nextionTakeManual(); setPump(true);  }
        touched = true; break;
      case '4':
        if (now - lastPumpCmd >= NEXTION_COOLDOWN) { lastPumpCmd = now; nextionTakeManual(); setPump(false); }
        touched = true; break;
      case '5':
        startFeeder("nextion");
        touched = true; break;
      default:
        break;   // abaikan byte lain (0xFF, kode balasan Nextion, dll.)
    }
  }
  // Tombol dual-state sudah berganti sendiri di layar saat disentuh.
  // Paksa kirim status ASLI agar tombol kembali bila perintah ditolak.
  if (touched) nextionUpdateButtons(true);
}

// ============================================================
// STREAM /controls
// PENTING: callback ini berjalan di task FreeRTOS terpisah.
// Di sini HANYA mem-parse dan menyimpan ke `pend`; eksekusi di loop().
// ============================================================

Val valFromJson(FirebaseJson &j, const char *key) {
  Val v = {};
  FirebaseJsonData d;
  if (!j.get(d, key) || !d.success) return v;
  v.ok = true;
  if (d.type == "boolean") {
    v.b = d.boolValue;
    v.f = v.b ? 1.0f : 0.0f;
  } else if (d.type == "int" || d.type == "float" || d.type == "double") {
    v.f = (float)d.doubleValue;
    v.b = (v.f != 0.0f);
  } else if (d.type == "string") {
    v.b = d.stringValue.equalsIgnoreCase("true") || d.stringValue == "1";
    v.f = v.b ? 1.0f : d.stringValue.toFloat();
  } else {
    v.ok = false;
  }
  v.i = (int)lroundf(v.f);
  return v;
}

Val valFromStream(FirebaseStream &s) {
  Val v = {};
  String t = s.dataType();
  v.ok = true;
  if (t == "boolean")      { v.b = s.boolData(); v.f = v.b ? 1.0f : 0.0f; }
  else if (t == "int")     { v.f = (float)s.intData(); }
  else if (t == "float")   { v.f = s.floatData(); }
  else if (t == "double")  { v.f = (float)s.doubleData(); }
  else if (t == "string")  {
    String str = s.stringData();
    v.b = str.equalsIgnoreCase("true") || str == "1";
    v.f = v.b ? 1.0f : str.toFloat();
  }
  else { v.ok = false; }   // null / json / tipe lain diabaikan
  if (t != "boolean" && t != "string") v.b = (v.f != 0.0f);
  v.i = (int)lroundf(v.f);
  return v;
}

void parseControlKey(const String &key, const Val &v, PendingCtl &p) {
  if (!v.ok) return;
  if      (key == "fan")        { p.hasFan  = true; p.fan  = v.b; }
  else if (key == "pump")       { p.hasPump = true; p.pump = v.b; }
  else if (key == "feed_now")   { if (v.b) p.feedNow = true; }
  else if (key == "auto_mode")  { p.hasAuto = true; p.autoMode = v.b; }
  else if (key == "thi_normal") { p.hasThiN = true; p.thiN = v.f; }
  else if (key == "thi_danger") { p.hasThiD = true; p.thiD = v.f; }
  else if (key.startsWith("feed_hour") && key.length() == 10) {
    int i = key[9] - '1';
    if (i >= 0 && i < 3) { p.hasFeedH[i] = true; p.feedH[i] = v.i; }
  }
  else if (key.startsWith("feed_min") && key.length() == 9) {
    int i = key[8] - '1';
    if (i >= 0 && i < 3) { p.hasFeedM[i] = true; p.feedM[i] = v.i; }
  }
  // fan_speed & key lain diabaikan
}

void mergePending(const PendingCtl &s) {
  portENTER_CRITICAL(&ctlMux);
  if (s.hasFan)  { pend.hasFan  = true; pend.fan  = s.fan;  }
  if (s.hasPump) { pend.hasPump = true; pend.pump = s.pump; }
  if (s.feedNow) { pend.feedNow = true; }
  if (s.hasAuto) { pend.hasAuto = true; pend.autoMode = s.autoMode; }
  if (s.hasThiN) { pend.hasThiN = true; pend.thiN = s.thiN; }
  if (s.hasThiD) { pend.hasThiD = true; pend.thiD = s.thiD; }
  for (int i = 0; i < 3; i++) {
    if (s.hasFeedH[i]) { pend.hasFeedH[i] = true; pend.feedH[i] = s.feedH[i]; }
    if (s.hasFeedM[i]) { pend.hasFeedM[i] = true; pend.feedM[i] = s.feedM[i]; }
  }
  portEXIT_CRITICAL(&ctlMux);
}

static const char *CONTROL_KEYS[] = {
  "fan", "pump", "feed_now", "auto_mode", "thi_normal", "thi_danger",
  "feed_hour1", "feed_min1", "feed_hour2", "feed_min2", "feed_hour3", "feed_min3"
};

void streamCallback(FirebaseStream data) {
  PendingCtl p = {};
  String path = data.dataPath();
  if (path == "/") {
    if (data.dataType() != "json") return;
    // v8.4.1: bedakan jenis event di root (lihat control_stream_policy.h).
    //  - put "/"   = snapshot penuh (stream baru / reconnect): JANGAN pulihkan
    //                fan, pump & auto_mode dari nilai lama di Firebase, supaya
    //                relay tidak menyala sendiri saat ESP32 baru hidup
    //                (boot Manual + relay OFF). Hanya pengaturan yang dipakai.
    //  - patch "/" = update() dari app (mis. preset kipas+pompa atomik):
    //                semua kunci yang ADA di payload diproses.
    const pitik::RootEvent ev = pitik::classifyRootEvent(data.eventType().c_str());
    if (ev == pitik::RootEvent::Ignore) return;
    FirebaseJson &j = data.jsonObject();
    for (const char *k : CONTROL_KEYS) {
      if (!pitik::rootKeyApplies(ev, k)) continue;
      parseControlKey(k, valFromJson(j, k), p);   // kunci yang tidak ada → !ok → diabaikan
    }
  } else {
    parseControlKey(path.substring(1), valFromStream(data), p);
  }
  mergePending(p);
}

void streamTimeoutCallback(bool timeout) {
  // Library akan melanjutkan stream otomatis setelah timeout.
  if (timeout) Serial.println("[Stream] timeout, auto-resume...");
}

// Eksekusi perintah dari app — dipanggil di loop().
void processPendingControls() {
  PendingCtl p;
  portENTER_CRITICAL(&ctlMux);
  p    = pend;
  pend = PendingCtl{};
  portEXIT_CRITICAL(&ctlMux);

  if (p.hasFan && p.fan != fanState) {
    if (applyFan(p.fan)) logMsg(String("[App] Fan ") + (p.fan ? "ON" : "OFF"));
    else syncFan = true;   // ditolak -> kembalikan status asli ke app
  }
  if (p.hasPump && p.pump != pumpState) {
    if (applyPump(p.pump)) logMsg(String("[App] Pump ") + (p.pump ? "ON" : "OFF"));
    else syncPump = true;
  }

  if (p.hasAuto && p.autoMode != autoMode) {
    autoMode = p.autoMode;
    logMsg(String("[App] Auto mode ") + (autoMode ? "ON" : "OFF"));
  }

  if (p.hasThiN || p.hasThiD) {
    float n = p.hasThiN ? p.thiN : thiNormalMax;
    float d = p.hasThiD ? p.thiD : thiDangerMax;
    if (n >= 50.0f && d <= 100.0f && n < d) {
      thiNormalMax = n;
      thiDangerMax = d;
      logMsg("[App] THI normal=" + String(n, 1) + " danger=" + String(d, 1));
    } else {
      logMsg("[App] THI ditolak (normal harus < danger, rentang 50-100)");
    }
  }

  int nowMin = currentHour * 60 + currentMinute;
  for (int i = 0; i < 3; i++) {
    bool changed = false;
    if (p.hasFeedH[i]) {
      if (p.feedH[i] >= 0 && p.feedH[i] <= 23) { feedHour[i] = p.feedH[i]; changed = true; }
      else logMsg("[App] feed_hour" + String(i + 1) + " di luar 0-23, diabaikan");
    }
    if (p.hasFeedM[i]) {
      if (p.feedM[i] >= 0 && p.feedM[i] <= 59) { feedMin[i] = p.feedM[i]; changed = true; }
      else logMsg("[App] feed_min" + String(i + 1) + " di luar 0-59, diabaikan");
    }
    // Jadwal digeser ke jam yang belum lewat hari ini -> izinkan jalan lagi.
    if (changed && timeValid && feedHour[i] * 60 + feedMin[i] > nowMin) fedToday[i] = false;
  }

  if (p.feedNow) {
    startFeeder("app");
    syncFeedNowReset = true;   // selalu reset flag, meski feed ditolak
  }
}

// ============================================================
// SENSOR
// ============================================================
void readSensors() {
  // DHT22: maksimal 1 pembacaan tiap 2 detik (SENSOR_INTERVAL = 2500 ms).
  float h = dht.readHumidity();
  float t = dht.readTemperature();          // °C

  if (isfinite(t) && isfinite(h) && h >= 0.0f && h <= 100.0f && t > -40.0f && t < 80.0f) {
    temperature  = t;
    humidity     = h;
    // THI (NRC 1971, input °C) — skala ~70-an, cocok dengan ambang 72/78.
    thi          = 0.8f * t + (h / 100.0f) * (t - 14.4f) + 46.4f;
    sensorValid  = true;
    dhtFailCount = 0;
  } else {
    dhtFailCount++;
    // DHT22 kadang gagal 1x (checksum). Nilai lama dipakai sampai 3x gagal berturut-turut.
    if (dhtFailCount >= 3) {
      sensorValid = false;
      logMsg("[DHT22] Gagal baca " + String(dhtFailCount) + "x — cek kabel GPIO4 & pull-up 10k. Auto ditahan");
    } else {
      logMsg("[DHT22] Gagal baca sekali, pakai nilai sebelumnya");
    }
  }

  mq137Raw  = analogRead(MQ137_AO_PIN);
  mq137Volt = analogReadMilliVolts(MQ137_AO_PIN) * MQ137_DIVIDER_RATIO / 1000.0f;

  nextionUpdateSensor();

  if (sensorValid) {
    char buf[112];
    snprintf(buf, sizeof(buf),
             "[Sensor] T=%.1f H=%.0f THI=%.1f MQ137_ADC=%d (%.2fV, bukan ppm)",
             temperature, humidity, thi, mq137Raw, mq137Volt);
    logMsg(buf);
  }
}

// ============================================================
// AUTO CLIMATE CONTROL (THI + histeresis)
// Catatan: saat auto_mode ON, perintah manual fan/pump dari app
// bisa ditimpa lagi oleh logika ini dalam <= 5 detik.
// ============================================================
void autoClimateControl() {
  static unsigned long lastCheck = 0;
  if (!autoMode || !sensorValid || !ENABLE_RELAY_OUTPUTS) return;
  if (millis() - lastCheck < AUTO_CHECK_INTERVAL) return;
  lastCheck = millis();

  bool newFan  = fanState  ? (thi > thiNormalMax - FAN_DEADBAND)  : (thi >= thiNormalMax);
  bool newPump = pumpState ? (thi > thiDangerMax - PUMP_DEADBAND) : (thi >= thiDangerMax);
  if (newFan == fanState && newPump == pumpState) return;

  setFan(newFan);
  setPump(newPump);
  logMsg("[AUTO] THI=" + String(thi, 1) +
         " -> Fan " + (newFan ? "ON" : "OFF") + ", Pump " + (newPump ? "ON" : "OFF"));

  const char *ev = (newFan && newPump) ? "fan_pump_on"
                 : newFan              ? "fan_on"
                 : newPump             ? "pump_on"
                                       : "all_off";
  ctrlLog = { true, ev, thi, newFan, newPump, timeValid ? (long)time(nullptr) : 0L };
}

// ============================================================
// FIREBASE
// ============================================================
void noteFirebaseError(const char *what) {
  firebaseErrors++;
  logMsg(String("[Firebase] ") + what + " GAGAL: " + fbdo.errorReason());
}

void firebaseBegin() {
  config.database_url               = FIREBASE_HOST;
  config.api_key                    = FIREBASE_API_KEY;
  // test_mode = tanpa autentikasi; rules database harus terbuka.
  // Untuk produksi: pakai Email/Password Auth + rules yang ketat.
  config.signer.test_mode           = true;
  config.token_status_callback      = tokenStatusCallback;
  config.timeout.serverResponse     = FB_TIMEOUT_MS;
  config.timeout.socketConnection   = FB_TIMEOUT_MS;
  Firebase.reconnectNetwork(true);
  Firebase.begin(&config, &auth);
  fbBegun = true;
  logMsg("[Firebase] begin()");
}

bool startControlStream() {
  static bool callbackSet = false;
  if (!Firebase.RTDB.beginStream(&stream, PATH_CONTROLS)) {
    logMsg("[Stream] begin error: " + stream.errorReason());
    return false;
  }
  if (!callbackSet) {
    Firebase.RTDB.setStreamCallback(&stream, streamCallback, streamTimeoutCallback);
    callbackSet = true;
  }
  streamStarted = true;
  logMsg("[Stream] listening on /" PATH_CONTROLS);
  return true;
}

void syncToFirebase() {
  if (syncFan) {
    if (Firebase.RTDB.setBool(&fbdo, PATH_CTRL_FAN, fanState) &&
        Firebase.RTDB.setInt(&fbdo, PATH_CTRL_FANSPEED, fanState ? 100 : 0))
      syncFan = false;
    else noteFirebaseError("sync fan");
  }
  if (syncAuto) {
    if (Firebase.RTDB.setBool(&fbdo, PATH_CONTROLS "/auto_mode", autoMode)) syncAuto = false;
    else noteFirebaseError("sync auto_mode");
  }
  if (syncPump) {
    if (Firebase.RTDB.setBool(&fbdo, PATH_CTRL_PUMP, pumpState)) syncPump = false;
    else noteFirebaseError("sync pump");
  }
  if (syncFeedNowReset) {
    if (Firebase.RTDB.setBool(&fbdo, PATH_CTRL_FEEDNOW, false)) syncFeedNowReset = false;
    else noteFirebaseError("reset feed_now");
  }
  if (syncLastFeed) {
    bool ok = Firebase.RTDB.setString(&fbdo, PATH_LAST_FEED, feederSource);
    if (ok && timeValid) ok = Firebase.RTDB.setInt(&fbdo, PATH_LAST_FEED_TS, (int)time(nullptr));
    if (ok) syncLastFeed = false;
    else noteFirebaseError("last_feed");
  }
  if (ctrlLog.pending) {
    FirebaseJson j;
    j.set("event", ctrlLog.event);
    j.set("thi",   roundf(ctrlLog.thi * 10.0f) / 10.0f);
    j.set("fan",   ctrlLog.fan);
    j.set("pump",  ctrlLog.pump);
    j.set("epoch", (int)ctrlLog.epoch);
    if (Firebase.RTDB.push(&fbdo, PATH_CTRL_LOG, &j)) ctrlLog.pending = false;
    else noteFirebaseError("control_log");
  }
}

void sendSensorData() {
  static float lastT = NAN, lastH = NAN;
  static int   lastRaw = -1;
  static unsigned long lastForce = 0;
  unsigned long now = millis();

  bool changed = (sensorValid && (!isfinite(lastT) ||
                                  fabsf(temperature - lastT) >= 0.3f ||
                                  fabsf(humidity - lastH) >= 1.0f)) ||
                 lastRaw < 0 || abs(mq137Raw - lastRaw) >= 10;
  if (!changed && now - lastForce < KEEPALIVE_INTERVAL) return;

  FirebaseJson json;
  json.set("sensor_ok", sensorValid);
  if (sensorValid) {
    json.set("temperature", roundf(temperature * 10.0f) / 10.0f);
    json.set("humidity",    roundf(humidity));
    json.set("thi",         roundf(thi * 10.0f) / 10.0f);
  }
  json.set("mq137_raw",          mq137Raw);
  json.set("mq137_volt",         roundf(mq137Volt * 100.0f) / 100.0f);
  json.set("ammonia_calibrated", false);
  json.set("relay_fan",          fanState);
  json.set("relay_pump",         pumpState);
  json.set("relays_enabled",     ENABLE_RELAY_OUTPUTS);
  json.set("feeder_enabled",     ENABLE_SERVO_FEEDER);
  json.set("auto_mode",          autoMode);
  json.set("online",             true);   // app: anggap offline jika timestamp > 60 dtk
  json.set("timestamp",          timeValid ? (int)time(nullptr) : 0);
  json.set("hour",               timeValid ? currentHour   : -1);
  json.set("minute",             timeValid ? currentMinute : -1);
  json.set("uptime_s",           (int)(millis() / 1000UL));
  json.set("device_id",          DEVICE_ID);
  json.set("fw",                 FW_VERSION);

  if (Firebase.RTDB.updateNode(&fbdo, PATH_SENSOR, &json)) {
    lastT = temperature; lastH = humidity; lastRaw = mq137Raw; lastForce = now;
    firebaseErrors = 0;
  } else {
    noteFirebaseError("kirim sensor");
  }
}

void saveHistory() {
  if (!timeValid || !sensorValid) return;

  char hhmm[6];
  snprintf(hhmm, sizeof(hhmm), "%02d:%02d", currentHour, currentMinute);
  String path = String(PATH_HISTORY) + "/" + currentDate + "/" + hhmm;

  FirebaseJson json;
  json.set("t",         roundf(temperature * 10.0f) / 10.0f);
  json.set("h",         roundf(humidity));
  json.set("thi",       roundf(thi * 10.0f) / 10.0f);
  json.set("mq137_raw", mq137Raw);
  json.set("f",         fanState  ? 1 : 0);
  json.set("p",         pumpState ? 1 : 0);
  json.set("ts",        (int)time(nullptr));

  if (Firebase.RTDB.setJSON(&fbdo, path, &json)) logMsg("[History] " + path);
  else noteFirebaseError("history");
}

void handleFirebase(unsigned long now) {
  if (!wifiConnected) { firebaseConnected = false; return; }
  if (!fbBegun) { firebaseBegin(); return; }

  firebaseConnected = Firebase.ready();
  if (!firebaseConnected) return;

  if (!streamStarted && now - lastStreamTry >= streamBackoff) {
    lastStreamTry = now;
    if (startControlStream()) streamBackoff = STREAM_BACKOFF_MIN;
    else streamBackoff = min(streamBackoff * 2UL, (unsigned long)STREAM_BACKOFF_MAX);
  }

  // Jangan blokir loop dengan request jaringan selama servo bekerja.
  if (isFeeding) return;

  syncToFirebase();

  if (now - lastFbSend >= FIREBASE_SEND_INTERVAL) {
    lastFbSend = now;
    sendSensorData();
  }
  if (now - lastHistory >= HISTORY_INTERVAL) {
    lastHistory = now;
    saveHistory();
  }
}

// ============================================================
// WIFI
// ============================================================
void connectWiFi() {
  Serial.print("[WiFi] Connecting");
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  for (int i = 0; i < 30 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  wifiConnected = (WiFi.status() == WL_CONNECTED);
  logMsg(wifiConnected ? "[WiFi] Connected, IP " + WiFi.localIP().toString()
                       : String("[WiFi] GAGAL — lanjut offline"));
}

void handleWiFi(unsigned long now) {
  bool up = (WiFi.status() == WL_CONNECTED);
  if (up != wifiConnected) logMsg(up ? "[WiFi] Tersambung lagi" : "[WiFi] Terputus");
  wifiConnected = up;
  if (!up && now - lastWifiRetry >= WIFI_RETRY_INTERVAL) {
    lastWifiRetry = now;
    WiFi.reconnect();
  }
}

// ============================================================
// WAKTU — HANYA NTP (tanpa RTC)
// Jadwal feeder & history baru berjalan setelah NTP valid.
// SNTP ESP32 menyinkronkan ulang sendiri secara berkala.
// ============================================================
void updateTime() {
  time_t ep = time(nullptr);
  if (ep < EPOCH_VALID_MIN) {
    timeValid   = false;
    currentDate = "";
    return;
  }
  struct tm ti;
  localtime_r(&ep, &ti);
  currentHour   = ti.tm_hour;
  currentMinute = ti.tm_min;
  currentSecond = ti.tm_sec;
  char d[11];
  snprintf(d, sizeof(d), "%04d-%02d-%02d", ti.tm_year + 1900, ti.tm_mon + 1, ti.tm_mday);
  currentDate = d;

  if (!timeValid) {
    timeValid = true;
    logMsg("[TIME] NTP valid: " + currentDate);
  }
}

// ============================================================
// WATCHDOG
// ============================================================
void initWatchdog() {
#ifdef WDT_CORE3
  esp_task_wdt_config_t cfg = {
    .timeout_ms     = WDT_TIMEOUT_S * 1000,
    .idle_core_mask = 0,
    .trigger_panic  = true
  };
  if (esp_task_wdt_reconfigure(&cfg) != ESP_OK) esp_task_wdt_init(&cfg);
#else
  esp_task_wdt_init(WDT_TIMEOUT_S, true);
#endif
  esp_task_wdt_add(NULL);
  logMsg("[WDT] Aktif (" + String(WDT_TIMEOUT_S) + " s)");
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  // v8.4: kunci relay ke OFF sebagai instruksi PERTAMA (sebelum Serial/WiFi/delay)
  if (ENABLE_RELAY_OUTPUTS) {
    digitalWrite(FAN_RELAY_PIN,  RELAY_ACTIVE_LOW ? HIGH : LOW);
    digitalWrite(PUMP_RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
    pinMode(FAN_RELAY_PIN,  OUTPUT);
    pinMode(PUMP_RELAY_PIN, OUTPUT);
  }
  Serial.begin(115200);
  delay(200);
  Serial.println("\n================================");
  Serial.println(" PITIK / SmartQuail v" FW_VERSION " — ESP32-S3");
  Serial.println(" Device: " DEVICE_ID);
  Serial.println("================================");

  // --- Relay onboard ---
  if (ENABLE_RELAY_OUTPUTS) {
    // Tulis level OFF DULU, baru jadikan OUTPUT -> relay tidak berkedip ON saat boot.
    digitalWrite(FAN_RELAY_PIN,  RELAY_ACTIVE_LOW ? HIGH : LOW);
    digitalWrite(PUMP_RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
    pinMode(FAN_RELAY_PIN,  OUTPUT);
    pinMode(PUMP_RELAY_PIN, OUTPUT);
    fanState  = false;
    pumpState = false;
    syncFan   = true;    // beri tahu Firebase: saat boot kipas & pompa MATI
    syncPump  = true;
    autoMode  = false;   // v8.4: boot MANUAL
    syncAuto  = true;    //       tulis controls/auto_mode = false ke Firebase
    Serial.printf("[Relay] Boot: semua OFF (level pin OFF = %s)\n", RELAY_ACTIVE_LOW ? "HIGH" : "LOW");
  } else {
    // Relay dikunci: tarik pin ke level OFF agar input relay tidak mengambang.
    pinMode(FAN_RELAY_PIN,  RELAY_ACTIVE_LOW ? INPUT_PULLUP : INPUT_PULLDOWN);
    pinMode(PUMP_RELAY_PIN, RELAY_ACTIVE_LOW ? INPUT_PULLUP : INPUT_PULLDOWN);
    Serial.println("[Safety] Relay DIKUNCI — jangan pasang beban dulu");
  }

  // --- AutoFeeder (servo) — posisi awal tertutup ---
  if (ENABLE_SERVO_FEEDER) {
    feederServo.setPeriodHertz(50);
    feederServo.attach(AUTOFEEDER_PIN, 500, 2400);
    feederServo.write(SERVO_CLOSED_ANGLE);
    delay(300);
    feederServo.detach();
  } else {
    Serial.println("[Safety] Feeder DIKUNCI — aktuator belum dikonfirmasi");
  }

  // --- DHT22 (GPIO4) ---
  dht.begin();
  delay(2000);   // DHT22 perlu ~2 detik setelah power-on sebelum pembacaan pertama
  Serial.println("[DHT22] Init di GPIO4");

  // --- MQ-137 (ADC GPIO6) ---
  analogReadResolution(12);

  // --- Nextion (UART1 RX GPIO18 / TX GPIO17) ---
  nextionSerial.begin(NEXTION_BAUD, SERIAL_8N1, NEXTION_RX_PIN, NEXTION_TX_PIN);
  delay(300);
  while (nextionSerial.available()) nextionSerial.read();
  Serial.println("[Nextion] Ready");

  // --- WiFi + NTP ---
  configTime(TZ_OFFSET_SEC, 0, "pool.ntp.org", "time.google.com");
  connectWiFi();
  if (wifiConnected) {
    for (int i = 0; i < 20 && time(nullptr) < EPOCH_VALID_MIN; i++) delay(500);
  }
  updateTime();
  if (!timeValid) logMsg("[TIME] Belum ada NTP — jadwal feeder & history menunggu");

  readSensors();
  nextionUpdateButtons(false);

  // --- Watchdog (setelah langkah blocking di atas) ---
  initWatchdog();

  logMsg("[SYSTEM] Ready. Nextion: 1=FAN ON 2=FAN OFF 3=PUMP ON 4=PUMP OFF 5=FEED");
  logMsg("[SYSTEM] autoMode=" + String(autoMode ? "ON" : "OFF") +
         " thiNormal=" + String(thiNormalMax, 0) +
         " thiDanger=" + String(thiDangerMax, 0));
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  unsigned long now = millis();

  handleWiFi(now);
  updateTime();

  processPendingControls();   // perintah dari app (via stream)
  readNextionCommands();      // perintah dari layar
  updateFeeder();

  if (now - lastSensorRead >= SENSOR_INTERVAL) {
    lastSensorRead = now;
    readSensors();
  }

  checkFeederSchedule();
  autoClimateControl();
  handleFirebase(now);

  esp_task_wdt_reset();
  delay(1);
}
