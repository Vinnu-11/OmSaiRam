// Om Sai Ram

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import 'festival_model.dart';

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository(ref.read(apiClientProvider));
});

class EventsRepository {
  final ApiClient _api;

  EventsRepository(this._api);

  Future<List<Festival>> getFestivals() async {
    final response = await _api.get('/festivals');
    final data = response.data as List<dynamic>;
    return data
        .map((json) => Festival.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
