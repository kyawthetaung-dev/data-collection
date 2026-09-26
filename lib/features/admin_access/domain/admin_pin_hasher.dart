import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// What a valid Admin PIN looks like.
abstract final class AdminPinRules {
  static const minLength = 4;
  static const maxLength = 12;

  static final _digits = RegExp(r'^[0-9]+$');

  /// Why [pin] is not acceptable, or `null` if it is.
  static String? validate(String pin) {
    if (pin.isEmpty) return 'Enter a PIN.';
    if (!_digits.hasMatch(pin)) return 'The PIN can only contain digits.';
    if (pin.length < minLength) {
      return 'The PIN must be at least $minLength digits.';
    }
    if (pin.length > maxLength) {
      return 'The PIN can be at most $maxLength digits.';
    }
    return null;
  }
}

/// A PIN as it is stored: never the PIN itself, only what is needed to check a
/// later guess against it.
class AdminPinRecord {
  const AdminPinRecord({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  /// Reads a record written by [toMap]. Throws a [FormatException] if it is
  /// not one, for example if it was edited by hand.
  factory AdminPinRecord.fromMap(Map<String, Object?> map) {
    final salt = map['salt'];
    final hash = map['hash'];
    final iterations = map['iterations'];
    if (map['version'] != _version ||
        salt is! String ||
        hash is! String ||
        iterations is! int ||
        iterations < 1 ||
        iterations > _maxIterations) {
      throw const FormatException('Not an Admin PIN record.');
    }
    return AdminPinRecord(
      salt: base64Decode(salt),
      hash: base64Decode(hash),
      iterations: iterations,
    );
  }

  static const _version = 1;

  /// A guard against a damaged record making a login attempt run for minutes.
  static const _maxIterations = 10000000;

  /// The random value mixed into the PIN, so equal PINs hash differently.
  final List<int> salt;

  /// The derived key.
  final List<int> hash;

  /// How many rounds of hashing produced [hash]. Stored, so the number can be
  /// raised later while old records still verify.
  final int iterations;

  Map<String, Object?> toMap() => {
    'version': _version,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'iterations': iterations,
  };
}

/// Turns a PIN into an [AdminPinRecord] and checks guesses against one.
///
/// It uses PBKDF2 with HMAC-SHA-256 and a random salt. In a browser this runs
/// on the Web Crypto API, which is fast; where that is not available (a page
/// served over plain http) a slower built-in version runs instead, so the
/// default cost is kept modest.
///
/// This slows down guessing; it does not make a short PIN safe from someone
/// who has a copy of the stored record.
class AdminPinHasher {
  /// [iterations] is for tests, which do not need the real cost.
  AdminPinHasher({this.iterations = defaultIterations, Random? random})
    : _random = random ?? Random.secure();

  static const defaultIterations = 100000;

  static const _saltLength = 16;
  static const _hashBits = 256;

  final int iterations;
  final Random _random;

  Future<AdminPinRecord> hash(String pin) async {
    final salt = List<int>.generate(_saltLength, (_) => _random.nextInt(256));
    return AdminPinRecord(
      salt: salt,
      hash: await _derive(pin, salt, iterations),
      iterations: iterations,
    );
  }

  /// Whether [pin] is the PIN that [record] was made from.
  Future<bool> verify(String pin, AdminPinRecord record) async {
    final derived = await _derive(pin, record.salt, record.iterations);
    return _sameBytes(derived, record.hash);
  }

  static Future<List<int>> _derive(
    String pin,
    List<int> salt,
    int iterations,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _hashBits,
    );
    final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  /// Compares without stopping at the first difference, so how long it takes
  /// does not reveal how much of a guess was right.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
