import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:ucss_data_collection/features/admin_access/data/indexed_db_admin_pin_store.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/datasources/graduation_registration_local_datasource.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/local/app_database.dart';

import '../graduation_registration/support/sample_registrations.dart';

void main() {
  late IdbFactory factory;
  late IndexedDbAdminPinStore store;

  setUp(() {
    factory = newIdbFactoryMemory();
    store = IndexedDbAdminPinStore(factory: factory);
  });

  tearDown(() => store.close());

  Future<AdminPinRecord> record([String pin = '4815']) =>
      AdminPinHasher(iterations: 1000).hash(pin);

  /// The raw stored value, read through a second connection.
  Future<Object?> rawValue() async {
    final db = await factory.open(IndexedDbAdminPinStore.defaultName);
    try {
      final txn = db.transaction('settings', idbModeReadOnly);
      final value = await txn.objectStore('settings').getObject('adminPin');
      await txn.completed;
      return value;
    } finally {
      db.close();
    }
  }

  group('the store', () {
    test('has nothing before a PIN is set', () async {
      expect(await store.read(), isNull);
    });

    test('keeps a record and reads it back', () async {
      final saved = await record();

      await store.write(saved);
      final loaded = await store.read();

      expect(loaded!.salt, saved.salt);
      expect(loaded.hash, saved.hash);
      expect(loaded.iterations, saved.iterations);
    });

    test('replaces an earlier record', () async {
      await store.write(await record('4815'));
      final second = await record('2468');

      await store.write(second);

      expect((await store.read())!.hash, second.hash);
    });

    test('survives closing and reopening', () async {
      final saved = await record();
      await store.write(saved);
      await store.close();

      final reopened = IndexedDbAdminPinStore(factory: factory);
      addTearDown(reopened.close);

      expect((await reopened.read())!.hash, saved.hash);
    });

    test('is checked by a session after reopening (a refresh)', () async {
      final session = AdminSession(
        store: store,
        hasher: AdminPinHasher(iterations: 1000),
      );
      await session.setUpPin('4815');
      session.dispose();
      await store.close();

      final refreshed = AdminSession(
        store: IndexedDbAdminPinStore(factory: factory),
        hasher: AdminPinHasher(iterations: 1000),
      );
      addTearDown(refreshed.dispose);

      expect(refreshed.isAdmin, isFalse);
      expect((await refreshed.login('4815')).succeeded, isTrue);
    });

    test('treats a damaged record as no PIN', () async {
      await store.write(await record());
      final db = await factory.open(IndexedDbAdminPinStore.defaultName);
      final txn = db.transaction('settings', idbModeReadWrite);
      await txn.objectStore('settings').put({'salt': 'x'}, 'adminPin');
      await txn.completed;
      // Not closed: the in-memory database shares one connection, so closing
      // this one would close the store's too.

      expect(await store.read(), isNull);
    });
  });

  group('what is stored', () {
    test('is a salt and a hash, never the PIN', () async {
      final session = AdminSession(
        store: store,
        hasher: AdminPinHasher(iterations: 1000),
      );
      addTearDown(session.dispose);

      await session.setUpPin('48151623');

      final raw = await rawValue() as Map;
      expect(
        raw.keys,
        unorderedEquals(['version', 'salt', 'hash', 'iterations']),
      );
      expect(raw.toString().contains('48151623'), isFalse);
      expect(raw.toString().contains('4815'), isFalse);
    });

    test('has its own database, named differently from the registrations', () {
      expect(IndexedDbAdminPinStore.defaultName, 'ucss_admin_settings');
      expect(
        IndexedDbAdminPinStore.defaultName,
        isNot(AppDatabase.defaultDatabaseName),
      );
    });

    test('has one store, with nothing else in it', () async {
      await store.write(await record());

      final db = await factory.open(IndexedDbAdminPinStore.defaultName);
      addTearDown(db.close);
      expect(db.objectStoreNames, ['settings']);
    });
  });

  group('kept apart from the registrations', () {
    test('the registration database has no PIN store', () async {
      final appDb = AppDatabase(factory: factory);
      addTearDown(appDb.close);
      await GraduationRegistrationLocalDataSource(
        appDb,
      ).insert(sampleRegistration());
      await store.write(await record());

      final db = await appDb.database;
      expect(db.objectStoreNames, [AppDatabase.registrationsStore]);
      expect(db.name, AppDatabase.defaultDatabaseName);
    });

    test('setting a PIN does not touch the registrations', () async {
      final appDb = AppDatabase(factory: factory);
      addTearDown(appDb.close);
      final data = GraduationRegistrationLocalDataSource(appDb);
      await data.insert(sampleRegistration());
      final before = await data.getAll();

      await store.write(await record());
      await store.write(await record('2468'));

      expect(await data.getAll(), before);
    });

    test('registrations being changed does not touch the PIN', () async {
      final saved = await record();
      await store.write(saved);
      final appDb = AppDatabase(factory: factory);
      addTearDown(appDb.close);
      final data = GraduationRegistrationLocalDataSource(appDb);

      await data.insertAll(sampleRegistrations());
      await data.delete('r1');

      expect((await store.read())!.hash, saved.hash);
    });
  });
}
