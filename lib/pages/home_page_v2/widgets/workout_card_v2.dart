import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';

/// A card displaying workout information with author, title, and interval visualization
class WorkoutCardV2 extends StatelessWidget {
  const WorkoutCardV2({
    super.key,
    required this.authorName,
    this.authorAvatarUrl,
    required this.date,
    required this.title,
    required this.duration,
    required this.intervals,
    required this.backgroundColor,
    this.onTap,
  });

  final String authorName;
  final String? authorAvatarUrl;
  final String date;
  final String title;
  final String duration;
  final List<IntervalBar> intervals;
  final Color backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background with solid color
          // Container(decoration: BoxDecoration(color: workout.backgroundColor)),
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.6), Colors.black.withValues(alpha: 1.0)],
                ),
              ),
            ),
          ),
          // Content on top
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Author and Date
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: authorAvatarUrl != null ? NetworkImage(authorAvatarUrl!) : null,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: authorAvatarUrl == null
                            ? Text(
                                authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        authorName,
                        style: GoogleFonts.publicSans(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          textBaseline: TextBaseline.alphabetic,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        date,
                        style: GoogleFonts.publicSans(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Title and Duration
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.sairaExtraCondensed(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w400,
                            height: 1.0,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        duration,
                        style: GoogleFonts.sairaExtraCondensed(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 36,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Interval Bars
                  WorkoutIntervalBars(intervals: intervals, height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
