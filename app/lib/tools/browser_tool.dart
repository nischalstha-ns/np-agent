import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'tool.dart';

/// REAL: Web tool backed by real HTTP (package:http).
///
/// Actions:
/// - `open`  {url}                  -> launches the URL in the OS default
///   browser via xdg-open / open / cmd start (needs approval: leaves NP).
/// - `fetch` {url, method?, headers?, maxBytes?} -> {statusCode, body, ...}
///   raw body fetch with byte cap.
/// - `page`  {url, maxBytes?}       -> {statusCode, title, text, links}:
///   GETs the page, extracts the <title>, visible text (tags/scripts/styles
///   stripped, entities decoded), and outbound href links.
class BrowserTool extends Tool {
  static const int _defaultMaxBytes = 512 * 1024;

  final http.Client _client = http.Client();

  /// REAL: The name.
  @override
  String get name => 'browser';

  /// REAL: The description.
  @override
  String get description =>
      'Open URLs in the system browser, fetch raw URL bodies over HTTP(S), '
      'or extract a page\'s title, visible text and links.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['open', 'fetch', 'page'],
          'required': true,
        },
        'url': {'type': 'string', 'required': true},
        'method': {'type': 'string', 'required': false},
        'headers': {'type': 'object', 'required': false},
        'maxBytes': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'open -> {launched}; fetch -> {statusCode, body, ...}; '
            'page -> {statusCode, title, text, links}',
      };

  /// REAL: Only http(s) URLs; `open` leaves the sandbox and needs approval.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    /// REAL: The url.
    final url = call.args['url'] as String? ?? '';
    /// REAL: The uri.
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return const PermissionDecision.denied('Only http(s) URLs are allowed');
    }
    switch (call.action) {
      case 'open':
        return const PermissionDecision.needsApproval(
            'Opening a browser leaves the NP sandbox; needs user approval');
      case 'fetch':
      case 'page':
        return const PermissionDecision.allowed('http fetch');
      default:
        return PermissionDecision.denied('Unknown browser action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    /// REAL: The url.
    final url = (call.args['url'] as String?) ?? '';
    try {
      switch (call.action) {
        case 'open':
          await _launchUrl(url);
          return ToolResult.ok({'launched': true, 'url': url});
        case 'fetch':
          return ToolResult.ok(await _fetch(call, url));
        case 'page':
          return ToolResult.ok(await _page(call, url));
        default:
          return ToolResult.fail('Unknown browser action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('browser.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data;
    if (data is! Map) return false;
    switch (call.action) {
      case 'open':
        return data['launched'] == true;
      case 'fetch':
        return data['statusCode'] is int && data['body'] is String;
      case 'page':
        return data['statusCode'] is int &&
            data['title'] is String &&
            data['text'] is String &&
            data['links'] is List;
      default:
        return true;
    }
  }

  /// REAL: Launch a URL in the OS default browser.
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

  /// REAL: Raw HTTP(S) fetch with a byte cap.
  Future<Map<String, dynamic>> _fetch(ToolCall call, String url) async {
    /// REAL: The method.
    final method = (call.args['method'] as String? ?? 'GET').toUpperCase();
    /// REAL: The max bytes.
    final maxBytes = (call.args['maxBytes'] as int?) ?? _defaultMaxBytes;
    /// REAL: The extra headers.
    final extraHeaders =
        Map<String, String>.from(call.args['headers'] as Map? ?? const {});

    /// REAL: The request.
    final request = http.Request(method, Uri.parse(url))
      ..headers['user-agent'] = 'NP-agent/0.1'
      ..headers.addAll(extraHeaders);
    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('HTTP fetch timed out: $url'),
          );
    } catch (e) {
      throw StateError('HTTP request failed for $url: $e');
    }

    /// REAL: The bytes.
    final bytes = <int>[];
    /// REAL: The truncated.
    var truncated = false;
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        /// REAL: The keep.
        final keep = maxBytes - bytes.length;
        if (keep > 0) bytes.addAll(chunk.sublist(0, keep));
        truncated = true;
        break;
      }
      bytes.addAll(chunk);
    }
    /// REAL: The body.
    String body;
    try {
      body = String.fromCharCodes(bytes);
    } catch (_) {
      body = '[binary body, ${bytes.length} bytes]';
    }
    return {
      'url': url,
      'statusCode': response.statusCode,
      'truncated': truncated,
      'bytes': bytes.length,
      'contentType': response.headers['content-type'],
      'body': body,
    };
  }

  /// REAL: Fetch a page and extract title, visible text and links.
  Future<Map<String, dynamic>> _page(ToolCall call, String url) async {
    final fetched = await _fetch(call, url);
    /// REAL: The html.
    final html = fetched['body'] as String;
    /// REAL: The base.
    final base = Uri.parse(url);
    return {
      'url': url,
      'statusCode': fetched['statusCode'],
      'title': _extractTitle(html),
      'text': _extractText(html, 8000),
      'links': _extractLinks(html, base, 100),
    };
  }

  /// REAL: Extract the <title> from HTML.
  String _extractTitle(String html) {
    /// REAL: The m.
    final m =
        RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
            .firstMatch(html);
    return m == null ? '' : _decodeEntities(m.group(1)!.trim());
  }

  /// REAL: Strip scripts/styles/tags and collapse whitespace.
  String _extractText(String html, int maxChars) {
    /// REAL: The text.
    var text = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>',
            caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>',
            caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = _decodeEntities(text);
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > maxChars
        ? '${text.substring(0, maxChars)}...'
        : text;
  }

  /// REAL: Extract absolute outbound hrefs (deduped, capped).
  List<String> _extractLinks(String html, Uri base, int max) {
    /// REAL: The links.
    final links = <String>[];
    /// REAL: The seen.
    final seen = <String>{};
    /// REAL: The re.
    final re = RegExp(
        r'''<a\s[^>]*href\s*=\s*["']([^"']+)["']''',
        caseSensitive: false);
    for (final m in re.allMatches(html)) {
      /// REAL: The raw.
      final raw = m.group(1)!.trim();
      if (raw.isEmpty ||
          raw.startsWith('#') ||
          raw.startsWith('javascript:') ||
          raw.startsWith('mailto:')) {
        continue;
      }
      /// REAL: The resolved.
      final resolved = base.resolve(raw).toString();
      if (seen.add(resolved)) links.add(resolved);
      if (links.length >= max) break;
    }
    return links;
  }

  /// REAL: Decode common HTML entities.
  String _decodeEntities(String s) {
    /// REAL: The entities.
    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&nbsp;': ' ',
      '&apos;': "'",
    };
    /// REAL: The out.
    var out = s;
    entities.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
    out = out.replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) =>
            String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    return out;
  }
}
