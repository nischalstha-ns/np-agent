import 'dart:io';

/// Real platform stats (dart:io available).
Future<Map<String, String>> collectPerfStats({
  required DateTime startedAt,
  required int messageCount,
  required int toolCallCount,
}) async {
  final rssMb = ProcessInfo.currentRss / (1024 * 1024);
  final uptime = DateTime.now().difference(startedAt);
  String uptimeStr;
  if (uptime.inHours > 0) {
    uptimeStr = '${uptime.inHours}h ${uptime.inMinutes % 60}m';
  } else if (uptime.inMinutes > 0) {
    uptimeStr = '${uptime.inMinutes}m ${uptime.inSeconds % 60}s';
  } else {
    uptimeStr = '${uptime.inSeconds}s';
  }
  return {
    'Process RSS': '${rssMb.toStringAsFixed(1)} MB',
    'Dart version': Platform.version.split(' ').first,
    'Operating system':
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion.split(' ').first}',
    'Processors': '${Platform.numberOfProcessors} cores',
    'App uptime': uptimeStr,
    'Chat messages': '$messageCount',
    'Tool calls (session)': '$toolCallCount',
  };
}
