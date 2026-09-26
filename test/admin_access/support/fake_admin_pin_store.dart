import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_store.dart';

/// An in-memory PIN store for tests. Set [readError] or [writeError] to make
/// that call fail.
class FakeAdminPinStore implements AdminPinStore {
  AdminPinRecord? record;
  Object? readError;
  Object? writeError;
  var reads = 0;
  var writes = 0;

  @override
  Future<AdminPinRecord?> read() async {
    reads++;
    if (readError != null) throw readError!;
    return record;
  }

  @override
  Future<void> write(AdminPinRecord record) async {
    writes++;
    if (writeError != null) throw writeError!;
    this.record = record;
  }
}
