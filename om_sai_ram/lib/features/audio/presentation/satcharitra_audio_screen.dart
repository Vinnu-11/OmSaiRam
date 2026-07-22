// Om Sai Ram
// Satcharitra Audio screen — language tabs + chapter download list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/l10n/s.dart';
import '../data/audio_data.dart';

class SatcharitaAudioScreen extends ConsumerStatefulWidget {
  const SatcharitaAudioScreen({super.key});

  @override
  ConsumerState<SatcharitaAudioScreen> createState() => _SatcharitaAudioScreenState();
}

class _SatcharitaAudioScreenState extends ConsumerState<SatcharitaAudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kSatcharitaAudio.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        title: Text(
          tr.satcharitaAudio,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.saffron,
              unselectedLabelColor: AppColors.mediumText,
              indicatorColor: AppColors.saffron,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              tabs: kSatcharitaAudio
                  .map((lang) => Tab(text: lang.displayName))
                  .toList(),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: kSatcharitaAudio.map((lang) => _ChapterList(language: lang, downloadLabel: tr.downloadAudio)).toList(),
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  final SatcharitaLanguage language;
  final String downloadLabel;
  const _ChapterList({required this.language, required this.downloadLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.saffron, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tap Download to save the audio on your device.',
                    style: TextStyle(fontSize: 13, color: AppColors.mediumText),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            itemCount: language.chapters.length,
            itemBuilder: (context, i) {
              final chapter = language.chapters[i];
              return _ChapterTile(index: i + 1, track: chapter, downloadLabel: downloadLabel);
            },
          ),
        ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final int index;
  final AudioTrack track;
  final String downloadLabel;
  const _ChapterTile({required this.index, required this.track, required this.downloadLabel});

  Future<void> _download(BuildContext context) async {
    final uri = Uri.parse(track.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open audio link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Chapter number badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.saffron.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: AppColors.saffron,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                track.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Download button — large enough for older users
            GestureDetector(
              onTap: () => _download(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.saffron,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 5),
                    Text(
                      downloadLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
