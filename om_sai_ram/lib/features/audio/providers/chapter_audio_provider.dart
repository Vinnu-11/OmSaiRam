// Om Sai Ram
// Provider that manages per-chapter audio: download tracking + playback.
// On web: streams directly from URL (no filesystem).
// On native: downloads to cache, then plays locally.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../data/audio_data.dart';

// Conditional imports for native-only file caching.
import 'chapter_audio_native.dart'
    if (dart.library.html) 'chapter_audio_web_stub.dart' as platform;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum ChapterAudioStatus {
  idle,         // no audio for this chapter / not started
  downloading,  // actively downloading (native only)
  buffering,    // player loading / buffering the stream
  playing,
  paused,
  stopped,
  error,
}

class ChapterAudioState {
  final ChapterAudioStatus status;
  /// 0.0–1.0 download progress; null when not downloading.
  final double? downloadProgress;
  final Duration position;
  final Duration total;
  final String? errorMessage;
  final AudioTrack? track;

  const ChapterAudioState({
    this.status = ChapterAudioStatus.idle,
    this.downloadProgress,
    this.position = Duration.zero,
    this.total = Duration.zero,
    this.errorMessage,
    this.track,
  });

  bool get isActive =>
      status == ChapterAudioStatus.playing ||
      status == ChapterAudioStatus.paused ||
      status == ChapterAudioStatus.buffering;

  ChapterAudioState copyWith({
    ChapterAudioStatus? status,
    double? downloadProgress,
    bool clearDownloadProgress = false,
    Duration? position,
    Duration? total,
    String? errorMessage,
    AudioTrack? track,
  }) {
    return ChapterAudioState(
      status: status ?? this.status,
      downloadProgress:
          clearDownloadProgress ? null : (downloadProgress ?? this.downloadProgress),
      position: position ?? this.position,
      total: total ?? this.total,
      errorMessage: errorMessage ?? this.errorMessage,
      track: track ?? this.track,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ChapterAudioNotifier extends StateNotifier<ChapterAudioState> {
  ChapterAudioNotifier() : super(const ChapterAudioState());

  final AudioPlayer _player = AudioPlayer(
    // On web, audio_session's platform channel methods (setActive,
    // becomingNoisyEventStream, etc.) are not implemented in
    // audio_session_web which causes "No implementation found" errors
    // in release builds. Disable these features on web.
    handleInterruptions: !kIsWeb,
    handleAudioSessionActivation: !kIsWeb,
  );

  bool _subscribed = false;
  void _subscribeToPlayer() {
    if (_subscribed) return;
    _subscribed = true;

    _player.playerStateStream.listen((ps) {
      if (!mounted) return;
      switch (ps.processingState) {
        case ProcessingState.buffering:
        case ProcessingState.loading:
          if (state.status != ChapterAudioStatus.downloading) {
            state = state.copyWith(status: ChapterAudioStatus.buffering);
          }
        case ProcessingState.ready:
          state = state.copyWith(
            status: ps.playing
                ? ChapterAudioStatus.playing
                : ChapterAudioStatus.paused,
            clearDownloadProgress: true,
          );
        case ProcessingState.completed:
          _player.seek(Duration.zero);
          _player.pause();
          state = state.copyWith(
            status: ChapterAudioStatus.paused,
            position: Duration.zero,
          );
        case ProcessingState.idle:
          break;
      }
    });

    _player.positionStream.listen((pos) {
      if (!mounted) return;
      state = state.copyWith(position: pos);
    });

    _player.durationStream.listen((dur) {
      if (!mounted) return;
      if (dur != null) state = state.copyWith(total: dur);
    });
  }

  /// Tap handler — play/pause toggle, or start new track.
  Future<void> toggleAudio(AudioTrack track) async {
    _subscribeToPlayer();

    // Same track — toggle play/pause.
    if (state.track?.fileName == track.fileName && state.isActive) {
      if (state.status == ChapterAudioStatus.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }

    // Different track or stopped — reset and start fresh.
    await _stopAndReset();
    state = state.copyWith(track: track);

    try {
      if (kIsWeb) {
        await _streamFromUrl(track);
      } else {
        await platform.downloadOrPlay(this, _player, track);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          status: ChapterAudioStatus.error,
          errorMessage: e.toString(),
        );
      }
    }
  }

  /// Web: stream directly from URL — plays immediately while buffering.
  Future<void> _streamFromUrl(AudioTrack track) async {
    state = state.copyWith(status: ChapterAudioStatus.buffering);
    // preload: false so setUrl returns immediately without waiting for metadata.
    // play() then triggers actual loading + playback in parallel.
    await _player.setUrl(track.downloadUrl, preload: false);
    await _player.play();
  }

  /// Called from the native helper to update download progress.
  void updateDownloadProgress(double progress) {
    if (!mounted) return;
    state = state.copyWith(downloadProgress: progress);
  }

  /// Called from the native helper to transition to buffering + play.
  Future<void> playFromFile(String path) async {
    if (!mounted) return;
    state = state.copyWith(
      status: ChapterAudioStatus.buffering,
      clearDownloadProgress: true,
    );
    await _player.setFilePath(path);
    await _player.play();
  }

  /// Mark as downloading.
  void setDownloading() {
    if (!mounted) return;
    state = state.copyWith(
      status: ChapterAudioStatus.downloading,
      downloadProgress: 0,
    );
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _stopAndReset();
  }

  Future<void> _stopAndReset() async {
    await _player.stop();
    if (mounted) {
      state = const ChapterAudioState();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider — single global instance so audio survives screen transitions.
// ---------------------------------------------------------------------------

final chapterAudioProvider =
    StateNotifierProvider<ChapterAudioNotifier, ChapterAudioState>(
  (ref) => ChapterAudioNotifier(),
);
