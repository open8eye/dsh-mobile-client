import 'package:dsh_mobile_client/core/state/session_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSet ordering', () {
    test('opening the first session makes it current', () {
      final sessions = SessionSet();
      expect(sessions.open('a'), isEmpty);
      expect(sessions.ids, <String>['a']);
      expect(sessions.currentId, 'a');
    });

    test('the most recently opened session is the current one', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b');
      expect(sessions.ids, <String>['a', 'b']);
      expect(sessions.currentId, 'b');
    });

    test('activating moves a session to the recent end', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b');
      expect(sessions.activate('a'), isTrue);
      expect(sessions.ids, <String>['b', 'a']);
      expect(sessions.currentId, 'a');
    });

    test('activating something that is not open is refused', () {
      final sessions = SessionSet()..open('a');
      expect(sessions.activate('b'), isFalse);
      expect(sessions.ids, <String>['a']);
      expect(sessions.currentId, 'a');
    });

    test('re-opening a session that is already live does not duplicate it', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b');
      expect(sessions.open('a'), isEmpty);
      expect(sessions.ids, <String>['b', 'a']);
      expect(sessions.currentId, 'a');
    });
  });

  group('SessionSet eviction', () {
    test('opening past the cap drops the least recently used one', () {
      final sessions = SessionSet(maxSessions: 2)
        ..open('a')
        ..open('b');
      expect(sessions.open('c'), <String>['a']);
      expect(sessions.ids, <String>['b', 'c']);
      expect(sessions.currentId, 'c');
    });

    test('re-opening an older session at the cap drops nothing', () {
      // 'a' is the oldest, but it is also the one being brought back, and
      // the count never went above the cap.
      final sessions = SessionSet(maxSessions: 2)
        ..open('a')
        ..open('b');
      expect(sessions.open('a'), isEmpty);
      expect(sessions.ids, <String>['b', 'a']);
      expect(sessions.currentId, 'a');
    });

    test('a cap of one keeps the newcomer', () {
      final sessions = SessionSet(maxSessions: 1)..open('a');
      expect(sessions.open('b'), <String>['a']);
      expect(sessions.ids, <String>['b']);
    });

    test('a long run of opens keeps exactly the cap, newest first', () {
      final sessions = SessionSet(maxSessions: 3);
      for (final id in <String>['a', 'b', 'c', 'd', 'e']) {
        sessions.open(id);
      }
      expect(sessions.ids, <String>['c', 'd', 'e']);
      expect(sessions.currentId, 'e');
    });

    test('activation decides who survives the next eviction', () {
      final sessions = SessionSet(maxSessions: 2)
        ..open('a')
        ..open('b');
      sessions.activate('a');
      expect(sessions.open('c'), <String>['b']);
      expect(sessions.ids, <String>['a', 'c']);
    });
  });

  group('SessionSet closing', () {
    test('closing the current session falls back to the most recent other one', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b')
        ..open('c');
      expect(sessions.close('c'), isTrue);
      expect(sessions.ids, <String>['a', 'b']);
      expect(sessions.currentId, 'b');
    });

    test('closing a background session leaves the current one alone', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b');
      expect(sessions.close('a'), isTrue);
      expect(sessions.currentId, 'b');
    });

    test('closing the last session leaves nothing current', () {
      final sessions = SessionSet()..open('a');
      expect(sessions.close('a'), isTrue);
      expect(sessions.isEmpty, isTrue);
      expect(sessions.currentId, isNull);
    });

    test('closing something that is not open is refused', () {
      final sessions = SessionSet()..open('a');
      expect(sessions.close('zz'), isFalse);
      expect(sessions.currentId, 'a');
    });
  });

  group('SessionSet.retain', () {
    test('drops sessions whose device was deleted and reports them', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b')
        ..open('c');
      expect(sessions.retain(<String>{'a', 'c'}), <String>['b']);
      expect(sessions.ids, <String>['a', 'c']);
    });

    test('repoints the current session when the current device is deleted', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b');
      sessions.retain(<String>{'a'});
      expect(sessions.currentId, 'a');
    });

    test('clears the current session when every device is deleted', () {
      final sessions = SessionSet()..open('a');
      sessions.retain(<String>{});
      expect(sessions.isEmpty, isTrue);
      expect(sessions.currentId, isNull);
    });

    test('is a no-op when nothing was deleted', () {
      final sessions = SessionSet()
        ..open('a')
        ..open('b');
      expect(sessions.retain(<String>{'a', 'b'}), isEmpty);
      expect(sessions.ids, <String>['a', 'b']);
      expect(sessions.currentId, 'b');
    });
  });

  test('the default cap is the four the shell uses', () {
    final sessions = SessionSet();
    for (final id in <String>['a', 'b', 'c', 'd', 'e']) {
      sessions.open(id);
    }
    expect(sessions.length, 4);
  });
}
