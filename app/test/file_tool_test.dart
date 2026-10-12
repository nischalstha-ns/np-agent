// Tests for FileTool: read/write/list roundtrips and the path-traversal guard.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/tools/file_tool.dart';
import 'package:np/tools/tool.dart';

void main() {
  group('FileTool basic actions (inside allowed roots)', () {
    late Directory root;
    late FileTool tool;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-file-');
      tool = FileTool(allowedRoots: [root.path]);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('write then read roundtrip', () async {
      final path = '${root.path}/note.txt';
      final writeCall =
          ToolCall(tool: 'file', action: 'write', args: {
        'path': path,
        'content': 'hello np',
      });
      expect((await tool.checkPermission(writeCall)).isAllowed, isTrue);

      final written = await tool.execute(writeCall);
      expect(written.success, isTrue);
      expect((written.data as Map)['bytesWritten'], 8);
      expect(await tool.verify(writeCall, written), isTrue);

      final readCall =
          ToolCall(tool: 'file', action: 'read', args: {'path': path});
      final read = await tool.execute(readCall);
      expect(read.success, isTrue);
      expect((read.data as Map)['content'], 'hello np');
      expect(await tool.verify(readCall, read), isTrue);
    });

    test('list / exists / stat / mkdir', () async {
      await tool.execute(ToolCall(tool: 'file', action: 'write', args: {
        'path': '${root.path}/a.txt',
        'content': 'a',
      }));
      await tool.execute(ToolCall(tool: 'file', action: 'mkdir', args: {
        'path': '${root.path}/sub',
      }));

      final list = await tool.execute(ToolCall(tool: 'file', action: 'list',
          args: {'dir': root.path}));
      expect(list.success, isTrue);
      expect(((list.data as Map)['entries'] as List).length, 2);

      final exists = await tool.execute(ToolCall(tool: 'file', action: 'exists',
          args: {'path': '${root.path}/a.txt'}));
      expect((exists.data as Map)['exists'], isTrue);

      final stat = await tool.execute(ToolCall(tool: 'file', action: 'stat',
          args: {'path': '${root.path}/a.txt'}));
      expect((stat.data as Map)['size'], 1);
    });

    test('copy and move', () async {
      final src = '${root.path}/src.txt';
      await tool.execute(ToolCall(tool: 'file', action: 'write', args: {
        'path': src,
        'content': 'data',
      }));

      final copy = await tool.execute(ToolCall(tool: 'file', action: 'copy',
          args: {'path': src, 'dest': '${root.path}/copy.txt'}));
      expect(copy.success, isTrue);
      expect(await tool.verify(
          ToolCall(tool: 'file', action: 'copy'), copy), isTrue);

      final move = await tool.execute(ToolCall(tool: 'file', action: 'move',
          args: {'path': src, 'dest': '${root.path}/moved.txt'}));
      expect(move.success, isTrue);
      expect(await File(src).exists(), isFalse);
      expect(await File('${root.path}/moved.txt').exists(), isTrue);
    });

    test('delete inside roots needs approval', () async {
      final decision = await tool.checkPermission(ToolCall(
          tool: 'file', action: 'delete', args: {'path': '${root.path}/x'}));
      expect(decision.needsApproval, isTrue);
    });

    test('unknown action is denied', () async {
      final decision = await tool
          .checkPermission(const ToolCall(tool: 'file', action: 'nuke'));
      expect(decision.isDenied, isTrue);
    });
  });

  group('FileTool traversal guard', () {
    late Directory rootA;
    late Directory rootB;
    late FileTool tool;

    setUp(() async {
      rootA = await Directory.systemTemp.createTemp('np-rootA-');
      rootB = await Directory.systemTemp.createTemp('np-rootB-');
      // Confine the tool to rootA only.
      tool = FileTool(allowedRoots: [rootA.path]);
    });

    tearDown(() async {
      for (final d in [rootA, rootB]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });

    test('write via ".." escape needs approval', () async {
      final escape = '${rootA.path}/../escape.txt';
      final decision = await tool.checkPermission(ToolCall(
          tool: 'file', action: 'write', args: {'path': escape, 'content': 'x'}));
      expect(decision.needsApproval, isTrue);
    });

    test('delete outside roots is denied at permission and execution', () async {
      final outside = '${rootB.path}/victim.txt';
      await File(outside).writeAsString('do not touch');

      final call =
          ToolCall(tool: 'file', action: 'delete', args: {'path': outside});
      final decision = await tool.checkPermission(call);
      expect(decision.isDenied, isTrue);

      final result = await tool.execute(call);
      expect(result.success, isFalse);
      expect(result.error, contains('Refusing to delete'));
      expect(await File(outside).exists(), isTrue); // untouched
    });

    test('copy destination outside roots fails', () async {
      final src = '${rootA.path}/s.txt';
      await File(src).writeAsString('s');
      final result = await tool.execute(ToolCall(
          tool: 'file',
          action: 'copy',
          args: {'path': src, 'dest': '${rootB.path}/d.txt'}));
      expect(result.success, isFalse);
      expect(result.error, contains('outside the allowed roots'));
    });

    test('write outside roots needs approval (not denied outright)', () async {
      final decision = await tool.checkPermission(ToolCall(
          tool: 'file',
          action: 'write',
          args: {'path': '${rootB.path}/w.txt', 'content': 'x'}));
      expect(decision.needsApproval, isTrue);
    });

    test('read of existing file inside roots is allowed', () async {
      final p = '${rootA.path}/r.txt';
      await File(p).writeAsString('readable');
      final decision = await tool.checkPermission(
          ToolCall(tool: 'file', action: 'read', args: {'path': p}));
      expect(decision.isAllowed, isTrue);
    });
  });
}
