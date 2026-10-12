/// Placeholder stats where dart:io is unavailable (e.g. web builds).
Future<Map<String, String>> collectPerfStats({
  required DateTime startedAt,
  required int messageCount,
  required int toolCallCount,
}) async {
  final uptime = DateTime.now().difference(startedAt);
  return {
    'Process RSS': 'n/a on this platform',
    'Dart version': 'n/a on this platform',
    'Operating system': 'n/a on this platform',
    'Processors': 'n/a on this platform',
    'App uptime': '${uptime.inSeconds}s',
    'Chat messages': '$messageCount',
    'Tool calls (session)': '$toolCallCount',
  };
}
