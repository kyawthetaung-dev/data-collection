import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb_shim.dart';

import '../domain/admin_pin_hasher.dart';
import '../domain/admin_pin_store.dart';

/// Stores the record in the browser's IndexedDB, in a database of its own.
///
/// It is deliberately **not** the registrations database: that one is never
/// opened here, so the Admin PIN can never end up in a registration export or
/// backup, and the registration schema is untouched. What is stored is a salt
/// and a hash, never the PIN.
///
/// Pass an in-memory `IdbFactory` in tests. In the app the default is the
/// browser's IndexedDB.
class IndexedDbAdminPinStore implements AdminPinStore {
  IndexedDbAdminPinStore({this._factory, this.databaseName = defaultName});

  static const defaultName = 'ucss_admin_settings';

  static const _schemaVersion = 1;
  static const _storeName = 'settings';
  static const _recordKey = 'adminPin';

  final IdbFactory? _factory;
  final String databaseName;
  Future<Database>? _database;

  Future<Database> get _db => _database ??= _open();

  Future<Database> _open() async {
    try {
      return await (_factory ?? idbFactoryWeb).open(
        databaseName,
        version: _schemaVersion,
        onUpgradeNeeded: (event) =>
            event.database.createObjectStore(_storeName),
      );
    } catch (_) {
      // Do not cache a failed open, so the next call can retry.
      _database = null;
      rethrow;
    }
  }

  @override
  Future<AdminPinRecord?> read() async {
    final db = await _db;
    final txn = db.transaction(_storeName, idbModeReadOnly);
    final value = await txn.objectStore(_storeName).getObject(_recordKey);
    await txn.completed;
    if (value == null) return null;
    try {
      return AdminPinRecord.fromMap(Map<String, Object?>.from(value as Map));
    } on FormatException catch (error) {
      // A damaged record cannot be checked against, so treat the PIN as not
      // set rather than locking everyone out for good.
      debugPrint('Ignoring a damaged Admin PIN record: $error');
      return null;
    }
  }

  @override
  Future<void> write(AdminPinRecord record) async {
    final db = await _db;
    final txn = db.transaction(_storeName, idbModeReadWrite);
    await txn.objectStore(_storeName).put(record.toMap(), _recordKey);
    await txn.completed;
  }

  /// Closes the connection. The next use opens a new one.
  Future<void> close() async {
    final opening = _database;
    _database = null;
    if (opening != null) (await opening).close();
  }
}
