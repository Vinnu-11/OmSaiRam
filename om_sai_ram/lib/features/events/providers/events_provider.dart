// Om Sai Ram

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/events_repository.dart';
import '../data/festival_model.dart';

final festivalsProvider =
    FutureProvider.autoDispose<List<Festival>>((ref) async {
  final repo = ref.read(eventsRepositoryProvider);
  return repo.getFestivals();
});
