// Tests for BrowserTool and ResearchTool.
// BrowserTool is exercised against a local HttpServer (hermetic, no real
// network). ResearchTool hits hardcoded public URLs, so its test only
// asserts the graceful offline/online contract (never throws, results list).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/tools/browser_tool.dart';
import 'package:np/tools/productivity_tools.dart';
import 'package:np/tools/tool.dart';

const _pageHtml = '''
<!DOCTYPE html>
<html>
<head><title>NP Test Page</title></head>
<body>
<h1>Hello from NP</h1>
<p>This is a test page for the browser tool.</p>
<a href="https://example.com/next">next page</a>
<script>var x = 1;</script>
</body>
</html>
''';

Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (req.uri.path == '/page') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(_pageHtml);
    } else if (req.uri.path == '/json') {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"ok": true}');
    } else {
      req.response.statusCode = 404;
      req.response.write('not found');
    }
    await req.response.close();
  });
  return server;
}

void main() {
  group('BrowserTool permission policy', () {
    final tool = BrowserTool();

    test('non-http urls are denied', () async {
      final decision = await tool.checkPermission(const ToolCall(
          tool: 'browser', action: 'fetch', args: {'url': 'file:///etc/passwd'}));
      expect(decision.isDenied, isTrue);
    });

    test('open needs approval, fetch/page are allowed', () async {
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'browser',
                  action: 'open',
                  args: {'url': 'https://example.com'})))
              .needsApproval,
          isTrue);
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'browser',
                  action: 'fetch',
                  args: {'url': 'https://example.com'})))
              .isAllowed,
          isTrue);
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'browser',
                  action: 'page',
                  args: {'url': 'https://example.com'})))
              .isAllowed,
          isTrue);
    });
  });

  group('BrowserTool against a local server', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await _startServer();
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('fetch returns status and body', () async {
      final tool = BrowserTool();
      final result = await tool.execute(ToolCall(
          tool: 'browser', action: 'fetch', args: {'url': '$base/json'}));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['statusCode'], 200);
      expect(data['body'], contains('"ok": true'));
      final call = ToolCall(
          tool: 'browser', action: 'fetch', args: {'url': '$base/json'});
      expect(await tool.verify(call, result), isTrue);
    });

    test('page extracts title, text and links', () async {
      final tool = BrowserTool();
      final result = await tool.execute(ToolCall(
          tool: 'browser', action: 'page', args: {'url': '$base/page'}));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['statusCode'], 200);
      expect(data['title'], 'NP Test Page');
      expect(data['text'], contains('Hello from NP'));
      expect(data['text'], isNot(contains('var x = 1'))); // scripts stripped
      final links = data['links'] as List;
      expect(links, contains('https://example.com/next'));
      final call = ToolCall(
          tool: 'browser', action: 'page', args: {'url': '$base/page'});
      expect(await tool.verify(call, result), isTrue);
    });

    test('fetch of a 404 still returns a result', () async {
      final tool = BrowserTool();
      final result = await tool.execute(ToolCall(
          tool: 'browser', action: 'fetch', args: {'url': '$base/missing'}));
      expect(result.success, isTrue);
      expect((result.data as Map)['statusCode'], 404);
    });
  });

  group('ResearchTool graceful contract', () {
    test('search never throws; honors the offline contract', () async {
      final tool = ResearchTool();
      final result = await tool.execute(const ToolCall(
          tool: 'research', action: 'search', args: {'query': 'kathmandu'}));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['results'], isA<List>());
      if (data['offline'] == true) {
        expect((data['results'] as List), isEmpty);
      }
      final call = const ToolCall(
          tool: 'research', action: 'search', args: {'query': 'kathmandu'});
      expect(await tool.verify(call, result), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('summarize keeps the summary/sources contract', () async {
      final tool = ResearchTool();
      final result = await tool.execute(const ToolCall(
          tool: 'research', action: 'summarize', args: {'query': 'kathmandu'}));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['summary'], isA<String>());
      expect(data['sources'], isA<List>());
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'research', action: 'search', args: {'query': 'x'})))
              .isAllowed,
          isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
