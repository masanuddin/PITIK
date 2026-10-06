# Firmware PITIK — kandidat v8.4.1 (D2)

Status: **kandidat, belum di-flash**. Basis: v8.4 yang diberikan pemilik
(teruji di hardware). Perubahan perilaku hanya di `streamCallback()`.

## Isi folder

| File | Keterangan |
|---|---|
| `pitik_v8_4/pitik_v8_4.ino` | Sketch kandidat D2 (v8.4.1) |
| `pitik_v8_4/control_stream_policy.h` | Kebijakan event `/controls` (put vs patch di root) |
| `pitik_v8_4/control_stream_policy_selftest.h` | `static_assert` — compile gagal bila kebijakan berubah |
| `pitik_v8_4/secrets.example.h` | Contoh kredensial; salin ke `secrets.h` (di-ignore git) |
| `patches/D3_feed_now_snapshot.patch` | Patch terpisah (belum diterapkan) |
| `patches/D4_telemetry_state.patch` | Patch terpisah (belum diterapkan) |
| `tools/verify_stream_events.mjs` | Verifikasi bentuk event di Firebase Emulator lokal |

## Masalah yang diperbaiki (D2)

Flutter menulis perintah dengan `ref('controls').update({...})`. Listener
`/controls` di ESP32 menerimanya sebagai event **patch** di path `/`.
Firmware v8.4 memperlakukan SEMUA event di `/` sebagai snapshot dan
melewati `fan`, `pump`, `auto_mode` → perintah kipas/pompa/mode dari app
diabaikan (pakan, ambang, jadwal tetap jalan karena tidak dilewati).

D2: `put "/"` (snapshot awal/reconnect) tetap tidak memulihkan
fan/pump/auto_mode (boot Manual + relay OFF); `patch "/"` memproses semua
kunci yang ada di payload (termasuk preset atomik kipas+pompa).

## Menyiapkan & compile (tanpa upload)

1. Salin `pitik_v8_4/secrets.example.h` → `pitik_v8_4/secrets.h`, isi dari
   sketch lama. Jangan commit.
2. Arduino IDE: buka `pitik_v8_4/pitik_v8_4.ino`, board **ESP32S3 Dev Module**,
   pengaturan board sama seperti saat v8.4 di-flash → **Verify**.
   Atau CLI:
   ```
   arduino-cli compile --fqbn esp32:esp32:esp32s3 firmware/pitik_v8_4
   ```
   Diuji di: Firebase Arduino Client (mobizt) 4.4.17, ESP32 core 3.3.12.

## Menerapkan patch terpisah (hanya setelah disetujui)

```
git apply firmware/patches/D3_feed_now_snapshot.patch
git apply firmware/patches/D4_telemetry_state.patch
```
