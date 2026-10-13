// Om Sai Ram
// Audio hub — entry point for Aarti, Satcharitra Audio, and Live Darshan.
// Designed for ease of use by elderly devotees.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/router_service.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/l10n/s.dart';

class AudioHubScreen extends ConsumerWidget {
  const AudioHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(tr.audio, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
              // Baba photo from sai.org.in
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  'https://sai.org.in/sites/default/files/video.jpg',
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Icon(Icons.temple_hindu_rounded, size: 60, color: AppColors.saffron),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'Listen & Download',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bhajans and sacred recitations from Shirdi',
                style: TextStyle(fontSize: 14, color: AppColors.lightText),
              ),

              const SizedBox(height: 20),

              // Aarti card
              _AudioCard(
                icon: Icons.music_note_rounded,
                title: tr.aarti,
                subtitle: 'Daily aartis from Shirdi Sansthan\n5 aartis · Bhupali, Kakad, Madhyan, Dhup, Shej',
                color: AppColors.saffron,
                onTap: () => context.go(AppRoutes.aarti),
              ),

              const SizedBox(height: 16),

              // Satcharitra audio card
              _AudioCard(
                icon: Icons.headphones_rounded,
                title: tr.satcharitaAudio,
                subtitle: 'Listen to Sai Satcharitra by chapter\nAvailable in Marathi, Hindi, Telugu, Tamil',
                color: AppColors.deepOrange,
                onTap: () => context.go(AppRoutes.satcharitaAudio),
              ),

          ],
        ),
      ),
    );
  }
}

class _AudioCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AudioCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.lightGrey),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.lightText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: AppColors.mediumText, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
