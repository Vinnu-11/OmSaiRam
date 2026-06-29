// Om Sai Ram
// Circular progress indicator widget for displaying reading completion.

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A custom circular progress widget showing percentage complete.
///
/// Used on the home screen and group detail to visualize reading progress.
class ReadingProgressCircle extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;

  const ReadingProgressCircle({
    super.key,
    required this.progress,
    this.size = 56,
    this.strokeWidth = 5,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (progress * 100).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeWidth,
              color: AppColors.progressNotStarted,
            ),
          ),
          // Progress arc
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: strokeWidth,
              color: progress >= 1.0
                  ? AppColors.progressComplete
                  : AppColors.progressInProgress,
              strokeCap: StrokeCap.round,
            ),
          ),
          // Percentage text
          Text(
            '$percentage%',
            style: TextStyle(
              fontSize: size * 0.22,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
        ],
      ),
    );
  }
}
