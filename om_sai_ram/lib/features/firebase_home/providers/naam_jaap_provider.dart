import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Naam Jaap progress, kept on this device only. Counts restart each day.
class NaamJaapState {
  static const beads = 108;
  /// Chants in the current mala, 0 to 107.
  final int count;
  /// Malas completed today.
  final int malas;
  const NaamJaapState({this.count = 0, this.malas = 0});
}

class NaamJaapNotifier extends StateNotifier<NaamJaapState> {
  final DateTime Function() _now;
  NaamJaapNotifier({DateTime Function() now = DateTime.now})
      : _now = now, super(const NaamJaapState()) {
    _load();
  }

  String get _today {
    final now = _now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || prefs.getString('jaap_date') != _today) return;
    final count = prefs.getInt('jaap_count') ?? 0, malas = prefs.getInt('jaap_malas') ?? 0;
    if (count < 0 || count >= NaamJaapState.beads || malas < 0) return;
    state = NaamJaapState(count: count, malas: malas);
  }

  Future<void> _save() async {
    // Captured first: the notifier may be disposed before the writes finish.
    final today = _today, count = state.count, malas = state.malas;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jaap_date', today);
    await prefs.setInt('jaap_count', count);
    await prefs.setInt('jaap_malas', malas);
  }

  /// Counts one chant. Returns true when this chant completed a mala.
  bool chant() {
    final completed = state.count + 1 == NaamJaapState.beads;
    state = completed
        ? NaamJaapState(malas: state.malas + 1)
        : NaamJaapState(count: state.count + 1, malas: state.malas);
    _save();
    return completed;
  }

  void reset() {
    state = const NaamJaapState();
    _save();
  }
}

final naamJaapProvider =
    StateNotifierProvider<NaamJaapNotifier, NaamJaapState>((ref) => NaamJaapNotifier());
