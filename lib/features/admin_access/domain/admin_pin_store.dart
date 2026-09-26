import 'admin_pin_hasher.dart';

/// Keeps the Admin PIN record between visits.
abstract interface class AdminPinStore {
  /// The stored record, or `null` if no PIN has been set up.
  Future<AdminPinRecord?> read();

  /// Stores [record], replacing any earlier one.
  Future<void> write(AdminPinRecord record);
}
