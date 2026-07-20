// Om Sai Ram
// Welcome screen — first screen shown on app launch for new/unauthenticated users.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/router_service.dart';

/// Welcome/onboarding screen shown on first launch or when not logged in.
///
/// Provides two paths:
/// - "Start Reading" — browse and read Satcharita chapters without an account
/// - "Join a Group" — requires login to participate in group readings
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 1),

                  // Baba image from official Shirdi Sansthan
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: 'https://sai.org.in/sites/default/files/video.jpg',
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: AppColors.saffron.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.temple_hindu_rounded,
                            size: 60,
                            color: AppColors.saffron,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 200,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.saffron, AppColors.deepOrange],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.temple_hindu_rounded,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App name
                  Text(
                    AppStrings.appName,
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 30,
                        ),
                  ),
                  const SizedBox(height: 8),

                  // Tagline
                  Text(
                    'Sai Satcharita · Aarti · Group Readings',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.mediumText,
                        ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 1),

                  // Feature highlights
                  _FeatureRow(
                    icon: Icons.auto_stories_outlined,
                    text: 'Read all 53 chapters anytime',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.headphones_outlined,
                    text: 'Listen & download Aarti and Satcharitra',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.live_tv_outlined,
                    text: 'Watch Live Darshan from Shirdi',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.group_outlined,
                    text: 'Organize group Parayana readings',
                  ),

                  const Spacer(flex: 2),

                  // Primary CTA — Start Reading (no login needed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.go(AppRoutes.reader),
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: const Text('Start Reading'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.saffron,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const SizedBox(height: 12),

                  // Audio CTA — listen to Aarti without login
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(AppRoutes.audio),
                      icon: const Icon(Icons.headphones_outlined),
                      label: const Text('Listen to Aarti & Audio'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.deepOrange,
                        side: BorderSide(color: AppColors.deepOrange.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Secondary CTA — Login for group features
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(AppRoutes.login),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Sign In for Group Reading'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.saffron,
                        side: BorderSide(color: AppColors.saffron.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row showing a feature with an icon and text.
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.saffron.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.saffron, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.darkText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
