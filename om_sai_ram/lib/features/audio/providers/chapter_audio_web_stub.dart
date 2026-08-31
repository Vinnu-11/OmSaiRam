// Web stub — native download logic is never called on web.
// The provider uses direct URL streaming for web instead.

import 'package:just_audio/just_audio.dart';
import '../data/audio_data.dart';
import 'chapter_audio_provider.dart';

Future<void> downloadOrPlay(
  ChapterAudioNotifier notifier,
  AudioPlayer player,
  AudioTrack track,
) async {
  throw UnsupportedError('downloadOrPlay should not be called on web');
}
