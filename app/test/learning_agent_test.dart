// Tests for LearningAgent: failure recording and failure-rule promotion.
import 'package:flutter_test/flutter_test.dart';
import 'package:np/agents/agent.dart';
import 'package:np/agents/learning_agent.dart';
import 'package:np/agents/planner_agent.dart';
import 'package:np/agents/safety_agent.dart';
import 'package:np/agents/tool_agent.dart';
import 'package:np/agents/verification_agent.dart';
import 'package:np/memory/in_memory_store.dart';
import 'package:np/tools/tool.dart';

void main() {
  group('LearningAgent failure-rule promotion', () {
    test('3 similar failures promote a failure rule', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store);

      expect(await store.listFailureRules(), isEmpty);

      await learning.recordFailure(
          't1', 'execution', 'Tool file threw: File not found: /x', null);
      await learning.recordFailure(
          't2', 'execution', 'Tool file threw: File not found: /x', null);
      expect(await store.listFailureRules(), isEmpty); // only 2 so far

      await learning.recordFailure(
          't3', 'execution', 'Tool file threw: File not found: /x', null);
      final rules = await store.listFailureRules();
      expect(rules.length, 1);
      expect(rules.first['pattern'], contains('File not found'));
      expect(rules.first['action'], contains('3 times'));
    });

    test('dissimilar failures do not promote a rule', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store);

      await learning.recordFailure('t1', 'execution', 'error alpha', null);
      await learning.recordFailure('t2', 'execution', 'error beta', null);
      await learning.recordFailure('t3', 'execution', 'error gamma', null);
      expect(await store.listFailureRules(), isEmpty);
      expect((await store.listFailures()).length, 3);
    });

    test('custom ruleThreshold is honored', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store, ruleThreshold: 2);
      await learning.recordFailure('t1', 'execution', 'same error', null);
      expect(await store.listFailureRules(), isEmpty);
      await learning.recordFailure('t2', 'execution', 'same error', null);
      expect((await store.listFailureRules()).length, 1);
    });

    test('long errors are truncated to a stable 120-char signature', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store);
      final long = 'x' * 200;
      for (var i = 0; i < 3; i++) {
        await learning.recordFailure('t$i', 'execution', long, null);
      }
      final rules = await store.listFailureRules();
      expect(rules.length, 1);
      expect((rules.first['pattern'] as String).length, lessThanOrEqualTo(120));
    });
  });

  group('LearningAgent learnFromRun', () {
    test('records task results and returns a lesson', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store);

      const step =
          PlanStep(id: 's1', description: 'd', tool: 'none', action: 'respond');
      final plan = Plan(goal: 'g', steps: [step]);
      final executions = [
        StepExecution(
          step: step,
          permission: const SafetyDecision.allowed('test'),
          result: null,
          blocked: false,
          skipped: true,
        ),
      ];
      final verification = VerificationAgent().verifyPlan(plan, executions);

      final lesson = await learning.learnFromRun(
        taskId: 'task1',
        plan: plan,
        executions: executions,
        verification: verification,
      );
      expect(lesson, contains('succeeded'));

      final results = await store.getTaskResults('task1');
      expect(results.map((r) => r['stage']),
          containsAll(['plan', 'executions', 'verification']));
    });

    test('failed executions become failure records', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store);

      const step = PlanStep(
          id: 's1', description: 'd', tool: 'file', action: 'read', args: {});
      final plan = Plan(goal: 'g', steps: [step]);
      final executions = [
        StepExecution(
          step: step,
          permission: const SafetyDecision.allowed('test'),
          result: ToolResult.fail('boom'),
          blocked: false,
        ),
      ];
      final verification = VerificationAgent().verifyPlan(plan, executions);

      await learning.learnFromRun(
        taskId: 'task2',
        plan: plan,
        executions: executions,
        verification: verification,
      );
      final failures = await store.listFailures();
      expect(failures, isNotEmpty);
      expect(failures.any((f) => (f['error'] as String).contains('boom')),
          isTrue);
    });

    test('execute records a stage result from metadata', () async {
      final store = InMemoryMemoryStore();
      final learning = LearningAgent(store: store);
      final result = await learning.execute(TaskContext(
        taskId: 'task9',
        input: 'x',
        metadata: {
          'stage': 'planning',
          'output': {'steps': 2},
        },
      ));
      expect(result.success, isTrue);
      final rows = await store.getTaskResults('task9');
      expect(rows.length, 1);
      expect(rows.first['stage'], 'planning');
    });
  });
}
