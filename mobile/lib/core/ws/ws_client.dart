import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A typed wrapper over a single chat-thread WebSocket.
///
/// Connects to `WS /ws/thread/:id?token=<jwt>` and exposes a broadcast stream of
/// decoded server frames (`message`, `read_receipt`, `thread_expired`).
class ThreadSocket {
  ThreadSocket({
    required String wsBaseUrl,
    required String threadId,
    required String token,
  }) : _uri = Uri.parse('$wsBaseUrl/ws/thread/$threadId?token=$token');

  final Uri _uri;
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;

  Stream<Map<String, dynamic>> connect() {
    final channel = WebSocketChannel.connect(_uri);
    _channel = channel;
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _controller = controller;

    channel.stream.listen(
      (event) {
        try {
          final decoded = jsonDecode(event as String);
          if (decoded is Map<String, dynamic>) controller.add(decoded);
        } catch (_) {
          // Ignore malformed frames.
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    return controller.stream;
  }

  void sendMessage(String body) => _send({'type': 'message', 'body': body});

  void sendRead(String upToMessageId) =>
      _send({'type': 'read', 'up_to_message_id': upToMessageId});

  void sendHeartbeat(double lat, double lng) =>
      _send({'type': 'heartbeat', 'lat': lat, 'lng': lng});

  void _send(Map<String, dynamic> frame) {
    _channel?.sink.add(jsonEncode(frame));
  }

  Future<void> close() async {
    await _channel?.sink.close();
    await _controller?.close();
  }
}
