import '../../domain/failures.dart';
import '../../domain/repositories/graduation_registration_repository.dart';
import 'export_result.dart';
import 'file_downloader.dart';
import 'registration_backup_builder.dart';

/// Exports every registration to a JSON backup file and downloads it.
///
/// Read-only: it only calls `getAll()`, so a backup never changes or removes
/// anything in the database.
class RegistrationBackupService {
  /// [now] can be replaced to make the file name and time deterministic.
  RegistrationBackupService({
    required this._repository,
    this._builder = const RegistrationBackupBuilder(),
    FileDownloader? downloader,
    DateTime Function()? now,
  }) : _downloader = downloader ?? createFileDownloader(),
       _now = now ?? DateTime.now;

  final GraduationRegistrationRepository _repository;
  final RegistrationBackupBuilder _builder;
  final FileDownloader _downloader;
  final DateTime Function() _now;

  /// Downloads a backup of all registrations, read fresh from the database.
  ///
  /// Throws [NothingToExportFailure], without downloading anything, if there
  /// are no registrations: an empty file would only look like a real backup.
  Future<ExportResult> exportAll() async {
    final registrations = await _repository.getAll();
    if (registrations.isEmpty) {
      throw const NothingToExportFailure(
        'There are no registrations to back up yet.',
      );
    }

    final exportedAt = _now();
    final fileName = RegistrationBackupBuilder.fileName(exportedAt);
    await _downloader.download(
      fileName: fileName,
      bytes: _builder.build(registrations, exportedAt: exportedAt),
      mimeType: RegistrationBackupBuilder.mimeType,
    );
    return ExportResult(fileName: fileName, count: registrations.length);
  }
}
