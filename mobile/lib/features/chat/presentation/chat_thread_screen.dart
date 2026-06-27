import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/ws/ws_client.dart';
import '../data/threads_repository.dart';

/// Real-time chat thread. Connects to the WebSocket, streams incoming frames,
/// shows a TTL/out-of-range banner, and sends messages + read receipts.
///
/// Note: the backend delivers messages over the socket (no history endpoint),
/// so the transcript starts from connect time.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _input = TextEditingController();
  final _messages = <Map<String, dynamic>>[];
  ThreadSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _expired = false;
  String? _myId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  void _connect() {
    final config = ref.read(appConfigProvider);
    final supabase = ref.read(supabaseProvider);
    final token = supabase.auth.currentSession?.accessToken;
    _myId = supabase.auth.currentUser?.id;
    if (token == null) return;

    final socket = ThreadSocket(
      wsBaseUrl: config.wsBaseUrl,
      threadId: widget.threadId,
      token: token,
    );
    _socket = socket;
    _sub = socket.connect().listen(_onFrame, onError: (_) {});
  }

  void _onFrame(Map<String, dynamic> frame) {
    switch (frame['type']) {
      case 'message':
        setState(() => _messages.add(frame));
        final id = frame['id'];
        if (id is String) _socket?.sendRead(id);
      case 'thread_expired':
        setState(() => _expired = true);
      case 'read_receipt':
        // Could mark a sent message as read; omitted for brevity.
        break;
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || _expired) return;
    _socket?.sendMessage(text);
    _input.clear();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: 'End chat',
            icon: const Icon(Icons.timer_off_outlined),
            onPressed: () =>
                ref.read(threadsRepositoryProvider).forceExpire(widget.threadId),
          ),
        ],
      ),
      body: Column(
        children: [
          const _TtlBanner(),
          if (_expired)
            MaterialBanner(
              content: const Text('This conversation has ended (out of range).'),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final mine = m['sender_id'] == _myId;
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text((m['body'] ?? '').toString()),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_expired,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _expired ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TtlBanner extends StatelessWidget {
  const _TtlBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Text(
        'Messages disappear after 24h or when you move out of range.',
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
      ),
    );
  }
}
