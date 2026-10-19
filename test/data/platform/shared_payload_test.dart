import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/channel_share_intake.dart';
import 'package:ghina/domain/services/share_intake.dart';

void main() {
  group('extractUrls', () {
    test('finds http(s) and www links in order', () {
      expect(
        extractUrls(
          'Cek https://a.com/x dan http://b.id/y?q=1 juga www.c.co.id',
        ),
        ['https://a.com/x', 'http://b.id/y?q=1', 'https://www.c.co.id'],
      );
    });

    test('strips trailing punctuation and unbalanced brackets', () {
      expect(extractUrls('lihat (https://a.com/b).'), ['https://a.com/b']);
      expect(extractUrls('"https://a.com/b",'), ['https://a.com/b']);
      expect(extractUrls('https://id.wikipedia.org/wiki/Nasi_(makanan)'), [
        'https://id.wikipedia.org/wiki/Nasi_(makanan)',
      ]);
      expect(extractUrls('link: https://a.com/b!?'), ['https://a.com/b']);
    });

    test('ignores non-links', () {
      expect(extractUrls('email a@b.com, harga 10.000, http://'), isEmpty);
      expect(extractUrls('https://localhost'), isEmpty);
    });
  });

  group('SharedPayload.normalize', () {
    test('browser share: subject = title, text = only the URL', () {
      final p = SharedPayload.normalize(
        subject: 'Resep Rendang',
        texts: ['https://masak.id/rendang'],
      );
      expect(p.title, 'Resep Rendang');
      expect(p.text, isNull);
      expect(p.urls, ['https://masak.id/rendang']);
      expect(p.isEmpty, isFalse);
    });

    test('text with links keeps the text and extracts deduplicated links', () {
      final p = SharedPayload.normalize(
        texts: [
          '  Nonton ini https://youtu.be/x\r\nlagi: https://youtu.be/x  ',
        ],
      );
      expect(p.text, 'Nonton ini https://youtu.be/x\nlagi: https://youtu.be/x');
      expect(p.urls, ['https://youtu.be/x']);
    });

    test('multiple texts are joined; subject equal to text is dropped', () {
      final p = SharedPayload.normalize(subject: 'a', texts: ['a']);
      expect(p.text, 'a');
      expect(p.title, isNull);
      final q = SharedPayload.normalize(texts: ['satu', ' ', 'dua']);
      expect(q.text, 'satu\n\ndua');
    });

    test('caps links and images; drops blanks and duplicate images', () {
      final many = List.generate(30, (i) => 'https://x.com/$i').join(' ');
      final p = SharedPayload.normalize(
        texts: [many],
        imagePaths: [
          '/a.jpg',
          '',
          '/a.jpg',
          ...List.generate(30, (i) => '/$i.png'),
        ],
      );
      expect(p.urls, hasLength(kMaxSharedLinks));
      expect(p.imagePaths.first, '/a.jpg');
      expect(p.imagePaths, hasLength(kMaxSharedImages));
    });

    test('a shared PDF makes the payload non-empty; only one is kept', () {
      final p = SharedPayload.normalize(
        pdfPaths: ['/c/1/mutasi.pdf', '', '/c/1/mutasi.pdf', '/c/2/lain.pdf'],
      );
      expect(p.pdfPaths, ['/c/1/mutasi.pdf']);
      expect(p.pdfPaths, hasLength(kMaxSharedPdfs));
      expect(p.hasPdf, isTrue);
      expect(p.isEmpty, isFalse);
      expect(SharedPayload.normalize(texts: ['hai']).hasPdf, isFalse);
    });

    test('empty share', () {
      expect(
        SharedPayload.normalize(subject: ' ', texts: ['']).isEmpty,
        isTrue,
      );
    });

    test('links in the subject are collected too', () {
      final p = SharedPayload.normalize(
        subject: 'https://a.com',
        texts: ['hai'],
      );
      expect(p.urls, ['https://a.com']);
    });
  });

  test('payloadFromRaw moves cached images into app storage', () async {
    final tmp = await Directory.systemTemp.createTemp('share_test');
    addTearDown(() => tmp.delete(recursive: true));
    final cache = Directory('${tmp.path}/cache')..createSync();
    final store = Directory('${tmp.path}/docs/shared_images')
      ..createSync(recursive: true);
    final img = File('${cache.path}/1.png')..writeAsBytesSync([1, 2, 3]);

    final p = await payloadFromRaw({
      'subject': null,
      'texts': ['foto https://a.com'],
      'images': [img.path, '${cache.path}/missing.jpg'],
    }, () async => store);

    expect(p.text, 'foto https://a.com');
    expect(p.urls, ['https://a.com']);
    expect(p.imagePaths, hasLength(1));
    expect(p.imagePaths.single, startsWith(store.path));
    expect(p.imagePaths.single, endsWith('.png'));
    expect(File(p.imagePaths.single).readAsBytesSync(), [1, 2, 3]);
    expect(img.existsSync(), isFalse);
  });

  test(
    'payloadFromRaw keeps shared PDFs where the activity put them',
    () async {
      final tmp = await Directory.systemTemp.createTemp('share_pdf_test');
      addTearDown(() => tmp.delete(recursive: true));
      final dir = Directory('${tmp.path}/share_intake/1')
        ..createSync(recursive: true);
      final pdf = File('${dir.path}/mutasi-oktober.pdf')
        ..writeAsBytesSync([37, 80, 68, 70]);

      final p = await payloadFromRaw({
        'subject': 'mutasi-oktober.pdf',
        'texts': <String>[],
        'images': <String>[],
        'pdfs': [pdf.path, '${dir.path}/missing.pdf'],
      }, () async => tmp);

      expect(p.pdfPaths, [pdf.path]);
      expect(pdf.existsSync(), isTrue);
      expect(p.isEmpty, isFalse);
    },
  );
}
