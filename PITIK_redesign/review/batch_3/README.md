# Review Batch 3 — Kontrol

Status: **review visual masih pending** (belum disetujui).

## Metode render

- Render offscreen lewat `flutter test` (mesin Flutter, Skia) — **bukan** browser dan
  **bukan** perangkat Android nyata. Tidak bisa dipakai sebagai bukti performa.
- Widget produksi yang sama (`ControlScreen`, `PitikBottomNav`) dengan data & perintah
  simulasi dari `lib/preview/preview_device.dart` + `preview_repository.dart` —
  tanpa Firebase; perintah hanya mengubah stream palsu.
- Font: Roboto (regular/medium/bold) & Material Icons dari cache Flutter SDK.
- Rasio piksel 2×; simulasi inset sistem 24 dp atas dan 24 dp bawah.
- Jam simulasi: 4 Okt 2026 16:20:05 WIB. Ambang THI default firmware 72 / 78.

## Daftar capture

| File | Viewport (dp) | Skala teks | Keadaan |
|---|---|---|---|
| b3_01_393x852_t100_manual_atas | 393×852 | 100% | Online, manual — header, koneksi, Sensor Monitor, Mode Iklim |
| b3_02_393x852_t100_manual_kipas-pompa | 393×852 | 100% | Kipas & Pompa + Preset Cepat |
| b3_03_393x852_t100_manual_bawah-preset-pakan | 393×852 | 100% | Bagian bawah: Pemberi Pakan di atas navigasi |
| b3_04_393x852_t100_otomatis_mode | 393×852 | 100% | Mode otomatis aktif |
| b3_05_393x852_t100_otomatis_kipas-pompa | 393×852 | 100% | Kipas/pompa/preset dikunci "Dikendalikan otomatis" |
| b3_06_393x852_t100_offline_atas | 393×852 | 100% | Offline / data lama — satu banner offline |
| b3_07_393x852_t100_offline_kipas-pompa | 393×852 | 100% | Status relay "Terakhir dilaporkan" + waktu |
| b3_08_393x852_t100_tamu_atas | 393×852 | 100% | Tamu (hanya melihat) |
| b3_09_393x852_t100_mengirim-kipas | 393×852 | 100% | Penulisan berjalan — kontrol lain dikunci |
| b3_10_393x852_t100_gagal-kirim-kipas | 393×852 | 100% | Penulisan gagal (sisi aplikasi) |
| b3_11_393x852_t100_permintaan-beda-status | 393×852 | 100% | Permintaan Menyala, relay dilaporkan Mati |
| b3_12_393x852_t100_feed-now-aktif | 393×852 | 100% | feed_now = true — "Menunggu perangkat…" |
| b3_13_393x852_t100_sensor-error_atas | 393×852 | 100% | Sensor error (DHT22) |
| b3_14_360x800_t100_manual_atas | 360×800 | 100% | Navigasi 1 baris |
| b3_15_360x800_t200_manual_atas | 360×800 | 200% | Navigasi grid 2×2 |
| b3_16_360x800_t200_manual_kipas | 360×800 | 200% | Switch turun ke baris sendiri (nama tidak terjepit) |
| b3_17_360x800_t200_manual_bawah | 360×800 | 200% | Tombol pakan di atas navigasi |
| b3_18_393x852_t100_permintaan-disimpan | 393×852 | 100% | Tulis selesai (preset "Semua mati", tanpa mismatch): "Permintaan disimpan. Menunggu status perangkat." |

Koreksi copy (setelah persetujuan Batch 3) sudah diterapkan dan semua capture di atas
dirender ulang: sukses tulis "Permintaan disimpan. Menunggu status perangkat." /
"Permintaan pakan disimpan. Menunggu perangkat.", mismatch "Menunggu perubahan status
perangkat.", gagal "Gagal mengirim perintah. Periksa koneksi."

## Keterbatasan

- Belum diverifikasi di perangkat Android nyata (DPI, font OEM, gesture bar asli,
  TalkBack).
- Simulasi "ESP32" di preview menerapkan perintah setelah 1,5 dtk; waktu nyata
  bergantung firmware & jaringan dan belum diukur.
- Banner tamu memakai komponen lama `GuestBanner` (dipakai bersama Pengaturan;
  tidak diubah di batch ini).
