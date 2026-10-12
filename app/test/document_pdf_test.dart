// Tests for DocumentTool (csv/json/txt) and PdfTool (hand-built minimal PDF).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/tools/productivity_tools.dart';
import 'package:np/tools/tool.dart';

const _minimalPdf = '''%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 120 >>
stream
BT
/F1 12 Tf
72 712 Td
(Hello NP world) Tj
ET
BT
[(Second) 20 ( line)] TJ
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
trailer
<< /Root 1 0 R >>
%%EOF
''';

const _encryptedPdf = '''%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 60 >>
stream
BT
(Secret content) Tj
ET
endstream
endobj
trailer
<< /Root 1 0 R /Encrypt 9 0 R >>
%%EOF
''';

void main() {
  group('DocumentTool', () {
    late Directory root;
    final tool = DocumentTool();

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-doc-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('csv parse: quoted commas and doubled quotes', () async {
      final path = '${root.path}/data.csv';
      await File(path).writeAsString(
          'name,note\n"doe, john","said ""hi"""\nalice,plain\n');
      final result = await tool.execute(
          ToolCall(tool: 'document', action: 'read', args: {'path': path}));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['format'], '.csv');
      final rows = data['rows'] as List;
      expect(rows[0], ['name', 'note']);
      expect(rows[1], ['doe, john', 'said "hi"']);
      expect(rows[2], ['alice', 'plain']);
    });

    test('json: valid parses, invalid is reported', () async {
      final good = '${root.path}/good.json';
      await File(good).writeAsString('{"a": 1, "b": [1, 2]}');
      final ok = await tool.execute(
          ToolCall(tool: 'document', action: 'read', args: {'path': good}));
      expect(ok.success, isTrue);
      final okData = ok.data as Map;
      expect(okData['validJson'], isTrue);
      expect((okData['parsed'] as Map)['a'], 1);

      final bad = '${root.path}/bad.json';
      await File(bad).writeAsString('{not json');
      final fail = await tool.execute(
          ToolCall(tool: 'document', action: 'read', args: {'path': bad}));
      expect(fail.success, isTrue);
      expect((fail.data as Map)['validJson'], isFalse);
    });

    test('write then read txt roundtrip', () async {
      final path = '${root.path}/note.txt';
      final written = await tool.execute(ToolCall(
          tool: 'document',
          action: 'write',
          args: {'path': path, 'content': 'plain text'}));
      expect(written.success, isTrue);
      expect((written.data as Map)['bytesWritten'], 10);

      final read = await tool.execute(
          ToolCall(tool: 'document', action: 'read', args: {'path': path}));
      expect((read.data as Map)['text'], 'plain text');
    });

    test('write invalid json fails', () async {
      final result = await tool.execute(ToolCall(
          tool: 'document',
          action: 'write',
          args: {'path': '${root.path}/x.json', 'content': '{bad'}));
      expect(result.success, isFalse);
    });

    test('unsupported extension is denied', () async {
      final decision = await tool.checkPermission(ToolCall(
          tool: 'document',
          action: 'read',
          args: {'path': '${root.path}/x.pdf'}));
      expect(decision.isDenied, isTrue);
    });
  });

  group('PdfTool', () {
    late Directory root;
    final tool = PdfTool();

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-pdf-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('read extracts Tj and TJ text from a hand-built PDF', () async {
      final path = '${root.path}/hello.pdf';
      await File(path).writeAsString(_minimalPdf);

      final info = await tool.execute(
          ToolCall(tool: 'pdf', action: 'info', args: {'path': path}));
      expect(info.success, isTrue);
      expect((info.data as Map)['pages'], 1);

      final read = await tool.execute(
          ToolCall(tool: 'pdf', action: 'read', args: {'path': path}));
      expect(read.success, isTrue);
      final data = read.data as Map;
      expect(data['pages'], 1);
      final text = data['text'] as String;
      expect(text, contains('Hello NP world'));
      expect(text, contains('Second'));
      expect(text, contains('line'));
      expect(data['extractionNotes'], isA<List>());
      expect(await tool.verify(
          ToolCall(tool: 'pdf', action: 'read', args: {}), read), isTrue);
    });

    test('encrypted marker is reported honestly in notes', () async {
      final path = '${root.path}/enc.pdf';
      await File(path).writeAsString(_encryptedPdf);
      final read = await tool.execute(
          ToolCall(tool: 'pdf', action: 'read', args: {'path': path}));
      expect(read.success, isTrue);
      final notes = (read.data as Map)['extractionNotes'] as List;
      expect(notes.join(' '), contains('Encrypt'));
    });

    test('missing file fails', () async {
      final result = await tool.execute(ToolCall(
          tool: 'pdf', action: 'read', args: {'path': '${root.path}/no.pdf'}));
      expect(result.success, isFalse);
      expect(result.error, contains('File not found'));
    });

    test('read is allowed by permission policy', () async {
      final decision = await tool.checkPermission(const ToolCall(
          tool: 'pdf', action: 'read', args: {'path': 'x.pdf'}));
      expect(decision.isAllowed, isTrue);
    });
  });
}
