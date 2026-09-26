import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';

import 'support/fake_admin_pin_store.dart';

void main() {
  late FakeAdminPinStore store;
  late DateTime now;
  late AdminSession session;

  AdminSession newSession() => AdminSession(
    store: store,
    hasher: AdminPinHasher(iterations: 1000),
    now: () => now,
  );

  setUp(() {
    store = FakeAdminPinStore();
    now = DateTime(2026, 9, 25, 10);
    session = newSession();
  });

  tearDown(() => session.dispose());

  /// A session with the PIN 4815 set, logged out.
  Future<void> withPin([String pin = '4815']) async {
    await session.setUpPin(pin);
    session.logout();
  }

  group('at the start', () {
    test('Admin Mode is off and no PIN is set', () async {
      expect(session.isAdmin, isFalse);
      expect(await session.hasPinSet(), isFalse);
      expect(session.lockRemaining, isNull);
    });
  });

  group('setting up the PIN', () {
    test('stores it and turns Admin Mode on', () async {
      await session.setUpPin('4815');

      expect(session.isAdmin, isTrue);
      expect(await session.hasPinSet(), isTrue);
      expect(store.writes, 1);
    });

    test('stores only a salted hash, never the PIN', () async {
      await session.setUpPin('48151623');

      final stored = jsonEncode(store.record!.toMap());
      expect(stored.contains('48151623'), isFalse);
      expect(store.record!.hash, hasLength(32));
      expect(store.record!.salt, hasLength(16));
    });

    test('rejects a PIN that breaks the rules, and stores nothing', () async {
      for (final pin in ['', '123', '12345678901234', 'abcd', '12 34']) {
        await expectLater(
          session.setUpPin(pin),
          throwsFormatException,
          reason: '"$pin"',
        );
      }

      expect(store.writes, 0);
      expect(session.isAdmin, isFalse);
    });

    test('never replaces a PIN that is already set', () async {
      await withPin();
      final before = store.record;

      await expectLater(
        session.setUpPin('9999'),
        throwsA(isA<AdminPinAlreadySetException>()),
      );

      expect(store.record, same(before));
      expect(store.writes, 1);
      expect(session.isAdmin, isFalse);
    });

    test('tells listeners', () async {
      var notified = 0;
      session.addListener(() => notified++);

      await session.setUpPin('4815');

      expect(notified, 1);
    });

    test('passes on a storage failure and stays off', () async {
      store.writeError = StateError('disk full');

      await expectLater(session.setUpPin('4815'), throwsStateError);

      expect(session.isAdmin, isFalse);
    });
  });

  group('logging in', () {
    test('with the right PIN turns Admin Mode on', () async {
      await withPin();

      final result = await session.login('4815');

      expect(result.outcome, LoginOutcome.success);
      expect(result.succeeded, isTrue);
      expect(session.isAdmin, isTrue);
    });

    test('with a wrong PIN leaves Admin Mode off', () async {
      await withPin();

      final result = await session.login('4816');

      expect(result.outcome, LoginOutcome.incorrect);
      expect(result.succeeded, isFalse);
      expect(session.isAdmin, isFalse);
    });

    test('says how many attempts are left', () async {
      await withPin();

      final first = await session.login('0000');
      final second = await session.login('0000');

      expect(first.attemptsLeft, 4);
      expect(second.attemptsLeft, 3);
    });

    test('with no PIN set says so', () async {
      final result = await session.login('4815');

      expect(result.outcome, LoginOutcome.noPinSet);
      expect(session.isAdmin, isFalse);
    });

    test('checks a PIN that is not even valid, without crashing', () async {
      await withPin();

      for (final guess in ['', 'abcd', '1' * 50, '  ']) {
        expect(
          (await session.login(guess)).outcome,
          anyOf(LoginOutcome.incorrect, LoginOutcome.lockedOut),
          reason: '"$guess"',
        );
      }
      expect(session.isAdmin, isFalse);
    });

    test('tells listeners only when it changes', () async {
      await withPin();
      var notified = 0;
      session.addListener(() => notified++);

      await session.login('0000');
      expect(notified, 0);
      await session.login('4815');
      expect(notified, 1);
      await session.login('4815');
      expect(notified, 1);
    });

    test('passes on a storage failure', () async {
      await withPin();
      store.readError = StateError('blocked');

      await expectLater(session.login('4815'), throwsStateError);
      expect(session.isAdmin, isFalse);
    });
  });

  group('too many wrong PINs', () {
    Future<void> failFiveTimes() async {
      for (var i = 0; i < 5; i++) {
        await session.login('0000');
      }
    }

    test('lock out further attempts for a while', () async {
      await withPin();

      await failFiveTimes();

      expect(session.lockRemaining, const Duration(seconds: 30));
      final result = await session.login('0000');
      expect(result.outcome, LoginOutcome.lockedOut);
      expect(result.retryAfter, const Duration(seconds: 30));
    });

    test('report the fifth wrong PIN as the lockout', () async {
      await withPin();
      for (var i = 0; i < 4; i++) {
        expect((await session.login('0000')).outcome, LoginOutcome.incorrect);
      }

      final fifth = await session.login('0000');

      expect(fifth.outcome, LoginOutcome.lockedOut);
      expect(fifth.retryAfter, const Duration(seconds: 30));
    });

    test('refuse even the right PIN while locked', () async {
      await withPin();
      await failFiveTimes();

      final result = await session.login('4815');

      expect(result.outcome, LoginOutcome.lockedOut);
      expect(session.isAdmin, isFalse);
    });

    test('count down, and end', () async {
      await withPin();
      await failFiveTimes();

      now = now.add(const Duration(seconds: 12));
      expect(session.lockRemaining, const Duration(seconds: 18));
      expect((await session.login('4815')).outcome, LoginOutcome.lockedOut);

      now = now.add(const Duration(seconds: 18));
      expect(session.lockRemaining, isNull);
      expect((await session.login('4815')).succeeded, isTrue);
    });

    test('start counting again after a wait', () async {
      await withPin();
      await failFiveTimes();
      now = now.add(const Duration(seconds: 31));

      final result = await session.login('0000');

      expect(result.outcome, LoginOutcome.incorrect);
      expect(result.attemptsLeft, 4);
    });

    test('are forgotten after a correct PIN', () async {
      await withPin();
      for (var i = 0; i < 4; i++) {
        await session.login('0000');
      }
      await session.login('4815');
      session.logout();

      final result = await session.login('0000');

      expect(result.attemptsLeft, 4);
    });

    test('do not last past a refresh (a new session)', () async {
      await withPin();
      await failFiveTimes();
      final refreshed = newSession();
      addTearDown(refreshed.dispose);

      expect(refreshed.lockRemaining, isNull);
      expect((await refreshed.login('4815')).succeeded, isTrue);
    });
  });

  group('logging out', () {
    test('turns Admin Mode off and tells listeners', () async {
      await session.setUpPin('4815');
      var notified = 0;
      session.addListener(() => notified++);

      session.logout();

      expect(session.isAdmin, isFalse);
      expect(notified, 1);
    });

    test('does nothing when already off', () {
      var notified = 0;
      session.addListener(() => notified++);

      session.logout();

      expect(notified, 0);
    });

    test('means the PIN is needed again', () async {
      await session.setUpPin('4815');
      session.logout();

      expect(session.isAdmin, isFalse);
      expect((await session.login('4815')).succeeded, isTrue);
    });

    test('keeps the stored PIN', () async {
      await session.setUpPin('4815');
      session.logout();

      expect(await session.hasPinSet(), isTrue);
    });
  });

  group('a refresh', () {
    test('always starts logged out, but remembers the PIN', () async {
      await session.setUpPin('4815');
      expect(session.isAdmin, isTrue);

      final refreshed = newSession();
      addTearDown(refreshed.dispose);

      expect(refreshed.isAdmin, isFalse);
      expect(await refreshed.hasPinSet(), isTrue);
      expect((await refreshed.login('4815')).succeeded, isTrue);
    });
  });

  group('changing the PIN', () {
    test('needs Admin Mode', () async {
      await withPin();

      await expectLater(
        session.changePin(currentPin: '4815', newPin: '2468'),
        throwsA(isA<AdminModeRequiredException>()),
      );
    });

    test('with the right current PIN replaces it', () async {
      await session.setUpPin('4815');

      final result = await session.changePin(
        currentPin: '4815',
        newPin: '2468',
      );

      expect(result.succeeded, isTrue);
      expect(store.writes, 2);
      session.logout();
      expect((await session.login('4815')).succeeded, isFalse);
      expect((await session.login('2468')).succeeded, isTrue);
    });

    test('with a wrong current PIN changes nothing', () async {
      await session.setUpPin('4815');
      final before = store.record;

      final result = await session.changePin(
        currentPin: '0000',
        newPin: '2468',
      );

      expect(result.outcome, LoginOutcome.incorrect);
      expect(store.record, same(before));
      expect(store.writes, 1);
    });

    test('rejects a new PIN that breaks the rules', () async {
      await session.setUpPin('4815');

      await expectLater(
        session.changePin(currentPin: '4815', newPin: '12'),
        throwsFormatException,
      );
      expect(store.writes, 1);
    });

    test('stays in Admin Mode', () async {
      await session.setUpPin('4815');

      await session.changePin(currentPin: '4815', newPin: '2468');

      expect(session.isAdmin, isTrue);
    });

    test('shares the wrong-PIN limit with logging in', () async {
      await session.setUpPin('4815');
      for (var i = 0; i < 5; i++) {
        await session.changePin(currentPin: '0000', newPin: '2468');
      }

      final result = await session.changePin(
        currentPin: '4815',
        newPin: '2468',
      );

      expect(result.outcome, LoginOutcome.lockedOut);
      expect(store.writes, 1);
    });

    test('stores a new salt each time', () async {
      await session.setUpPin('4815');
      final firstSalt = store.record!.salt;

      await session.changePin(currentPin: '4815', newPin: '4815');

      expect(store.record!.salt, isNot(firstSalt));
    });
  });
}
