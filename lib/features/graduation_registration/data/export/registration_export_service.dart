import '../../domain/failures.dart';
import '../../domain/repositories/graduation_registration_repository.dart';
import 'export_result.dart';
import 'file_downloader.dart';
import 'registration_excel_builder.dart';

/// Exports every registration to an Excel report and downloads it.
///
/// Read-only: it only calls `getAll()`, so exporting never changes or removes
/// anything in the database.
class RegistrationExportService {
  /// [now] can be replaced to make the file name deterministic in tests.
  RegistrationExportService({
    required this._repository,
    this._builder = const RegistrationExcelBuilder(),
    FileDownloader? downloader,
    DateTime Function()? now,
  }) : _downloader = downloader ?? createFileDownloader(),
       _now = now ?? DateTime.now;

  final GraduationRegistrationRepository _repository;
  final RegistrationExcelBuilder _builder;
  final FileDownloader _downloader;
  final DateTime Function() _now;

  /// Downloads the report of all registrations, read fresh from the database.
  ///
  /// Throws [NothingToExportFailure], without downloading anything, if there
  /// are no registrations.
  Future<ExportResult> exportAll() async {
    final registrations = await _repository.getAll();
    if (registrations.isEmpty) {
      throw const NothingToExportFailure(
        'There are no registrations to export yet.',
      );
    }

    final fileName = RegistrationExcelBuilder.fileName(_now());
    await _downloader.download(
      fileName: fileName,
      bytes: _builder.build(registrations),
      mimeType: RegistrationExcelBuilder.mimeType,
    );
    return ExportResult(fileName: fileName, count: registrations.length);
  }
}
