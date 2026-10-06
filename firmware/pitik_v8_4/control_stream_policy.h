// ============================================================
//  Kebijakan event stream /controls (dipakai firmware DAN self-test).
//  Header murni tanpa Arduino/Firebase agar bisa diuji dengan static_assert.
//
//  Firebase RTDB streaming (REST/SSE) — dikonfirmasi pada
//  Firebase_ESP_Client 4.4.17 (FB_RTDB.cpp: put & patch diproses sama,
//  dataPath() = field "path" event, eventType() tersedia):
//   - put   path "/" : snapshot PENUH node — dikirim saat stream baru
//                      tersambung / reconnect (juga bila seluruh node di-set).
//   - patch path "/" : update SEBAGIAN — mis. Flutter
//                      ref('controls').update({'fan': true}) atau preset
//                      update({'fan': true, 'pump': true}).
//   - put   path "/fan" dst. : satu anak di-set (mis. firmware setBool).
//
//  Kebijakan:
//   - Snapshot (put "/"): fan, pump, auto_mode TIDAK dipulihkan → boot
//     Manual + relay OFF (v8.3/v8.4). Kunci lain (ambang, jadwal, feed_now)
//     diproses seperti sebelumnya.
//   - Patch (patch "/"): SEMUA kunci yang ada di payload diproses,
//     termasuk fan/pump/auto_mode (perintah eksplisit dari app).
//   - Event lain di "/" (tidak dikenal): diabaikan.
// ============================================================
#pragma once

namespace pitik {

enum class RootEvent : unsigned char { Snapshot, Patch, Ignore };

// strcmp versi constexpr (C++11: satu return, rekursif).
constexpr bool streq(const char *a, const char *b) {
  return (*a == *b) && (*a == '\0' || streq(a + 1, b + 1));
}

// Klasifikasi event di path "/" berdasarkan eventType() library.
constexpr RootEvent classifyRootEvent(const char *eventType) {
  return streq(eventType, "put")     ? RootEvent::Snapshot
         : streq(eventType, "patch") ? RootEvent::Patch
                                     : RootEvent::Ignore;
}

// Kunci aktuator/mode yang tidak boleh dipulihkan dari snapshot.
constexpr bool isActuatorKey(const char *key) {
  return streq(key, "fan") || streq(key, "pump") || streq(key, "auto_mode");
}

// Apakah `key` dari payload JSON di path "/" boleh diproses untuk event `ev`.
// (Kunci yang tidak ada di payload tetap diabaikan oleh parser.)
constexpr bool rootKeyApplies(RootEvent ev, const char *key) {
  return ev == RootEvent::Patch      ? true
         : ev == RootEvent::Snapshot ? !isActuatorKey(key)
                                     : false;
}

}  // namespace pitik
