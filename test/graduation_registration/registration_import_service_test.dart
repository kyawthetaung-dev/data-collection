import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/datasources/graduation_registration_local_datasource.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/backup_import_planner.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_backup_parser.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_import_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/local/app_database.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/repositories/graduation_registration_repository_impl.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';

import 'support/backup_test_data.dart';
import 'support/fake_file_downloader.dart';
import 'support/sample_registrations.dart';

/// Counts every write that reaches the database.
class _CountingDataSource extends GraduationRegistrationLocalDataSource {
  _CountingDataSource(super.appDatabase);

  var writes = 0;

  /// When set, `insertAll` fails with this before writing anything.
  Object? insertAllFailure;

  @override
  Future<void> insert(GraduationRegistration registration) {
    writes++;
    return super.insert(registration);
  }

  @override
  Future<void> insertAll(List<GraduationRegistration> registrations) {
    writes++;
    if (insertAllFailure != null) throw insertAllFailure!;
    return super.insertAll(registrations);
  }

  @override
  Future<void> update(GraduationRegistration registration) {
    writes++;
    return super.update(registration);
  }

  @override
  Future<bool> delete(String id) {
    writes++;
    return super.delete(id);
  }
}

/// One in-memory database with a repository and an import service on it.
class _Site {
  _Site() {
    database = AppDatabase(factory: newIdbFactoryMemory());
    dataSource = _CountingDataSource(database);
    repository = GraduationRegistrationRepositoryImpl(
      dataSource,
      now: () => DateTime.utc(2030, 1, 1, 12, _clock++),
      generateId: () => 'new-${_ids++}',
    );
    service = RegistrationImportService(repository: repository);
  }

  late final AppDatabase database;
  late final _CountingDataSource dataSource;
  late final GraduationRegistrationRepositoryImpl repository;
  late final RegistrationImportService service;
  var _clock = 0;
  var _ids = 0;

  Future<List<GraduationRegistration>> all() => repository.getAll();

  Future<void> close() => database.close();
}

Uint8List backupOf(List<GraduationRegistration> registrations) =>
    const RegistrationBackupBuilder().build(
      registrations,
      exportedAt: DateTime.utc(2026, 9, 25, 8, 30),
    );

