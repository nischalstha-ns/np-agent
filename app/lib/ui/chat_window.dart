import 'dart:async';

import '../agents/np_core.dart';
import 'bubble.dart';

/// Chat window state controller, wired to the real [NpCore] pipeline.
///
/// A Flutter widget layer would listen to [messages] (a broadcast stream of
/// the full bubble list) and call [send]. This class owns no widgets — it is
/// the state the widgets render.
class ChatWindowController {
  final NpCore core;
  final String sessionId;

  final _messages = StreamController<List<ChatBubble>>.broadcast();
  final List<ChatBubble> _list = [];
  bool _busy = false;

  ChatWindowController({required this.core, this.sessionId = 'default'});

  /// Broadcast stream of the current bubble list (emitted on every change).
  Stream<List<ChatBubble>> get messages => _messages.stream;

  /// Synchronous snapshot of the current bubbles.
  List<ChatBubble> get current => List.unmodifiable(_list);

  bool get isBusy => _busy;

  /// Send user text through the pipeline and append the reply.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    _busy = true;
    _add(ChatBubble(role: 'user', text: trimmed));
    try {
      final reply = await core.handle(trimmed, sessionId: sessionId);
      _add(ChatBubble(role: 'assistant', text: reply));
    } catch (e) {
      _add(ChatBubble(role: 'system', text: 'Error: $e'));
    } finally {
      _busy = false;
    }
  }

  /// Append a system notice (e.g. connectivity changes).
  void notice(String text) {
    _add(ChatBubble(role: 'system', text: text));
  }

  void clear() {
    _list.clear();
    _emit();
  }

  void _add(ChatBubble bubble) {
    _list.add(bubble);
    _emit();
  }

  void _emit() {
    if (!_messages.isClosed) _messages.add(List.unmodifiable(_list));
  }

  void dispose() => _messages.close();
}
