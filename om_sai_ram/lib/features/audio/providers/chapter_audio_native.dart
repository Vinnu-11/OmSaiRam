// Native (Android/iOS/desktop) — download to cache, then play from file.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../data/audio_data.dart';
import 'chapter_audio_provider.dart';

final Dio _dio = Dio();

Future<String> _localPath(AudioTrack track) async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/satcharitra_audio/${track.fileName}';
}

Future<bool> _isDownloaded(AudioTrack track) async {
  final path = await _localPath(track);
  return File(path).existsSync();
}

Future<void> downloadOrPlay(
  ChapterAudioNotifier notifier,
  AudioPlayer player,
  AudioTrack track,
) async {
  if (await _isDownloaded(track)) {
    final path = await _localPath(track);
    await notifier.playFromFile(path);
    return;
  }

  notifier.setDownloading();
  final path = await _localPath(track);
  await Directory(path).parent.create(recursive: true);

  await _dio.download(
    track.downloadUrl,
    path,
    onReceiveProgress: (received, total) {
      final progress = total > 0 ? received / total : 0.0;
      notifier.updateDownloadProgress(progress);
    },
  );

  await notifier.playFromFile(path);
}
