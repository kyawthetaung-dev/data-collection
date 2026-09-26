import 'package:flutter/foundation.dart';

import 'admin_pin_hasher.dart';
import 'admin_pin_store.dart';

/// How a PIN check ended.
enum LoginOutcome {
  /// The PIN was right.
  success,

  /// The PIN was wrong.
  incorrect,

  /// Too many wrong PINs in a row: no attempts are accepted for a while.
  lockedOut,

  /// No Admin PIN has been set up on this browser yet.
  noPinSet,
}

/// [AdminSession.setUpPin] was called while a PIN is already set. Setting up
/// never replaces a PIN.
class AdminPinAlreadySetException implements Exception {
  const AdminPinAlreadySetException();

  @override
  String toString() => 'An Admin PIN is already set.';
}

/// An action that needs Admin Mode was tried while it is off.
class AdminModeRequiredException implements Exception {
  const AdminModeRequiredException();

  @override
  String toString() => 'Admin Mode is off.';
}

class LoginResult {
  const LoginResult(this.outcome, {this.attemptsLeft, this.retryAfter});

  final LoginOutcome outcome;

  /// After a wrong PIN: how many more may be tried before a wait.
  final int? attemptsLeft;

  /// When locked out: how long to wait.
  final Duration? retryAfter;

  bool get succeeded => outcome == LoginOutcome.success;
}

/// Whether Admin Mode is on, and the ways to turn it on and off.
///
/// **This is a convenience, not security.** It keeps casual users out of the
/// management screens on a shared device. Everything lives in the user's own
/// browser: anyone able to open the browser's developer tools can still read
/// the stored registrations and can remove the PIN. Nothing here is checked by
/// a server, because there is none.
///
/// Admin Mode is held in memory only. A page refresh, a closed tab or a
/// restart always ends it.
class AdminSession extends ChangeNotifier {
  AdminSession({
    required this._store,
    AdminPinHasher? hasher,
    DateTime Function()? now,
    this.maxFailedAttempts = 5,
    this.lockDuration = const Duration(seconds: 30),
  }) : _hasher = hasher ?? AdminPinHasher(),
       _now = now ?? DateTime.now;

  final AdminPinStore _store;
  final AdminPinHasher _hasher;
  final DateTime Function() _now;

  /// How many wrong PINs in a row are allowed before a wait.
  final int maxFailedAttempts;

  /// How long the wait is. It is held in memory, so a refresh ends it.
  final Duration lockDuration;

  bool _isAdmin = false;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  /// Whether Admin Mode is on.
  bool get isAdmin => _isAdmin;

  /// How long until PIN attempts are accepted again, or `null` if they are.
  Duration? get lockRemaining {
    final until = _lockedUntil;
    if (until == null) return null;
    final remaining = until.difference(_now());
    return remaining > Duration.zero ? remaining : null;
  }

  /// Whether an Admin PIN has been set up on this browser.
  ///
  /// Read from storage every time, not remembered, so it is never out of date.
  Future<bool> hasPinSet() async => await _store.read() != null;

  /// Sets the first Admin PIN and turns Admin Mode on.
  ///
  /// Throws a [FormatException] if [pin] breaks [AdminPinRules], and an
  /// [AdminPinAlreadySetException] if a PIN is already set: this never replaces
  /// one.
  Future<void> setUpPin(String pin) async {
    final problem = AdminPinRules.validate(pin);
    if (problem != null) throw FormatException(problem);
    if (await _store.read() != null) {
      throw const AdminPinAlreadySetException();
    }
    await _store.write(await _hasher.hash(pin));
    _turnOn();
  }

  /// Checks [pin] and, if it is right, turns Admin Mode on.
  Future<LoginResult> login(String pin) async {
    final record = await _store.read();
    if (record == null) return const LoginResult(LoginOutcome.noPinSet);
    final result = await _check(pin, record);
    if (result.succeeded) _turnOn();
    return result;
  }

  /// Replaces the Admin PIN. Only possible in Admin Mode, and only with the
  /// current PIN. Wrong tries count towards the same limit as a login.
  ///
  /// Throws a [FormatException] if [newPin] breaks [AdminPinRules], and an
  /// [AdminModeRequiredException] outside Admin Mode.
  Future<LoginResult> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    if (!_isAdmin) throw const AdminModeRequiredException();
    final problem = AdminPinRules.validate(newPin);
    if (problem != null) throw FormatException(problem);
    final record = await _store.read();
    if (record == null) return const LoginResult(LoginOutcome.noPinSet);
    final result = await _check(currentPin, record);
    if (result.succeeded) await _store.write(await _hasher.hash(newPin));
    return result;
  }

  /// Turns Admin Mode off. Protected screens close and protected actions stop
  /// working at once.
  void logout() {
    if (!_isAdmin) return;
    _isAdmin = false;
    notifyListeners();
  }

  Future<LoginResult> _check(String pin, AdminPinRecord record) async {
    final wait = lockRemaining;
    if (wait != null) {
      return LoginResult(LoginOutcome.lockedOut, retryAfter: wait);
    }
    if (await _hasher.verify(pin, record)) {
      _failedAttempts = 0;
      _lockedUntil = null;
      return const LoginResult(LoginOutcome.success);
    }
    _failedAttempts++;
    if (_failedAttempts >= maxFailedAttempts) {
      _failedAttempts = 0;
      _lockedUntil = _now().add(lockDuration);
      return LoginResult(LoginOutcome.lockedOut, retryAfter: lockDuration);
    }
    return LoginResult(
      LoginOutcome.incorrect,
      attemptsLeft: maxFailedAttempts - _failedAttempts,
    );
  }

  void _turnOn() {
    _failedAttempts = 0;
    _lockedUntil = null;
    if (_isAdmin) return;
    _isAdmin = true;
    notifyListeners();
  }
}
