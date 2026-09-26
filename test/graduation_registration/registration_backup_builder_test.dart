import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';

import 'support/sample_registrations.dart';

const _builder = RegistrationBackupBuilder();

final _exportedAt = DateTime.utc(2026, 9, 25, 8, 30);

Map<String, Object?> decode(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

List<Map<String, Object?>> recordsOf(Map<String, Object?> backup) => [
  for (final record in backup['records']! as List)
    record as Map<String, Object?>,
];

void main() {
  final all = sampleRegistrations();

  group('envelope', () {
    test('identifies the format and its version', () {
      final backup = decode(_builder.build(all, exportedAt: _exportedAt));

      expect(backup['format'], 'graduation-registration-backup');
      expect(backup['version'], 1);
      expect(RegistrationBackupFormat.currentVersion, 1);
      expect(RegistrationBackupFormat.formatId, backup['format']);
    });

    test('records when it was made, as ISO-8601 UTC', () {
      final backup = decode(_builder.build(all, exportedAt: _exportedAt));

      expect(backup['exportedAt'], '2026-09-25T08:30:00.000Z');
    });

    test('converts a local export time to UTC', () {
      final local = DateTime(2026, 9, 25, 14, 30);

      final backup = decode(_builder.build(all, exportedAt: local));

      expect(backup['exportedAt'], local.toUtc().toIso8601String());
      expect(DateTime.parse(backup['exportedAt']! as String), local.toUtc());
    });

    test('counts its records', () {
      final backup = decode(_builder.build(all, exportedAt: _exportedAt));

      expect(backup['recordCount'], 4);
      expect(backup['records'], hasLength(4));
    });

    test('has exactly the expected top-level keys', () {
      final backup = decode(_builder.build(all, exportedAt: _exportedAt));

      expect(backup.keys, [
        'format',
        'version',
        'exportedAt',
        'recordCount',
        'records',
      ]);
    });
  });

  group('records', () {
    test('contain every field needed to restore a registration', () {
      final records = recordsOf(
        decode(_builder.build(all, exportedAt: _exportedAt)),
      );

      for (final record in records) {
        expect(record.keys, [
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
    });

    test('carry the values of the registration', () {
      final first = recordsOf(
        decode(_builder.build(all, exportedAt: _exportedAt)),
      ).first;

      expect(first, {
        'id': 'r1',
        'name': 'Aung Aung',
        'fatherName': 'U Kyaw',
        'motherName': 'Daw Mya',
        'phoneNo': '09-123-456-789',
        'nrc': '12/LAMANA(N)111111',
        'rollNo': 'CS-001',
        'major': 'Computer Science',
        'attendanceStatus': 'canAttend',
        'currentCountry': 'myanmar',
        'otherCountry': null,
        'currentCity': 'Yangon',
        'email': 'aung@example.com',
        'remark': 'Bringing two guests',
        'createdAt': '2026-09-01T12:00:00.000Z',
        'updatedAt': '2026-09-01T12:00:00.000Z',
      });
    });

    test('write empty optional fields as explicit null', () {
      final last = recordsOf(
        decode(_builder.build(all, exportedAt: _exportedAt)),
      ).last;

      for (final key in [
        'motherName',
        'otherCountry',
        'currentCity',
        'email',
        'remark',
      ]) {
        expect(last.containsKey(key), isTrue, reason: key);
        expect(last[key], isNull, reason: key);
      }
    });

    test('write enums by storage name, not by display label', () {
      final records = recordsOf(
        decode(_builder.build(all, exportedAt: _exportedAt)),
      );

      expect(records[1]['attendanceStatus'], 'cannotAttend');
      expect(records[1]['currentCountry'], 'japan');
      expect(records[2]['currentCountry'], 'other');
      expect(records[2]['otherCountry'], 'Thailand');
    });

    test('leave out the database\'s internal duplicate-check keys', () {
      final text = utf8.decode(_builder.build(all, exportedAt: _exportedAt));

      expect(text.contains('rollNoKey'), isFalse);
      expect(text.contains('nrcKey'), isFalse);
    });

    test('keep the order they are given in', () {
      final backup = decode(
        _builder.build(all.reversed.toList(), exportedAt: _exportedAt),
      );

      expect(recordsOf(backup).map((r) => r['id']), ['r4', 'r3', 'r2', 'r1']);
    });
  });

  group('restoring', () {
    /// The whole point of a backup: reading it back gives the same records.
    List<GraduationRegistration> roundTrip(List<GraduationRegistration> list) {
      final backup = decode(_builder.build(list, exportedAt: _exportedAt));
      return [
        for (final record in recordsOf(backup))
          GraduationRegistration.fromMap(record),
      ];
    }

    test('gives back every record exactly, ids and dates included', () {
      expect(roundTrip(all), all);
    });

    test('keeps tricky text exactly', () {
      final tricky = [
        sampleRegistration(
          name: 'မောင်မောင် "Aung" O\'Brien',
          nrc: '၁၂/မမန(နိုင်)၁၂၃၄၅၆',
          remark: 'Line 1\nLine 2\t\\ backslash / slash 😀',
          currentCity: '  spaced  ',
        ),
      ];

      expect(roundTrip(tricky), tricky);
    });

    test('keeps the original dates, not the time of the backup', () {
      final old = sampleRegistration(
        createdAt: DateTime.utc(2020, 1, 2, 3, 4, 5),
        updatedAt: DateTime.utc(2021, 6, 7, 8, 9, 10),
      );

      final restored = roundTrip([old]).single;

      expect(restored.createdAt, DateTime.utc(2020, 1, 2, 3, 4, 5));
      expect(restored.updatedAt, DateTime.utc(2021, 6, 7, 8, 9, 10));
    });

    test('keeps every country and attendance value', () {
      final everything = [
        for (final country in CurrentCountry.values)
          for (final status in AttendanceStatus.values)
            sampleRegistration(
              id: '${country.name}-${status.name}',
              rollNo: '${country.name}-${status.name}',
              nrc: 'nrc-${country.name}-${status.name}',
              currentCountry: country,
              otherCountry: country == CurrentCountry.other ? 'Peru' : null,
              attendanceStatus: status,
            ),
      ];

      expect(roundTrip(everything), everything);
    });
  });

  group('bytes', () {
    test('are UTF-8 without a byte-order mark', () {
      final bytes = _builder.build(all, exportedAt: _exportedAt);

      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(() => utf8.decode(bytes), returnsNormally);
      expect(bytes.first, 0x7B); // "{"
    });

    test('are indented so they can be read and compared', () {
      final text = utf8.decode(_builder.build(all, exportedAt: _exportedAt));

      expect(text, contains('\n  "format": "graduation-registration-backup"'));
      expect(text, contains('\n  "records": ['));
      expect(text.endsWith('}\n'), isTrue);
    });

    test('keep Burmese text as written, not as \\u escapes', () {
      final text = utf8.decode(
        _builder.build([
          sampleRegistration(name: 'မောင်မောင်'),
        ], exportedAt: _exportedAt),
      );

      expect(text, contains('မောင်မောင်'));
      // A backslash followed by "u", which is how an escaped character starts.
      expect(text.contains('\\u'), isFalse);
    });

    test('are the same for the same input', () {
      expect(
        _builder.build(all, exportedAt: _exportedAt),
        _builder.build(all, exportedAt: _exportedAt),
      );
    });

    test('build a valid, empty backup for no registrations', () {
      final backup = decode(_builder.build([], exportedAt: _exportedAt));

      expect(backup['recordCount'], 0);
      expect(backup['records'], isEmpty);
    });
  });

  group('fileName', () {
    test('is graduation_backup_YYYY-MM-DD_HH-mm.json', () {
      expect(
        RegistrationBackupBuilder.fileName(DateTime(2026, 9, 25, 14, 30, 45)),
        'graduation_backup_2026-09-25_14-30.json',
      );
    });

    test('pads every part', () {
      expect(
        RegistrationBackupBuilder.fileName(DateTime(2026, 1, 5, 9, 7)),
        'graduation_backup_2026-01-05_09-07.json',
      );
    });

    test('uses 24-hour time', () {
      expect(
        RegistrationBackupBuilder.fileName(DateTime(2026, 9, 25, 0, 0)),
        'graduation_backup_2026-09-25_00-00.json',
      );
      expect(
        RegistrationBackupBuilder.fileName(DateTime(2026, 9, 25, 23, 59)),
        'graduation_backup_2026-09-25_23-59.json',
      );
    });

    test('always matches the documented pattern', () {
      final pattern = RegExp(
        r'^graduation_backup_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.json$',
      );

      for (final time in [
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31, 23, 59),
        DateTime.utc(2026, 6, 15, 12),
      ]) {
        expect(RegistrationBackupBuilder.fileName(time), matches(pattern));
      }
    });

    test('uses local time', () {
      final instant = DateTime.utc(2026, 9, 25, 23, 59);
      final local = instant.toLocal();

      expect(
        RegistrationBackupBuilder.fileName(instant),
        contains(
          '${local.year}-${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}_'
          '${local.hour.toString().padLeft(2, '0')}-'
          '${local.minute.toString().padLeft(2, '0')}',
        ),
      );
    });
  });
}
