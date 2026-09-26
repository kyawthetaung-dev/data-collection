import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/graduation_registration.dart';

/// The identity and version of the backup file format.
///
/// ## Versioning
///
/// [currentVersion] is a whole number stored in every backup, so the format can
/// change without old files becoming unreadable.
///
/// * Adding an optional field does **not** change the version. Readers ignore
///   fields they do not know.
/// * Renaming or removing a field, or changing what a value means, **does**
///   change it.
/// * A reader must refuse a version newer than it understands, and must
///   migrate older versions it still supports.
abstract final class RegistrationBackupFormat {
  /// Marks a file as one of ours, so an unrelated JSON file is rejected.
  static const formatId = 'graduation-registration-backup';

  static const currentVersion = 1;
}

/// Builds the JSON backup of registrations.
///
/// ```json
/// {
///   "format": "graduation-registration-backup",
///   "version": 1,
///   "exportedAt": "2026-09-25T08:30:00.000Z",
///   "recordCount": 2,
///   "records": [ { "id": "...", "name": "...", ... } ]
/// }
/// ```
///
/// Each record is the entity's own `toMap()`: all 16 fields, including the id
/// and both dates, so a record can be restored exactly as it was. Enums are
/// written by their stable storage names and dates as ISO-8601 UTC. The
/// database's internal duplicate-check keys are not part of a backup; they are
/// rebuilt on restore.
class RegistrationBackupBuilder {
  const RegistrationBackupBuilder();

  static const mimeType = 'application/json';

  static const _encoder = JsonEncoder.withIndent('  ');

  /// `graduation_backup_YYYY-MM-DD_HH-mm.json`, in local time.
  static String fileName(DateTime now) {
    final local = now.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'graduation_backup_'
        '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
        '${two(local.day)}_${two(local.hour)}-${two(local.minute)}.json';
  }

  /// The backup as a JSON-ready map.
  Map<String, Object?> buildJson(
    List<GraduationRegistration> registrations, {
    required DateTime exportedAt,
  }) {
    return {
      'format': RegistrationBackupFormat.formatId,
      'version': RegistrationBackupFormat.currentVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'recordCount': registrations.length,
      'records': [for (final r in registrations) r.toMap()],
    };
  }

  /// The backup as UTF-8 bytes: indented JSON, no byte-order mark.
  Uint8List build(
    List<GraduationRegistration> registrations, {
    required DateTime exportedAt,
  }) {
    final json = buildJson(registrations, exportedAt: exportedAt);
    return Uint8List.fromList(utf8.encode('${_encoder.convert(json)}\n'));
  }
}
