import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';

KantorOfficeFeed _feed(List<Map<String, dynamic>> sessions) =>
    KantorOfficeFeed('o', null)
      ..office = {'id': 'o', 'sessions': sessions}
      ..loading = false;

void main() {
  test('/clear: halaman sesi ikut ke id baru lewat session-gone next', () {
    final f = _feed([
      {'sid': 'lama', 'status': 'idle', 'tmux': 'kc-o-zora'},
    ]);
    expect(f.follow('lama'), 'lama');
    f.apply({
      't': 'session',
      'office': 'o',
      'session': {'sid': 'baru', 'status': 'idle', 'tmux': 'kc-o-zora'},
    });
    f.apply({
      't': 'session-gone',
      'office': 'o',
      'sid': 'lama',
      'next': 'baru',
    });
    expect(f.follow('lama'), 'baru');
    expect(f.follow('baru'), 'baru');
  });

  test(
    'kabar terlewat: sesi selesai pindah ke sesi hidup di pane yang sama',
    () {
      final f = _feed([
        {'sid': 'lama', 'status': 'idle', 'tmux': 'kc-o-zora'},
      ]);
      expect(f.follow('lama'), 'lama'); // pane-nya tercatat
      f.office = {
        'id': 'o',
        'sessions': [
          {'sid': 'baru', 'status': 'working', 'tmux': 'kc-o-zora'},
          {'sid': 'lain', 'status': 'working', 'tmux': 'kc-o-arya'},
        ],
      };
      expect(f.follow('lama'), 'baru');
    },
  );

  test('sesi di luar tmux dan sesi yang masih hidup tidak dipindah', () {
    final f = _feed([
      {'sid': 'a', 'status': 'ended'},
      {'sid': 'b', 'status': 'idle', 'tmux': 'kc-o-zora'},
      {'sid': 'c', 'status': 'working', 'tmux': 'kc-o-zora'},
    ]);
    expect(f.follow('a'), 'a');
    expect(f.follow('b'), 'b');
  });
}
