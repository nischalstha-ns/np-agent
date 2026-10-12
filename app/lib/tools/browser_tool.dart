import 'dart:convert';
import 'dart:io';

import 'tool.dart';

/// Real local browser/network tool.
///
/// Actions:
/// - `open`  {url}                  -> launches the URL in the OS default
///   browser via xdg-open / open / cmd start (needs approval: leaves NP).
/// - `fetch` {url, method?, headers?, maxBytes?} -> {statusCode, body, ...}
///   performed with [HttpClient]; real network I/O.
class BrowserTool extends Tool {
  static const int _defaultMaxBytes = 512 * 1024;

  @override
  String get name => 'browser';

  @override
  String get description =>
      'Open URLs in the system browser, or fetch a URL body over HTTP(S).';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['open', 'fetch'],
          'required': true,
        },
        'url': {'type': 'string', 'required': true},
        'method': {'type': 'string', 'required': false},
        'headers': {'type': 'object', 'required': false},
        'maxBytes': {'type': 'int', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'open -> {launched}; fetch -> {statusCode, body, ...}',
      };

  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    final url = call.args['url'] as String? ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return const PermissionDecision.denied('Only http(s) URLs are allowed');
    }
    switch (call.action) {
      case 'open':
        return const PermissionDecision.needsApproval(
            'Opening a browser leaves the NP sandbox; needs user approval');
      case 'fetch':
        return const PermissionDecision.allowed('http fetch');
      default:
        return PermissionDecision.denied('Unknown browser action "${call.action}"');
    }
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final url = (call.args['url'] as String?) ?? '';
    try {
      switch (call.action) {
        case 'open':
          await _launchUrl(url);
          return ToolResult.ok({'launched': true, 'url': url});
        case 'fetch':
          return ToolResult.ok(await _fetch(call, url));
        default:
          return ToolResult.fail('Unknown browser action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('browser.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    final data = result.data;
    if (data is! Map) return false;
    switch (call.action) {
      case 'open':
        return data['launched'] == true;
      case 'fetch':
        return data['statusCode'] is int && data['body'] is String;
      default:
        return true;
    }
  }

  Future<void> _launchUrl(String url) async {
    if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      throw UnsupportedError(
          'URL launch is not supported on ${Platform.operatingSystem}');
    }
  }

  Future<Map<String, dynamic>> _fetch(ToolCall call, String url) async {
    final method = (call.args['method'] as String? ?? 'GET').toUpperCase();
    final maxBytes = (call.args['maxBytes'] as int?) ?? _defaultMaxBytes;
    final extraHeaders =
        Map<String, String>.from(call.args['headers'] as Map? ?? const {});

    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      request.headers.set('user-agent', 'NP-agent/0.1');
      extraHeaders.forEach(request.headers.set);
      final response = await request.close();

      final builder = BytesBuilder();
      var received = 0;
      var truncated = false;
      await for (final chunk in response) {
        if (received + chunk.length > maxBytes) {
          final keep = maxBytes - received;
          if (keep > 0) builder.add(chunk.sublist(0, keep));
          received = maxBytes;
          truncated = true;
          break;
        }
        builder.add(chunk);
        received += chunk.length;
      }
      String body;
      try {
        body = utf8.decode(builder.takeBytes(), allowMalformed: true);
      } catch (_) {
        body = '[binary body, ${builder.length} bytes]';
      }
      return {
        'url': url,
        'statusCode': response.statusCode,
        'truncated': truncated,
        'bytes': received,
        'contentType': response.headers.contentType?.toString(),
        'body': body,
      };
    } finally {
      client.close(force: true);
    }
  }
}
