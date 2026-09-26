import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_backup_parser.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';

import 'support/backup_test_data.dart';
import 'support/sample_registrations.dart';

const _parser = RegistrationBackupParser();

/// The message of the [BackupFileException] that parsing [bytes] throws.
String fileError(Uint8List bytes) {
  try {
    _parser.parse(bytes);
  } on BackupFileException catch (error) {
    return error.message;
  }
  fail('Expected a BackupFileException, but the file was accepted.');
}

/// The reasons the single record [record] is rejected for.
List<String> reasonsFor(Map<String, Object?> record) {
  final parsed = _parser.parse(jsonBytes(backupJson([record])));
  expect(parsed.valid, isEmpty, reason: 'expected the record to be invalid');
  return parsed.invalid.single.reasons;
}

void main() {
  group('a valid backup', () {
    test('reads the records the builder wrote, exactly', () {
      final original = sampleRegistrations();
      final bytes = const RegistrationBackupBuilder().build(
        original,
        exportedAt: DateTime.utc(2026, 9, 25, 8, 30),
      );

      final parsed = _parser.parse(bytes);

      expect(parsed.valid.map((r) => r.registration), original);
      expect(parsed.valid.map((r) => r.index), [1, 2, 3, 4]);
      expect(parsed.invalid, isEmpty);
      expect(parsed.totalRecords, 4);
      expect(parsed.version, 1);
      expect(parsed.exportedAt, DateTime.utc(2026, 9, 25, 8, 30));
      expect(parsed.declaredCount, 4);
      expect(parsed.countWarning, isNull);
    });

    test('accepts a backup with no records', () {
      final parsed = _parser.parse(jsonBytes(backupJson([])));

      expect(parsed.totalRecords, 0);
      expect(parsed.valid, isEmpty);
      expect(parsed.invalid, isEmpty);
    });

    test('ignores a leading byte-order mark', () {
      final withMark = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...jsonBytes(backupJson([recordJson()])),
      ]);

      expect(_parser.parse(withMark).valid, hasLength(1));
    });

    test('ignores fields it does not know', () {
      final json = backupJson([
        recordJson(overrides: {'futureField': 42}),
      ])..['generator'] = 'some other tool';

      final parsed = _parser.parse(jsonBytes(json));

      expect(parsed.valid, hasLength(1));
      expect(parsed.invalid, isEmpty);
    });

    test('does not need the optional fields', () {
      final record = recordJson(
        remove: [
          'motherName',
          'otherCountry',
          'currentCity',
          'email',
          'remark',
        ],
      );

      final parsed = _parser.parse(jsonBytes(backupJson([record])));

      expect(parsed.valid.single.registration.motherName, isNull);
      expect(parsed.valid.single.registration.remark, isNull);
    });

    test('does not need the export time or the record count', () {
      final json = backupJson(
        [recordJson()],
        omit: ['exportedAt', 'recordCount'],
      );

      final parsed = _parser.parse(jsonBytes(json));

      expect(parsed.exportedAt, isNull);
      expect(parsed.declaredCount, isNull);
      expect(parsed.countWarning, isNull);
      expect(parsed.valid, hasLength(1));
    });

    test('ignores an export time it cannot read', () {
      final parsed = _parser.parse(
        jsonBytes(backupJson([recordJson()], exportedAt: 'yesterday')),
      );

      expect(parsed.exportedAt, isNull);
      expect(parsed.valid, hasLength(1));
    });

    test('warns when the record count does not match', () {
      final json = backupJson([
        recordJson(),
        recordJson(id: 'r2', rollNo: 'X', nrc: 'Y'),
      ], recordCount: 5);

      final parsed = _parser.parse(jsonBytes(json));

      expect(parsed.countWarning, contains('5'));
      expect(parsed.countWarning, contains('2'));
      expect(parsed.valid, hasLength(2));
    });

    test('trims text in the records', () {
      final record = recordJson(
        overrides: {'name': '  Spaced  ', 'email': ' '},
      );

      final parsed = _parser.parse(jsonBytes(backupJson([record])));

      expect(parsed.valid.single.registration.name, 'Spaced');
      expect(parsed.valid.single.registration.email, isNull);
    });

    test('keeps Burmese text', () {
      final record = recordJson(name: 'မောင်မောင်', nrc: '၁၂/မမန(နိုင်)၁၂၃၄၅၆');

      final parsed = _parser.parse(jsonBytes(backupJson([record])));

      expect(parsed.valid.single.registration.name, 'မောင်မောင်');
      expect(parsed.valid.single.registration.nrc, '၁၂/မမန(နိုင်)၁၂၃၄၅၆');
    });

    test('keeps the original dates', () {
      final record = recordJson(
        overrides: {
          'createdAt': '2020-01-02T03:04:05.000Z',
          'updatedAt': '2021-06-07T08:09:10.000Z',
        },
      );

      final r = _parser
          .parse(jsonBytes(backupJson([record])))
          .valid
          .single
          .registration;

      expect(r.createdAt, DateTime.utc(2020, 1, 2, 3, 4, 5));
      expect(r.updatedAt, DateTime.utc(2021, 6, 7, 8, 9, 10));
    });
  });

  group('a file that cannot be a backup', () {
    test('is refused when empty', () {
      expect(fileError(Uint8List(0)), 'The file is empty.');
    });

    test('is refused when too large', () {
      final huge = Uint8List(RegistrationBackupParser.maxFileBytes + 1);

      expect(fileError(huge), contains('too large'));
    });

    test('is refused when not UTF-8 text', () {
      expect(
        fileError(Uint8List.fromList([0xFF, 0xFE, 0x00, 0xC3, 0x28])),
        contains('not readable text'),
      );
    });

    test('is refused when not JSON', () {
      expect(
        fileError(textBytes('name,roll\nA,1')),
        contains('not valid JSON'),
      );
      expect(fileError(textBytes('{"format": ')), contains('not valid JSON'));
    });

    test('is refused when JSON but not an object', () {
      for (final text in ['[]', '"backup"', '42', 'null', '[{"a": 1}]']) {
        expect(
          fileError(textBytes(text)),
          'This file is not a graduation registration backup.',
          reason: text,
        );
      }
    });

    test('is refused with a missing or different format', () {
      for (final json in [
        backupJson([], omit: ['format']),
        backupJson([], format: 'something-else'),
        backupJson([], format: 7),
        {'records': [], 'version': 1},
      ]) {
        expect(
          fileError(jsonBytes(json)),
          'This file is not a graduation registration backup.',
          reason: '$json',
        );
      }
    });

    test('is refused with a missing or invalid version', () {
      for (final version in [null, 'one', '1', 1.5, 0, -1, true, <Object?>[]]) {
        expect(
          fileError(jsonBytes(backupJson([], version: version))),
          'The backup has no valid version number.',
          reason: '$version',
        );
      }
      expect(
        fileError(jsonBytes(backupJson([], omit: ['version']))),
        'The backup has no valid version number.',
      );
    });

    test('is refused when made by a newer version', () {
      final message = fileError(jsonBytes(backupJson([], version: 2)));

      expect(message, contains('newer version of the app'));
      expect(message, contains('version 2'));
      expect(message, contains('up to version 1'));
    });

    test('is refused when it has no list of records', () {
      for (final json in [
        backupJson([], omit: ['records']),
        {...backupJson([]), 'records': 'many'},
        {
          ...backupJson([]),
          'records': {'a': 1},
        },
        {...backupJson([]), 'records': null},
      ]) {
        expect(
          fileError(jsonBytes(json)),
          'The backup has no list of records.',
          reason: '$json',
        );
      }
    });
  });

  group('invalid records', () {
    test('a record that is not an object', () {
      final parsed = _parser.parse(
        jsonBytes(
          backupJson([
            null,
            5,
            'text',
            [1, 2],
            true,
          ]),
        ),
      );

      expect(parsed.valid, isEmpty);
      expect(parsed.invalid, hasLength(5));
      for (final invalid in parsed.invalid) {
        expect(invalid.reasons, ['Not a record: expected an object.']);
      }
      expect(parsed.invalid.map((r) => r.index), [1, 2, 3, 4, 5]);
    });

    test('each required field, when missing', () {
      for (final field in [
        'id',
        'name',
        'fatherName',
        'phoneNo',
        'nrc',
        'rollNo',
        'major',
        'attendanceStatus',
        'currentCountry',
        'createdAt',
        'updatedAt',
      ]) {
        final reasons = reasonsFor(recordJson(remove: [field]));

        expect(reasons.single, 'Missing or invalid "$field".', reason: field);
      }
    });

    test('a field of the wrong type', () {
      expect(reasonsFor(recordJson(overrides: {'name': 5})), [
        'Missing or invalid "name".',
      ]);
      expect(reasonsFor(recordJson(overrides: {'motherName': 7})), [
        'Missing or invalid "motherName".',
      ]);
      expect(reasonsFor(recordJson(overrides: {'id': null})), [
        'Missing or invalid "id".',
      ]);
    });

    test('an unknown attendance status or country', () {
      expect(reasonsFor(recordJson(overrides: {'attendanceStatus': 'maybe'})), [
        'Missing or invalid "attendanceStatus".',
      ]);
      // A display label is not a storage value.
      expect(
        reasonsFor(recordJson(overrides: {'attendanceStatus': 'Can Attend'})),
        ['Missing or invalid "attendanceStatus".'],
      );
      expect(reasonsFor(recordJson(overrides: {'currentCountry': 'Mars'})), [
        'Missing or invalid "currentCountry".',
      ]);
    });

    test('a date that cannot be read', () {
      expect(reasonsFor(recordJson(overrides: {'createdAt': 'yesterday'})), [
        'Missing or invalid "createdAt".',
      ]);
      expect(reasonsFor(recordJson(overrides: {'updatedAt': 20260925})), [
        'Missing or invalid "updatedAt".',
      ]);
    });

    test('blank required text', () {
      expect(reasonsFor(recordJson(overrides: {'name': '   '})), [
        'Name is required.',
      ]);
      expect(reasonsFor(recordJson(overrides: {'nrc': '', 'major': ' '})), [
        'NRC is required.',
        'Major is required.',
      ]);
    });

    test('a blank id', () {
      expect(reasonsFor(recordJson(overrides: {'id': '  '})), [
        'The record has no id.',
      ]);
    });

    test('breaks of the registration form rules', () {
      expect(reasonsFor(recordJson(overrides: {'email': 'not-an-email'})), [
        'Email is not valid.',
      ]);
      expect(reasonsFor(recordJson(overrides: {'phoneNo': 'abc'})), [
        'Phone No. is not valid.',
      ]);
      expect(
        reasonsFor(
          recordJson(
            overrides: {
              'currentCountry': CurrentCountry.other.storageValue,
              'otherCountry': null,
            },
          ),
        ),
        ['Other Country is required when Current Country is Other.'],
      );
    });

    test('keeps the good records around a bad one', () {
      final parsed = _parser.parse(
        jsonBytes(
          backupJson([
            recordJson(id: 'a', rollNo: 'A', nrc: 'na'),
            recordJson(
              id: 'b',
              rollNo: 'B',
              nrc: 'nb',
              overrides: {'name': ''},
            ),
            recordJson(id: 'c', rollNo: 'C', nrc: 'nc'),
          ]),
        ),
      );

      expect(parsed.valid.map((r) => r.registration.id), ['a', 'c']);
      expect(parsed.valid.map((r) => r.index), [1, 3]);
      expect(parsed.invalid.single.index, 2);
      expect(parsed.totalRecords, 3);
    });

    test('names the record by Roll No., or by name, or not at all', () {
      final parsed = _parser.parse(
        jsonBytes(
          backupJson([
            recordJson(rollNo: 'CS-7', overrides: {'name': ''}),
            recordJson(remove: ['rollNo', 'major']),
            {'x': 1},
          ]),
        ),
      );

      expect(parsed.invalid[0].label, 'CS-7');
      expect(parsed.invalid[0].description, 'Record 1 (CS-7)');
      expect(parsed.invalid[1].label, 'Aung Aung');
      expect(parsed.invalid[2].label, isNull);
      expect(parsed.invalid[2].description, 'Record 3');
    });

    test('accounts for every record, valid or not', () {
      final parsed = _parser.parse(
        jsonBytes(
          backupJson([
            recordJson(id: 'a', rollNo: 'A', nrc: 'na'),
            null,
            recordJson(
              id: 'c',
              rollNo: 'C',
              nrc: 'nc',
              overrides: {'email': 'x'},
            ),
            recordJson(id: 'd', rollNo: 'D', nrc: 'nd'),
          ]),
        ),
      );

      expect(parsed.valid.length + parsed.invalid.length, parsed.totalRecords);
    });
  });
}
