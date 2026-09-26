import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/graduation_registration.dart';
import '../../domain/validators/registration_validator.dart';
import '../export/registration_backup_builder.dart';

/// The file cannot be used as a backup at all: it is not the right kind of
/// file, or it is unreadable or too new. The message is written for the user.
class BackupFileException implements Exception {
  const BackupFileException(this.message);

  final String message;

  @override
  String toString() => 'BackupFileException: $message';
}

/// A record of a backup that cannot be imported, and why.
class InvalidBackupRecord {
  const InvalidBackupRecord({
    required this.index,
    required this.reasons,
    this.label,
  });

  /// The record's position in the file, counting from 1.
  final int index;

  /// Something to recognise the record by, such as its Roll No., if readable.
  final String? label;
  final List<String> reasons;

  String get description =>
      label == null ? 'Record $index' : 'Record $index ($label)';
}

/// A record of a backup that is valid and can be imported.
class ParsedBackupRecord {
  const ParsedBackupRecord(this.index, this.registration);

  /// The record's position in the file, counting from 1.
  final int index;
  final GraduationRegistration registration;
}

/// A backup file that was read successfully: its details, and each of its
/// records sorted into valid and invalid.
class ParsedBackup {
  const ParsedBackup({
    required this.version,
    required this.exportedAt,
    required this.declaredCount,
    required this.totalRecords,
    required this.valid,
    required this.invalid,
  });

  final int version;

  /// When the backup was made, if the file says so.
  final DateTime? exportedAt;

  /// The record count the file claims to have, if it says.
  final int? declaredCount;

  /// How many records the file actually holds, valid or not.
  final int totalRecords;
  final List<ParsedBackupRecord> valid;
  final List<InvalidBackupRecord> invalid;

  /// A warning if the file's own count disagrees with its records, which
  /// suggests it was edited or is incomplete. Otherwise `null`.
  String? get countWarning {
    final declared = declaredCount;
    if (declared == null || declared == totalRecords) return null;
    return 'The file says it holds $declared records, but it contains '
        '$totalRecords. It may have been edited or be incomplete.';
  }
}

/// Reads and checks a JSON backup file, without touching the database.
///
/// The file is checked in layers: it must be UTF-8 JSON, then an object made
/// by this app (`format`), of a version this app understands (`version`), with
/// a list of `records`. Each record is then checked on its own, with the same
/// rules as the registration form, so one bad record never blocks the rest.
class RegistrationBackupParser {
  const RegistrationBackupParser({
    this.validator = const RegistrationValidator(),
  });

  /// Larger files are refused before they are read, so a wrong file cannot
  /// freeze the page.
  static const maxFileBytes = 20 * 1024 * 1024;

  final RegistrationValidator validator;

  static const _byteOrderMark = 0xFEFF;

  /// Reads [bytes] as a backup. Throws [BackupFileException] if the file as a
  /// whole cannot be used; problems with single records are reported in the
  /// result instead.
  ParsedBackup parse(Uint8List bytes) {
    if (bytes.isEmpty) throw const BackupFileException('The file is empty.');
    if (bytes.length > maxFileBytes) {
      throw const BackupFileException(
        'The file is too large to be a backup (over 20 MB).',
      );
    }

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const BackupFileException(
        'The file is not readable text. A backup is a UTF-8 JSON file.',
      );
    }
    // A byte-order mark is added by some editors; JSON itself does not allow it.
    if (text.isNotEmpty && text.codeUnitAt(0) == _byteOrderMark) {
      text = text.substring(1);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const BackupFileException(
        'The file is not valid JSON. It may be damaged or incomplete.',
      );
    }
    if (decoded is! Map ||
        decoded['format'] != RegistrationBackupFormat.formatId) {
      throw const BackupFileException(
        'This file is not a graduation registration backup.',
      );
    }

    final version = decoded['version'];
    if (version is! int || version < 1) {
      throw const BackupFileException(
        'The backup has no valid version number.',
      );
    }
    if (version > RegistrationBackupFormat.currentVersion) {
      throw BackupFileException(
        'This backup was made by a newer version of the app (backup version '
        '$version; this app understands up to version '
        '${RegistrationBackupFormat.currentVersion}). Update the app to '
        'restore it.',
      );
    }

    final records = decoded['records'];
    if (records is! List) {
      throw const BackupFileException('The backup has no list of records.');
    }

    final valid = <ParsedBackupRecord>[];
    final invalid = <InvalidBackupRecord>[];
    for (var i = 0; i < records.length; i++) {
      final result = _parseRecord(i + 1, _upgrade(version, records[i]));
      switch (result) {
        case final ParsedBackupRecord record:
          valid.add(record);
        case final InvalidBackupRecord record:
          invalid.add(record);
      }
    }

    final exportedAt = decoded['exportedAt'];
    final declaredCount = decoded['recordCount'];
    return ParsedBackup(
      version: version,
      exportedAt: exportedAt is String
          ? DateTime.tryParse(exportedAt)?.toUtc()
          : null,
      declaredCount: declaredCount is int ? declaredCount : null,
      totalRecords: records.length,
      valid: valid,
      invalid: invalid,
    );
  }

  /// Brings a record written by backup [version] up to the current format.
  ///
  /// There is only version 1 so far, so nothing changes yet. When the format
  /// changes, older versions are converted here.
  Object? _upgrade(int version, Object? record) => record;

  /// Either a [ParsedBackupRecord] or an [InvalidBackupRecord].
  Object _parseRecord(int index, Object? raw) {
    if (raw is! Map) {
      return InvalidBackupRecord(
        index: index,
        reasons: const ['Not a record: expected an object.'],
      );
    }
    final map = <String, Object?>{
      for (final entry in raw.entries) '${entry.key}': entry.value,
    };
    final label = _labelOf(map);

    final GraduationRegistration registration;
    try {
      registration = GraduationRegistration.fromMap(map).normalized();
    } on FormatException catch (error) {
      // fromMap reports the first bad field as `Invalid "name"`.
      final detail = error.message.replaceFirst('Invalid ', '');
      return InvalidBackupRecord(
        index: index,
        label: label,
        reasons: ['Missing or invalid $detail.'],
      );
    }

    final reasons = <String>[
      if (registration.id.isEmpty) 'The record has no id.',
      ...validator.validate(registration).values,
    ];
    if (reasons.isNotEmpty) {
      return InvalidBackupRecord(index: index, label: label, reasons: reasons);
    }
    return ParsedBackupRecord(index, registration);
  }

  /// The Roll No. or, failing that, the name, to help find a bad record.
  String? _labelOf(Map<String, Object?> map) {
    for (final key in ['rollNo', 'name']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
