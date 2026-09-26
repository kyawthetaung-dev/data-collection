import '../../domain/entities/graduation_registration.dart';
import 'registration_backup_parser.dart';

/// Why a valid backup record is not going to be imported.
enum DuplicateReason {
  /// The same record, identical in every field, is already stored.
  alreadyPresent,

  /// A stored record has the same id but different data. It is never
  /// overwritten.
  sameIdDifferentData,

  /// A different stored record already uses this Roll No.
  rollNoTaken,

  /// A different stored record already uses this NRC.
  nrcTaken,

  /// An earlier record of the same file has the same id, Roll No. or NRC.
  repeatedInFile,
}

/// A valid backup record that will be skipped, and why.
class SkippedDuplicate {
  const SkippedDuplicate({
    required this.index,
    required this.registration,
    required this.reason,
  });

  /// The record's position in the file, counting from 1.
  final int index;
  final GraduationRegistration registration;
  final DuplicateReason reason;
}

/// What importing a backup would do, decided before anything is written.
///
/// Every record of the file lands in exactly one of [toImport], [duplicates]
/// or [invalid].
class ImportPlan {
  const ImportPlan({
    required this.totalRecords,
    required this.toImport,
    required this.duplicates,
    required this.invalid,
  });

  /// How many records the backup holds.
  final int totalRecords;

  /// New records, in file order. Only these are written.
  final List<GraduationRegistration> toImport;
  final List<SkippedDuplicate> duplicates;
  final List<InvalidBackupRecord> invalid;

  int get newCount => toImport.length;
  int get duplicateCount => duplicates.length;
  int get invalidCount => invalid.length;

  int duplicatesOf(DuplicateReason reason) =>
      duplicates.where((d) => d.reason == reason).length;
}

/// Sorts the records of a backup into new, duplicate and invalid ones.
///
/// It never changes anything. Existing records are the reference and are only
/// ever added to: a record that clashes with one is skipped, never overwrites
/// it.
///
/// A record is recognised as already stored by its **id** first. A record with
/// a different id is still a duplicate if its Roll No. or NRC belongs to
/// another stored record, because two registrations may not share those (they
/// are compared ignoring case and spacing, like the registration form does).
/// Within the file the first record wins.
class BackupImportPlanner {
  const BackupImportPlanner();

  ImportPlan plan(ParsedBackup backup, List<GraduationRegistration> existing) {
    final storedById = {for (final r in existing) r.id: r};
    final storedRollKeys = {
      for (final r in existing) normalizeLookupKey(r.rollNo),
    };
    final storedNrcKeys = {for (final r in existing) normalizeLookupKey(r.nrc)};

    final fileIds = <String>{};
    final fileRollKeys = <String>{};
    final fileNrcKeys = <String>{};

    final toImport = <GraduationRegistration>[];
    final duplicates = <SkippedDuplicate>[];

    void skip(ParsedBackupRecord record, DuplicateReason reason) {
      duplicates.add(
        SkippedDuplicate(
          index: record.index,
          registration: record.registration,
          reason: reason,
        ),
      );
    }

    for (final record in backup.valid) {
      final r = record.registration;
      final rollKey = normalizeLookupKey(r.rollNo);
      final nrcKey = normalizeLookupKey(r.nrc);

      final stored = storedById[r.id];
      if (stored != null) {
        skip(
          record,
          stored == r
              ? DuplicateReason.alreadyPresent
              : DuplicateReason.sameIdDifferentData,
        );
      } else if (storedRollKeys.contains(rollKey)) {
        skip(record, DuplicateReason.rollNoTaken);
      } else if (storedNrcKeys.contains(nrcKey)) {
        skip(record, DuplicateReason.nrcTaken);
      } else if (fileIds.contains(r.id) ||
          fileRollKeys.contains(rollKey) ||
          fileNrcKeys.contains(nrcKey)) {
        skip(record, DuplicateReason.repeatedInFile);
      } else {
        fileIds.add(r.id);
        fileRollKeys.add(rollKey);
        fileNrcKeys.add(nrcKey);
        toImport.add(r);
      }
    }

    return ImportPlan(
      totalRecords: backup.totalRecords,
      toImport: toImport,
      duplicates: duplicates,
      invalid: backup.invalid,
    );
  }
}
