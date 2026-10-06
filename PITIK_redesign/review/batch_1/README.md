# Review Batch 1 — Dashboard & Navigasi Bawah

Status: **review visual masih pending** (belum disetujui).

## Metode render

- Render offscreen lewat `flutter test` (mesin Flutter, Skia) — **bukan** Chrome/Edge
  dan **bukan** perangkat Android nyata. Tidak bisa dipakai sebagai bukti performa.
- Widget produksi yang sama (`DashboardScreen`, `PitikBottomNav`) dengan data simulasi
  dari `lib/preview/preview_device.dart` — tanpa Firebase.
- Font: Roboto (regular/medium/bold) & Material Icons dari cache Flutter SDK.
- Rasio piksel 2×; simulasi inset sistem 24 dp atas dan 24 dp bawah.
- Jam simulasi: 4 Okt 2026 16:20:05 WIB.

## Daftar capture

| File | Viewport (dp) | Skala teks | Keadaan | Catatan |
|---|---|---|---|---|
| b1_01_360x800_t100_online_atas_nav-normal | 360×800 | 100% | Online | Navigasi 1 baris |
| b1_02_360x800_t110_online_atas_nav-fallback | 360×800 | 110% | Online | Fallback grid 2×2 (label "Pengaturan" tidak muat di 1 baris) |
| b1_03_360x800_t150_online_atas_nav-fallback | 360×800 | 150% | Online | Fallback grid 2×2 |
| b1_04_360x800_t200_online_bawah_nav-fallback | 360×800 | 200% | Online | Bagian bawah; konten terakhir di atas navigasi |
| b1_05_393x852_t100_online_atas | 393×852 | 100% | Online | |
| b1_06_393x852_t100_online_bawah | 393×852 | 100% | Online | Bagian bawah (THI Monitor) |
| b1_07_393x852_t100_serverError-dataFresh_atas | 393×852 | 100% | Server error, data masih baru | Setelah tap "Sambungkan Ulang" |
| b1_08_393x852_t100_stale_atas | 393×852 | 100% | Data lama (offline) | |

## Keterbatasan

- Render tes tidak memakai font fallback sistem; karena itu teks "NH₃" diganti "NH3".
- Belum diverifikasi di perangkat Android nyata (DPI, font OEM, gesture bar asli).
