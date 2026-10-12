// Isolation tests for each agent class: planner, reasoning, memory,
// safety, tool, verification, speech, vision, automation.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/agents/agent.dart';
import 'package:np/agents/automation_agent.dart';
import 'package:np/agents/memory_agent.dart';
import 'package:np/agents/planner_agent.dart';
import 'package:np/agents/reasoning_agent.dart';
import 'package:np/agents/safety_agent.dart';
import 'package:np/agents/speech_agent.dart';
import 'package:np/agents/tool_agent.dart';
import 'package:np/agents/verification_agent.dart';
import 'package:np/agents/vision_agent.dart';
import 'package:np/memory/embeddings.dart';
import 'package:np/memory/in_memory_store.dart';
import 'package:np/memory/retrieval.dart';
import 'package:np/memory/short_term.dart';
import 'package:np/memory/tool_usage.dart';
import 'package:np/tools/file_tool.dart';
import 'package:np/tools/productivity_tools.dart';
import 'package:np/tools/terminal_tool.dart';
import 'package:np/tools/tool.dart';
import 'package:np/tools/tool_registry.dart';
import 'package:np/vision/ocr_mock.dart';
import 'package:np/vision/screen_mock.dart';
import 'package:np/voice/stt.dart';
import 'package:np/voice/tts_mock.dart';

TaskContext _ctx(String input, {Map<String, dynamic> metadata = const {}}) =>
    TaskContext(taskId: 't1', input: input, metadata: metadata);

