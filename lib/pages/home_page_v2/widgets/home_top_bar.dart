import 'package:flutter/material.dart';
import 'package:vekolo/models/user.dart';
import 'package:vekolo/widgets/user_avatar.dart';

/// Top bar for the home page with bookmark, filter indicator, and profile
class HomeTopBar extends StatelessWidget {
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onFilterTap;
  final VoidCallback? onDevicesTap;
  final VoidCallback? onProfileTap;
  final List<Color> activeFilters;
  final User? user;
  final GlobalKey? filterButtonKey;

  const HomeTopBar({
    super.key,
    this.onBookmarkTap,
    this.onFilterTap,
    this.onDevicesTap,
    this.onProfileTap,
    this.activeFilters = const [],
    this.user,
    this.filterButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Combined bookmark + filter pill
            SizedBox(
              key: filterButtonKey,
              width: 160,
              child: PillButton(onTap: onFilterTap, activeFilters: activeFilters),
            ),

            Spacer(),

            // devices
            GestureDetector(
              onTap: onDevicesTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade900),
                child: const Icon(Icons.devices, color: Colors.white70, size: 24),
              ),
            ),
            const SizedBox(width: 12),

            // Profile image / Login button
            GestureDetector(
              onTap: onProfileTap,
              child: user != null
                  ? UserAvatar(
                      user: user!,
                      radius: 24,
                      backgroundColor: Colors.grey.shade900,
                      foregroundColor: Colors.white,
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade900),
                      child: const Icon(Icons.person_outline, color: Colors.white70, size: 24),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  final VoidCallback? onTap;
  final List<Color> activeFilters;

  const PillButton({required this.onTap, required this.activeFilters});

  @override
  Widget build(BuildContext context) {
    // Default filter colors if none provided
    final colors = activeFilters.isEmpty
        ? [
            const Color(0xFF00D9FF),
            const Color(0xFF00FF94),
            const Color(0xFFFFD93D),
            const Color(0xFFFF6B6B),
            const Color(0xFFFF00E5),
          ]
        : activeFilters;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(100)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Bookmark icon
            const Icon(Icons.bookmark_outline, color: Color(0xFFFF6F00), size: 28),
            const SizedBox(width: 16),
            // Colored stripes
            SizedBox(
              width: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: colors.map((color) {
                  return Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
