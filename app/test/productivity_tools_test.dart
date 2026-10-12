// Tests for CalendarTool, TaskTool, EmailTool and DatabaseTool with
// throwaway stores in temp dirs (hermetic — never touches ~/.np).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/memory/in_memory_store.dart';
import 'package:np/tools/productivity_tools.dart';
import 'package:np/tools/tool.dart';
import 'package:np/tools/tool_registry.dart';

Future<PermissionDecision> _allow(ToolCall call) async =>
    const PermissionDecision.allowed('test override');

void main() {
  group('CalendarTool', () {
    late Directory root;
    late CalendarTool tool;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-cal-');
      tool = CalendarTool(storePath: '${root.path}/calendar.json');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('create then list', () async {
      final created = await tool.execute(ToolCall(
          tool: 'calendar',
          action: 'create',
          args: {
            'title': 'Dashain dinner',
            'start': '2026-10-20T19:00:00+05:45',
            'description': 'family'
          }));
      expect(created.success, isTrue);
      final event = (created.data as Map)['event'] as Map;
      expect(event['title'], 'Dashain dinner');
      expect(event['id'], isNotEmpty);
      expect(await tool.verify(
          const ToolCall(tool: 'calendar', action: 'create'), created),
          isTrue);

      final listed = await tool.execute(const ToolCall(
          tool: 'calendar', action: 'list', args: {'limit': 10}));
      final events = (listed.data as Map)['events'] as List;
      expect(events.length, 1);
      expect(events.first['title'], 'Dashain dinner');
    });

    test('list filters by date range', () async {
      for (final day in ['2026-10-20', '2026-11-01']) {
        await tool.execute(ToolCall(tool: 'calendar', action: 'create', args: {
          'title': 'evt $day',
          'start': '${day}T10:00:00+05:45',
        }));
      }
      final filtered = await tool.execute(const ToolCall(
          tool: 'calendar',
          action: 'list',
          args: {
            'from': '2026-10-25T00:00:00+05:45',
            'to': '2026-11-05T00:00:00+05:45',
          }));
      final events = (filtered.data as Map)['events'] as List;
      expect(events.length, 1);
      expect(events.first['title'], 'evt 2026-11-01');
    });

    test('delete needs approval; registry override deletes', () async {
      final created = await tool.execute(ToolCall(
          tool: 'calendar',
          action: 'create',
          args: {'title': 'tmp', 'start': '2026-10-20T10:00:00+05:45'}));
      final id = ((created.data as Map)['event'] as Map)['id'] as String;

      expect(
          (await tool.checkPermission(
                  ToolCall(tool: 'calendar', action: 'delete', args: {'id': id})))
              .needsApproval,
          isTrue);

      final registry = ToolRegistry()..register(tool);
      final deleted = await registry.dispatch(
        ToolCall(tool: 'calendar', action: 'delete', args: {'id': id}),
        permissionOverride: _allow,
      );
      expect(deleted.success, isTrue);
      expect((deleted.data as Map)['deleted'], isTrue);

      final listed = await tool.execute(const ToolCall(
          tool: 'calendar', action: 'list', args: {}));
      expect(((listed.data as Map)['events'] as List), isEmpty);
    });

    test('create requires title and valid start', () async {
      final bad = await tool.execute(const ToolCall(
          tool: 'calendar', action: 'create', args: {'title': ''}));
      expect(bad.success, isFalse);
    });
  });

  group('TaskTool', () {
    late Directory root;
    late TaskTool tool;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-task-');
      tool = TaskTool(
        store: InMemoryMemoryStore(),
        indexPath: '${root.path}/task_index.json',
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('create, list, complete, update', () async {
      final created = await tool.execute(const ToolCall(
          tool: 'task', action: 'create', args: {'title': 'buy milk'}));
      expect(created.success, isTrue);
      final task = (created.data as Map)['task'] as Map;
      final id = task['id'] as String;
      expect(task['title'], 'buy milk');
      expect(task['status'], 'running');

      var listed = await tool.execute(
          const ToolCall(tool: 'task', action: 'list', args: {}));
      expect(((listed.data as Map)['tasks'] as List).length, 1);

      final completed = await tool.execute(
          ToolCall(tool: 'task', action: 'complete', args: {'id': id}));
      expect(((completed.data as Map)['task'] as Map)['status'], 'done');

      final updated = await tool.execute(ToolCall(
          tool: 'task', action: 'update', args: {'id': id, 'status': 'archived'}));
      expect(((updated.data as Map)['task'] as Map)['status'], 'archived');

      listed = await tool.execute(const ToolCall(
          tool: 'task', action: 'list', args: {'status': 'done'}));
      expect(((listed.data as Map)['tasks'] as List), isEmpty);
    });

    test('delete tombstones and drops the index entry', () async {
      final created = await tool.execute(const ToolCall(
          tool: 'task', action: 'create', args: {'title': 'temp'}));
      final id = (((created.data as Map)['task']) as Map)['id'] as String;

      expect(
          (await tool.checkPermission(
                  ToolCall(tool: 'task', action: 'delete', args: {'id': id})))
              .needsApproval,
          isTrue);

      final registry = ToolRegistry()..register(tool);
      final deleted = await registry.dispatch(
        ToolCall(tool: 'task', action: 'delete', args: {'id': id}),
        permissionOverride: _allow,
      );
      expect(deleted.success, isTrue);
      expect((deleted.data as Map)['deleted'], isTrue);

      final listed = await tool
          .execute(const ToolCall(tool: 'task', action: 'list', args: {}));
      expect(((listed.data as Map)['tasks'] as List), isEmpty);
    });

    test('create requires a title', () async {
      final bad = await tool.execute(
          const ToolCall(tool: 'task', action: 'create', args: {'title': ' '}));
      expect(bad.success, isFalse);
    });
  });

  group('EmailTool', () {
    late Directory root;
    late EmailTool tool;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-email-');
      tool = EmailTool(storePath: '${root.path}/email.json');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('send queues to outbox (approval-gated), list/read work', () async {
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'email', action: 'send', args: {})))
              .needsApproval,
          isTrue);

      final registry = ToolRegistry()..register(tool);
      final sent = await registry.dispatch(
        const ToolCall(tool: 'email', action: 'send', args: {
          'to': 'ssblucky07@gmail.com',
          'subject': 'Dashain Presentation',
          'body': 'Please find attached.',
        }),
        permissionOverride: _allow,
      );
      expect(sent.success, isTrue);
      final msg = (sent.data as Map)['message'] as Map;
      expect(msg['folder'], 'outbox');
      expect(msg['subject'], 'Dashain Presentation');
      final id = msg['id'] as String;

      final listed = await tool.execute(const ToolCall(
          tool: 'email', action: 'list', args: {'query': 'dashain'}));
      expect(((listed.data as Map)['messages'] as List).length, 1);

      final read =
          await tool.execute(ToolCall(tool: 'email', action: 'read', args: {'id': id}));
      expect(((read.data as Map)['message'] as Map)['read'], isTrue);
    });

    test('delete removes the message', () async {
      final registry = ToolRegistry()..register(tool);
      final sent = await registry.dispatch(
        const ToolCall(tool: 'email', action: 'send', args: {
          'to': 'a@b.c',
          'subject': 'x',
          'body': 'y',
        }),
        permissionOverride: _allow,
      );
      final id = (((sent.data as Map)['message']) as Map)['id'] as String;
      final deleted = await registry.dispatch(
        ToolCall(tool: 'email', action: 'delete', args: {'id': id}),
        permissionOverride: _allow,
      );
      expect((deleted.data as Map)['deleted'], isTrue);
    });
  });

  group('DatabaseTool', () {
    test('queries the memory store read-only', () async {
      final store = InMemoryMemoryStore();
      await store.saveMemoryItem(
          layer: 'long_term', key: 'k', content: 'remember this');
      await store.logToolUsage(
          tool: 'file', argsJson: '{}', success: true, durationMs: 3);

      final tool = DatabaseTool(store: store);

      final items = await tool.execute(const ToolCall(
          tool: 'database', action: 'memoryItems', args: {'layer': 'long_term'}));
      expect(items.success, isTrue);
      expect(((items.data as Map)['rows'] as List).length, 1);

      final usage = await tool.execute(const ToolCall(
          tool: 'database', action: 'toolUsage', args: {'tool': 'file'}));
      expect(((usage.data as Map)['rows'] as List).length, 1);

      final rate = await tool.execute(const ToolCall(
          tool: 'database', action: 'successRate', args: {'tool': 'file'}));
      expect(((rate.data as Map))['successRate'], 1.0);

      final tables = await tool.execute(
          const ToolCall(tool: 'database', action: 'tables', args: {}));
      expect(((tables.data as Map)['tables'] as List),
          containsAll(['memory_items', 'tool_usage']));

      final tablesCall = const ToolCall(tool: 'database', action: 'tables');
      expect((await tool.checkPermission(tablesCall)).isAllowed, isTrue);
      expect(await tool.verify(tablesCall, tables), isTrue);
    });
  });
}
