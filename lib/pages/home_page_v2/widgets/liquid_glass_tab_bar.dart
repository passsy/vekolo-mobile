import 'dart:ui';
import 'package:flutter/material.dart';

/// A pill-shaped tab bar with frosted glass blur effect
class LiquidGlassTabBar extends StatelessWidget {
  const LiquidGlassTabBar({super.key, required this.selectedIndex, required this.onTabSelected, required this.tabs});

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final List<TabItem> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(100),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _TabButton(
                    tab: tabs[i],
                    isSelected: i == selectedIndex,
                    onTap: () => onTabSelected(i),
                    accentColor: accentColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.isSelected, required this.onTap, required this.accentColor});

  final TabItem tab;
  final bool isSelected;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? accentColor : Colors.white.withValues(alpha: 0.6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class TabItem {
  const TabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
