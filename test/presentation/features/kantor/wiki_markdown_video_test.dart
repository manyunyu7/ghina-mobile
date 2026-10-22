import 'package:flutter_test/flutter_test.dart';

import 'package:ghina/presentation/features/kantor/wiki/wiki_markdown.dart';

void main() {
  test('legacy video file links become video embeds', () {
    final out = WikiMarkdown.prepare(
      '[📎 klip uji.mp4](/api/offices/x/media/abc)',
    );
    expect(out, '![klip uji](/api/offices/x/media/abc.mp4)');
    expect(
      WikiMarkdown.isVideoUri(Uri.parse('/api/offices/x/media/abc.mp4')),
      isTrue,
    );
  });

  test('non-video links, images and new video syntax are untouched', () {
    for (final s in [
      '[📎 laporan.xlsx](/api/offices/x/media/abc)',
      '![gambar](/api/offices/x/media/abc)',
      '![klip](/api/offices/x/media/abc.mp4)',
    ]) {
      expect(WikiMarkdown.prepare(s), s);
    }
    expect(
      WikiMarkdown.isVideoUri(Uri.parse('/api/offices/x/media/abc')),
      isFalse,
    );
  });

  test('a lone YouTube link becomes a card link', () {
    expect(
      WikiMarkdown.prepare('Lihat:\n\nhttps://youtu.be/dQw4w9WgXcQ\n'),
      contains('[▶ Putar di YouTube](https://youtu.be/dQw4w9WgXcQ)'),
    );
    expect(
      WikiMarkdown.prepare('teks https://youtu.be/dQw4w9WgXcQ lagi'),
      isNot(contains('▶')),
    );
  });
}
