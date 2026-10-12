/// Chat bubble model (UI-agnostic).
///
/// Rendering (Material widgets) is intentionally left out of this scaffold —
/// these classes carry the state that widgets will render, so the logic is
/// testable without Flutter.
class ChatBubble {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String text;
  final DateTime at;

  ChatBubble({
    String? id,
    required this.role,
    required this.text,
    DateTime? at,
  })  : id = id ?? 'b_${DateTime.now().microsecondsSinceEpoch}',
        at = at ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  /// Plain-text rendering used by the console bootstrap and logs.
  String format() => '[$role @ ${_time()}] $text';

  String _time() {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'at': at.toIso8601String(),
      };
}
