// Om Sai Ram
// Aarti screen — daily aartis with in-app playback.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../data/audio_data.dart';
import '../providers/chapter_audio_provider.dart';

class AartiScreen extends StatefulWidget {
  const AartiScreen({super.key});

  @override
  State<AartiScreen> createState() => _AartiScreenState();
}

class _AartiScreenState extends State<AartiScreen> {
  int _expanded = -1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        title: const Text('Aarti', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: kAartis.length,
        itemBuilder: (context, i) {
          final group = kAartis[i];
          final isOpen = _expanded == i;
          return _AartiSection(
            group: group,
            isOpen: isOpen,
            onTap: () => setState(() => _expanded = isOpen ? -1 : i),
          );
        },
      ),
    );
  }
}

class _AartiSection extends StatelessWidget {
  final AartiGroup group;
  final bool isOpen;
  final VoidCallback onTap;

  const _AartiSection({
    required this.group,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOpen ? AppColors.saffron.withOpacity(0.4) : AppColors.lightGrey,
          width: isOpen ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Section header — large tap target
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.music_note_rounded, color: AppColors.saffron, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${group.time}  ·  ${group.tracks.length} bhajans',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.mediumText,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),

          if (isOpen)
            Column(
              children: [
                const Divider(height: 1, color: AppColors.lightGrey),
                ...group.tracks.map((track) => _TrackTile(track: track)),
                const SizedBox(height: 8),
              ],
            ),
        ],
      ),
    );
  }
}

class _TrackTile extends ConsumerWidget {
  final AudioTrack track;
  const _TrackTile({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(chapterAudioProvider);
    final isThisTrack = audioState.track?.fileName == track.fileName;
    final isDownloading =
        isThisTrack && audioState.status == ChapterAudioStatus.downloading;
    final isPlaying =
        isThisTrack && audioState.status == ChapterAudioStatus.playing;
    final isActive = isThisTrack && audioState.isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              track.title,
              style: TextStyle(
                fontSize: 15,
                color: isActive ? AppColors.saffron : AppColors.darkText,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Play / Pause / Loading button
          GestureDetector(
            onTap: () =>
                ref.read(chapterAudioProvider.notifier).toggleAudio(track),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.saffron
                    : AppColors.saffron.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isDownloading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        value: audioState.downloadProgress,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: isActive ? Colors.white : AppColors.saffron,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPlaying ? 'Pause' : 'Play',
                          style: TextStyle(
                            color: isActive ? Colors.white : AppColors.saffron,
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
    );
  }
}
