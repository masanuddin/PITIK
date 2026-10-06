// Navigasi bawah 4 tab (redesign).
//  - Satu baris bila SEMUA label muat pada skala teks pengguna.
//  - Bila tidak muat → grid 2 kolom (Dashboard | Riwayat / Kontrol | Pengaturan).
// Keputusan diambil dari pengukuran label sebenarnya (TextPainter dengan style,
// font, dan skala teks yang sama dengan yang dirender) terhadap lebar tersedia —
// bukan dari ambang skala teks. Label TIDAK dikecilkan, dipotong, atau di-ellipsis.
// Tinggi mengikuti isi (min. 64 per tombol) + safe area.
// lib/widgets/pitik_bottom_nav.dart

import 'package:flutter/material.dart';

import '../theme/pitik_tokens.dart';

class PitikNavItem {
  const PitikNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class PitikBottomNav extends StatelessWidget {
  const PitikBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<PitikNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const double _gap = 4;
  static const double _itemHPadding = 2;
  static const int gridColumns = 2;

  /// Style label (versi tebal = terlebar, dipakai untuk pengukuran).
  static TextStyle labelStyle(BuildContext context, {required bool selected}) =>
      DefaultTextStyle.of(context).style.merge(TextStyle(
            fontSize: 14,
            height: 1.2,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ));

  /// Apakah semua label muat dalam [columns] kolom selebar [width],
  /// dengan skala teks pengguna saat ini.
  static bool labelsFit(
    BuildContext context, {
    required List<String> labels,
    required double width,
    required int columns,
  }) {
    final itemWidth =
        (width - _gap * (columns - 1)) / columns - _itemHPadding * 2;
    final style = labelStyle(context, selected: true);
    final scaler = MediaQuery.textScalerOf(context);
    for (final label in labels) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final fits = tp.width <= itemWidth;
      tp.dispose();
      if (!fits) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: PitikColors.surface,
        border: Border(top: BorderSide(color: PitikColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: LayoutBuilder(builder: (context, constraints) {
            final oneRow = labelsFit(
              context,
              labels: [for (final i in items) i.label],
              width: constraints.maxWidth,
              columns: items.length,
            );
            Widget button(int i) => _NavButton(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onSelected(i),
                );
            if (oneRow) {
              return Row(
                key: const ValueKey('pitik-nav-row'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(child: button(i)),
                  ],
                ],
              );
            }
            // Fallback: grid 2 kolom, urutan tab tetap (baris demi baris).
            return Column(
              key: const ValueKey('pitik-nav-grid'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < items.length; r += gridColumns) ...[
                  if (r > 0) const SizedBox(height: _gap),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < gridColumns; c++) ...[
                          if (c > 0) const SizedBox(width: _gap),
                          Expanded(
                            child: r + c < items.length
                                ? button(r + c)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PitikNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PitikColors.accent : PitikColors.navInactive;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? PitikColors.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: PitikBottomNav._itemHPadding, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? item.activeIcon : item.icon,
                      size: 26, color: color),
                  const SizedBox(height: 4),
                  // Skala teks penuh; tanpa FittedBox / ellipsis.
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: PitikBottomNav.labelStyle(context, selected: selected)
                        .copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