void main() {
  group('PlannerAgent', () {
    final planner = PlannerAgent();

    test('list files intent -> file.list step', () {
      final plan = planner.producePlan('list files in /tmp');
      expect(plan.steps.length, 1);
      expect(plan.steps.first.tool, 'file');
      expect(plan.steps.first.action, 'list');
      expect(plan.steps.first.args['dir'], '/tmp');
    });

    test('read file intent -> file.read step', () {
      final plan = planner.producePlan('read the file /tmp/a.txt');
      expect(plan.steps.first.tool, 'file');
      expect(plan.steps.first.action, 'read');
      expect(plan.steps.first.args['path'], '/tmp/a.txt');
    });

    test('run command intent -> terminal.run step', () {
      final plan = planner.producePlan('run command echo hi');
      expect(plan.steps.first.tool, 'terminal');
      expect(plan.steps.first.action, 'run');
      expect(plan.steps.first.args['command'], 'echo hi');
    });

    test('greeting -> direct-answer step', () {
      final plan = planner.producePlan('hello there');
      expect(plan.steps.length, 1);
      expect(plan.steps.first.tool, 'none');
    });

    test('empty input throws', () {
      expect(() => planner.producePlan('   '), throwsArgumentError);
    });

    test('paths keep their original case (no lowercase mangling)', () {
      final plan = planner.producePlan('list files in /Tmp/My-Dir/Sub');
      expect(plan.steps.first.args['dir'], '/Tmp/My-Dir/Sub');
    });

    test('intent keywords match case-insensitively', () {
      final plan = planner.producePlan('LIST FILES in /tmp');
      expect(plan.steps.first.tool, 'file');
      expect(plan.steps.first.action, 'list');
    });

    test('execute returns an ok AgentResult with stepCount', () async {
      final result = await planner.execute(_ctx('hello'));
      expect(result.success, isTrue);
      expect(result.output['stepCount'], 1);
      expect(result.agentName, 'planner');
    });
  });

  group('ReasoningAgent', () {
    final reasoning = ReasoningAgent();

    Plan _plan(List<PlanStep> steps) =>
        Plan(goal: 'g', steps: steps, rationale: '');

    test('deduplicates exact repeat steps', () {
      final step = const PlanStep(
          id: 's1', description: 'd', tool: 'file', action: 'list', args: {
        'dir': '/tmp'
      });
      final refined = reasoning.refine(_plan([step, step]));
      expect(refined.steps.length, 1);
      expect(refined.rationale, contains('Dropped duplicate'));
    });

    test('topological order honors dependsOn', () {
      final a = const PlanStep(
          id: 'a', description: 'a', tool: 'file', action: 'list', args: {});
      final b = const PlanStep(
          id: 'b',
          description: 'b',
          tool: 'file',
          action: 'read',
          args: {},
          dependsOn: ['a']);
      final refined = reasoning.refine(_plan([b, a]));
      expect(refined.steps.map((s) => s.id).toList(), ['a', 'b']);
    });

    test('dependency cycle is broken deterministically', () {
      final a = const PlanStep(
          id: 'a',
          description: 'a',
          tool: 'file',
          action: 'list',
          args: {},
          dependsOn: ['b']);
      final b = const PlanStep(
          id: 'b',
          description: 'b',
          tool: 'file',
          action: 'read',
          args: {},
          dependsOn: ['a']);
      final refined = reasoning.refine(_plan([a, b]));
      expect(refined.steps.length, 2);
      expect(refined.rationale, contains('cycle'));
    });

    test('execute fails gracefully without a plan in metadata', () async {
      final result = await reasoning.execute(_ctx('x'));
      expect(result.success, isFalse);
      expect(result.error, contains('No plan'));
    });

    test('execute refines a plan from metadata', () async {
      final plan = PlannerAgent().producePlan('hello');
      final result = await reasoning.execute(
          _ctx('hello', metadata: {'plan': plan.toJson()}));
      expect(result.success, isTrue);
      expect(result.output['stepCount'], 1);
    });
  });

  group('MemoryAgent', () {
    test('execute records the turn and recalls relevant memories', () async {
      final store = InMemoryMemoryStore();
      final emb = HashingEmbedding(dimension: 256);
      final agent = MemoryAgent(
        retrieval: RetrievalService(store: store, embeddings: emb),
        shortTerm: ShortTermMemory(store, emb),
      );

      // Seed a memory whose embedding matches the query.
      final vec = await emb.embed('the user loves strong coffee');
      await store.saveMemoryItem(
        layer: 'long_term',
        key: 'coffee',
        content: 'the user loves strong coffee',
        embedding: encodeEmbedding(vec),
      );

      final result = await agent.execute(_ctx('do I like coffee?'));
      expect(result.success, isTrue);
      final memories = result.output['memories'] as List;
      expect(memories, isNotEmpty);
      // The turn itself matches the query exactly and ranks first; the
      // seeded long-term memory must be recalled too.
      expect(memories.map((m) => (m as Map)['key']), contains('coffee'));

      // The turn itself was recorded into short_term.
      final short = await store.getMemoryItems(layer: 'short_term');
      expect(short.any((r) => (r['key'] as String).startsWith('turn_')),
          isTrue);
    });

    test('recall is callable directly', () async {
      final store = InMemoryMemoryStore();
      final emb = HashingEmbedding(dimension: 256);
      final agent = MemoryAgent(
        retrieval: RetrievalService(store: store, embeddings: emb),
        shortTerm: ShortTermMemory(store, emb),
      );
      expect(await agent.recall(_ctx('anything')), isEmpty);
    });
  });

  group('SafetyAgent', () {
    late ToolRegistry registry;
    late SafetyAgent safety;

    setUp(() {
      registry = ToolRegistry()
        ..register(TerminalTool())
        ..register(AutomationTool());
      safety = SafetyAgent(registry);
    });

    test('no-tool call is allowed', () async {
      final d =
          await safety.check(const ToolCall(tool: 'none', action: 'respond'));
      expect(d.allowed, isTrue);
      expect(d.requiresApproval, isFalse);
    });

    test('unknown tool is denied', () async {
      final d =
          await safety.check(const ToolCall(tool: 'ghost', action: 'haunt'));
      expect(d.allowed, isFalse);
    });

    test('destructive terminal command is denied', () async {
      final d = await safety.check(const ToolCall(
          tool: 'terminal', action: 'run', args: {'command': 'rm -rf /'}));
      expect(d.allowed, isFalse);
    });

    test('automation tool always needs approval by policy', () async {
      final d = await safety.check(const ToolCall(
          tool: 'automation', action: 'listRoutines', args: {}));
      expect(d.allowed, isTrue);
      expect(d.requiresApproval, isTrue);
    });

    test('execute with toolCall metadata evaluates one call', () async {
      final result = await safety.execute(_ctx('x', metadata: {
        'toolCall': {
          'tool': 'terminal',
          'action': 'run',
          'args': {'command': 'echo hi'}
        }
      }));
      expect(result.success, isTrue);
      expect((result.output['decision'] as Map)['allowed'], isTrue);
    });
  });

  group('ToolAgent', () {
    late Directory root;
    late ToolRegistry registry;
    late ToolAgent toolAgent;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-toolagent-');
      await File('${root.path}/a.txt').writeAsString('A');
      registry = ToolRegistry()
        ..register(FileTool(allowedRoots: [root.path]))
        ..register(TerminalTool());
      toolAgent = ToolAgent(
        registry: registry,
        safety: SafetyAgent(registry),
        usage: ToolUsageMemory(InMemoryMemoryStore()),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('selectTools gates each step; none-steps may execute', () async {
      final plan = Plan(goal: 'g', steps: [
        PlanStep(
            id: 's1',
            description: 'list',
            tool: 'file',
            action: 'list',
            args: {'dir': root.path}),
        const PlanStep(
            id: 's2', description: 'answer', tool: 'none', action: 'respond'),
        const PlanStep(
            id: 's3',
            description: 'boom',
            tool: 'terminal',
            action: 'run',
            args: {'command': 'rm -rf /'}),
      ]);
      final calls = await toolAgent.selectTools(plan);
      expect(calls.length, 3);
      expect(calls[0].mayExecute, isTrue);
      // no-tool steps carry no call and are skipped (not "executed")
      expect(calls[1].call, isNull);
      expect(calls[1].mayExecute, isFalse);
      expect(calls[1].decision.allowed, isTrue);
      expect(calls[2].mayExecute, isFalse); // denied by safety
    });

    test('executeCalls runs approved, skips none, blocks denied', () async {
      final plan = Plan(goal: 'g', steps: [
        PlanStep(
            id: 's1',
            description: 'list',
            tool: 'file',
            action: 'list',
            args: {'dir': root.path}),
        const PlanStep(
            id: 's2', description: 'answer', tool: 'none', action: 'respond'),
        const PlanStep(
            id: 's3',
            description: 'boom',
            tool: 'terminal',
            action: 'run',
            args: {'command': 'rm -rf /'}),
      ]);
      final executions =
          await toolAgent.executePlan(plan, autoApprove: false);
      expect(executions.length, 3);
      expect(executions[0].result?.success, isTrue);
      expect(
          ((executions[0].result!.data as Map)['entries'] as List).length, 1);
      expect(executions[1].skipped, isTrue);
      expect(executions[2].blocked, isTrue);
    });

    test('execute fails gracefully without a plan in metadata', () async {
      final result = await toolAgent.execute(_ctx('x'));
      expect(result.success, isFalse);
    });
  });

  group('VerificationAgent', () {
    final verification = VerificationAgent();

    StepExecution _exec(PlanStep step,
        {ToolResult? result, bool blocked = false, bool skipped = false}) {
      return StepExecution(
        step: step,
        permission: const SafetyDecision.allowed('test'),
        result: result,
        blocked: blocked,
        skipped: skipped,
      );
    }

    test('all passing -> passed report', () {
      const step =
          PlanStep(id: 's1', description: 'd', tool: 'none', action: 'respond');
      final report = verification.verifyPlan(
          Plan(goal: 'g', steps: [step]), [_exec(step, skipped: true)]);
      expect(report.passed, isTrue);
      expect(report.succeeded, 1);
      expect(report.total, 1);
    });

    test('failed tool result -> issue', () {
      const step = PlanStep(
          id: 's1', description: 'd', tool: 'file', action: 'read', args: {});
      final report = verification.verifyPlan(
        Plan(goal: 'g', steps: [step]),
        [_exec(step, result: ToolResult.fail('disk exploded'))],
      );
      expect(report.passed, isFalse);
      expect(report.issues.join(' '), contains('disk exploded'));
    });

    test('blocked step -> issue', () {
      const step = PlanStep(
          id: 's1', description: 'd', tool: 'terminal', action: 'run', args: {});
      final report = verification.verifyPlan(
        Plan(goal: 'g', steps: [step]),
        [
          StepExecution(
            step: step,
            permission: const SafetyDecision.denied('nope'),
            result: null,
            blocked: true,
          )
        ],
      );
      expect(report.passed, isFalse);
      expect(report.issues.join(' '), contains('blocked'));
    });

    test('expectContains is enforced', () {
      const step = PlanStep(
          id: 's1',
          description: 'd',
          tool: 'terminal',
          action: 'run',
          args: {'expectContains': 'hello'});
      final ok = verification.verifyPlan(
        Plan(goal: 'g', steps: [step]),
        [_exec(step, result: ToolResult.ok('say hello world'))],
      );
      expect(ok.passed, isTrue);

      final bad = verification.verifyPlan(
        Plan(goal: 'g', steps: [step]),
        [_exec(step, result: ToolResult.ok('say goodbye'))],
      );
      expect(bad.passed, isFalse);
      expect(bad.issues.join(' '), contains('did not contain'));
    });

    test('missing execution record -> issue', () {
      const step =
          PlanStep(id: 's1', description: 'd', tool: 'file', action: 'list');
      final report =
          verification.verifyPlan(Plan(goal: 'g', steps: [step]), []);
      expect(report.passed, isFalse);
      expect(report.issues.join(' '), contains('never executed'));
    });
  });

  group('SpeechAgent', () {
    test('idle when there is nothing to do', () async {
      final agent = SpeechAgent();
      final result = await agent.execute(_ctx('x'));
      expect(result.success, isTrue);
      expect(result.output['status'], 'idle');
    });

    test('speaks through the mock TTS', () async {
      final tts = MockTts();
      final agent = SpeechAgent(
          tts: tts, controller: SpeechController()..bargeInEnabled = false);
      final result =
          await agent.execute(_ctx('x', metadata: {'speak': 'hi'}));
      expect(result.success, isTrue);
      expect(result.output['spoken'], isTrue);
      expect(tts.spokenTexts, ['hi']);
    });

    test('audio without an STT engine reports honestly', () async {
      final agent = SpeechAgent();
      final result = await agent.execute(
          _ctx('x', metadata: {'audioBytes': Uint8List.fromList([1, 2, 3])}));
      expect(result.success, isTrue);
      expect(result.output['transcript'], contains('unavailable'));
    });
  });

  group('VisionAgent', () {
    final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i));

    test('no image -> no_image status', () async {
      final agent = VisionAgent();
      final result = await agent.execute(_ctx('x'));
      expect(result.success, isTrue);
      expect(result.output['status'], 'no_image');
    });

    test('image without engines reports honestly', () async {
      final agent = VisionAgent();
      final result =
          await agent.execute(_ctx('x', metadata: {'imageBytes': bytes}));
      expect(result.success, isTrue);
      expect(result.output['ocr'], contains('unavailable'));
      expect(result.output['screen'], contains('unavailable'));
    });

    test('image with mock engines returns ocr + description + elements',
        () async {
      final agent =
          VisionAgent(ocr: MockOcr(), screen: MockScreenUnderstanding());
      final result = await agent.execute(_ctx('x', metadata: {
        'imageBytes': bytes,
        'findElement': 'button',
      }));
      expect(result.success, isTrue);
      final ocr = result.output['ocr'] as Map;
      expect((ocr['text'] as String), contains('MOCK'));
      expect(result.output['description'], contains('Simulated'));
      final elements = result.output['elements'] as List;
      expect(elements.length, 3);
      expect((elements.first as Map)['label'], contains('button'));
    });
  });

  group('AutomationAgent', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-auto-');
      await File('${root.path}/f.txt').writeAsString('f');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('runRoutine executes steps sequentially', () async {
      final registry = ToolRegistry()
        ..register(FileTool(allowedRoots: [root.path]));
      final agent = AutomationAgent(
          registry: registry, safety: SafetyAgent(registry));
      agent.registerRoutine('list-files', [
        ToolCall(tool: 'file', action: 'list', args: {'dir': root.path}),
      ]);
      expect(agent.listRoutines(), contains('list-files'));

      final transcript = await agent.runRoutine('list-files');
      expect(transcript.length, 1);
      expect(transcript.first.blocked, isFalse);
      expect(transcript.first.result?.success, isTrue);
    });

    test('unknown routine throws ArgumentError', () async {
      final registry = ToolRegistry();
      final agent = AutomationAgent(
          registry: registry, safety: SafetyAgent(registry));
      expect(() => agent.runRoutine('nope'), throwsArgumentError);
    });

    test('routine stops at first failure', () async {
      final registry = ToolRegistry()
        ..register(FileTool(allowedRoots: [root.path]));
      final agent = AutomationAgent(
          registry: registry, safety: SafetyAgent(registry));
      agent.registerRoutine('mixed', [
        ToolCall(
            tool: 'file', action: 'read', args: {'path': '${root.path}/no.txt'}),
        ToolCall(tool: 'file', action: 'list', args: {'dir': root.path}),
      ]);
      final transcript = await agent.runRoutine('mixed');
      expect(transcript.length, 1); // stopped after the failed read
      expect(transcript.first.result?.success, isFalse);
    });

    test('execute lists routines / runs one from metadata', () async {
      final registry = ToolRegistry()
        ..register(FileTool(allowedRoots: [root.path]));
      final agent = AutomationAgent(
          registry: registry, safety: SafetyAgent(registry));
      agent.registerRoutine('list-files', [
        ToolCall(tool: 'file', action: 'list', args: {'dir': root.path}),
      ]);

      final listed = await agent.execute(_ctx('x'));
      expect(listed.success, isTrue);
      expect((listed.output['routines'] as List), contains('list-files'));

      final ran = await agent.execute(
          _ctx('x', metadata: {'routine': 'list-files'}));
      expect(ran.success, isTrue);
      expect(ran.output['steps'], 1);
    });
  });
}
