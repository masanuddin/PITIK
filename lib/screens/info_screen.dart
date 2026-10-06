// lib/screens/info_screen.dart
// Halaman Bantuan & Kebijakan Privasi PITIK

import 'package:flutter/material.dart';

class InfoScreen extends StatelessWidget {
  final int initialTab; // 0 = Bantuan, 1 = Kebijakan Privasi

  const InfoScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          title: const Text(
            'Informasi',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1D1D1F),
          elevation: 0,
          bottom: const TabBar(
            labelColor: Color(0xFF007AFF),
            unselectedLabelColor: Color(0xFF8E8E93),
            indicatorColor: Color(0xFF007AFF),
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(icon: Icon(Icons.help_outline_rounded), text: 'Bantuan'),
              Tab(icon: Icon(Icons.privacy_tip_outlined), text: 'Kebijakan Privasi'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _HelpTab(),
            _PrivacyTab(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TAB BANTUAN
// ─────────────────────────────────────────────
class _HelpTab extends StatelessWidget {
  const _HelpTab();

  @override
  Widget build(BuildContext context) {
    final sections = [
      _HelpSection(
        icon: Icons.wifi_rounded,
        color: const Color(0xFF007AFF),
        title: 'Menghubungkan ESP32',
        items: [
          'Pastikan ESP32 sudah diprogram dan terhubung ke WiFi yang sama dengan Firebase.',
          'Indikator "ESP32 Online" (hijau) akan muncul di halaman Kontrol jika koneksi berhasil.',
          'Jika offline, periksa daya ESP32 dan sinyal WiFi.',
        ],
      ),
      _HelpSection(
        icon: Icons.sensors_rounded,
        color: const Color(0xFF34C759),
        title: 'Memahami Indikator Sensor',
        items: [
          '🌡️ Suhu — Temperatur udara kandang dalam °C.',
          '💧 Kelembaban — Persentase kelembaban relatif (RH).',
          '📊 THI (Temperature Humidity Index) — Indeks gabungan suhu dan kelembaban. Batasnya mengikuti Ambang THI di Pengaturan (default 72 dan 78): di bawah ambang normal = Normal, mulai ambang normal = Perhatian (kipas), mulai ambang bahaya = Bahaya (kipas + pompa).',
          '☁️ NH₃ / Amonia — Nilai mentah sensor MQ-137 (ADC 0–4095), belum dikalibrasi sehingga belum bisa dibaca sebagai ppm. Gunakan untuk melihat tren naik/turun.',
        ],
      ),
      _HelpSection(
        icon: Icons.autorenew_rounded,
        color: const Color(0xFF5856D6),
        title: 'Kontrol Perangkat',
        items: [
          'Mode Manual: kipas & pompa dinyalakan dari aplikasi atau layar Nextion di kandang. Setelah perangkat restart, mode selalu kembali ke Manual dengan kipas & pompa mati.',
          'Mode Otomatis: ESP32 menyalakan kipas bila THI ≥ ambang normal dan pompa bila THI ≥ ambang bahaya. Selama mode otomatis, tombol kipas/pompa dikunci ("Dikendalikan otomatis").',
          'Tombol hanya aktif saat perangkat online. Status "Relay aktual" menunjukkan kondisi relay sebenarnya di kandang.',
          'Gunakan Preset Cepat (Semua OFF, Kipas Saja, Full Cool) untuk mengatur cepat di mode Manual.',
        ],
      ),
      _HelpSection(
        icon: Icons.air_rounded,
        color: const Color(0xFF34C759),
        title: 'Kontrol Kipas',
        items: [
          'Kipas dikontrol lewat relay — hanya ON (nyala) atau OFF (mati).',
          'Tekan tombol kipas di layar Kontrol untuk menyalakan/mematikan.',
          'Aktifkan kipas agar sirkulasi udara kandang lancar dan suhu turun.',
        ],
      ),
      _HelpSection(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFF9500),
        title: 'Troubleshooting',
        items: [
          'Data sensor tidak update / perangkat offline → tekan "Sambungkan Ulang" (di Dashboard, Kontrol, atau Pengaturan). Bila hasilnya "perangkat belum mengirim data", periksa daya & WiFi ESP32 di kandang; bila "gagal terhubung ke server", periksa internet HP.',
          'Relay tidak merespons → pastikan ESP32 online (indikator hijau), mode Manual, dan relay tidak dinonaktifkan di perangkat.',
          'Pakan tidak keluar → perintah pakan yang dikirim saat perangkat offline tidak dijalankan; kirim ulang setelah perangkat online.',
          'Muncul "Sensor error (DHT22)" → sensor suhu/kelembaban tidak terbaca, cek kabel DHT22.',
          'OTP tidak terkirim → gunakan nomor test, atau hubungi developer (region/billing SMS).',
          'Aplikasi crash → clear cache atau reinstall aplikasi.',
        ],
      ),
      _HelpSection(
        icon: Icons.contact_support_rounded,
        color: const Color(0xFFFF3B30),
        title: 'Kontak Developer',
        items: [
          '📧 Email: widodo@binus.edu',
          '🏫 BINUS University — Computer Science (AI & Robotika)',
          'Developer: Ricky Rudiansyah & Marcellino Asanuddin',
          'Supervisor: Prof. Dr. Ir. Widodo Budiharto',
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: sections
          .map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: s,
              ))
          .toList(),
    );
  }
}

class _HelpSection extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;

  const _HelpSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
  });

