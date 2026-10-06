// ============================================================
//  Self-test kebijakan stream /controls — dievaluasi oleh COMPILER
//  toolchain ESP32 setiap kali sketch di-compile (biaya runtime nol).
//  Bila kebijakan berubah tanpa disengaja, compile GAGAL.
// ============================================================
#pragma once
#include "control_stream_policy.h"

namespace pitik {
namespace selftest {

// --- Klasifikasi event di path "/" ---
static_assert(classifyRootEvent("put") == RootEvent::Snapshot, "put / = snapshot");
static_assert(classifyRootEvent("patch") == RootEvent::Patch, "patch / = update sebagian");
static_assert(classifyRootEvent("keep-alive") == RootEvent::Ignore, "keep-alive diabaikan");
static_assert(classifyRootEvent("cancel") == RootEvent::Ignore, "cancel diabaikan");
static_assert(classifyRootEvent("") == RootEvent::Ignore, "kosong diabaikan");
static_assert(classifyRootEvent("putx") == RootEvent::Ignore, "bukan prefix match");

// --- Snapshot awal / reconnect (put "/"): boot Manual + relay OFF ---
static_assert(!rootKeyApplies(RootEvent::Snapshot, "fan"), "snapshot: fan tidak dipulihkan");
static_assert(!rootKeyApplies(RootEvent::Snapshot, "pump"), "snapshot: pump tidak dipulihkan");
static_assert(!rootKeyApplies(RootEvent::Snapshot, "auto_mode"), "snapshot: auto_mode tidak dipulihkan");
static_assert(rootKeyApplies(RootEvent::Snapshot, "thi_normal"), "snapshot: ambang dipakai");
static_assert(rootKeyApplies(RootEvent::Snapshot, "thi_danger"), "snapshot: ambang dipakai");
static_assert(rootKeyApplies(RootEvent::Snapshot, "feed_hour1"), "snapshot: jadwal dipakai");
static_assert(rootKeyApplies(RootEvent::Snapshot, "feed_min3"), "snapshot: jadwal dipakai");
// Perilaku v8.4 dipertahankan (D3 terpisah): feed_now di snapshot masih diproses.
static_assert(rootKeyApplies(RootEvent::Snapshot, "feed_now"), "snapshot: feed_now (perilaku v8.4)");

// --- Patch root (Flutter update(), termasuk preset atomik) ---
static_assert(rootKeyApplies(RootEvent::Patch, "fan"), "patch: fan diproses");
static_assert(rootKeyApplies(RootEvent::Patch, "pump"), "patch: pump diproses");
static_assert(rootKeyApplies(RootEvent::Patch, "auto_mode"), "patch: auto_mode diproses");
static_assert(rootKeyApplies(RootEvent::Patch, "feed_now"), "patch: feed_now diproses");
static_assert(rootKeyApplies(RootEvent::Patch, "thi_normal"), "patch: ambang diproses");
static_assert(rootKeyApplies(RootEvent::Patch, "feed_hour2"), "patch: jadwal diproses");

// --- Event tidak dikenal di "/": tidak ada kunci yang diproses ---
static_assert(!rootKeyApplies(RootEvent::Ignore, "fan"), "ignore: fan");
static_assert(!rootKeyApplies(RootEvent::Ignore, "feed_now"), "ignore: feed_now");
static_assert(!rootKeyApplies(RootEvent::Ignore, "thi_normal"), "ignore: ambang");

// --- streq dasar ---
static_assert(streq("fan", "fan") && !streq("fan", "fan_speed") && !streq("fan_speed", "fan"),
              "streq exact match");

}  // namespace selftest
}  // namespace pitik
