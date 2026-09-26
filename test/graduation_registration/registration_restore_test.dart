import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/datasources/graduation_registration_local_datasource.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/local/app_database.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/repositories/graduation_registration_repository_impl.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/failures.dart';

import 'support/sample_registrations.dart';

/// Reports no stored registrations the first time it is asked, as if another
/// tab stored a clashing record right after the repository looked.
class _StaleReadDataSource extends GraduationRegistrationLocalDataSource {
  _StaleReadDataSource(super.appDatabase);

  bool _stale = true;

  @override
  Future<List<GraduationRegistration>> getAll() async {
    if (!_stale) return super.getAll();
    _stale = false;
    return [];
  }
}

void main() {
  late AppDatabase appDatabase;
  late GraduationRegistrationLocalDataSource dataSource;
  late GraduationRegistrationRepositoryImpl repository;
  var generatedIds = 0;
  var clockReads = 0;

  setUp(() {
    appDatabase = AppDatabase(factory: newIdbFactoryMemory());
    dataSource = GraduationRegistrationLocalDataSource(appDatabase);
    generatedIds = 0;
    clockReads = 0;
    repository = GraduationRegistrationRepositoryImpl(
      dataSource,
      now: () {
        clockReads++;
        return DateTime.utc(2030);
      },
      generateId: () => 'generated-${generatedIds++}',
    );
  });

  tearDown(() => appDatabase.close());

  final stored = sampleRegistration(
    id: 'stored',
    name: 'Already Here',
    rollNo: 'CS-900',
    nrc: '12/LAMANA(N)900900',
  );

  Future<void> seed() => dataSource.insert(stored);

  Future<List<GraduationRegistration>> everything() => dataSource.getAll();

  group('datasource insertAll (one transaction)', () {
    test('stores every registration', () async {
      await dataSource.insertAll(sampleRegistrations());

      expect(await everything(), sampleRegistrations());
    });

    test('does nothing for an empty list', () async {
      await seed();

      await dataSource.insertAll([]);

      expect(await everything(), [stored]);
    });

    test(
      'stores nothing if a later record clashes with a stored one',
      () async {
        await seed();
        final batch = [
          sampleRegistration(id: 'a', rollNo: 'A-1', nrc: 'nrc-a'),
          sampleRegistration(id: 'b', rollNo: 'B-1', nrc: 'nrc-b'),
          // Same Roll No. as the stored record, so the unique index rejects it.
          sampleRegistration(id: 'c', rollNo: 'CS-900', nrc: 'nrc-c'),
        ];

        await expectLater(
          dataSource.insertAll(batch),
          throwsA(isA<DatabaseError>()),
        );

        expect(await everything(), [stored]);
      },
    );

    test('stores nothing if two records of the batch share an NRC', () async {
      final batch = [
        sampleRegistration(id: 'a', rollNo: 'A-1', nrc: 'same-nrc'),
        sampleRegistration(id: 'b', rollNo: 'B-1', nrc: 'same-nrc'),
      ];

      await expectLater(
        dataSource.insertAll(batch),
        throwsA(isA<DatabaseError>()),
      );

      expect(await everything(), isEmpty);
    });

    test('stores nothing if two records of the batch share an id', () async {
      final batch = [
        sampleRegistration(id: 'same', rollNo: 'A-1', nrc: 'nrc-a'),
        sampleRegistration(id: 'same', rollNo: 'B-1', nrc: 'nrc-b'),
      ];

      await expectLater(
        dataSource.insertAll(batch),
        throwsA(isA<DatabaseError>()),
      );

      expect(await everything(), isEmpty);
    });

    test('leaves the database usable after a failed batch', () async {
      await expectLater(
        dataSource.insertAll([
          sampleRegistration(id: 'same', rollNo: 'A-1', nrc: 'nrc-a'),
          sampleRegistration(id: 'same', rollNo: 'B-1', nrc: 'nrc-b'),
        ]),
        throwsA(isA<DatabaseError>()),
      );

      await dataSource.insertAll(sampleRegistrations());

      expect(await everything(), hasLength(4));
    });
  });

  group('repository restoreAll', () {
    test('stores registrations exactly, ids and dates included', () async {
      final backup = [
        sampleRegistration(
          id: 'original-1',
          createdAt: DateTime.utc(2020, 1, 2, 3, 4, 5),
          updatedAt: DateTime.utc(2021, 6, 7, 8, 9, 10),
        ),
        sampleRegistration(
          id: 'original-2',
          name: 'Second',
          rollNo: 'CS-002',
          nrc: '12/LAMANA(N)222222',
          createdAt: DateTime.utc(2020, 2, 2),
          updatedAt: DateTime.utc(2020, 3, 3),
        ),
      ];

      await repository.restoreAll(backup);

      expect(await repository.getAll(), backup);
      expect(await repository.getById('original-2'), backup[1]);
    });

    test('does not stamp new ids or new dates', () async {
      await repository.restoreAll(sampleRegistrations());

      expect(generatedIds, 0);
      expect(clockReads, 0);
      final restored = await repository.getAll();
      expect(restored.map((r) => r.id), ['r1', 'r2', 'r3', 'r4']);
      expect(restored.first.createdAt, DateTime.utc(2026, 9, 1, 12));
    });

    test('does nothing for an empty list', () async {
      await seed();

      await repository.restoreAll([]);

      expect(await everything(), [stored]);
    });

    test(
      'leaves the registrations that are already stored untouched',
      () async {
        await seed();

        await repository.restoreAll(sampleRegistrations());

        final all = await repository.getAll();
        expect(all, hasLength(5));
        expect(all.contains(stored), isTrue);
        expect(await repository.getById('stored'), stored);
      },
    );

    test('rebuilds the Roll No. and NRC lookups', () async {
      await repository.restoreAll(sampleRegistrations());

      expect(await repository.isRollNoTaken('cs-001'), isTrue);
      expect(await repository.isRollNoTaken(' LW - 002 '), isTrue);
      expect(await repository.isRollNoTaken('LW-002'), isTrue);
      expect(await repository.isNrcTaken('12/LAMANA(N)222222'), isTrue);
      expect(await repository.isNrcTaken('၁၂/lamana(n)၂၂၂၂၂၂'), isTrue);
      await expectLater(
        repository.create(
          GraduationRegistration.draft(
            name: 'Newcomer',
            fatherName: 'U New',
            phoneNo: '0912345678',
            nrc: '12/OTHER(N)1',
            rollNo: 'CS-001',
            major: 'Law',
            attendanceStatus: AttendanceStatus.canAttend,
            currentCountry: CurrentCountry.japan,
          ),
        ),
        throwsA(isA<DuplicateRollNoFailure>()),
      );
    });

    test(
      'restored registrations can be edited and deleted afterwards',
      () async {
        await repository.restoreAll(sampleRegistrations());

        final edited = await repository.update(
          (await repository.getById('r1'))!.copyWith(major: 'Law'),
        );
        await repository.delete('r2');

        expect(edited.major, 'Law');
        expect(edited.createdAt, DateTime.utc(2026, 9, 1, 12));
        expect((await repository.getAll()).map((r) => r.id), [
          'r1',
          'r3',
          'r4',
        ]);
      },
    );

    test('trims text, like every other way of saving', () async {
      await repository.restoreAll([
        sampleRegistration(name: '  Spaced Out  ', currentCity: '   '),
      ]);

      final restored = (await repository.getAll()).single;
      expect(restored.name, 'Spaced Out');
      expect(restored.currentCity, isNull);
    });

    test('restores a large backup', () async {
      final many = [
        for (var i = 0; i < 2000; i++)
          sampleRegistration(
            id: 'id-$i',
            name: 'Person $i',
            rollNo: 'CS-$i',
            nrc: '12/LAMANA(N)$i',
          ),
      ];

      await repository.restoreAll(many);

      expect(await repository.getAll(), hasLength(2000));
      expect(await repository.isNrcTaken('12/LAMANA(N)1999'), isTrue);
    });
  });

  group('repository restoreAll is all or nothing', () {
    /// Restores [batch] on top of one stored registration and checks that the
    /// call failed and that nothing at all was added.
    Future<void> expectRejected(
      List<GraduationRegistration> batch,
      Matcher failure,
    ) async {
      await seed();

      await expectLater(repository.restoreAll(batch), throwsA(failure));

      expect(await everything(), [stored]);
    }

    final goodFirst = sampleRegistration(
      id: 'good',
      name: 'Good Record',
      rollNo: 'CS-777',
      nrc: '12/LAMANA(N)777777',
    );

    test('a clashing id stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 'stored', rollNo: 'CS-1', nrc: 'nrc-1'),
      ], isA<DuplicateIdFailure>());
    });

    test('a clashing Roll No. stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 'x', rollNo: ' cs-900 ', nrc: 'nrc-1'),
      ], isA<DuplicateRollNoFailure>());
    });

    test('a clashing NRC stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 'x', rollNo: 'CS-1', nrc: '12/lamana(n) 900900'),
      ], isA<DuplicateNrcFailure>());
    });

    test('a repeated id within the batch stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 'twin', rollNo: 'T-1', nrc: 'nrc-t1'),
        sampleRegistration(id: 'twin', rollNo: 'T-2', nrc: 'nrc-t2'),
      ], isA<DuplicateIdFailure>());
    });

    test('a repeated Roll No. within the batch stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 't1', rollNo: 'T-1', nrc: 'nrc-t1'),
        sampleRegistration(id: 't2', rollNo: 't-1', nrc: 'nrc-t2'),
      ], isA<DuplicateRollNoFailure>());
    });

    test('a repeated NRC within the batch stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 't1', rollNo: 'T-1', nrc: 'nrc-t'),
        sampleRegistration(id: 't2', rollNo: 'T-2', nrc: 'NRC-T'),
      ], isA<DuplicateNrcFailure>());
    });

    test('an invalid record stores nothing, not even the valid ones', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: 'bad', name: '   ', rollNo: 'B-1', nrc: 'n-b'),
      ], isA<ValidationFailure>());
    });

    test('a record without an id stores nothing', () {
      return expectRejected([
        goodFirst,
        sampleRegistration(id: '  ', rollNo: 'B-1', nrc: 'n-b'),
      ], isA<ArgumentError>());
    });

    test('a clash found only by the database stores nothing', () async {
      // Another tab stored a clashing record after the repository read the
      // database, so only the unique index catches it.
      await seed();
      final racing = GraduationRegistrationRepositoryImpl(
        _StaleReadDataSource(appDatabase),
      );

      await expectLater(
        racing.restoreAll([
          goodFirst,
          sampleRegistration(id: 'x', rollNo: 'CS-900', nrc: 'nrc-x'),
        ]),
        throwsA(isA<DuplicateRollNoFailure>()),
      );

      expect(await everything(), [stored]);
    });

    test('can be retried once the problem is fixed', () async {
      await seed();
      await expectLater(
        repository.restoreAll([
          goodFirst,
          sampleRegistration(id: 'x', rollNo: 'CS-900', nrc: 'nrc-x'),
        ]),
        throwsA(isA<DuplicateRollNoFailure>()),
      );

      await repository.restoreAll([goodFirst]);

      expect(
        (await everything()).map((r) => r.id),
        unorderedEquals(['stored', 'good']),
      );
    });
  });
}
