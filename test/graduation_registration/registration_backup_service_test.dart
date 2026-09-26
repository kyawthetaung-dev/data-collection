import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/failures.dart';

import 'support/fake_file_downloader.dart';
import 'support/fake_registration_repository.dart';
import 'support/sample_registrations.dart';

void main() {
  final backupTime = DateTime(2026, 9, 5, 9, 7, 30);

  late FakeRegistrationRepository repository;
  late FakeFileDownloader downloader;
  late RegistrationBackupService service;

  setUp(() {
    repository = FakeRegistrationRepository(sampleRegistrations());
    downloader = FakeFileDownloader();
    service = RegistrationBackupService(
      repository: repository,
      downloader: downloader,
      now: () => backupTime,
    );
  });

  Map<String, Object?> backupOf(DownloadedFile file) =>
      jsonDecode(utf8.decode(file.bytes)) as Map<String, Object?>;

  group('exportAll', () {
    test('downloads one JSON file with a timestamped name', () async {
      final result = await service.exportAll();

      expect(downloader.downloads, hasLength(1));
      final file = downloader.downloads.single;
      expect(file.fileName, 'graduation_backup_2026-09-05_09-07.json');
      expect(file.mimeType, 'application/json');
      expect(result.fileName, file.fileName);
      expect(result.count, 4);
    });

    test('backs up every registration, fully restorable', () async {
      await service.exportAll();

      final backup = backupOf(downloader.downloads.single);
      expect(backup['version'], 1);
      expect(backup['recordCount'], 4);
      final restored = [
        for (final record in backup['records']! as List)
          GraduationRegistration.fromMap(record as Map<String, Object?>),
      ];
      expect(restored, sampleRegistrations());
    });

    test('stamps the backup with the time it was made', () async {
      await service.exportAll();

      final backup = backupOf(downloader.downloads.single);
      expect(backup['exportedAt'], backupTime.toUtc().toIso8601String());
    });

    test('reads the database fresh on every backup', () async {
      await service.exportAll();
      repository.items.add(
        sampleRegistration(
          id: 'r5',
          name: 'New Person',
          rollNo: 'CS-005',
          nrc: '12/LAMANA(N)555555',
        ),
      );

      final result = await service.exportAll();

      expect(result.count, 5);
      expect(backupOf(downloader.downloads.last)['recordCount'], 5);
      expect(repository.getAllCalls, 2);
    });
  });

  group('a backup never changes the data', () {
    test('makes no write calls and leaves every record as it was', () async {
      final before = List.of(repository.items);

      await service.exportAll();

      expect(repository.writeCalls, 0);
      expect(repository.items, before);
    });

    test('leaves the data alone when there is nothing to back up', () async {
      repository.items.clear();

      await expectLater(
        service.exportAll(),
        throwsA(isA<NothingToExportFailure>()),
      );

      expect(repository.writeCalls, 0);
      expect(repository.items, isEmpty);
    });

    test('leaves the data alone when the download fails', () async {
      downloader.error = StateError('blocked');
      final before = List.of(repository.items);

      await expectLater(service.exportAll(), throwsStateError);

      expect(repository.writeCalls, 0);
      expect(repository.items, before);
    });
  });

  group('when there is nothing to back up', () {
    test('throws NothingToExportFailure and downloads nothing', () async {
      repository.items.clear();

      await expectLater(
        service.exportAll(),
        throwsA(
          isA<NothingToExportFailure>().having(
            (f) => f.message,
            'message',
            'There are no registrations to back up yet.',
          ),
        ),
      );

      expect(downloader.downloads, isEmpty);
    });
  });

  group('failures', () {
    test('a database error is passed on and nothing is downloaded', () async {
      repository.getAllError = StateError('IndexedDB is unavailable');

      await expectLater(service.exportAll(), throwsStateError);

      expect(downloader.downloads, isEmpty);
    });

    test('a download error is passed on', () async {
      downloader.error = UnsupportedError('no browser');

      await expectLater(service.exportAll(), throwsUnsupportedError);
    });

    test('waits for the download to finish', () async {
      downloader.gate = Completer<void>();
      var finished = false;

      final backup = service.exportAll().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);

      downloader.gate!.complete();
      await backup;
      expect(finished, isTrue);
    });
  });

  test('uses the same format constants the builder documents', () async {
    await service.exportAll();

    final backup = backupOf(downloader.downloads.single);
    expect(backup['format'], RegistrationBackupFormat.formatId);
    expect(backup['version'], RegistrationBackupFormat.currentVersion);
  });
}
