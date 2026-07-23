// Om Sai Ram
// Satcharitra Audio screen — language tabs + in-app chapter player.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/l10n/s.dart';
import '../data/audio_data.dart';
import '../providers/chapter_audio_provider.dart';

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
    final audioState = ref.watch(chapterAudioProvider);

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
      // Mini player docked at the bottom when audio is active
      bottomNavigationBar: audioState.isActive || audioState.status == ChapterAudioStatus.downloading
          ? _SatcharitaMiniPlayer(audioState: audioState)
          : null,
      body: TabBarView(
        controller: _tabController,
        children: kSatcharitaAudio.map((lang) => _ChapterList(language: lang)).toList(),
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  final SatcharitaLanguage language;
  const _ChapterList({required this.language});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: language.chapters.length,
      itemBuilder: (context, i) {
        final chapter = language.chapters[i];
        return _ChapterTile(index: i + 1, track: chapter);
      },
    );
  }
}

class _ChapterTile extends ConsumerWidget {
  final int index;
  final AudioTrack track;
  const _ChapterTile({required this.index, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(chapterAudioProvider);
    final isThisTrack = audioState.track?.fileName == track.fileName;
    final isDownloading = isThisTrack && audioState.status == ChapterAudioStatus.downloading;
    final isPlaying = isThisTrack && audioState.status == ChapterAudioStatus.playing;
    final isActive = isThisTrack && audioState.isActive;
    final isError = isThisTrack && audioState.status == ChapterAudioStatus.error;

    // Show error snackbar when playback fails
    if (isError && audioState.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audio error: ${audioState.errorMessage}'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppColors.saffron : AppColors.lightGrey,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Chapter number badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.saffron.withOpacity(0.18)
                        : AppColors.saffron.withOpacity(0.10),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isActive ? AppColors.saffron : AppColors.darkText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Play / Pause / Loading button
                GestureDetector(
                  onTap: () =>
                      ref.read(chapterAudioProvider.notifier).toggleAudio(track),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: isDownloading
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              value: audioState.downloadProgress,
                              strokeWidth: 2.5,
                              color: AppColors.saffron,
                            ),
                          )
                        : Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: AppColors.saffron,
                            size: 26,
                          ),
                  ),
                ),
              ],
            ),
            // Download progress bar
            if (isDownloading && audioState.downloadProgress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: audioState.downloadProgress,
                backgroundColor: AppColors.lightGrey,
                color: AppColors.saffron,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 2),
              Text(
                'Loading… ${(audioState.downloadProgress! * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, color: AppColors.mediumText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini player docked at the bottom of the Satcharitra Audio screen
// ---------------------------------------------------------------------------

class _SatcharitaMiniPlayer extends ConsumerWidget {
  final ChapterAudioState audioState;
  const _SatcharitaMiniPlayer({required this.audioState});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chapterAudioProvider.notifier);
    final track = audioState.track;
    if (track == null) return const SizedBox.shrink();

    final isDownloading = audioState.status == ChapterAudioStatus.downloading;
    final isPlaying = audioState.status == ChapterAudioStatus.playing;
    final total = audioState.total;
    final position = audioState.position;
    final sliderMax =
        total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
    final sliderVal =
        position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.lightGrey)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16, 10, 16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.saffron.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.headphones_rounded,
                    color: AppColors.saffron, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isDownloading && audioState.downloadProgress != null)
                      Text(
                        'Loading… ${(audioState.downloadProgress! * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.mediumText),
                      )
                    else
                      Text(
                        '${_fmt(position)}  /  ${_fmt(total)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.mediumText),
                      ),
                  ],
                ),
              ),
              if (isDownloading)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    value: audioState.downloadProgress,
                    strokeWidth: 2.5,
                    color: AppColors.saffron,
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    color: AppColors.saffron,
                    size: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => notifier.toggleAudio(track),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 20, color: AppColors.mediumText),
                padding: EdgeInsets.zero,
                onPressed: () => notifier.stop(),
              ),
            ],
          ),
          if (!isDownloading && total.inSeconds > 0)
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: AppColors.saffron,
                inactiveTrackColor: AppColors.lightGrey,
                thumbColor: AppColors.saffron,
                overlayColor: AppColors.saffron.withOpacity(0.15),
              ),
              child: Slider(
                value: sliderVal,
                min: 0,
                max: sliderMax,
                onChanged: (v) =>
                    notifier.seek(Duration(milliseconds: v.round())),
              ),
            ),
        ],
      ),
    );
  }
}
