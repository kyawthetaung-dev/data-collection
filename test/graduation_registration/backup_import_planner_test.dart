import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/backup_import_planner.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_backup_parser.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';

import 'support/backup_test_data.dart';
import 'support/sample_registrations.dart';

const _parser = RegistrationBackupParser();
const _planner = BackupImportPlanner();

/// The plan for importing a file holding [records] into a database holding
/// [existing].
ImportPlan planFor(
  List<Object?> records, {
  List<GraduationRegistration> existing = const [],
}) {
  final backup = _parser.parse(jsonBytes(backupJson(records)));
  return _planner.plan(backup, existing);
}

/// A backup record for [r].
Map<String, Object?> recordFor(GraduationRegistration r) => recordOf(r);

List<String> idsOf(ImportPlan plan) => [for (final r in plan.toImport) r.id];

Map<String, DuplicateReason> reasonsById(ImportPlan plan) => {
  for (final d in plan.duplicates) d.registration.id: d.reason,
};

void main() {
  final backup = sampleRegistrations();
  final backupRecords = [for (final r in backup) recordFor(r)];

  group('new records', () {
    test('into an empty database, everything is new', () {
      final plan = planFor(backupRecords);

      expect(plan.newCount, 4);
      expect(plan.duplicateCount, 0);
      expect(plan.invalidCount, 0);
      expect(plan.totalRecords, 4);
      expect(plan.toImport, backup);
    });

    test('keep the order of the file', () {
      final plan = planFor(backupRecords.reversed.toList());

      expect(idsOf(plan), ['r4', 'r3', 'r2', 'r1']);
    });

    test('are found among unrelated stored records', () {
      final stored = sampleRegistration(
        id: 'other',
        rollNo: 'ZZ-1',
        nrc: '12/ZZ(N)1',
      );

      final plan = planFor(backupRecords, existing: [stored]);

      expect(plan.newCount, 4);
      expect(plan.duplicateCount, 0);
    });

    test('an empty backup has nothing to do', () {
      final plan = planFor([]);

      expect(plan.totalRecords, 0);
      expect(plan.newCount + plan.duplicateCount + plan.invalidCount, 0);
    });
  });

  group('duplicates: identified by id', () {
    test('an identical stored record is already present', () {
      final plan = planFor(backupRecords, existing: [backup[1]]);

      expect(idsOf(plan), ['r1', 'r3', 'r4']);
      expect(reasonsById(plan), {'r2': DuplicateReason.alreadyPresent});
    });

    test('every record already stored means nothing is new', () {
      final plan = planFor(backupRecords, existing: backup);

      expect(plan.newCount, 0);
      expect(plan.duplicatesOf(DuplicateReason.alreadyPresent), 4);
    });

    test(
      'a stored record with the same id but different data is a conflict',
      () {
        final edited = backup[0].copyWith(name: 'Edited Since The Backup');

        final plan = planFor(backupRecords, existing: [edited]);

        expect(reasonsById(plan), {'r1': DuplicateReason.sameIdDifferentData});
        expect(plan.newCount, 3);
      },
    );

    test('a different update time alone counts as different data', () {
      final touched = backup[0].copyWith(updatedAt: DateTime.utc(2030));

      final plan = planFor(backupRecords, existing: [touched]);

      expect(reasonsById(plan)['r1'], DuplicateReason.sameIdDifferentData);
    });

    test('a same-id record is never taken for new, even with new numbers', () {
      final stored = backup[0].copyWith(rollNo: 'CHANGED', nrc: 'CHANGED');

      final plan = planFor(backupRecords, existing: [stored]);

      expect(reasonsById(plan)['r1'], DuplicateReason.sameIdDifferentData);
      expect(idsOf(plan), isNot(contains('r1')));
    });
  });

  group('duplicates: Roll No. and NRC of a different record', () {
    test('a different id with the same Roll No. is skipped', () {
      final stored = sampleRegistration(
        id: 'someone-else',
        rollNo: 'CS-001',
        nrc: '12/OTHER(N)1',
      );

      final plan = planFor(backupRecords, existing: [stored]);

      expect(reasonsById(plan), {'r1': DuplicateReason.rollNoTaken});
      expect(plan.newCount, 3);
    });

    test('a different id with the same NRC is skipped', () {
      final stored = sampleRegistration(
        id: 'someone-else',
        rollNo: 'OTHER-1',
        nrc: '12/LAMANA(N)222222',
      );

      final plan = planFor(backupRecords, existing: [stored]);

      expect(reasonsById(plan), {'r2': DuplicateReason.nrcTaken});
    });

    test('compares ignoring case, spacing and digit script', () {
      final stored = [
        sampleRegistration(id: 'a', rollNo: ' cs - 001 ', nrc: 'x1'),
        sampleRegistration(id: 'b', rollNo: 'x2', nrc: '၁၂/lamana(n) ၂၂၂၂၂၂'),
      ];

      final plan = planFor(backupRecords, existing: stored);

      expect(reasonsById(plan), {
        'r1': DuplicateReason.rollNoTaken,
        'r2': DuplicateReason.nrcTaken,
      });
    });

    test('reports the Roll No. when both Roll No. and NRC clash', () {
      final stored = sampleRegistration(
        id: 'someone-else',
        rollNo: 'CS-001',
        nrc: '12/LAMANA(N)111111',
      );

      final plan = planFor(backupRecords, existing: [stored]);

      expect(reasonsById(plan)['r1'], DuplicateReason.rollNoTaken);
    });

    test('Roll No. and NRC clashing with different stored records', () {
      final stored = [
        sampleRegistration(id: 'a', rollNo: 'CS-001', nrc: 'x1'),
        sampleRegistration(id: 'b', rollNo: 'x2', nrc: '12/LAMANA(N)111111'),
      ];

      final plan = planFor([backupRecords[0]], existing: stored);

      expect(plan.newCount, 0);
      expect(plan.duplicateCount, 1);
    });
  });

  group('duplicates: within the file', () {
    test('a repeated id keeps the first', () {
      final first = recordJson(id: 'twin', rollNo: 'T-1', nrc: 'nt1');
      final second = recordJson(id: 'twin', rollNo: 'T-2', nrc: 'nt2');

      final plan = planFor([first, second]);

      expect(idsOf(plan), ['twin']);
      expect(plan.toImport.single.rollNo, 'T-1');
      expect(plan.duplicates.single.reason, DuplicateReason.repeatedInFile);
      expect(plan.duplicates.single.index, 2);
    });

    test('a repeated Roll No. keeps the first', () {
      final plan = planFor([
        recordJson(id: 'a', rollNo: 'CS-9', nrc: 'na'),
        recordJson(id: 'b', rollNo: 'cs-9', nrc: 'nb'),
      ]);

      expect(idsOf(plan), ['a']);
      expect(reasonsById(plan), {'b': DuplicateReason.repeatedInFile});
    });

    test('a repeated NRC keeps the first', () {
      final plan = planFor([
        recordJson(id: 'a', rollNo: 'A', nrc: '12/LAMANA(N)5'),
        recordJson(id: 'b', rollNo: 'B', nrc: '12/lamana(n) 5'),
      ]);

      expect(idsOf(plan), ['a']);
      expect(reasonsById(plan), {'b': DuplicateReason.repeatedInFile});
    });

    test('a record skipped for clashing with a stored one does not count', () {
      // "b" repeats "a", but "a" is skipped, so "b" clashes with the stored
      // record itself and is skipped for that instead.
      final stored = sampleRegistration(id: 's', rollNo: 'CS-9', nrc: 'ns');

      final plan = planFor(
        [
          recordJson(id: 'a', rollNo: 'CS-9', nrc: 'na'),
          recordJson(id: 'b', rollNo: 'CS-9', nrc: 'nb'),
        ],
        existing: [stored],
      );

      expect(plan.newCount, 0);
      expect(reasonsById(plan), {
        'a': DuplicateReason.rollNoTaken,
        'b': DuplicateReason.rollNoTaken,
      });
    });
  });

  group('invalid records', () {
    test('are counted and never imported', () {
      final plan = planFor([
        backupRecords[0],
        recordJson(id: 'bad', overrides: {'name': ''}),
        null,
        backupRecords[1],
      ]);

      expect(plan.totalRecords, 4);
      expect(idsOf(plan), ['r1', 'r2']);
      expect(plan.invalidCount, 2);
      expect(plan.invalid.map((r) => r.index), [2, 3]);
    });

    test('are not compared with stored records', () {
      final stored = sampleRegistration(id: 'bad', rollNo: 'CS-001');

      final plan = planFor(
        [
          recordJson(id: 'bad', overrides: {'name': ''}),
        ],
        existing: [stored],
      );

      expect(plan.invalidCount, 1);
      expect(plan.duplicateCount, 0);
    });
  });

  group('every record is accounted for', () {
    test('new plus duplicates plus invalid is the total', () {
      final stored = [
        backup[1],
        sampleRegistration(id: 'x', rollNo: 'LW-001', nrc: 'nx'),
      ];
      final plan = planFor([
        ...backupRecords,
        null,
        recordJson(id: 'r1', rollNo: 'CS-1', nrc: 'again'),
        recordJson(id: 'z', overrides: {'email': 'bad'}),
      ], existing: stored);

      expect(
        plan.newCount + plan.duplicateCount + plan.invalidCount,
        plan.totalRecords,
      );
      expect(plan.totalRecords, 7);
    });

    test('the four counts add up in a mixed import', () {
      final plan = planFor(
        [
          ...backupRecords, // r1, r2 (stored), r3, r4
          recordJson(id: 'bad', overrides: {'phoneNo': 'no'}),
        ],
        existing: [backup[1]],
      );

      expect(plan.totalRecords, 5);
      expect(plan.newCount, 3);
      expect(plan.duplicateCount, 1);
      expect(plan.invalidCount, 1);
    });
  });

  group('safety', () {
    test('never changes the stored registrations it is given', () {
      final existing = List<GraduationRegistration>.unmodifiable([
        backup[0],
        backup[1],
      ]);
      final before = List.of(existing);

      planFor(backupRecords, existing: existing);

      expect(existing, before);
    });

    test('is deterministic', () {
      final a = planFor(backupRecords, existing: [backup[2]]);
      final b = planFor(backupRecords, existing: [backup[2]]);

      expect(idsOf(a), idsOf(b));
      expect(reasonsById(a), reasonsById(b));
    });

    test('plans a large backup quickly', () {
      final many = [
        for (var i = 0; i < 5000; i++)
          recordJson(id: 'id-$i', name: 'P$i', rollNo: 'R-$i', nrc: 'N-$i'),
      ];
      final stored = [
        for (var i = 0; i < 2500; i++)
          sampleRegistration(
            id: 'id-$i',
            name: 'P$i',
            rollNo: 'R-$i',
            nrc: 'N-$i',
          ),
      ];
      final watch = Stopwatch()..start();

      final plan = planFor(many, existing: stored);

      watch.stop();
      expect(plan.newCount, 2500);
      expect(plan.duplicateCount, 2500);
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