  @override
  State<_HelpSection> createState() => _HelpSectionState();
}

class _HelpSectionState extends State<_HelpSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF8E8E93),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5, right: 8),
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: widget.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF3C3C43),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TAB KEBIJAKAN PRIVASI
// ─────────────────────────────────────────────
class _PrivacyTab extends StatelessWidget {
  const _PrivacyTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _privacyCard(
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF007AFF),
          title: 'Tentang Kebijakan Ini',
          content:
              'Kebijakan Privasi ini menjelaskan bagaimana aplikasi PITIK mengumpulkan, menggunakan, dan melindungi data Anda. Dengan menggunakan aplikasi ini, Anda menyetujui ketentuan yang dijelaskan di bawah ini.',
        ),
        const SizedBox(height: 12),
        _privacyCard(
          icon: Icons.data_usage_rounded,
          color: const Color(0xFF5856D6),
          title: 'Data yang Dikumpulkan',
          content:
              '• Data sensor kandang: suhu, kelembaban, THI, dan kadar amonia.\n'
              '• Status perangkat: kondisi relay kipas dan pompa, status online/offline ESP32.\n'
              '• Data akun: nomor telepon (jika login via OTP) atau status tamu.\n\n'
              'Data sensor disimpan di Firebase Realtime Database dan Firebase Firestore milik tim developer.',
        ),
        const SizedBox(height: 12),
        _privacyCard(
          icon: Icons.lock_outline_rounded,
          color: const Color(0xFF34C759),
          title: 'Penggunaan Data',
          content:
              'Data yang dikumpulkan digunakan semata-mata untuk:\n'
              '• Menampilkan kondisi kandang secara real-time di aplikasi.\n'
              '• Mengirim perintah kontrol ke ESP32.\n'
              '• Menyimpan riwayat data sensor untuk monitoring.\n\n'
              'Kami tidak menjual, menyewakan, atau membagikan data Anda kepada pihak ketiga manapun.',
        ),
        const SizedBox(height: 12),
        _privacyCard(
          icon: Icons.security_rounded,
          color: const Color(0xFFFF9500),
          title: 'Keamanan Data',
          content:
              'Data dikelola menggunakan Firebase (Google) dengan enkripsi SSL/TLS. Autentikasi menggunakan Firebase Authentication sesuai standar keamanan Google. Akses database dibatasi hanya untuk pengguna yang terautentikasi.',
        ),
        const SizedBox(height: 12),
        _privacyCard(
          icon: Icons.update_rounded,
          color: const Color(0xFF8E8E93),
          title: 'Perubahan Kebijakan',
          content:
              'Kami dapat memperbarui kebijakan ini sewaktu-waktu. Perubahan signifikan akan diinformasikan melalui pembaruan aplikasi. Tanggal efektif: 28 September 2026.',
        ),
        const SizedBox(height: 12),
        _privacyCard(
          icon: Icons.contact_mail_rounded,
          color: const Color(0xFF007AFF),
          title: 'Hubungi Kami',
          content:
              'Untuk pertanyaan terkait kebijakan privasi ini, silakan hubungi:\n📧 widodo@binus.edu\n🏫 BINUS University, Jakarta',
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'PITIK v1.0.0 · BINUS University © 2026',
            style: TextStyle(fontSize: 11, color: Color(0xFFAEAEB2)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _privacyCard({
    required IconData icon,
    required Color color,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Color(0xFF1D1D1F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF3C3C43),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
