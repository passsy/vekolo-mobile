import 'package:flutter/material.dart';

/// Displays the workout library with saved/bookmarked workouts
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Top padding
        const SliverToBoxAdapter(child: SizedBox(height: 60)),

        // Empty state placeholder
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_border, size: 80, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 24),
                Text(
                  'No saved workouts yet',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bookmark workouts from the Activities tab\nto save them here for quick access',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Navigate back to Activities tab
                  },
                  icon: const Icon(Icons.explore, color: Color(0xFFFF6F00)),
                  label: const Text('Explore Workouts', style: TextStyle(color: Color(0xFFFF6F00))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF6F00)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
