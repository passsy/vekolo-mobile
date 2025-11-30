import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vekolo/pages/home_page_v2/widgets/workout_interval_bars.dart';
import 'package:vekolo/widgets/gradient_card_background.dart';

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
    this.isLocal = false,
  });

  final String authorName;
  final String? authorAvatarUrl;
  final String date;
  final String title;
  final String duration;
  final List<IntervalBar> intervals;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background with solid color and gradient overlay
          Positioned.fill(child: GradientCardBackground(color: backgroundColor)),
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
                        backgroundImage: authorAvatarUrl != null && !authorAvatarUrl!.startsWith('http://localhost')
                            ? NetworkImage(authorAvatarUrl!)
                            : null,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: authorAvatarUrl == null || authorAvatarUrl!.startsWith('http://localhost')
                            ? Text(
                                authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          authorName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.publicSans(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            textBaseline: TextBaseline.alphabetic,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isLocal) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.smartphone,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'LOCAL',
                                style: GoogleFonts.publicSans(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        date,
                        textAlign: TextAlign.end,
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
                        textAlign: TextAlign.right,
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
