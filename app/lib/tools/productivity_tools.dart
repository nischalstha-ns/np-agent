import 'tool.dart';

/// Interface-consistent stubs for productivity/integration tools.
///
/// Each class below exposes the full six-layer [Tool] contract (real name,
/// description, schemas, permission policy) but [execute] throws
/// [UnimplementedError] with a clear message, because every one of them needs
/// an external account connection or native capability that is not part of
/// this scaffold:
///
/// - [CalendarTool]   -> needs a calendar account connection (Google/Outlook).
/// - [EmailTool]      -> needs an email account connection (Gmail/IMAP).
/// - [TaskTool]       -> needs a task provider connection.
/// - [PdfTool]        -> needs a native PDF rendering plugin.
/// - [DocumentTool]   -> needs a document (docx/md) processing plugin.
/// - [DatabaseTool]   -> needs configured database connection profiles.
/// - [AutomationTool] -> needs the OS automation backend (see lib/control).
/// - [ResearchTool]   -> needs a web-search API key / provider.

abstract class _StubTool extends Tool {
  UnimplementedError get _missing => UnimplementedError(
      '$name.execute requires an external account, API key, or native plugin '
      'that is not connected in this scaffold.');

  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async =>
      PermissionDecision.denied('$name is not implemented in this build');

  @override
  Future<ToolResult> execute(ToolCall call) async => throw _missing;

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async => false;
}

class CalendarTool extends _StubTool {
  @override
  String get name => 'calendar';
  @override
  String get description =>
      'List/create calendar events (requires a connected calendar account).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['list', 'create', 'delete'],
          'required': true,
        },
        'title': {'type': 'string', 'required': false},
        'start': {'type': 'string', 'required': false},
        'end': {'type': 'string', 'required': false},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'events': {'type': 'array'},
        },
      };
}

class EmailTool extends _StubTool {
  @override
  String get name => 'email';
  @override
  String get description =>
      'Search, read and send email (requires a connected email account).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['search', 'read', 'send'],
          'required': true,
        },
        'query': {'type': 'string', 'required': false},
        'to': {'type': 'string', 'required': false},
        'subject': {'type': 'string', 'required': false},
        'body': {'type': 'string', 'required': false},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'messages': {'type': 'array'},
        },
      };
}

class TaskTool extends _StubTool {
  @override
  String get name => 'task';
  @override
  String get description =>
      'Manage to-do tasks (requires a connected task provider).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['list', 'create', 'complete'],
          'required': true,
        },
        'title': {'type': 'string', 'required': false},
        'id': {'type': 'string', 'required': false},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'tasks': {'type': 'array'},
        },
      };
}

class PdfTool extends _StubTool {
  @override
  String get name => 'pdf';
  @override
  String get description =>
      'Read/merge/split PDF files (requires a native PDF plugin).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['read', 'merge', 'split'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'pages': {'type': 'int'},
        },
      };
}

class DocumentTool extends _StubTool {
  @override
  String get name => 'document';
  @override
  String get description =>
      'Read/write office documents (requires a document processing plugin).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['read', 'write', 'convert'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
      };
}

class DatabaseTool extends _StubTool {
  @override
  String get name => 'database';
  @override
  String get description =>
      'Query external databases (requires configured connection profiles).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['query', 'listTables'],
          'required': true,
        },
        'profile': {'type': 'string', 'required': true},
        'sql': {'type': 'string', 'required': false},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'rows': {'type': 'array'},
        },
      };
}

class AutomationTool extends _StubTool {
  @override
  String get name => 'automation';
  @override
  String get description =>
      'Run OS-level automation routines (requires the native control backend; see lib/control).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['runRoutine', 'listRoutines'],
          'required': true,
        },
        'routine': {'type': 'string', 'required': false},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'result': {'type': 'string'},
        },
      };
}

class ResearchTool extends _StubTool {
  @override
  String get name => 'research';
  @override
  String get description =>
      'Deep web research with citations (requires a search API provider).';
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['search', 'summarize'],
          'required': true,
        },
        'query': {'type': 'string', 'required': true},
      };
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'results': {'type': 'array'},
        },
      };
}
