import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_model.dart';
import 'package:ghina/presentation/features/kantor/session/chat_model.dart';
import 'package:ghina/presentation/features/kantor/session/chat_timeline.dart';

KantorAttachment att({String? message, String? note, String id = 'a1'}) =>
    KantorAttachment.fromJson({
      'id': id,
      'name': 'bukti.png',
      'mime': 'image/png',
      'size': 10,
      'dir': 'in',
      'at': '2026-11-12T09:00:00Z',
      'message': ?message,
      'note': ?note,
    });

void main() {
  const merged =
      'Tolong cek layar ini\n\n[Lampiran dari pemilik, 2 file]\n- bukti.png\n- log.txt';

  test('the attachment reads message and note from the daemon', () {
    final a = att(message: merged, note: 'Tolong cek layar ini');
    expect(a.message, merged);
    expect(a.note, 'Tolong cek layar ini');
    expect(att().message, isNull);
  });

  test('the combined prompt shows only the owner note', () {
    final out = hideBatchMessages(
      [
        const UserEntry('halo', '1'),
        const UserEntry(merged, '2'),
        const ClaudeEntry('siap', '3'),
      ],
      [att(message: merged, note: 'Tolong cek layar ini')],
    );
    expect(out.map((e) => e.runtimeType), [UserEntry, UserEntry, ClaudeEntry]);
    expect((out[1] as UserEntry).text, 'Tolong cek layar ini');
    expect(out[1].at, '2');
  });

  test('an empty note hides the prompt altogether', () {
    final msg = '[Lampiran dari pemilik] bukti.png (10 B)';
    final out = hideBatchMessages(
      [const UserEntry('halo', '1'), UserEntry(msg, '2')],
      [att(message: msg, note: '')],
    );
    expect(out, hasLength(1));
    expect((out.single as UserEntry).text, 'halo');
  });

  test('a long prompt cut by the transcript still matches', () {
    final cut = '${merged.substring(0, merged.length - 4)}…';
    final out = hideBatchMessages(
      [UserEntry(cut, '2')],
      [att(message: merged, note: 'Tolong cek layar ini')],
    );
    expect((out.single as UserEntry).text, 'Tolong cek layar ini');
  });

  test('pasted_content wrappers and whitespace do not matter', () {
    final out = hideBatchMessages(
      [UserEntry('<pasted_content>\n$merged\n</pasted_content>', '2')],
      [att(message: merged, note: 'Catatan')],
    );
    expect((out.single as UserEntry).text, 'Catatan');
  });

  test('unrelated prompts and short texts are never hidden', () {
    final out = hideBatchMessages(
      [const UserEntry('lanjut', '1'), const UserEntry('Prompt lain', '2')],
      [att(message: merged, note: '')],
    );
    expect(out, hasLength(2));
  });

  test('without batch messages the list is returned untouched', () {
    final list = <ChatEntry>[const UserEntry('halo', '1')];
    expect(identical(hideBatchMessages(list, [att()]), list), isTrue);
  });

  test('batchNoteFor: null = not a batch, empty = hide', () {
    final b = batchNotes([att(message: merged, note: '')]);
    expect(batchNoteFor('lain', b), isNull);
    expect(batchNoteFor(merged, b), '');
  });

  test('hiddenBeforeClear reads the count, 0 for a bare list', () {
    expect(hiddenBeforeClear({'items': [], 'hiddenBeforeClear': 3}), 3);
    expect(hiddenBeforeClear([]), 0);
    expect(hiddenBeforeClear({'items': []}), 0);
  });
}
