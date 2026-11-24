import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTextScaleKey = 'app_text_scale';

/// App-wide text size chosen by the reader, multiplied with the phone's own
/// font-size setting. Three plain steps instead of a slider.
class TextScaleNotifier extends StateNotifier<double> {
  static const steps = [1.0, 1.2, 1.4];
  TextScaleNotifier() : super(steps.first) {
    _load();
  }

  Future<void> _load() async {
    final saved = (await SharedPreferences.getInstance()).getDouble(_kTextScaleKey);
    if (mounted && saved != null && steps.contains(saved)) state = saved;
  }

  Future<void> set(double scale) async {
    if (!steps.contains(scale)) return;
    state = scale;
    await (await SharedPreferences.getInstance()).setDouble(_kTextScaleKey, scale);
  }
}

final textScaleProvider =
    StateNotifierProvider<TextScaleNotifier, double>((ref) => TextScaleNotifier());
