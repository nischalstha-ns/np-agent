// Tests for the ToolRegistry: lookup, permission dispatch, overrides.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/tools/file_tool.dart';
import 'package:np/tools/productivity_tools.dart';
import 'package:np/tools/terminal_tool.dart';
import 'package:np/tools/tool.dart';
import 'package:np/tools/tool_registry.dart';

/// A tool whose permission policy is scripted per test.
class _ScriptedTool extends Tool {
  final PermissionDecision decision;
  final ToolResult result;

  _ScriptedTool(this.decision, this.result);

  @override
  String get name => 'scripted';
  @override
  String get description => 'scripted test tool';
  @override
  Map<String, dynamic> get inputSchema => {};
  @override
  Map<String, dynamic> get outputSchema => {};
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async => decision;
  @override
  Future<ToolResult> execute(ToolCall call) async => result;
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async => true;
}

void main() {
  group('ToolRegistry lookup', () {
    test('get throws ToolNotFoundError for unknown tool', () {
      final registry = ToolRegistry()..register(TerminalTool());
      expect(() => registry.get('nope'), throwsA(isA<ToolNotFoundError>()));
    });

    test('getOrNull / contains / names / list', () {
      final registry = ToolRegistry();
      expect(registry.getOrNull('file'), isNull);
      expect(registry.contains('file'), isFalse);

      registry.register(FileTool());
      expect(registry.contains('file'), isTrue);
      expect(registry.get('file'), isA<FileTool>());
      expect(registry.names(), contains('file'));
      expect(registry.list().map((t) => t.name), contains('file'));
    });

    test('dispatch to unknown tool fails instead of throwing', () async {
      final registry = ToolRegistry();
      final result = await registry
          .dispatch(const ToolCall(tool: 'ghost', action: 'haunt'));
      expect(result.success, isFalse);
      expect(result.error, contains('Unknown tool'));
    });
  });

  group('ToolRegistry permission dispatch', () {
    test('denied call is blocked before execute', () async {
      final registry = ToolRegistry()..register(TerminalTool());
      final result = await registry.dispatch(const ToolCall(
        tool: 'terminal',
        action: 'run',
        args: {'command': 'rm -rf /'},
      ));
      expect(result.success, isFalse);
      expect(result.error, contains('Permission denied'));
    });

    test('needsApproval without override is blocked', () async {
      final registry = ToolRegistry()..register(TerminalTool());
      final result = await registry.dispatch(const ToolCall(
        tool: 'terminal',
        action: 'run',
        args: {'command': 'sudo ls'},
      ));
      expect(result.success, isFalse);
      expect(result.error, contains('Approval required'));
    });

    test('needsApproval with granting override executes', () async {
      final registry = ToolRegistry()
        ..register(_ScriptedTool(
          const PermissionDecision.needsApproval('needs a human'),
          ToolResult.ok({'ran': true}),
        ));
      final result = await registry.dispatch(
        const ToolCall(tool: 'scripted', action: 'go'),
        permissionOverride: (call) async =>
            const PermissionDecision.allowed('test override'),
      );
      expect(result.success, isTrue);
      expect(result.data, {'ran': true});
    });

    test('needsApproval with denying override stays blocked', () async {
      final registry = ToolRegistry()
        ..register(_ScriptedTool(
          const PermissionDecision.needsApproval('needs a human'),
          ToolResult.ok({'ran': true}),
        ));
      final result = await registry.dispatch(
        const ToolCall(tool: 'scripted', action: 'go'),
        permissionOverride: (call) async =>
            const PermissionDecision.denied('nope'),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('Approval not granted'));
    });

    test('allowed call executes and carries durationMs', () async {
      final registry = ToolRegistry()
        ..register(_ScriptedTool(
          const PermissionDecision.allowed(),
          ToolResult.ok({'ran': true}),
        ));
      final result = await registry
          .dispatch(const ToolCall(tool: 'scripted', action: 'go'));
      expect(result.success, isTrue);
      expect(result.durationMs, greaterThanOrEqualTo(0));
    });

    test('exceptions inside execute become failed results', () async {
      final registry = ToolRegistry()
        ..register(_ExplodingTool(
            const PermissionDecision.allowed(), explodeInExecute: true));
      final result = await registry
          .dispatch(const ToolCall(tool: 'scripted', action: 'go'));
      expect(result.success, isFalse);
      expect(result.error, contains('threw'));
    });

    test('exceptions inside checkPermission become failed results', () async {
      final registry = ToolRegistry()
        ..register(_ExplodingTool(
            const PermissionDecision.allowed(), explodeInPermission: true));
      final result = await registry
          .dispatch(const ToolCall(tool: 'scripted', action: 'go'));
      expect(result.success, isFalse);
      expect(result.error, contains('Permission check crashed'));
    });

    test('failed verification turns success into failure', () async {
      final registry = ToolRegistry()
        ..register(_ExplodingTool(
            const PermissionDecision.allowed(), failVerification: true));
      final result = await registry
          .dispatch(const ToolCall(tool: 'scripted', action: 'go'));
      expect(result.success, isFalse);
      expect(result.error, contains('Verification failed'));
    });

    test('calendar delete needs approval; override grants it', () async {
      // Uses a throwaway calendar file in a temp dir — hermetic.
      final dir = await Directory.systemTemp.createTemp('np-reg-cal-');
      addTearDown(() => dir.delete(recursive: true));
      final registry = ToolRegistry()
        ..register(CalendarTool(storePath: '${dir.path}/cal.json'));
      final noOverride = await registry.dispatch(const ToolCall(
        tool: 'calendar',
        action: 'delete',
        args: {'id': 'evt_x'},
      ));
      expect(noOverride.success, isFalse);
      expect(noOverride.error, contains('Approval required'));

      final granted = await registry.dispatch(
        const ToolCall(
            tool: 'calendar', action: 'delete', args: {'id': 'evt_x'}),
        permissionOverride: (call) async =>
            const PermissionDecision.allowed('test override'),
      );
      // delete of a missing id still "succeeds" the tool call with deleted:false
      expect(granted.success, isTrue);
      expect((granted.data as Map)['deleted'], isFalse);
    });
  });
}

class _ExplodingTool extends _ScriptedTool {
  final bool explodeInExecute;
  final bool explodeInPermission;
  final bool failVerification;

  _ExplodingTool(
    PermissionDecision decision, {
    this.explodeInExecute = false,
    this.explodeInPermission = false,
    this.failVerification = false,
  }) : super(decision, ToolResult.ok({'ran': true}));

  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    if (explodeInPermission) throw StateError('perm boom');
    return decision;
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    if (explodeInExecute) throw StateError('exec boom');
    return result;
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (failVerification) return false;
    return true;
  }
}
