// Tests for TerminalTool: safe commands run, destructive ones are denied.
import 'package:flutter_test/flutter_test.dart';
import 'package:np/tools/terminal_tool.dart';
import 'package:np/tools/tool.dart';

void main() {
  final tool = TerminalTool();

  group('TerminalTool permission policy', () {
    test('echo command is allowed', () async {
      final decision = await tool.checkPermission(const ToolCall(
        tool: 'terminal',
        action: 'run',
        args: {'command': 'echo', 'args': ['hello']},
      ));
      expect(decision.isAllowed, isTrue);
    });

    test('destructive patterns are denied', () async {
      for (final cmd in [
        'rm -rf /',
        'rm -rf ~/',
        'mkfs /dev/sda',
        'dd if=/dev/zero of=/dev/sda',
        'shutdown now',
        'reboot',
        ':(){ :|:& };:',
      ]) {
        final decision = await tool.checkPermission(ToolCall(
          tool: 'terminal',
          action: 'run',
          args: {'command': cmd},
        ));
        expect(decision.isDenied, isTrue, reason: 'expected deny for: $cmd');
      }
    });

    test('privileged patterns need approval', () async {
      for (final cmd in ['sudo ls', 'systemctl restart x', 'service foo start']) {
        final decision = await tool.checkPermission(ToolCall(
          tool: 'terminal',
          action: 'run',
          args: {'command': cmd},
        ));
        expect(decision.needsApproval, isTrue,
            reason: 'expected approval for: $cmd');
      }
    });

    test('empty command and unknown action are denied', () async {
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'terminal', action: 'run', args: {'command': ' '})))
              .isDenied,
          isTrue);
      expect(
          (await tool.checkPermission(const ToolCall(
                  tool: 'terminal', action: 'exec', args: {'command': 'ls'})))
              .isDenied,
          isTrue);
    });
  });

  group('TerminalTool execution', () {
    test('runs echo and captures stdout', () async {
      final result = await tool.execute(const ToolCall(
        tool: 'terminal',
        action: 'run',
        args: {'command': 'echo', 'args': ['hello', 'np']},
      ));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['exitCode'], 0);
      expect((data['stdout'] as String).trim(), 'hello np');
      expect(data['timedOut'], isFalse);
      expect(await tool.verify(
          const ToolCall(tool: 'terminal', action: 'run'), result), isTrue);
    });

    test('non-zero exit code still returns a result', () async {
      final result = await tool.execute(const ToolCall(
        tool: 'terminal',
        action: 'run',
        args: {'command': 'ls', 'args': ['/definitely/not/here']},
      ));
      expect(result.success, isTrue);
      expect((result.data as Map)['exitCode'], isNot(0));
    });

    test('timeout produces a failed result', () async {
      final result = await tool.execute(const ToolCall(
        tool: 'terminal',
        action: 'run',
        args: {'command': 'sleep', 'args': ['5'], 'timeoutSeconds': 1},
      ));
      expect(result.success, isFalse);
      expect(result.error, contains('timed out'));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
