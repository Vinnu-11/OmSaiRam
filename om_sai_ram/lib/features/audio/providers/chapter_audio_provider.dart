// Om Sai Ram
// Provider that manages per-chapter audio: download tracking + playback.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../data/audio_data.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum ChapterAudioStatus {
  idle,         // no audio for this chapter / not started
  downloading,  // actively downloading
  buffering,    // audio ready; player buffering
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

  final AudioPlayer _player = AudioPlayer();
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  // Subscribe to player events once when the notifier is created.
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

  /// Path where a track is cached locally.
  Future<String> _localPath(AudioTrack track) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/satcharitra_audio/${track.fileName}';
  }

  Future<bool> _isDownloaded(AudioTrack track) async {
    final path = await _localPath(track);
    return File(path).existsSync();
  }

  /// Tap handler called from the reader.
  /// • If already playing this track → pause/resume.
  /// • If a different track is playing → stop it, start new one.
  /// • If idle → download-if-needed, then play.
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
      final downloaded = await _isDownloaded(track);
      if (downloaded) {
        await _play(track);
      } else {
        await _downloadThenPlay(track);
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

  Future<void> _downloadThenPlay(AudioTrack track) async {
    state = state.copyWith(
      status: ChapterAudioStatus.downloading,
      downloadProgress: 0,
    );

    final path = await _localPath(track);
    await Directory(path).parent.create(recursive: true);

    _cancelToken = CancelToken();
    await _dio.download(
      track.downloadUrl,
      path,
      cancelToken: _cancelToken,
      onReceiveProgress: (received, total) {
        if (!mounted) return;
        final progress = total > 0 ? received / total : 0.0;
        state = state.copyWith(downloadProgress: progress);
      },
    );

    if (!mounted) return;
    await _play(track);
  }

  Future<void> _play(AudioTrack track) async {
    final path = await _localPath(track);
    state = state.copyWith(
      status: ChapterAudioStatus.buffering,
      clearDownloadProgress: true,
    );
    await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _stopAndReset();
  }

  Future<void> _stopAndReset() async {
    _cancelToken?.cancel();
    _cancelToken = null;
    await _player.stop();
    if (mounted) {
      state = const ChapterAudioState();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _dio.close();
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
