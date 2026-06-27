import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/thread.dart';

/// Chat thread API access (POST/GET /threads, force-expire).
class ThreadsRepository {
  ThreadsRepository(this._api);

  final ApiClient _api;

  /// Open or reuse a thread with [peerId]; returns the thread id.
  Future<String> openThread(String peerId) async {
    final json = await _api.postJson('/threads', body: {'peer_id': peerId});
    return json['thread_id'] as String;
  }

  Future<List<ThreadSummary>> list() async {
    final json = await _api.getJson('/threads');
    final items = json['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => ThreadSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> forceExpire(String threadId) async {
    await _api.postJson('/threads/$threadId/expire');
  }
}

final threadsRepositoryProvider = Provider<ThreadsRepository>((ref) {
  return ThreadsRepository(ref.watch(apiClientProvider));
});

/// The current user's active threads.
final threadsListProvider = FutureProvider<List<ThreadSummary>>((ref) {
  return ref.watch(threadsRepositoryProvider).list();
});
