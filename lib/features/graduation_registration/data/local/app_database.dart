import 'package:idb_shim/idb_shim.dart';

/// Owns the browser's IndexedDB connection and its schema.
///
/// Pass an in-memory [IdbFactory] (`newIdbFactoryMemory()`) in tests. In the
/// app the default is the browser's IndexedDB.
class AppDatabase {
  AppDatabase({this._factory, this.databaseName = defaultDatabaseName});

  static const defaultDatabaseName = 'ucss_graduation_registration';
  static const schemaVersion = 1;

  static const registrationsStore = 'registrations';

  /// Unique index over the normalised Roll No. (see `normalizeLookupKey`).
  static const rollNoKeyIndex = 'rollNoKey';

  /// Unique index over the normalised NRC (see `normalizeLookupKey`).
  static const nrcKeyIndex = 'nrcKey';

  final String databaseName;
  final IdbFactory? _factory;
  Future<Database>? _database;

  /// The open database. Opened on first use and shared afterwards.
  Future<Database> get database => _database ??= _open();

  Future<Database> _open() async {
    try {
      return await (_factory ?? idbFactoryWeb).open(
        databaseName,
        version: schemaVersion,
        onUpgradeNeeded: _onUpgradeNeeded,
      );
    } catch (_) {
      // Do not cache a failed open, so the next call can retry.
      _database = null;
      rethrow;
    }
  }

  void _onUpgradeNeeded(VersionChangeEvent event) {
    final db = event.database;
    if (event.oldVersion < 1) {
      final store = db.createObjectStore(registrationsStore, keyPath: 'id');
      store.createIndex(rollNoKeyIndex, 'rollNoKey', unique: true);
      store.createIndex(nrcKeyIndex, 'nrcKey', unique: true);
    }
  }

  /// Closes the connection. The next use of [database] opens a new one.
  Future<void> close() async {
    final opening = _database;
    _database = null;
    if (opening != null) (await opening).close();
  }
}
