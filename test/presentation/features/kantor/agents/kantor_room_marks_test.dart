import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_room_marks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('messengerStamp', () {
    final now = DateTime(2026, 11, 13, 18, 40); // Jumat
    test('today shows the clock', () {
      expect(messengerStamp(DateTime(2026, 11, 13, 9, 5), now: now), '09.05');
    });
    test('yesterday', () {
      expect(messengerStamp(DateTime(2026, 11, 12, 23), now: now), 'Kemarin');
    });
    test('this week shows the weekday', () {
      expect(messengerStamp(DateTime(2026, 11, 9, 8), now: now), 'Senin');
    });
    test('older shows the date', () {
      expect(messengerStamp(DateTime(2026, 10, 1), now: now), '01/10/26');
    });
    test('null is empty', () => expect(messengerStamp(null, now: now), ''));
  });

  group('KantorRoomMarks', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('pin, mute and unread toggle and survive json', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(kantorRoomMarksProvider.notifier);
      n.togglePin('a');
      n.toggleMute('a');
      n.markUnread('b');
      var m = c.read(kantorRoomMarksProvider);
      expect(m.pinned, {'a'});
      expect(m.muted, {'a'});
      expect(m.unread, {'b'});
      n.markRead('b');
      m = c.read(kantorRoomMarksProvider);
      expect(m.unread, isEmpty);
      expect(m.readAt.containsKey('b'), isTrue);
      final back = KantorRoomMarks.fromJson(m.toJson());
      expect(back.pinned, {'a'});
      expect(back.muted, {'a'});
      expect(back.readAt['b'], m.readAt['b']);
      n.togglePin('a');
      expect(c.read(kantorRoomMarksProvider).pinned, isEmpty);
    });
  });
}
