// Tests for InMemoryMemoryStore (pure-Dart MemoryStore) and
// RetrievalService ranking.
import 'package:flutter_test/flutter_test.dart';
import 'package:np/memory/embeddings.dart';
import 'package:np/memory/in_memory_store.dart';
import 'package:np/memory/retrieval.dart';

void main() {
  group('InMemoryMemoryStore CRUD', () {
    late InMemoryMemoryStore store;

    setUp(() {
      store = InMemoryMemoryStore();
    });

    test('save/get roundtrip', () async {
      final id = await store.saveMemoryItem(
        layer: 'long_term',
        key: 'k1',
        content: 'hello world',
      );
      expect(id, isNonZero);

      final row = await store.getMemoryItem('long_term', 'k1');
      expect(row, isNotNull);
      expect(row!['id'], id);
      expect(row['content'], 'hello world');
      expect(row['importance'], 0.5);
    });

    test('upsert semantics: same layer+key keeps id, updates content', () async {
      final id1 = await store.saveMemoryItem(
          layer: 'semantic', key: 'up', content: 'v1', importance: 0.2);
      final id2 = await store.saveMemoryItem(
          layer: 'semantic', key: 'up', content: 'v2', importance: 0.9);
      expect(id2, id1);

      final row = await store.getMemoryItem('semantic', 'up');
      expect(row!['content'], 'v2');
      expect(row['importance'], 0.9);
      expect(await store.countMemoryItems('semantic'), 1);
    });

    test('different layers are independent', () async {
      await store.saveMemoryItem(
          layer: 'short_term', key: 'k', content: 'short');
      await store.saveMemoryItem(
          layer: 'long_term', key: 'k', content: 'long');
      expect(await store.countMemoryItems('short_term'), 1);
      expect(await store.countMemoryItems('long_term'), 1);
      expect((await store.getMemoryItem('short_term', 'k'))!['content'],
          'short');
    });

    test('updateImportance and touchMemoryItem', () async {
      final id = await store.saveMemoryItem(
          layer: 'long_term', key: 'imp', content: 'x');
      expect(await store.updateImportance(id, 0.95), 1);
      expect((await store.getMemoryItem('long_term', 'imp'))!['importance'],
          0.95);
      // importance is clamped to 0..1
      expect(await store.updateImportance(id, 5.0), 1);
      expect((await store.getMemoryItem('long_term', 'imp'))!['importance'],
          1.0);
      expect(await store.touchMemoryItem(id), 1);
      // unknown ids are no-ops
      expect(await store.updateImportance(999999, 0.1), 0);
      expect(await store.touchMemoryItem(999999), 0);
    });

    test('deleteMemoryItem removes the row', () async {
      final id = await store.saveMemoryItem(
          layer: 'long_term', key: 'gone', content: 'x');
      expect(await store.countMemoryItems('long_term'), 1);
      expect(await store.deleteMemoryItem(id), 1);
      expect(await store.getMemoryItem('long_term', 'gone'), isNull);
      expect(await store.countMemoryItems('long_term'), 0);
      expect(await store.deleteMemoryItem(id), 0);
    });

    test('getMemoryItems filtering, ordering and limit', () async {
      await store.saveMemoryItem(
          layer: 'long_term', key: 'a', content: 'a', importance: 0.1);
      await store.saveMemoryItem(
          layer: 'long_term', key: 'b', content: 'b', importance: 0.9);
      await store.saveMemoryItem(
          layer: 'short_term', key: 'c', content: 'c', importance: 0.5);

      final byLayer = await store.getMemoryItems(layer: 'long_term');
      expect(byLayer.map((r) => r['key']), containsAll(['a', 'b']));
      expect(byLayer.length, 2);

      // default order is importance desc
      expect(byLayer.first['key'], 'b');

      final limited = await store.getMemoryItems(layer: 'long_term', limit: 1);
      expect(limited.length, 1);

      final byLayers =
          await store.getMemoryItems(layers: ['short_term', 'long_term']);
      expect(byLayers.length, 3);
    });

    test('profile get/set/all', () async {
      expect(await store.profileGet('name'), isNull);
      await store.profileSet('name', 'ddd');
      await store.profileSet('tz', 'Asia/Kathmandu');
      expect(await store.profileGet('name'), 'ddd');
      final all = await store.profileAll();
      expect(all['name'], 'ddd');
      expect(all['tz'], 'Asia/Kathmandu');
    });

    test('tool usage log, recent list and success rate', () async {
      await store.logToolUsage(
          tool: 'file',
          argsJson: '{}',
          success: true,
          durationMs: 10);
      await store.logToolUsage(
          tool: 'file',
          argsJson: '{}',
          success: false,
          durationMs: 12);
      await store.logToolUsage(
          tool: 'terminal',
          argsJson: '{}',
          success: true,
          durationMs: 5);

      final recent = await store.recentToolUsage(limit: 2);
      expect(recent.length, 2);
      expect(recent.first['tool'], 'terminal'); // newest first

      expect(await store.toolSuccessRate('file'), 0.5);
      expect(await store.toolSuccessRate('terminal'), 1.0);
      expect(await store.toolSuccessRate('never_called'), 1.0);
    });

    test('projects CRUD', () async {
      await store.saveProject('p1', 'Proj', '{"a":1}');
      expect((await store.getProject('p1'))!['name'], 'Proj');
      expect((await store.listProjects()).length, 1);
      await store.saveProject('p1', 'Proj2', '{"a":2}');
      expect((await store.getProject('p1'))!['name'], 'Proj2');
      expect(await store.deleteProject('p1'), 1);
      expect(await store.getProject('p1'), isNull);
      expect(await store.deleteProject('p1'), 0);
    });

    test('skills CRUD', () async {
      await store.saveSkill('s1', 'gmail', 'mail skill', '{}');
      expect((await store.findSkillByName('gmail'))!['id'], 's1');
      expect((await store.listSkills()).length, 1);
      expect(await store.deleteSkill('s1'), 1);
      expect(await store.findSkillByName('gmail'), isNull);
    });

    test('tasks + task results', () async {
      await store.createTask('t1', 'do things');
      expect((await store.getTask('t1'))!['status'], 'running');
      await store.updateTaskStatus('t1', 'done');
      expect((await store.getTask('t1'))!['status'], 'done');

      await store.addTaskResult('t1', 'planning', '{"steps":1}');
      await store.addTaskResult('t1', 'execution', '{"ok":true}');
      final results = await store.getTaskResults('t1');
      expect(results.length, 2);
      expect(results.first['stage'], 'planning'); // oldest first
    });

    test('failures: record, list, countSimilar', () async {
      await store.recordFailure('t1', 'execution', 'boom: file missing', null);
      await store.recordFailure('t2', 'execution', 'boom: file missing', null);
      await store.recordFailure('t3', 'execution', 'other error', null);

      final failures = await store.listFailures();
      expect(failures.length, 3);
      expect(failures.first['task_id'], 't3'); // newest first

      expect(await store.countSimilarFailures('boom: file missing'), 2);
      expect(await store.countSimilarFailures('other error'), 1);
      expect(await store.countSimilarFailures('nothing like this'), 0);
    });

    test('failure rules upsert/list', () async {
      await store.upsertFailureRule('r1', 'boom', 'avoid boom');
      await store.upsertFailureRule('r1', 'boom', 'really avoid boom');
      final rules = await store.listFailureRules();
      expect(rules.length, 1);
      expect(rules.first['action'], 'really avoid boom');
    });

    test('close is a no-op', () async {
      await store.close();
    });
  });

  group('HashingEmbedding', () {
    test('deterministic, normalized, cosine sane', () async {
      final emb = HashingEmbedding(dimension: 256);
      final a = await emb.embed('hello world');
      final b = await emb.embed('hello world');
      expect(a.length, 256);
      expect(HashingEmbedding.cosine(a, b), closeTo(1.0, 1e-6));

      final c = await emb.embed('completely different words zzz qqq');
      final sim = HashingEmbedding.cosine(a, c);
      expect(sim, lessThan(0.9));

      // empty text -> zero vector, cosine 0
      final empty = await emb.embed('');
      expect(HashingEmbedding.cosine(a, empty), 0.0);
    });

    test('encode/decode embedding roundtrip', () async {
      final emb = HashingEmbedding(dimension: 64);
      final vec = await emb.embed('roundtrip me');
      final blob = encodeEmbedding(vec);
      final back = decodeEmbedding(blob);
      expect(back.length, 64);
      expect(HashingEmbedding.cosine(vec, back), closeTo(1.0, 1e-4));
    });
  });

  group('RetrievalService ranking', () {
    test('most similar item ranks first', () async {
      final store = InMemoryMemoryStore();
      final emb = HashingEmbedding(dimension: 256);
      final retrieval = RetrievalService(store: store, embeddings: emb);

      Future<void> save(String key, String content) async {
        final vec = await emb.embed(content);
        await store.saveMemoryItem(
          layer: 'long_term',
          key: key,
          content: content,
          embedding: encodeEmbedding(vec),
          importance: 0.5,
        );
      }

      await save('cats', 'the cat sat on the mat and purred softly all afternoon');
      await save('dogs', 'the dog barked loudly at the mail carrier this morning');
      await save('cars', 'the engine roared as the car sped down the highway');

      final results = await retrieval.retrieve('my cat purred softly');
      expect(results.length, 3);
      expect(results.first.key, 'cats');
      expect(results.first.similarity, greaterThan(0.0));
      // scores strictly descending
      for (var i = 0; i < results.length - 1; i++) {
        expect(results[i].score, greaterThanOrEqualTo(results[i + 1].score));
      }
    });

    test('items without embeddings still compete on recency/importance', () async {
      final store = InMemoryMemoryStore();
      final emb = HashingEmbedding(dimension: 256);
      final retrieval = RetrievalService(store: store, embeddings: emb);

      await store.saveMemoryItem(
          layer: 'long_term', key: 'plain', content: 'no embedding here');
      final results = await retrieval.retrieve('anything at all');
      expect(results.length, 1);
      expect(results.first.key, 'plain');
      expect(results.first.similarity, 0.0);
    });

    test('layer filter and topK', () async {
      final store = InMemoryMemoryStore();
      final emb = HashingEmbedding(dimension: 256);
      final retrieval = RetrievalService(store: store, embeddings: emb);

      for (var i = 0; i < 4; i++) {
        await store.saveMemoryItem(
            layer: 'short_term', key: 's$i', content: 'short $i');
        await store.saveMemoryItem(
            layer: 'semantic', key: 'm$i', content: 'semantic $i');
      }

      final all = await retrieval.retrieve('x', topK: 100);
      expect(all.length, 8);
      final shortOnly =
          await retrieval.retrieve('x', layers: const ['short_term']);
      expect(shortOnly.length, 4);
      expect(shortOnly.every((m) => m.layer == 'short_term'), isTrue);
      final top2 = await retrieval.retrieve('x', topK: 2);
      expect(top2.length, 2);
    });
  });
}
