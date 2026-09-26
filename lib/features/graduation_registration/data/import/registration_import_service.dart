import 'dart:typed_data';

import '../../domain/repositories/graduation_registration_repository.dart';
import 'backup_import_planner.dart';
import 'registration_backup_parser.dart';

/// What importing a chosen backup file would do. Nothing has been written.
class ImportPreview {
  const ImportPreview({
    required this.fileName,
    required this.backup,
    required this.plan,
  });

  final String fileName;
  final ParsedBackup backup;
  final ImportPlan plan;
}

/// What an import did.
class ImportResult {
  const ImportResult({
    required this.total,
    required this.imported,
    required this.duplicates,
    required this.invalid,
  });

  /// How many records the backup held.
  final int total;

  /// New records that were added.
  final int imported;

  /// Records skipped because they duplicate or clash with a stored one.
  final int duplicates;

  /// Records skipped because they were not valid.
  final int invalid;
}

/// Imports a JSON backup: read, check, preview, then add what is new.
///
/// Import only ever **adds** registrations. It never overwrites or deletes
/// anything, and the write is all or nothing.
class RegistrationImportService {
  RegistrationImportService({
    required this._repository,
    this._parser = const RegistrationBackupParser(),
    this._planner = const BackupImportPlanner(),
  });

  final GraduationRegistrationRepository _repository;
  final RegistrationBackupParser _parser;
  final BackupImportPlanner _planner;

  /// Reads and checks [bytes] and works out what importing them would do
  /// against the registrations stored right now. Writes nothing.
  ///
  /// Throws [BackupFileException] if the file cannot be used as a backup.
  Future<ImportPreview> prepare({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final backup = _parser.parse(bytes);
    final existing = await _repository.getAll();
    return ImportPreview(
      fileName: fileName,
      backup: backup,
      plan: _planner.plan(backup, existing),
    );
  }

  /// Adds the new records of [preview] to the database.
  ///
  /// The plan is worked out again first, because another browser tab may have
  /// changed the data since the preview was made. Only records that are still
  /// new are written, in one all-or-nothing operation, and the result reports
  /// what really happened.
  ///
  /// If this throws, nothing was written.
  Future<ImportResult> commit(ImportPreview preview) async {
    final existing = await _repository.getAll();
    final plan = _planner.plan(preview.backup, existing);
    await _repository.restoreAll(plan.toImport);
    return ImportResult(
      total: plan.totalRecords,
      imported: plan.newCount,
      duplicates: plan.duplicateCount,
      invalid: plan.invalidCount,
    );
  }
}
