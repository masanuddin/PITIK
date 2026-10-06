// ============================================================
//  D4 — kebijakan kirim telemetry /sensor_data (dipakai firmware DAN self-test).
//  Header murni tanpa Arduino/Firebase agar bisa diuji dengan static_assert.
//
//  Selain perubahan nilai sensor (logika lama), perubahan state berikut
//  memicu pengiriman pada pemanggilan sendSensorData() BERIKUTNYA:
//    relay_fan, relay_pump, auto_mode, sensor_ok (sensorValid).
//  "Terakhir terkirim" hanya diperbarui setelah updateNode BERHASIL, sehingga
//  kegagalan kirim dicoba lagi pada siklus berikutnya.
//
//  Tidak ada jaminan waktu: cadence tetap FIREBASE_SEND_INTERVAL, dan kirim
//  tetap ditunda saat feeder bekerja, Wi-Fi/Firebase belum siap, atau gagal.
// ============================================================
#pragma once

namespace pitik {

struct TelemetryState {
  bool fan;          // relay_fan  (state output yang diperintahkan, bukan feedback fisik)
  bool pump;         // relay_pump (idem)
  bool autoMode;     // auto_mode
  bool sensorValid;  // sensor_ok
};

// true bila belum pernah berhasil kirim, atau salah satu state berbeda dari
// state yang terakhir BERHASIL dikirim.
constexpr bool telemetryStateChanged(bool sentOnce, TelemetryState lastSent,
                                     TelemetryState now) {
  return !sentOnce || lastSent.fan != now.fan || lastSent.pump != now.pump ||
         lastSent.autoMode != now.autoMode ||
         lastSent.sensorValid != now.sensorValid;
}

}  // namespace pitik
