# Review Batch 4 — Pengaturan

Status: arah visual & behavior **disetujui**, dengan koreksi copy final (lihat di bawah).

> **Catatan:** capture di folder ini dirender SEBELUM koreksi copy final dan belum
> dirender ulang. Perbedaan dengan kode saat ini:
> - Sukses simpan: "Perubahan disimpan." (±5 detik), tanpa baris detail nilai.
> - Sedang menyimpan: "Menyimpan perubahan…"; gagal: "Gagal menyimpan perubahan. Periksa koneksi."
> - Helper statis di bawah tombol simpan & reset jadwal: "Perangkat akan menggunakan
>   pengaturan ini saat tersambung."
> - "Interval Update" tidak ditampilkan lagi (b4_09, b4_10 masih menampilkannya).
> - Keterangan Nama Kandang: "Label tampilan aplikasi".

## Metode render

- Render offscreen lewat `flutter test` (mesin Flutter, Skia) — **bukan** browser dan
  **bukan** perangkat Android nyata. Tidak bisa dipakai sebagai bukti performa.
- Widget produksi yang sama (`SettingsScreen`, `PitikBottomNav`) dengan data & tulisan
  simulasi dari `lib/preview/` — tanpa Firebase. Simpan ambang/jadwal hanya mengubah
  stream `/controls` palsu.
- Data sintetis: nomor HP `+6281200001234` (bukan nomor nyata), Device ID `SIMULASI-01`,
  firmware `8.4`, uptime 2 jam 17 menit. SharedPreferences kosong (nilai default).
- Font: Roboto (regular/medium/bold) & Material Icons dari cache Flutter SDK.
- Rasio piksel 2×; simulasi inset sistem 24 dp atas dan 24 dp bawah.
- Jam simulasi: 4 Okt 2026 16:20:05 WIB.

## Daftar capture

| File | Viewport (dp) | Skala teks | Keadaan |
|---|---|---|---|
| b4_01_393x852_t100_peternak_atas | 393×852 | 100% | Akun (nomor disamarkan, Terverifikasi) + Perangkat |
| b4_02_393x852_t100_koneksi | 393×852 | 100% | Koneksi + Ambang THI tanpa perubahan |
| b4_03_393x852_t100_ambang_tanpa-perubahan | 393×852 | 100% | "Tidak ada perubahan", tombol simpan nonaktif |
| b4_04_393x852_t100_ambang_draft | 393×852 | 100% | Draft "Belum disimpan" + nilai tersimpan |
| b4_05_393x852_t100_ambang_menyimpan | 393×852 | 100% | Menyimpan… |
| b4_06_393x852_t100_ambang_disimpan | 393×852 | 100% | "Pengaturan disimpan. Menunggu perangkat menerapkan perubahan." |
| b4_07_393x852_t100_ambang_gagal | 393×852 | 100% | Gagal simpan; draft dipertahankan |
| b4_08_393x852_t100_jadwal-pakan | 393×852 | 100% | Jadwal pakan + pakan terakhir + reset |
| b4_09_393x852_t100_preferensi-placeholder | 393×852 | 100% | Placeholder nonaktif "Belum tersedia"; Interval Update info statis |
| b4_10_393x852_t100_bawah-info-keluar | 393×852 | 100% | Info, Keluar dari Akun, footer versi |
| b4_11_393x852_t100_tamu_atas | 393×852 | 100% | Mode tamu |
| b4_12_393x852_t100_tamu_ambang | 393×852 | 100% | Tamu: ambang & jadwal terkunci, alasan terbaca |
| b4_13_393x852_t100_data-lama_server-terhubung | 393×852 | 100% | Perangkat offline, server terhubung; "Nilai dari laporan terakhir perangkat" |
| b4_14_360x800_t100_peternak_atas | 360×800 | 100% | Navigasi 1 baris |
| b4_15_360x800_t200_ambang | 360×800 | 200% | Ambang, teks 200% |
| b4_16_360x800_t200_koneksi | 360×800 | 200% | Koneksi, teks 200% |
| b4_17_360x800_t200_bawah | 360×800 | 200% | Keluar & footer di atas navigasi |

## Keterbatasan

- Belum diverifikasi di perangkat Android nyata (DPI, font OEM, TalkBack, time picker
  sistem, keyboard input jam).
- Versi "PITIK v1.0.0" masih teks tetap (sama dengan `pubspec.yaml` 1.0.0+1); belum
  dibaca otomatis karena tidak ada paket info aplikasi di dependensi.
- Banner tamu memakai komponen lama `GuestBanner` (dipakai bersama Kontrol; tidak diubah).
- Di preview, tombol "Keluar"/"Masuk dengan No. HP" memanggil AuthService produksi;
  tanpa Firebase.initializeApp panggilan itu gagal — tidak ada efek ke akun mana pun.
