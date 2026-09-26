import 'package:idb_shim/idb_shim.dart';

import '../../domain/entities/graduation_registration.dart';
import '../local/app_database.dart';

/// Reads and writes registrations in IndexedDB.
///
/// This layer does no validation and no duplicate pre-checks. It only enforces
/// the database's own unique indexes, which surface as [DatabaseError].
class GraduationRegistrationLocalDataSource {
  GraduationRegistrationLocalDataSource(this._appDatabase);

  final AppDatabase _appDatabase;

  static const _store = AppDatabase.registrationsStore;

  Future<List<GraduationRegistration>> getAll() async {
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadOnly);
    final records = await txn.objectStore(_store).getAll();
    await txn.completed;
    return records.map(_fromRecord).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<GraduationRegistration?> getById(String id) async {
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadOnly);
    final record = await txn.objectStore(_store).getObject(id);
    await txn.completed;
    return record == null ? null : _fromRecord(record);
  }

  /// The id of the registration using [rollNo], or `null` if none does.
  Future<String?> findIdByRollNo(String rollNo) =>
      _findIdByKey(AppDatabase.rollNoKeyIndex, rollNo);

  /// The id of the registration using [nrc], or `null` if none does.
  Future<String?> findIdByNrc(String nrc) =>
      _findIdByKey(AppDatabase.nrcKeyIndex, nrc);

  /// Adds [registration]. Throws [DatabaseError] if its id, Roll No. or NRC is
  /// already stored.
  Future<void> insert(GraduationRegistration registration) async {
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadWrite);
    final store = txn.objectStore(_store);
    await store.add(_toRecord(registration));
    await txn.completed;
  }

  /// Adds every registration in [registrations] in **one transaction**, so
  /// either all of them are stored or none are.
  ///
  /// Throws [DatabaseError] if any id, Roll No. or NRC is already stored, or
  /// repeats within [registrations]. The transaction is then aborted and
  /// nothing from this call remains.
  Future<void> insertAll(List<GraduationRegistration> registrations) async {
    if (registrations.isEmpty) return;
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadWrite);
    // A failed transaction reports its error to whoever awaits it. Mark it
    // handled here, so an error that is thrown before it is awaited is not
    // also reported as uncaught.
    final completed = txn.completed..ignore();
    final store = txn.objectStore(_store);
    try {
      for (final registration in registrations) {
        await store.add(_toRecord(registration));
      }
      await completed;
    } catch (_) {
      try {
        txn.abort();
      } catch (_) {
        // Already aborted by the database itself, which is what we want.
      }
      rethrow;
    }
  }

  /// Replaces the stored registration with the same id. Throws
  /// [DatabaseError] if its Roll No. or NRC belongs to another registration.
  Future<void> update(GraduationRegistration registration) async {
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadWrite);
    final store = txn.objectStore(_store);
    await store.put(_toRecord(registration));
    await txn.completed;
  }

  /// Deletes the registration with [id]. Returns whether it existed.
  Future<bool> delete(String id) async {
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadWrite);
    final store = txn.objectStore(_store);
    final existed = await store.getKey(id) != null;
    if (existed) await store.delete(id);
    await txn.completed;
    return existed;
  }

  Future<String?> _findIdByKey(String indexName, String value) async {
    final key = normalizeLookupKey(value);
    if (key.isEmpty) return null;
    final db = await _appDatabase.database;
    final txn = db.transaction(_store, idbModeReadOnly);
    final id = await txn.objectStore(_store).index(indexName).getKey(key);
    await txn.completed;
    return id as String?;
  }

  /// The stored form: the entity plus the normalised keys the unique indexes
  /// are built on.
  Map<String, Object?> _toRecord(GraduationRegistration registration) => {
    ...registration.toMap(),
    'rollNoKey': normalizeLookupKey(registration.rollNo),
    'nrcKey': normalizeLookupKey(registration.nrc),
  };

  GraduationRegistration _fromRecord(Object record) =>
      GraduationRegistration.fromMap(Map<String, Object?>.from(record as Map));
}
