import 'dart:async';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_excel_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_export_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/failures.dart';

import 'support/fake_file_downloader.dart';
import 'support/fake_registration_repository.dart';
import 'support/sample_registrations.dart';

void main() {
  late FakeRegistrationRepository repository;
  late FakeFileDownloader downloader;
  late RegistrationExportService service;

  setUp(() {
    repository = FakeRegistrationRepository(sampleRegistrations());
    downloader = FakeFileDownloader();
    service = RegistrationExportService(
      repository: repository,
      downloader: downloader,
      now: () => DateTime(2026, 9, 5, 9, 7),
    );
  });

  Sheet sheetOf(DownloadedFile file) =>
      Excel.decodeBytes(file.bytes).tables[RegistrationExcelBuilder.sheetName]!;

  group('exportAll', () {
    test('downloads one Excel file with a dated name', () async {
      final result = await service.exportAll();

      expect(downloader.downloads, hasLength(1));
      final file = downloader.downloads.single;
      expect(file.fileName, 'graduation_registrations_2026-09-05.xlsx');
      expect(file.mimeType, RegistrationExcelBuilder.mimeType);
      expect(result.fileName, file.fileName);
      expect(result.count, 4);
    });

    test('exports every registration under a header row', () async {
      await service.exportAll();

      final sheet = sheetOf(downloader.downloads.single);
      expect(sheet.maxRows, 5);
      expect(
        [for (var i = 1; i <= 4; i++) sheet.rows[i][1]!.value.toString()],
        ['Aung Aung', 'Mya Mya', 'Kyaw Kyaw', 'Su Su'],
      );
    });

    test('produces a file that is a valid zip archive', () async {
      await service.exportAll();

      final bytes = downloader.downloads.single.bytes;
      // "PK" is the signature every .xlsx (a zip file) starts with.
      expect(bytes.take(2), [0x50, 0x4B]);
    });

    test('reads the database fresh on every export', () async {
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
      expect(sheetOf(downloader.downloads.last).maxRows, 6);
      expect(repository.getAllCalls, 2);
    });
  });

  group('exporting never changes the data', () {
    test('makes no write calls and leaves every record as it was', () async {
      final before = List.of(repository.items);

      await service.exportAll();

      expect(repository.writeCalls, 0);
      expect(repository.items, before);
    });

    test('leaves the data alone when there is nothing to export', () async {
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

  group('when there is nothing to export', () {
    test('throws NothingToExportFailure and downloads nothing', () async {
      repository.items.clear();

      await expectLater(
        service.exportAll(),
        throwsA(
          isA<NothingToExportFailure>().having(
            (f) => f.message,
            'message',
            'There are no registrations to export yet.',
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

      final export = service.exportAll().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);

      downloader.gate!.complete();
      await export;
      expect(finished, isTrue);
    });
  });
}
