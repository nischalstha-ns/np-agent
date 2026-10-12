// End-to-end pipeline tests through NpCore.initialize(useMocks: true).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/agents/np_core.dart';
import 'package:np/agents/pipeline.dart';
import 'package:np/core/di.dart';
import 'package:np/llm/router.dart';
import 'package:np/memory/in_memory_store.dart';
import 'package:np/memory/memory_store.dart';
import 'package:np/tools/tool_registry.dart';

void main() {
  group('NpCore end-to-end (mocks + in-memory)', () {
    late NpCore core;

    setUp(() async {
      core = await NpCore.initialize(useMocks: true);
    });

    tearDown(() async {
      await core.dispose();
    });

    test('DI container is wired with mocks and in-memory store', () {
      expect(core.di, isA<ServiceLocator>());
      expect(core.store, isA<InMemoryMemoryStore>());
      expect(core.di.get<MemoryStore>(), isA<InMemoryMemoryStore>());
      expect(core.di.get<ToolRegistry>(), isA<ToolRegistry>());
      expect(core.di.get<Pipeline>(), isA<Pipeline>());
      expect(core.llm, isA<LlmRouter>());
      // all 16 tools registered
      final names = core.di.get<ToolRegistry>().names();
      expect(names.length, 16);
      for (final t in [
        'file',
        'terminal',
        'browser',
        'code',
        'image',
        'video',
        'audio',
        'calendar',
        'email',
        'task',
        'pdf',
        'document',
        'database',
        'memory',
        'research',
        'automation',
      ]) {
        expect(names, contains(t), reason: 'missing tool: $t');
      }
    });

    test('greeting is answered directly', () async {
      final reply = await core.handle('hello');
      expect(reply, isNotEmpty);
      expect(reply, contains('Done.'));
    });

    test('list files prompt lists a temp dir end-to-end', () async {
      final dir = await Directory.systemTemp.createTemp('np-e2e-list-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/marker.txt').writeAsString('x');

      final reply = await core.handle('list files in ${dir.path}');
      expect(reply, isNotEmpty);
      expect(reply, contains('marker.txt'));
    });

    test('run command prompt executes and returns stdout', () async {
      final reply = await core.handle('run command echo np-e2e-ok');
      expect(reply, contains('np-e2e-ok'));
    });

    test('runDetailed reports all 9 stages succeeding', () async {
      final result = await core.runDetailed('hello');
      expect(result.success, isTrue);
      expect(result.response, isNotEmpty);
      expect(result.stages.length, PipelineStage.values.length);
      for (final stage in PipelineStage.values) {
        final report = result.reportFor(stage);
        expect(report, isNotNull, reason: 'missing stage $stage');
        expect(report!.success, isTrue, reason: 'stage $stage failed');
      }
      expect(result.totalMs, greaterThanOrEqualTo(0));
    });

    test('destructive step is held for approval, not executed', () async {
      final dir = await Directory.systemTemp.createTemp('np-e2e-del-');
      addTearDown(() => dir.delete(recursive: true));
      final victim = '${dir.path}/todelete.txt';
      await File(victim).writeAsString('x');

      final reply = await core.handle('delete the file $victim');
      expect(reply, contains('Held for your approval'));
      // nothing was actually deleted
      expect(await File(victim).exists(), isTrue);
    });

    test('empty input produces a graceful error response', () async {
      final result = await core.runDetailed('   ');
      expect(result.success, isFalse);
      expect(result.response, contains('error'));
    });

    test('memory persists across handles in the same core', () async {
      // First handle stores the turn; the memory stage should recall
      // something on the second handle (the first turn itself).
      await core.handle('remember that my favorite editor is helix');
      final result = await core.runDetailed('what is my favorite editor?');
      expect(result.success, isTrue);
      final memoryReport = result.reportFor(PipelineStage.memory)!;
      expect(memoryReport.detail, isNot(contains('0 memor')));
    });
  });

  group('NpCore with autoApprove', () {
    test('initializes and answers', () async {
      final core = await NpCore.initialize(useMocks: true, autoApprove: true);
      addTearDown(core.dispose);
      final reply = await core.handle('hello');
      expect(reply, isNotEmpty);
    });
  });
}
