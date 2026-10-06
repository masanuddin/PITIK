# Review Batch 2 — Riwayat

Status: **review visual masih pending** (belum disetujui).

## Metode render

- Render offscreen lewat `flutter test` (mesin Flutter, Skia) — **bukan** Chrome/Edge
  dan **bukan** perangkat Android nyata. Tidak bisa dipakai sebagai bukti performa.
- Widget produksi yang sama (`HistoryScreen`, `HistoryChartCard`, `PitikBottomNav`)
  dengan riwayat sintetis dari `lib/preview/preview_history.dart` — tanpa Firebase.
- Data sintetis deterministik (siklus harian, THI dari rumus firmware, resolusi 5 menit;
  30 Hari tiap titik ke-6 seperti `PitikRepository.selectPeriod`). **Bukan** data
  prototipe dan bukan data kandang nyata.
- Ambang THI = default firmware 72 / 78 (dari `/controls` simulasi).
- Font: Roboto (regular/medium/bold) & Material Icons dari cache Flutter SDK.
- Rasio piksel 2×; simulasi inset sistem 24 dp atas dan 24 dp bawah.
- Jam simulasi: 4 Okt 2026 16:20:05 WIB.

## Daftar capture

| File | Viewport (dp) | Skala teks | Keadaan |
|---|---|---|---|
| b2_01_393x852_t100_24jam_atas | 393×852 | 100% | 24 Jam termuat, bagian atas |
| b2_02_393x852_t100_24jam_thi-mq | 393×852 | 100% | Grafik THI (zona dari ambang) + MQ-137 (ADC) |
| b2_03_393x852_t100_24jam_bawah-statistik | 393×852 | 100% | Bagian bawah: catatan kalibrasi + Statistik |
| b2_04_393x852_t100_readout-titik | 393×852 | 100% | Setelah ketuk grafik Suhu — readout titik asli |
| b2_05_360x800_t100_24jam_atas | 360×800 | 100% | Navigasi 1 baris |
| b2_06_360x800_t200_24jam_atas | 360×800 | 200% | Navigasi grid 2×2; tombol periode 2 baris (putus di spasi) |
| b2_07_360x800_t200_24jam_bawah | 360×800 | 200% | Konten terakhir di atas navigasi |
| b2_08_393x852_t100_memuat-awal | 393×852 | 100% | Memuat awal (kerangka statis) |
| b2_09_393x852_t100_ganti-ke-7hari_data-lama-24jam | 393×852 | 100% | Memuat 7 Hari; grafik masih & dilabeli 24 Jam; CSV nonaktif |
| b2_10_393x852_t100_gagal-7hari_data-lama-24jam | 393×852 | 100% | Gagal 7 Hari; data 24 Jam tetap + Coba Lagi |
| b2_11_393x852_t100_7hari_atas | 393×852 | 100% | 7 Hari termuat |
| b2_12_393x852_t100_30hari_atas | 393×852 | 100% | 30 Hari termuat |
| b2_13_393x852_t100_kosong | 393×852 | 100% | Kosong (tanpa angka nol) |
| b2_14_393x852_t100_error-awal | 393×852 | 100% | Gagal memuat awal + Coba Lagi |

## Keterbatasan

- Belum diverifikasi di perangkat Android nyata (DPI, font OEM, gesture bar asli).
- Label sumbu grafik dibatasi skala 1,3× agar muat di area grafik; nilai penting
  tersedia sebagai teks skala penuh (readout & statistik).
- Bentuk grafik 7/30 Hari bergantung pada data nyata; data sintetis sangat periodik.
