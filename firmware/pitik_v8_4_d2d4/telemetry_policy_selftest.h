// ============================================================
//  Self-test D4 (kebijakan telemetry) — dievaluasi oleh COMPILER toolchain
//  ESP32 setiap kali sketch di-compile. Biaya runtime nol.
// ============================================================
#pragma once
#include "telemetry_policy.h"

namespace pitik {
namespace selftest {

constexpr TelemetryState kOff{false, false, false, true};

// Belum pernah berhasil kirim → harus kirim.
static_assert(telemetryStateChanged(false, kOff, kOff), "D4: kiriman pertama");
// Tidak ada perubahan state → tidak memaksa kirim (logika sensor lama tetap berlaku).
static_assert(!telemetryStateChanged(true, kOff, kOff), "D4: state sama");
// Masing-masing perubahan state memicu kirim.
static_assert(telemetryStateChanged(true, kOff, TelemetryState{true, false, false, true}), "D4: relay_fan");
static_assert(telemetryStateChanged(true, kOff, TelemetryState{false, true, false, true}), "D4: relay_pump");
static_assert(telemetryStateChanged(true, kOff, TelemetryState{false, false, true, true}), "D4: auto_mode");
static_assert(telemetryStateChanged(true, kOff, TelemetryState{false, false, false, false}), "D4: sensor_ok");
// Kembali ke nilai yang sudah terkirim → tidak dianggap berubah
// (cache = nilai terakhir BERHASIL terkirim, bukan nilai sebelumnya di loop).
static_assert(!telemetryStateChanged(true, TelemetryState{true, true, false, true},
                                     TelemetryState{true, true, false, true}),
              "D4: cache = terakhir terkirim");

}  // namespace selftest
}  // namespace pitik
