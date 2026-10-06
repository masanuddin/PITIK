// Kartu & header seksi bergaya redesign PITIK.
// lib/widgets/pitik_card.dart

import 'package:flutter/material.dart';

import '../theme/pitik_tokens.dart';

class PitikCard extends StatelessWidget {
  const PitikCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PitikSpace.card),
    this.color = PitikColors.surface,
    this.borderColor = PitikColors.border,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration:
          PitikDecor.card(color: color, border: borderColor, shadow: shadow),
      child: child,
    );
  }
}

/// Ikon + judul kartu (+ subjudul opsional). Teks dibungkus, tidak dipotong.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: PitikText.cardTitle),
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text(subtitle!, style: PitikText.body),
          ),
      ],
    );
  }
}

/// Buka/tutup konten (mis. pesan hasil) dengan transisi ukuran singkat.
/// Bila sistem meminta "kurangi animasi", konten langsung berganti tanpa
/// AnimatedSize (AnimatedSize berdurasi nol memicu assertion layout).
class RevealSize extends StatelessWidget {
  const RevealSize({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (PitikMotion.reduced(context)) return child;
    return AnimatedSize(
      duration: PitikMotion.reveal,
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: child,
    );
  }
}

/// Kotak ikon berwarna (tile) seperti di prototipe.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    this.size = 36,
    this.iconSize = 22,
    this.radius = 10,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
