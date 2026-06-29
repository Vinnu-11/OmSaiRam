// Om Sai Ram
// Reusable social login button widget.

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A styled button for social authentication (Google, Apple).
///
/// Displays an icon and label in an outlined button style.
class SocialLoginButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const SocialLoginButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkText,
          side: BorderSide(color: AppColors.lightGrey),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
