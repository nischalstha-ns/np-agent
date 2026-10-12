import 'agent.dart';

/// One step of a [Plan]: a single tool invocation (or a direct answer).
class PlanStep {
  final String id;
  final String description;
  final String tool; // tool name in the registry, or 'none' for direct answer
  final String action;
  final Map<String, dynamic> args;
  final List<String> dependsOn;

  const PlanStep({
    required this.id,
    required this.description,
    required this.tool,
    required this.action,
    this.args = const {},
    this.dependsOn = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'tool': tool,
        'action': action,
        'args': args,
        'dependsOn': dependsOn,
      };

  factory PlanStep.fromJson(Map<String, dynamic> json) => PlanStep(
        id: json['id'] as String,
        description: json['description'] as String? ?? '',
        tool: json['tool'] as String? ?? 'none',
        action: json['action'] as String? ?? 'respond',
        args: Map<String, dynamic>.from(json['args'] as Map? ?? const {}),
        dependsOn: List<String>.from(json['dependsOn'] as List? ?? const []),
      );
}

/// An ordered list of steps that fulfills the user's request.
class Plan {
  final String goal;
  final List<PlanStep> steps;
  final String rationale;

  const Plan({
    required this.goal,
    required this.steps,
    this.rationale = '',
  });

  Map<String, dynamic> toJson() => {
        'goal': goal,
        'rationale': rationale,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

/// Turns a raw user request into an ordered [Plan] of tool calls.
///
/// This is a real, rule-based intent parser (deliberately simplified):
/// it recognizes file, terminal, browser, code-analysis, and web-search
/// intents via regular expressions. Anything it cannot map becomes a
/// single `tool: 'none'` step, meaning "answer directly from the model".
class PlannerAgent extends Agent {
  @override
  String get name => 'planner';

  @override
  String describe() =>
      'Turns a user request into an ordered Plan of tool calls.';

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final plan = producePlan(ctx.input);
      return AgentResult.ok(
        name,
        {
          'plan': plan.toJson(),
          'stepCount': plan.steps.length,
        },
        started,
        DateTime.now(),
      );
    } catch (e) {
      return AgentResult.fail(name, 'Planning failed: $e', started, DateTime.now());
    }
  }

  /// Pure planning logic — also used directly by the pipeline.
  Plan producePlan(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw ArgumentError('Cannot plan for empty input');
    }
    final lower = text.toLowerCase();
    final steps = <PlanStep>[];
    var n = 0;
    String nextId() => 's${++n}';

    void addFileStep(RegExpMatch m, String action, String description) {
      final path = m.group(1)!.trim();
      steps.add(PlanStep(
        id: nextId(),
        description: description,
        tool: 'file',
        action: action,
        args: {'path': path},
      ));
    }

    // --- file intents -------------------------------------------------------
    final readMatch =
        RegExp(r'\bread\s+(?:the\s+)?file\s+["\u201c]?([^\s"\u201d]+)').firstMatch(lower);
    if (readMatch != null) {
      addFileStep(readMatch, 'read', 'Read file ${readMatch.group(1)}');
    }

    final listMatch = RegExp(
            r'\blist\s+(?:files\s+)?in\s+["\u201c]?([^\s"\u201d]+)')
        .firstMatch(lower);
    if (listMatch != null) {
      steps.add(PlanStep(
        id: nextId(),
        description: 'List directory ${listMatch.group(1)}',
        tool: 'file',
        action: 'list',
        args: {'dir': listMatch.group(1)!.trim()},
      ));
    }

    final writeMatch = RegExp(
            r'\bwrite\s+(?:the\s+)?(?:file\s+)?["\u201c]?([^\s"\u201d]+\.\w+)')
        .firstMatch(lower);
    if (writeMatch != null) {
      steps.add(PlanStep(
        id: nextId(),
        description: 'Write file ${writeMatch.group(1)}',
        tool: 'file',
        action: 'write',
        args: {
          'path': writeMatch.group(1)!.trim(),
          // Content comes from the reasoning stage / model, not the parser.
          'content': '',
          'expectContains': '',
        },
      ));
    }

    final deleteMatch =
        RegExp(r'\bdelete\s+(?:the\s+)?file\s+["\u201c]?([^\s"\u201d]+)')
            .firstMatch(lower);
    if (deleteMatch != null) {
      addFileStep(deleteMatch, 'delete', 'Delete file ${deleteMatch.group(1)}');
    }

    // --- terminal intents ---------------------------------------------------
    final runMatch = RegExp(r'\b(?:run|execute)\s+(?:command\s+)?["\u201c]?(.+)')
        .firstMatch(lower);
    if (runMatch != null && !lower.contains('routine')) {
      steps.add(PlanStep(
        id: nextId(),
        description: 'Run command: ${runMatch.group(1)}',
        tool: 'terminal',
        action: 'run',
        args: {'command': runMatch.group(1)!.trim()},
      ));
    }

    // --- browser intents ----------------------------------------------------
    final urlMatch = RegExp(r'\bopen\s+(https?://[^\s"\u201d]+)').firstMatch(lower);
    if (urlMatch != null) {
      steps.add(PlanStep(
        id: nextId(),
        description: 'Open ${urlMatch.group(1)}',
        tool: 'browser',
        action: 'open',
        args: {'url': urlMatch.group(1)!.trim()},
      ));
    }

    final searchMatch =
        RegExp(r'\bsearch(?:\s+the\s+web)?\s+for\s+["\u201c]?(.+)')
            .firstMatch(lower);
    if (searchMatch != null) {
      final query = searchMatch.group(1)!.trim().replaceAll(RegExp(r'["\u201d]+$'), '');
      steps.add(PlanStep(
        id: nextId(),
        description: 'Web search for "$query"',
        tool: 'browser',
        action: 'fetch',
        args: {
          'url':
              'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}',
        },
      ));
    }

    // --- code intents -------------------------------------------------------
    final analyzeMatch =
        RegExp(r'\banalyze\s+(?:the\s+)?(?:code\s+)?["\u201c]?([^\s"\u201d]+\.dart)')
            .firstMatch(lower);
    if (analyzeMatch != null) {
      steps.add(PlanStep(
        id: nextId(),
        description: 'Analyze ${analyzeMatch.group(1)}',
        tool: 'code',
        action: 'analyze',
        args: {'path': analyzeMatch.group(1)!.trim()},
      ));
    }

    // --- fallback: answer directly ------------------------------------------
    if (steps.isEmpty) {
      steps.add(PlanStep(
        id: nextId(),
        description: 'Answer directly from model knowledge',
        tool: 'none',
        action: 'respond',
      ));
    }

    return Plan(
      goal: text,
      steps: steps,
      rationale:
          'Rule-based parse of the request produced ${steps.length} step(s).',
    );
  }
}
