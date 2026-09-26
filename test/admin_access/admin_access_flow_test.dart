import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:ucss_data_collection/features/admin_access/data/indexed_db_admin_pin_store.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_mode_button.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/datasources/graduation_registration_local_datasource.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_excel_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_export_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_import_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/local/app_database.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/repositories/graduation_registration_repository_impl.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_form_page.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_list_page.dart';
import 'package:ucss_data_collection/main.dart';

import '../graduation_registration/support/backup_test_data.dart';
import '../graduation_registration/support/fake_file_downloader.dart';
import '../graduation_registration/support/fake_registration_repository.dart';
import '../graduation_registration/support/sample_registrations.dart';
import 'support/admin_test_support.dart';
import 'support/fake_admin_pin_store.dart';

const _desktop = Size(1280, 3000);
const _phone = Size(390, 3000);

/// Every label of something that only an admin may use.
const _adminOnlyLabels = [
  'Registrations',
  'Total registrations',
  'Export Excel',
  'Export JSON Backup',
  'Import Backup',
  'Import a backup',
  'Refresh',
];

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

/// The app as a visitor first sees it. Pass the same [store] and [repository]
/// again to act like the same browser after a page refresh.
Future<AdminSession> pumpApp(
  WidgetTester tester, {
  FakeRegistrationRepository? repository,
  FakeAdminPinStore? store,
  Size size = _desktop,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = await adminSession(tester, signedIn: false, store: store);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    GraduationApp(
      repository: repository ?? FakeRegistrationRepository(),
      adminSession: session,
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> typeInto(WidgetTester tester, String label, String text) =>
    tester.enterText(find.widgetWithText(TextField, label), text);

/// Uses the Admin icon: sets the first PIN on a browser without one.
Future<void> setUpAdmin(WidgetTester tester, [String pin = testPin]) async {
  await tester.tap(find.byTooltip(AdminModeButton.signedOutTooltip));
  await settle(tester);
  await typeInto(tester, 'New PIN', pin);
  await typeInto(tester, 'Confirm PIN', pin);
  await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
  await settle(tester);
}

/// Uses the Admin icon: logs in on a browser that has a PIN.
Future<void> logIn(WidgetTester tester, [String pin = testPin]) async {
  await tester.tap(find.byTooltip(AdminModeButton.signedOutTooltip));
  await settle(tester);
  await typeInto(tester, 'PIN', pin);
  await tester.tap(find.widgetWithText(FilledButton, 'Login'));
  await settle(tester);
}

/// Opens the Admin mode menu and chooses Exit Admin Mode. On a wide screen the
/// control is a labelled button, on a phone an icon.
Future<void> exitAdmin(WidgetTester tester) async {
  final labelled = find.text('Admin mode');
  await tester.tap(
    labelled.evaluate().isNotEmpty
        ? labelled
        : find.byTooltip(AdminModeButton.signedInTooltip),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Exit Admin Mode'));
  await tester.pumpAndSettle();
}

void expectNoAdminControls(WidgetTester tester) {
  for (final label in _adminOnlyLabels) {
    expect(find.text(label), findsNothing, reason: '"$label" text');
    expect(find.byTooltip(label), findsNothing, reason: '"$label" tooltip');
  }
  expect(find.byIcon(Icons.list_alt), findsNothing);
}

Future<void> fillValidForm(WidgetTester tester) async {
  Future<void> put(String label, String text) =>
      tester.enterText(find.widgetWithText(TextFormField, label), text);
  await put('Name *', 'Public Person');
  await put('Father Name *', 'U Father');
  await put('NRC *', '12/LAMANA(N)123456');
  await put('Roll No. *', 'CS-100');
  await put('Major *', 'Computer Science');
  await put('Phone No. *', '09123456789');
  await tester.tap(find.widgetWithText(ChoiceChip, 'Can Attend'));
  await tester.tap(find.widgetWithText(ChoiceChip, 'Japan'));
  await tester.pump();
}

void main() {
  group('a public visitor', () {
    testWidgets('sees the form and only a quiet Admin icon', (tester) async {
      await pumpApp(tester);

      expect(find.text('Registration Form'), findsOneWidget);
      expect(find.text('Submit Registration'), findsOneWidget);
      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsOneWidget);
      expect(find.text('Admin mode'), findsNothing);
      expectNoAdminControls(tester);
    });

    testWidgets('sees the same on a phone', (tester) async {
      await pumpApp(tester, size: _phone);

      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsOneWidget);
      expectNoAdminControls(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('can register without any PIN', (tester) async {
      final repository = FakeRegistrationRepository();
      final session = await pumpApp(tester, repository: repository);

      await fillValidForm(tester);
      await tester.tap(find.text('Submit Registration'));
      await tester.pumpAndSettle();

      expect(repository.items.single.name, 'Public Person');
      expect(find.textContaining('Registration saved'), findsOneWidget);
      expect(session.isAdmin, isFalse);
      expectNoAdminControls(tester);
    });

    testWidgets('cannot reach the list, exports or import', (tester) async {
      await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );

      // Nothing on the page leads to any of them, nor shows any of the data.
      expectNoAdminControls(tester);
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.textContaining('Roll No. CS-001'), findsNothing);
    });
  });

  group('becoming an admin for the first time', () {
    testWidgets('asks for a new PIN, then shows the admin features', (
      tester,
    ) async {
      final repository = FakeRegistrationRepository(sampleRegistrations());
      final store = FakeAdminPinStore();
      final session = await pumpApp(
        tester,
        repository: repository,
        store: store,
      );

      await tester.tap(find.byTooltip(AdminModeButton.signedOutTooltip));
      await settle(tester);
      expect(find.text('Set an Admin PIN'), findsOneWidget);
      await typeInto(tester, 'New PIN', '246810');
      await typeInto(tester, 'Confirm PIN', '246810');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(session.isAdmin, isTrue);
      expect(find.text('Admin mode'), findsOneWidget);
      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsNothing);
      expect(find.text('Registrations'), findsOneWidget);
      // Only a salted hash was stored.
      expect(store.record!.toMap().toString().contains('246810'), isFalse);
    });

    testWidgets('opens the list with everything an admin needs', (
      tester,
    ) async {
      await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );
      await setUpAdmin(tester);

      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsOneWidget);
      expect(find.text('Total registrations: 4'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets); // the search
      expect(find.text('Export Excel'), findsOneWidget);
      expect(find.text('Export JSON Backup'), findsOneWidget);
      expect(find.text('Import Backup'), findsOneWidget);
      expect(find.byTooltip('View details'), findsWidgets);
      expect(find.byTooltip('Edit'), findsWidgets);
      expect(find.byTooltip('Delete'), findsWidgets);
    });

    testWidgets('shows a clear indicator on every admin page', (tester) async {
      await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );
      await setUpAdmin(tester);

      expect(find.byType(AdminModeBar), findsOneWidget);
      expect(find.text('Admin mode'), findsOneWidget);

      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminModeBar), findsOneWidget);
      expect(find.text('Admin mode'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      expect(find.byType(RegistrationFormPage), findsOneWidget);
      expect(find.text('Edit Registration'), findsOneWidget);
      expect(find.text('Admin mode'), findsOneWidget);
    });
  });

  group('coming back later', () {
    testWidgets('a refresh always starts logged out', (tester) async {
      final store = FakeAdminPinStore();
      final repository = FakeRegistrationRepository(sampleRegistrations());
      await pumpApp(tester, repository: repository, store: store);
      await setUpAdmin(tester);
      expect(find.text('Admin mode'), findsOneWidget);

      final refreshed = await pumpApp(
        tester,
        repository: repository,
        store: store,
      );

      expect(refreshed.isAdmin, isFalse);
      expect(find.text('Admin mode'), findsNothing);
      expectNoAdminControls(tester);
    });

    testWidgets('and asks for the PIN, not to set a new one', (tester) async {
      final store = FakeAdminPinStore();
      final repository = FakeRegistrationRepository(sampleRegistrations());
      await pumpApp(tester, repository: repository, store: store);
      await setUpAdmin(tester);
      await pumpApp(tester, repository: repository, store: store);

      await tester.tap(find.byTooltip(AdminModeButton.signedOutTooltip));
      await settle(tester);

      expect(find.text('Admin PIN'), findsOneWidget);
      expect(find.text('Set an Admin PIN'), findsNothing);
    });

    testWidgets('the right PIN brings the admin features back', (tester) async {
      final store = FakeAdminPinStore();
      final repository = FakeRegistrationRepository(sampleRegistrations());
      await pumpApp(tester, repository: repository, store: store);
      await setUpAdmin(tester);
      await pumpApp(tester, repository: repository, store: store);

      await logIn(tester);

      expect(find.text('Admin mode'), findsOneWidget);
      expect(find.text('Registrations'), findsOneWidget);
    });

    testWidgets('a wrong PIN keeps every admin feature hidden', (tester) async {
      final store = FakeAdminPinStore();
      final repository = FakeRegistrationRepository(sampleRegistrations());
      await pumpApp(tester, repository: repository, store: store);
      await setUpAdmin(tester);
      final session = await pumpApp(
        tester,
        repository: repository,
        store: store,
      );

      await logIn(tester, '0000');

      expect(find.text('Incorrect PIN.'), findsOneWidget);
      expect(session.isAdmin, isFalse);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);
      expectNoAdminControls(tester);
    });
  });

  group('leaving Admin Mode', () {
    testWidgets('from the form hides the admin features again', (tester) async {
      final session = await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );
      await setUpAdmin(tester);

      await exitAdmin(tester);

      expect(session.isAdmin, isFalse);
      expect(find.text('Admin mode is off.'), findsOneWidget);
      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsOneWidget);
      expectNoAdminControls(tester);
    });

    testWidgets('from the list returns to the public form', (tester) async {
      final session = await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );
      await setUpAdmin(tester);
      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();
      expect(find.text('Aung Aung'), findsOneWidget);

      await exitAdmin(tester);

      expect(session.isAdmin, isFalse);
      expect(find.byType(RegistrationListPage), findsNothing);
      expect(find.text('Registration Form'), findsOneWidget);
      // The registrations are no longer on screen.
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Total registrations: 4'), findsNothing);
      expectNoAdminControls(tester);
    });

    testWidgets('from the edit page returns to the public form', (
      tester,
    ) async {
      final session = await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );
      await setUpAdmin(tester);
      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Registration'), findsOneWidget);

      await exitAdmin(tester);

      expect(session.isAdmin, isFalse);
      expect(find.text('Edit Registration'), findsNothing);
      expect(find.byType(RegistrationListPage), findsNothing);
      expect(find.text('Registration Form'), findsOneWidget);
      expectNoAdminControls(tester);
    });

    testWidgets('closes an open dialog with the page', (tester) async {
      final session = await pumpApp(
        tester,
        repository: FakeRegistrationRepository(sampleRegistrations()),
      );
      await setUpAdmin(tester);
      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete registration?'), findsOneWidget);

      session.logout();
      await tester.pumpAndSettle();

      expect(find.text('Delete registration?'), findsNothing);
      expect(find.text('Registration Form'), findsOneWidget);
    });

    testWidgets('needs the PIN again to come back', (tester) async {
      final session = await pumpApp(tester);
      await setUpAdmin(tester);
      await exitAdmin(tester);

      await tester.tap(find.byTooltip(AdminModeButton.signedOutTooltip));
      await settle(tester);

      expect(find.text('Admin PIN'), findsOneWidget);
      expect(session.isAdmin, isFalse);
    });

    testWidgets('does not touch the registrations', (tester) async {
      final repository = FakeRegistrationRepository(sampleRegistrations());
      await pumpApp(tester, repository: repository);
      await setUpAdmin(tester);
      await exitAdmin(tester);

      expect(repository.items, sampleRegistrations());
      expect(repository.writeCalls, 0);
    });
  });

  group('the protected pages', () {
    testWidgets('the list shows nothing and reads nothing without Admin Mode', (
      tester,
    ) async {
      tester.view.physicalSize = _desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeRegistrationRepository(sampleRegistrations());
      final session = await adminSession(tester, signedIn: false);

      await tester.pumpWidget(
        adminApp(session, RegistrationListPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin access required'), findsWidgets);
      expect(
        find.text('This page is only available in Admin Mode.'),
        findsOneWidget,
      );
      // Not built at all, so it never even loaded the data.
      expect(repository.getAllCalls, 0);
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Total registrations: 4'), findsNothing);
      expect(find.text('Export Excel'), findsNothing);
    });

    testWidgets('the edit page shows nothing without Admin Mode', (
      tester,
    ) async {
      tester.view.physicalSize = _desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeRegistrationRepository(sampleRegistrations());
      final session = await adminSession(tester, signedIn: false);

      await tester.pumpWidget(
        adminApp(
          session,
          RegistrationFormPage(
            repository: repository,
            initialRegistration: sampleRegistrations().first,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin access required'), findsWidgets);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Aung Aung'), findsNothing);
    });

    testWidgets('offer a way to log in that then shows the page', (
      tester,
    ) async {
      tester.view.physicalSize = _desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeRegistrationRepository(sampleRegistrations());
      final session = await adminSession(tester);
      session.logout();
      await tester.pumpWidget(
        adminApp(session, RegistrationListPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter Admin PIN'));
      await settle(tester);
      await typeInto(tester, 'PIN', testPin);
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await settle(tester);

      expect(find.text('Total registrations: 4'), findsOneWidget);
      expect(repository.getAllCalls, greaterThan(0));
    });

    testWidgets('offer a way back to the public form', (tester) async {
      final session = await pumpApp(tester);
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push<void>(
            MaterialPageRoute(
              builder: (_) => RegistrationListPage(
                repository: FakeRegistrationRepository(sampleRegistrations()),
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Admin access required'), findsWidgets);

      await tester.tap(find.text('Back to registration'));
      await tester.pumpAndSettle();

      expect(find.text('Registration Form'), findsOneWidget);
      expect(session.isAdmin, isFalse);
    });
  });

  group('exports and backups never hold admin data', () {
    late IdbFactory factory;
    late IndexedDbAdminPinStore pinStore;
    late AppDatabase appDatabase;
    late GraduationRegistrationRepositoryImpl repository;
    late AdminSession session;
    late FakeFileDownloader downloader;

    const secretPin = '48151623';

    setUp(() async {
      factory = newIdbFactoryMemory();
      pinStore = IndexedDbAdminPinStore(factory: factory);
      appDatabase = AppDatabase(factory: factory);
      repository = GraduationRegistrationRepositoryImpl(
        GraduationRegistrationLocalDataSource(appDatabase),
      );
      session = AdminSession(
        store: pinStore,
        hasher: AdminPinHasher(iterations: 1000),
      );
      downloader = FakeFileDownloader();
      await session.setUpPin(secretPin);
      await repository.restoreAll(sampleRegistrations());
    });

    tearDown(() async {
      session.dispose();
      await pinStore.close();
      await appDatabase.close();
    });

    /// Every string that could give the PIN away: the PIN, the stored salt
    /// and hash in both forms, and the names of the admin settings.
    Future<List<String>> secrets() async {
      final record = (await pinStore.read())!;
      return [
        secretPin,
        base64Encode(record.salt),
        base64Encode(record.hash),
        record.hash.join(','),
        'adminPin',
        'ucss_admin_settings',
        'iterations',
        'isAdmin',
        'salt',
        'PBKDF2',
      ];
    }

    test('the JSON backup has exactly the registration data', () async {
      await RegistrationBackupService(
        repository: repository,
        downloader: downloader,
        now: () => DateTime(2026, 9, 25, 14, 30),
      ).exportAll();

      final text = utf8.decode(downloader.downloads.single.bytes);
      final json = jsonDecode(text) as Map<String, Object?>;

      // The format is exactly what it was before Admin Mode existed.
      expect(json.keys, [
        'format',
        'version',
        'exportedAt',
        'recordCount',
        'records',
      ]);
      expect(json['format'], RegistrationBackupFormat.formatId);
      expect(json['version'], 1);
      for (final record in json['records']! as List) {
        expect((record as Map).keys, [
          'id',
          'name',
          'fatherName',
          'motherName',
          'phoneNo',
          'nrc',
          'rollNo',
          'major',
          'attendanceStatus',
          'currentCountry',
          'otherCountry',
          'currentCity',
          'email',
          'remark',
          'createdAt',
          'updatedAt',
        ]);
      }
      for (final secret in await secrets()) {
        expect(text.contains(secret), isFalse, reason: 'contains "$secret"');
      }
    });

    test('the Excel report has exactly the registration columns', () async {
      await RegistrationExportService(
        repository: repository,
        downloader: downloader,
      ).exportAll();

      final excel = Excel.decodeBytes(downloader.downloads.single.bytes);
      expect(excel.tables.keys, [RegistrationExcelBuilder.sheetName]);
      final sheet = excel.tables[RegistrationExcelBuilder.sheetName]!;
      expect([
        for (final cell in sheet.rows.first) cell!.value.toString(),
      ], RegistrationExcelBuilder.headers);
      final everyCell = [
        for (final row in sheet.rows)
          for (final cell in row) cell?.value.toString() ?? '',
      ].join('\n');
      for (final secret in await secrets()) {
        expect(
          everyCell.contains(secret),
          isFalse,
          reason: 'contains "$secret"',
        );
      }
    });

    test('logging in and out writes nothing to the settings', () async {
      final before = (await pinStore.read())!.toMap();

      session.logout();
      await session.login(secretPin);
      session.logout();
      await session.login('0000');

      expect((await pinStore.read())!.toMap(), before);
    });

    test('a backup cannot change who is an admin', () async {
      session.logout();
      final before = (await pinStore.read())!.toMap();
      // A file that tries to smuggle admin settings in alongside the records.
      final hostile = jsonBytes({
        ...backupJson([
          recordJson(
            id: 'new-1',
            rollNo: 'NEW-1',
            nrc: 'nrc-new-1',
            overrides: {
              'isAdmin': true,
              'pin': '0000',
              'adminPin': {'salt': 'x', 'hash': 'y', 'iterations': 1},
            },
          ),
        ]),
        'isAdmin': true,
        'adminPin': {'salt': 'x', 'hash': 'y', 'iterations': 1},
        'pin': '0000',
      });
      final importer = RegistrationImportService(repository: repository);

      final preview = await importer.prepare(
        fileName: 'hostile.json',
        bytes: hostile,
      );
      await importer.commit(preview);

      expect(session.isAdmin, isFalse);
      expect((await pinStore.read())!.toMap(), before);
      expect((await session.login('0000')).succeeded, isFalse);
      expect((await session.login(secretPin)).succeeded, isTrue);
      // The record was imported, and only as a registration.
      expect((await repository.getById('new-1'))!.name, 'Aung Aung');
    });

    test('registration data and the PIN live in separate databases', () async {
      final appDb = await appDatabase.database;

      expect(appDb.name, AppDatabase.defaultDatabaseName);
      expect(appDb.objectStoreNames, [AppDatabase.registrationsStore]);
      expect(
        IndexedDbAdminPinStore.defaultName,
        isNot(AppDatabase.defaultDatabaseName),
      );
    });
  });
}
