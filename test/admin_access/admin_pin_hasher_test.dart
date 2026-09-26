import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';

/// Real hashing is slow; tests do not need the production cost.
AdminPinHasher fastHasher({Random? random}) =>
    AdminPinHasher(iterations: 1000, random: random);

List<int> hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

void main() {
  group('AdminPinRules', () {
    test('accepts 4 to 12 digits', () {
      for (final pin in ['1234', '000000', '123456789012', '9' * 8]) {
        expect(AdminPinRules.validate(pin), isNull, reason: pin);
      }
    });

    test('rejects an empty PIN', () {
      expect(AdminPinRules.validate(''), 'Enter a PIN.');
    });

    test('rejects a PIN that is too short or too long', () {
      expect(AdminPinRules.validate('123'), contains('at least 4'));
      expect(AdminPinRules.validate('1234567890123'), contains('at most 12'));
    });

    test('rejects anything that is not a plain digit', () {
      for (final pin in ['12a4', '12 34', '12.34', '-1234', '12_34', '١٢٣٤']) {
        expect(
          AdminPinRules.validate(pin),
          'The PIN can only contain digits.',
          reason: pin,
        );
      }
    });
  });

  group('hashing', () {
    test('produces a random salt and a 256-bit hash', () async {
      final record = await fastHasher().hash('4815');

      expect(record.salt, hasLength(16));
      expect(record.hash, hasLength(32));
      expect(record.iterations, 1000);
    });

    test('gives the same PIN a different salt and hash each time', () async {
      final hasher = fastHasher();

      final a = await hasher.hash('4815');
      final b = await hasher.hash('4815');

      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
    });

    test('is repeatable for the same salt', () async {
      final a = await fastHasher(random: Random(7)).hash('4815');
      final b = await fastHasher(random: Random(7)).hash('4815');

      expect(a.salt, b.salt);
      expect(a.hash, b.hash);
    });

    test('a different PIN gives a different hash', () async {
      final a = await fastHasher(random: Random(7)).hash('4815');
      final b = await fastHasher(random: Random(7)).hash('4816');

      expect(a.hash, isNot(b.hash));
    });

    test('never keeps the PIN in the record', () async {
      final record = await fastHasher().hash('48151623');

      final stored = jsonEncode(record.toMap());

      expect(stored.contains('48151623'), isFalse);
      expect(stored.contains('4815'), isFalse);
      expect(record.toMap().keys, ['version', 'salt', 'hash', 'iterations']);
    });
  });

  group('checking a PIN', () {
    test('accepts the right PIN', () async {
      final hasher = fastHasher();
      final record = await hasher.hash('4815');

      expect(await hasher.verify('4815', record), isTrue);
    });

    test('rejects a wrong PIN, however close', () async {
      final hasher = fastHasher();
      final record = await hasher.hash('4815');

      for (final guess in ['4816', '481', '48150', '', ' 4815', '4815 ']) {
        expect(await hasher.verify(guess, record), isFalse, reason: '"$guess"');
      }
    });

    test('uses the cost the record was made with', () async {
      final record = await fastHasher().hash('4815');

      // A checker with a different default cost still verifies old records.
      final other = AdminPinHasher(iterations: 5000);
      expect(await other.verify('4815', record), isTrue);
      expect(await other.verify('9999', record), isFalse);
    });

    test('rejects a record with a different salt', () async {
      final hasher = fastHasher();
      final a = await hasher.hash('4815');
      final b = await hasher.hash('4815');
      final mixed = AdminPinRecord(
        salt: b.salt,
        hash: a.hash,
        iterations: a.iterations,
      );

      expect(await hasher.verify('4815', mixed), isFalse);
    });
  });

  group('the algorithm is standard PBKDF2-HMAC-SHA256', () {
    // Published test vectors (RFC 7914, and the widely used SHA-256 vectors
    // for PBKDF2), so the result is proven against a reference, not only
    // against this code.
    final hasher = fastHasher();

    Future<bool> matches(
      String password,
      String salt,
      int iterations,
      String key,
    ) {
      return hasher.verify(
        password,
        AdminPinRecord(
          salt: utf8.encode(salt),
          hash: hex(key),
          iterations: iterations,
        ),
      );
    }

    test('1 iteration', () async {
      expect(
        await matches(
          'password',
          'salt',
          1,
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        ),
        isTrue,
      );
    });

    test('2 iterations', () async {
      expect(
        await matches(
          'password',
          'salt',
          2,
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
        ),
        isTrue,
      );
    });

    test('4096 iterations', () async {
      expect(
        await matches(
          'password',
          'salt',
          4096,
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
        ),
        isTrue,
      );
    });

    test('a wrong vector is rejected', () async {
      expect(
        await matches(
          'password',
          'salt',
          1,
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17c',
        ),
        isFalse,
      );
    });
  });

  group('AdminPinRecord storage form', () {
    test('round-trips', () async {
      final record = await fastHasher().hash('4815');

      final copy = AdminPinRecord.fromMap(record.toMap());

      expect(copy.salt, record.salt);
      expect(copy.hash, record.hash);
      expect(copy.iterations, record.iterations);
    });

    test('rejects anything that is not a record', () async {
      final good = (await fastHasher().hash('4815')).toMap();

      for (final bad in [
        {...good, 'version': 2},
        {...good, 'version': null},
        {...good, 'salt': 5},
        {...good, 'hash': null},
        {...good, 'iterations': '1000'},
        {...good, 'iterations': 0},
        {...good, 'iterations': -5},
        {...good, 'iterations': 1000000000},
        {...good, 'salt': '!!! not base64 !!!'},
        <String, Object?>{},
      ]) {
        expect(
          () => AdminPinRecord.fromMap(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });
}
