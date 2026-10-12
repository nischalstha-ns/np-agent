import '../memory/memory_store.dart';
import 'tool.dart';

/// REAL: Direct memory operations (meta-tool) over the app's [MemoryStore].
///
/// Actions:
/// - `save`        {layer, key, content, importance?} -> {id}
/// - `recall`      {layer?, limit?}                    -> {items}
/// - `get`         {layer, key}                        -> {item?}
/// - `count`       {layer}                             -> {count}
/// - `profileGet`  {key}                               -> {value}
/// - `profileSet`  {key, value}                        -> {ok}
/// - `recentUsage` {limit?}                            -> {rows}
///
/// Layers: `short_term`, `long_term`, `semantic`.
class MemoryTool extends Tool {
  /// REAL: The memory store this tool operates on.
  final MemoryStore store;

  MemoryTool({required this.store});

  @override
  String get name => 'memory';

  @override
  String get description =>
      'Save, recall and inspect NP\'s own memory (memory items, user '
      'profile, tool-usage history).';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': [
            'save',
            'recall',
            'get',
            'count',
            'profileGet',
            'profileSet',
            'recentUsage'
          ],
          'required': true,
        },
        'layer': {'type': 'string', 'required': false},
        'key': {'type': 'string', 'required': false},
        'content': {'type': 'string', 'required': false},
        'importance': {'type': 'double', 'required': false},
        'value': {'type': 'string', 'required': false},
        'limit': {'type': 'int', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'Action-dependent payload (items, counts, values).',
      };

  /// REAL: Local memory access — open, except profile writes need approval.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'save':
      case 'recall':
      case 'get':
      case 'count':
      case 'profileGet':
      case 'recentUsage':
        return const PermissionDecision.allowed('local memory access');
      case 'profileSet':
        return const PermissionDecision.needsApproval(
            'changing the user profile needs approval');
      default:
        return PermissionDecision.denied(
            'Unknown memory action "${call.action}"');
    }
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'save':
          return ToolResult.ok(await _save(call));
        case 'recall':
          return ToolResult.ok(await _recall(call));
        case 'get':
          return ToolResult.ok(await _get(call));
        case 'count':
          return ToolResult.ok(await _count(call));
        case 'profileGet':
          return ToolResult.ok(await _profileGet(call));
        case 'profileSet':
          return ToolResult.ok(await _profileSet(call));
        case 'recentUsage':
          return ToolResult.ok(await _recentUsage(call));
        default:
          return ToolResult.fail('Unknown memory action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('memory.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    return result.data is Map;
  }

  Future<Map<String, dynamic>> _save(ToolCall call) async {
    final layer = (call.args['layer'] as String? ?? 'short_term').trim();
    final key = (call.args['key'] as String? ?? '').trim();
    final content = call.args['content'] as String? ?? '';
    if (key.isEmpty) throw ArgumentError('save requires "key"');
    if (!{'short_term', 'long_term', 'semantic'}.contains(layer)) {
      throw ArgumentError('save: unknown layer "$layer"');
    }
    final id = await store.saveMemoryItem(
      layer: layer,
      key: key,
      content: content,
      importance: (call.args['importance'] as num?)?.toDouble() ?? 0.5,
    );
    return {'id': id, 'layer': layer, 'key': key};
  }

  Future<Map<String, dynamic>> _recall(ToolCall call) async {
    final layer = call.args['layer'] as String?;
    final limit = (call.args['limit'] as int?) ?? 20;
    final rows = await store.getMemoryItems(
      layer: layer,
      limit: limit,
      orderByRecency: true,
    );
    return {
      'items': rows
          .map((r) => {
                'id': r['id'],
                'layer': r['layer'],
                'key': r['key'],
                'content': r['content'],
                'importance': r['importance'],
              })
          .toList(),
      'count': rows.length,
    };
  }

  Future<Map<String, dynamic>> _get(ToolCall call) async {
    final layer = (call.args['layer'] as String? ?? '').trim();
    final key = (call.args['key'] as String? ?? '').trim();
    if (layer.isEmpty || key.isEmpty) {
      throw ArgumentError('get requires "layer" and "key"');
    }
    final row = await store.getMemoryItem(layer, key);
    return {
      'item': row == null
          ? null
          : {
              'id': row['id'],
              'layer': row['layer'],
              'key': row['key'],
              'content': row['content'],
              'importance': row['importance'],
            }
    };
  }

  Future<Map<String, dynamic>> _count(ToolCall call) async {
    final layer = (call.args['layer'] as String? ?? '').trim();
    if (layer.isEmpty) throw ArgumentError('count requires "layer"');
    return {'layer': layer, 'count': await store.countMemoryItems(layer)};
  }

  Future<Map<String, dynamic>> _profileGet(ToolCall call) async {
    final key = (call.args['key'] as String? ?? '').trim();
    if (key.isEmpty) throw ArgumentError('profileGet requires "key"');
    return {'key': key, 'value': await store.profileGet(key)};
  }

  Future<Map<String, dynamic>> _profileSet(ToolCall call) async {
    final key = (call.args['key'] as String? ?? '').trim();
    final value = call.args['value'] as String? ?? '';
    if (key.isEmpty) throw ArgumentError('profileSet requires "key"');
    await store.profileSet(key, value);
    return {'key': key, 'ok': true};
  }

  Future<Map<String, dynamic>> _recentUsage(ToolCall call) async {
    final limit = (call.args['limit'] as int?) ?? 20;
    final rows = await store.recentToolUsage(limit: limit);
    return {
      'rows': rows
          .map((r) => {
                'tool': r['tool'],
                'success': r['success'],
                'duration_ms': r['duration_ms'],
                'created_at': r['created_at'],
              })
          .toList(),
      'count': rows.length,
    };
  }
}