void main() {
  late _Site site;

  setUp(() => site = _Site());
  tearDown(() => site.close());

  final backup = sampleRegistrations();

  group('prepare', () {
    test('works out what an import would do', () async {
      await site.repository.restoreAll([backup[1]]);
      final bytes = jsonBytes(
        backupJson([
          for (final r in backup) recordOf(r),
          recordJson(id: 'bad', overrides: {'name': ''}),
        ]),
      );

      final preview = await site.service.prepare(
        fileName: 'my_backup.json',
        bytes: bytes,
      );

      expect(preview.fileName, 'my_backup.json');
      expect(preview.plan.totalRecords, 5);
      expect(preview.plan.newCount, 3);
      expect(preview.plan.duplicateCount, 1);
      expect(preview.plan.invalidCount, 1);
      expect(preview.backup.version, 1);
    });

    test('writes nothing', () async {
      await site.repository.restoreAll([backup[1]]);
      final writesBefore = site.dataSource.writes;
      final before = await site.all();

      await site.service.prepare(fileName: 'b.json', bytes: backupOf(backup));

      expect(site.dataSource.writes, writesBefore);
      expect(await site.all(), before);
    });

    test('refuses a file that is not a backup, and writes nothing', () async {
      await expectLater(
        site.service.prepare(
          fileName: 'notes.json',
          bytes: textBytes('{"hello": "world"}'),
        ),
        throwsA(isA<BackupFileException>()),
      );

      expect(site.dataSource.writes, 0);
      expect(await site.all(), isEmpty);
    });

    test('refuses a backup from a newer version', () async {
      await expectLater(
        site.service.prepare(
          fileName: 'future.json',
          bytes: jsonBytes(backupJson([], version: 99)),
        ),
        throwsA(
          isA<BackupFileException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });
  });

  group('commit', () {
    test('adds the new records exactly as they were', () async {
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );

      final result = await site.service.commit(preview);

      expect(result.imported, 4);
      expect(result.duplicates, 0);
      expect(result.invalid, 0);
      expect(result.total, 4);
      expect(await site.all(), backup);
    });

    test('adds only what is new and leaves the rest alone', () async {
      await site.repository.restoreAll([backup[0]]);
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );

      final result = await site.service.commit(preview);

      expect(result.imported, 3);
      expect(result.duplicates, 1);
      expect(await site.all(), backup);
    });

    test('never deletes a record that is not in the backup', () async {
      final mine = sampleRegistration(
        id: 'mine',
        name: 'Only Here',
        rollNo: 'MINE-1',
        nrc: '12/MINE(N)1',
      );
      await site.repository.restoreAll([mine]);
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );

      await site.service.commit(preview);

      final ids = (await site.all()).map((r) => r.id);
      expect(ids, containsAll(['mine', 'r1', 'r2', 'r3', 'r4']));
      expect(await site.repository.getById('mine'), mine);
    });

    test(
      'never overwrites a record, even one with new data in the backup',
      () async {
        final changedHere = backup[0].copyWith(
          name: 'Changed Here',
          updatedAt: DateTime.utc(2027),
        );
        await site.repository.restoreAll([changedHere]);
        final preview = await site.service.prepare(
          fileName: 'b.json',
          bytes: backupOf(backup),
        );

        final result = await site.service.commit(preview);

        expect(result.duplicates, 1);
        expect(await site.repository.getById('r1'), changedHere);
        expect(
          preview.plan.duplicates.single.reason,
          DuplicateReason.sameIdDifferentData,
        );
      },
    );

    test('skips invalid records and imports the valid ones', () async {
      final bytes = jsonBytes(
        backupJson([
          recordOf(backup[0]),
          recordJson(id: 'bad', overrides: {'email': 'nope'}),
          null,
          recordOf(backup[1]),
        ]),
      );
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: bytes,
      );

      final result = await site.service.commit(preview);

      expect(result.imported, 2);
      expect(result.invalid, 2);
      expect(result.total, 4);
      expect((await site.all()).map((r) => r.id), ['r1', 'r2']);
    });

    test(
      'importing the same file twice adds nothing the second time',
      () async {
        final bytes = backupOf(backup);
        await site.service.commit(
          await site.service.prepare(fileName: 'b.json', bytes: bytes),
        );
        final afterFirst = await site.all();

        final second = await site.service.commit(
          await site.service.prepare(fileName: 'b.json', bytes: bytes),
        );

        expect(second.imported, 0);
        expect(second.duplicates, 4);
        expect(await site.all(), afterFirst);
      },
    );

    test('writes nothing when there is nothing new', () async {
      await site.repository.restoreAll(backup);
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );
      final writesBefore = site.dataSource.writes;

      final result = await site.service.commit(preview);

      expect(result.imported, 0);
      expect(site.dataSource.writes, writesBefore);
    });

    test('checks again before writing, in case the data changed', () async {
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );
      expect(preview.plan.newCount, 4);
      // Another tab registers someone with a Roll No. from the backup after
      // the preview was shown.
      await site.repository.restoreAll([
        sampleRegistration(id: 'other-tab', rollNo: 'CS-001', nrc: 'nx'),
      ]);

      final result = await site.service.commit(preview);

      expect(result.imported, 3);
      expect(result.duplicates, 1);
      final all = await site.all();
      expect(all, hasLength(4));
      expect(all.map((r) => r.id), isNot(contains('r1')));
      expect(all.map((r) => r.id), contains('other-tab'));
    });

    test('leaves the database untouched if the write fails', () async {
      await site.repository.restoreAll([backup[0]]);
      final before = await site.all();
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );
      site.dataSource.insertAllFailure = StateError('disk full');

      await expectLater(site.service.commit(preview), throwsStateError);

      expect(await site.all(), before);
    });

    test('can be retried after a failure', () async {
      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: backupOf(backup),
      );
      site.dataSource.insertAllFailure = StateError('disk full');
      await expectLater(site.service.commit(preview), throwsStateError);

      site.dataSource.insertAllFailure = null;
      final result = await site.service.commit(preview);

      expect(result.imported, 4);
      expect(await site.all(), backup);
    });

    test('imports a large backup and then sees it all as duplicates', () async {
      final many = [
        for (var i = 0; i < 2000; i++)
          sampleRegistration(
            id: 'id-$i',
            name: 'Person $i',
            rollNo: 'CS-$i',
            nrc: '12/LAMANA(N)$i',
          ),
      ];
      final bytes = backupOf(many);

      final first = await site.service.commit(
        await site.service.prepare(fileName: 'big.json', bytes: bytes),
      );
      final again = await site.service.prepare(
        fileName: 'big.json',
        bytes: bytes,
      );

      expect(first.imported, 2000);
      expect(again.plan.newCount, 0);
      expect(again.plan.duplicatesOf(DuplicateReason.alreadyPresent), 2000);
      expect(await site.all(), hasLength(2000));
    });
  });

  group('export, then restore', () {
    /// Registers people the normal way, edits one, and returns the registrations
    /// as stored.
    Future<List<GraduationRegistration>> populate(_Site source) async {
      GraduationRegistration draft(
        String name,
        String roll,
        String nrc, {
        CurrentCountry country = CurrentCountry.myanmar,
        String? other,
        String? remark,
      }) => GraduationRegistration.draft(
        name: name,
        fatherName: 'U Father',
        motherName: 'Daw Mother',
        phoneNo: '09-123-456-789',
        nrc: nrc,
        rollNo: roll,
        major: 'Computer Science',
        attendanceStatus: AttendanceStatus.canAttend,
        currentCountry: country,
        otherCountry: other,
        email: 'p@example.com',
        currentCity: 'Yangon',
        remark: remark,
      );

      await source.repository.create(draft('Aung Aung', 'CS-1', 'n1'));
      final second = await source.repository.create(
        draft(
          'မောင်မောင်',
          'CS-2',
          '၁၂/မမန(နိုင်)၁၂၃၄၅၆',
          country: CurrentCountry.other,
          other: 'Thailand',
          remark: 'Line 1\nLine 2 "quoted"',
        ),
      );
      await source.repository.create(draft('Su Su', 'CS-3', 'n3'));
      // An edit, so updatedAt differs from createdAt.
      await source.repository.update(second.copyWith(major: 'Law'));
      await source.repository.create(draft('Kyaw', 'CS-4', 'n4'));
      return source.all();
    }

    /// Backs up [source] the way the app does and returns the file bytes.
    Future<Uint8List> backUp(_Site source) async {
      final downloader = FakeFileDownloader();
      await RegistrationBackupService(
        repository: source.repository,
        downloader: downloader,
        now: () => DateTime(2026, 9, 25, 14, 30),
      ).exportAll();
      return downloader.downloads.single.bytes;
    }

    test('restores every record into an empty database, identically', () async {
      final original = await populate(site);
      final bytes = await backUp(site);
      final fresh = _Site();
      addTearDown(fresh.close);

      final preview = await fresh.service.prepare(
        fileName: 'graduation_backup.json',
        bytes: bytes,
      );
      final result = await fresh.service.commit(preview);

      expect(result.imported, 4);
      expect(result.duplicates, 0);
      expect(result.invalid, 0);
      final restored = await fresh.all();
      // == compares every field, ids and both dates included.
      expect(restored, original);
      for (final record in original) {
        expect(await fresh.repository.getById(record.id), record);
      }
    });

    test('keeps the original dates, not the time of the restore', () async {
      final original = await populate(site);
      final bytes = await backUp(site);
      final fresh = _Site();
      addTearDown(fresh.close);

      await fresh.service.commit(
        await fresh.service.prepare(fileName: 'b.json', bytes: bytes),
      );

      final restored = await fresh.all();
      expect(
        restored.map((r) => r.createdAt),
        original.map((r) => r.createdAt),
      );
      expect(
        restored.map((r) => r.updatedAt),
        original.map((r) => r.updatedAt),
      );
      // The edited record really has different dates, so this is meaningful.
      expect(original.any((r) => r.updatedAt != r.createdAt), isTrue);
    });

    test('a restored database keeps checking for duplicates', () async {
      await populate(site);
      final bytes = await backUp(site);
      final fresh = _Site();
      addTearDown(fresh.close);
      await fresh.service.commit(
        await fresh.service.prepare(fileName: 'b.json', bytes: bytes),
      );

      expect(await fresh.repository.isRollNoTaken('cs-1'), isTrue);
      expect(await fresh.repository.isNrcTaken('n3'), isTrue);
    });

    test(
      'restoring into a database that has half of the records adds the rest',
      () async {
        final original = await populate(site);
        final bytes = await backUp(site);
        final half = _Site();
        addTearDown(half.close);
        await half.repository.restoreAll(original.take(2).toList());

        final result = await half.service.commit(
          await half.service.prepare(fileName: 'b.json', bytes: bytes),
        );

        expect(result.imported, 2);
        expect(result.duplicates, 2);
        expect(await half.all(), original);
      },
    );

    test('restoring the same backup again changes nothing', () async {
      final original = await populate(site);
      final bytes = await backUp(site);

      final preview = await site.service.prepare(
        fileName: 'b.json',
        bytes: bytes,
      );
      final result = await site.service.commit(preview);

      expect(result.imported, 0);
      expect(result.duplicates, 4);
      expect(await site.all(), original);
    });

    test(
      'the same people registered separately are skipped, not merged',
      () async {
        await populate(site);
        final bytes = await backUp(site);
        // Someone re-registered the same people by hand: same Roll No. and NRC,
        // but different ids.
        final other = _Site();
        addTearDown(other.close);
        await populate(other);
        final before = await other.all();

        final preview = await other.service.prepare(
          fileName: 'b.json',
          bytes: bytes,
        );
        final result = await other.service.commit(preview);

        expect(result.imported, 0);
        expect(result.duplicates, 4);
        expect(await other.all(), before);
      },
    );
  });

  group('the backup service and the import service agree on the format', () {
    test('a backup made now is accepted by the parser', () async {
      final bytes = backupOf(backup);

      final parsed = const RegistrationBackupParser().parse(bytes);

      expect(parsed.version, RegistrationBackupFormat.currentVersion);
      expect(parsed.invalid, isEmpty);
    });
  });
}
