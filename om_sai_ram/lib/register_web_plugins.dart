import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio_web/just_audio_web.dart';

void registerJustAudioWeb() {
  JustAudioPlatform.instance = JustAudioPlugin();
}
