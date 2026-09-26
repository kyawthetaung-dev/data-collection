import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/datasources/graduation_registration_local_datasource.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/local/app_database.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/repositories/graduation_registration_repository_impl.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/failures.dart';

GraduationRegistration draft({
  String name = 'Aung Aung',
  String rollNo = 'CS-001',
  String nrc = '12/LAMANA(N)123456',
  String phoneNo = '+95 9 123 456 789',
  CurrentCountry currentCountry = CurrentCountry.myanmar,
  String? otherCountry,
  String? motherName,
  String? email,
}) {
  return GraduationRegistration.draft(
    name: name,
    fatherName: 'U Kyaw',
    motherName: motherName,
    phoneNo: phoneNo,
    nrc: nrc,
    rollNo: rollNo,
    major: 'Computer Science',
    attendanceStatus: AttendanceStatus.canAttend,
    currentCountry: currentCountry,
    otherCountry: otherCountry,
    email: email,
  );
}

/// Reports the first lookup of each kind as "not taken", as if another tab
/// wrote the record right after the repository checked.
class _StaleCheckDataSource extends GraduationRegistrationLocalDataSource {
  _StaleCheckDataSource(super.appDatabase);

  bool _rollNoStale = true;
  bool _nrcStale = true;

  @override
  Future<String?> findIdByRollNo(String rollNo) async {
    if (!_rollNoStale) return super.findIdByRollNo(rollNo);
    _rollNoStale = false;
    return null;
  }

  @override
  Future<String?> findIdByNrc(String nrc) async {
    if (!_nrcStale) return super.findIdByNrc(nrc);
    _nrcStale = false;
    return null;
  }
}

void main() {
  late IdbFactory factory;
  late AppDatabase appDatabase;
  late GraduationRegistrationLocalDataSource dataSource;
  late GraduationRegistrationRepositoryImpl repository;
  late DateTime clock;
  late int nextId;

  GraduationRegistrationRepositoryImpl newRepository(
    GraduationRegistrationLocalDataSource source,
  ) {
    return GraduationRegistrationRepositoryImpl(
      source,
      now: () => clock,
      generateId: () => 'id-${nextId++}',
    );
  }

  setUp(() {
    factory = newIdbFactoryMemory();
    appDatabase = AppDatabase(factory: factory);
    dataSource = GraduationRegistrationLocalDataSource(appDatabase);
    clock = DateTime.utc(2026, 9, 25, 10);
    nextId = 1;
    repository = newRepository(dataSource);
  });

  tearDown(() => appDatabase.close());

  group('create', () {
    test('assigns an id and sets both dates to now', () async {
      final saved = await repository.create(draft());

      expect(saved.id, 'id-1');
      expect(saved.createdAt, clock);
      expect(saved.updatedAt, clock);
      expect(await repository.getById('id-1'), saved);
    });

    test('ignores an id and dates supplied by the caller', () async {
      final saved = await repository.create(
        draft().copyWith(
          id: 'caller-id',
          createdAt: DateTime.utc(2000),
          updatedAt: DateTime.utc(2001),
        ),
      );

      expect(saved.id, 'id-1');
      expect(saved.createdAt, clock);
      expect(saved.updatedAt, clock);
    });

    test('trims text and turns blank optional text into null', () async {
      final saved = await repository.create(
        draft(
          name: '  Aung Aung ',
          rollNo: ' CS-001 ',
          motherName: '   ',
          email: '',
        ),
      );

      expect(saved.name, 'Aung Aung');
      expect(saved.rollNo, 'CS-001');
      expect(saved.motherName, isNull);
      expect(saved.email, isNull);
    });

    test('drops Other Country unless the country is Other', () async {
      final myanmar = await repository.create(draft(otherCountry: 'Thailand'));
      final other = await repository.create(
        draft(
          rollNo: 'CS-002',
          nrc: '12/LAMANA(N)000002',
          currentCountry: CurrentCountry.other,
          otherCountry: ' Thailand ',
        ),
      );

      expect(myanmar.otherCountry, isNull);
      expect(other.otherCountry, 'Thailand');
    });

    test('rejects an invalid registration and stores nothing', () async {
      await expectLater(
        repository.create(draft(name: ' ', phoneNo: 'abc')),
        throwsA(
          isA<ValidationFailure>().having((f) => f.errors.keys, 'fields', {
            RegistrationField.name,
            RegistrationField.phoneNo,
          }),
        ),
      );
      expect(await repository.getAll(), isEmpty);
    });

    test('rejects a duplicate Roll No.', () async {
      await repository.create(draft());

      await expectLater(
        repository.create(draft(nrc: '12/LAMANA(N)000002')),
        throwsA(isA<DuplicateRollNoFailure>()),
      );
      expect(await repository.getAll(), hasLength(1));
    });

    test('rejects a duplicate NRC', () async {
      await repository.create(draft());

      await expectLater(
        repository.create(draft(rollNo: 'CS-002')),
        throwsA(isA<DuplicateNrcFailure>()),
      );
      expect(await repository.getAll(), hasLength(1));
    });

    test('treats case, spacing and Myanmar digits as the same value', () async {
      await repository.create(
        draft(rollNo: 'CS-001', nrc: '12/LAMANA(N)123456'),
      );

      await expectLater(
        repository.create(
          draft(rollNo: ' cs - 001 ', nrc: '12/LAMANA(N)000002'),
        ),
        throwsA(isA<DuplicateRollNoFailure>()),
      );
      await expectLater(
        repository.create(draft(rollNo: 'CS-002', nrc: '၁၂/lamana(n) ၁၂၃၄၅၆')),
        throwsA(isA<DuplicateNrcFailure>()),
      );
    });

    test('reports a duplicate created by another tab mid-write', () async {
      await repository.create(draft());
      final stale = newRepository(_StaleCheckDataSource(appDatabase));

      await expectLater(
        stale.create(draft(nrc: '12/LAMANA(N)000002')),
        throwsA(isA<DuplicateRollNoFailure>()),
      );
      await expectLater(
        stale.create(draft(rollNo: 'CS-002')),
        throwsA(isA<DuplicateNrcFailure>()),
      );
      expect(await repository.getAll(), hasLength(1));
    });
  });

  group('read', () {
    test('getAll returns registrations oldest first', () async {
      await repository.create(draft(name: 'First'));
      clock = clock.add(const Duration(minutes: 5));
      await repository.create(
        draft(name: 'Second', rollNo: 'CS-002', nrc: '12/LAMANA(N)000002'),
      );

      final all = await repository.getAll();
      expect(all.map((r) => r.name), ['First', 'Second']);
    });

    test('getAll is empty on a new database', () async {
      expect(await repository.getAll(), isEmpty);
    });

    test('getById returns null for an unknown id', () async {
      expect(await repository.getById('missing'), isNull);
    });
  });

  group('update', () {
    test('keeps createdAt and refreshes updatedAt', () async {
      final created = await repository.create(draft());
      clock = clock.add(const Duration(hours: 2));

      final updated = await repository.update(
        created.copyWith(
          name: 'Aung Aung Updated',
          createdAt: DateTime.utc(1999),
          updatedAt: DateTime.utc(1999),
        ),
      );

      expect(updated.name, 'Aung Aung Updated');
      expect(updated.createdAt, created.createdAt);
      expect(updated.updatedAt, clock);
      expect(await repository.getById(created.id), updated);
    });

    test('can clear an optional field with a blank value', () async {
      final created = await repository.create(draft(motherName: 'Daw Mya'));

      final updated = await repository.update(created.copyWith(motherName: ''));

      expect(updated.motherName, isNull);
    });

    test('lets a registration keep its own Roll No. and NRC', () async {
      final created = await repository.create(draft());

      final updated = await repository.update(created.copyWith(major: 'Law'));

      expect(updated.major, 'Law');
    });

    test('lets a registration change its Roll No. and NRC', () async {
      final created = await repository.create(draft());

      await repository.update(
        created.copyWith(rollNo: 'CS-009', nrc: '12/LAMANA(N)000009'),
      );

      expect(await repository.isRollNoTaken('CS-001'), isFalse);
      expect(await repository.isRollNoTaken('CS-009'), isTrue);
      expect(await repository.isNrcTaken('12/LAMANA(N)123456'), isFalse);
      expect(await repository.isNrcTaken('12/LAMANA(N)000009'), isTrue);
    });

    test('rejects another registration\'s Roll No. or NRC', () async {
      await repository.create(draft());
      final second = await repository.create(
        draft(rollNo: 'CS-002', nrc: '12/LAMANA(N)000002'),
      );

      await expectLater(
        repository.update(second.copyWith(rollNo: 'CS-001')),
        throwsA(isA<DuplicateRollNoFailure>()),
      );
      await expectLater(
        repository.update(second.copyWith(nrc: '12/LAMANA(N)123456')),
        throwsA(isA<DuplicateNrcFailure>()),
      );
      expect(await repository.getById(second.id), second);
    });

    test('rejects an invalid registration and keeps the stored one', () async {
      final created = await repository.create(draft());

      await expectLater(
        repository.update(created.copyWith(name: ' ')),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await repository.getById(created.id), created);
    });

    test('throws NotFoundFailure for an unknown id', () async {
      await expectLater(
        repository.update(draft().copyWith(id: 'missing')),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('delete', () {
    test('removes the registration and frees its Roll No. and NRC', () async {
      final created = await repository.create(draft());

      await repository.delete(created.id);

      expect(await repository.getById(created.id), isNull);
      expect(await repository.isRollNoTaken('CS-001'), isFalse);
      expect(await repository.isNrcTaken('12/LAMANA(N)123456'), isFalse);
      await repository.create(draft());
    });

    test('throws NotFoundFailure for an unknown id', () async {
      await expectLater(
        repository.delete('missing'),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('duplicate checks', () {
    test('report whether a value is in use', () async {
      await repository.create(draft());

      expect(await repository.isRollNoTaken('CS-001'), isTrue);
      expect(await repository.isRollNoTaken('CS-999'), isFalse);
      expect(await repository.isNrcTaken('12/LAMANA(N)123456'), isTrue);
      expect(await repository.isNrcTaken('12/LAMANA(N)999999'), isFalse);
    });

    test('ignore the excluded registration', () async {
      final created = await repository.create(draft());

      expect(
        await repository.isRollNoTaken('CS-001', excludeId: created.id),
        isFalse,
      );
      expect(
        await repository.isNrcTaken(
          '12/LAMANA(N)123456',
          excludeId: created.id,
        ),
        isFalse,
      );
      expect(
        await repository.isRollNoTaken('CS-001', excludeId: 'someone-else'),
        isTrue,
      );
    });

    test('never report a blank value as taken', () async {
      await repository.create(draft());

      expect(await repository.isRollNoTaken('  '), isFalse);
      expect(await repository.isNrcTaken(''), isFalse);
    });
  });

  group('persistence', () {
    test('data survives closing and reopening the database', () async {
      final created = await repository.create(draft());
      await appDatabase.close();

      final reopened = newRepository(
        GraduationRegistrationLocalDataSource(AppDatabase(factory: factory)),
      );

      expect(await reopened.getAll(), [created]);
      await expectLater(
        reopened.create(draft()),
        throwsA(isA<DuplicateRollNoFailure>()),
      );
    });
  });

  group('GraduationRegistration map', () {
    test('toMap and fromMap round-trip every field', () {
      final registration = GraduationRegistration(
        id: 'id-1',
        name: 'Aung Aung',
        fatherName: 'U Kyaw',
        motherName: 'Daw Mya',
        phoneNo: '0912345678',
        nrc: '12/LAMANA(N)123456',
        rollNo: 'CS-001',
        major: 'Computer Science',
        attendanceStatus: AttendanceStatus.cannotAttend,
        currentCountry: CurrentCountry.other,
        otherCountry: 'Thailand',
        currentCity: 'Bangkok',
        email: 'aung@example.com',
        remark: 'Line 1\nLine 2',
        createdAt: DateTime.utc(2026, 9, 25, 10, 30, 15, 123),
        updatedAt: DateTime.utc(2026, 9, 26),
      );

      expect(
        GraduationRegistration.fromMap(registration.toMap()),
        registration,
      );
    });

    test('fromMap rejects a record with missing or malformed values', () {
      final valid = draft().copyWith(id: 'id-1').toMap();

      for (final broken in [
        {...valid, 'name': null},
        {...valid, 'rollNo': 5},
        {...valid, 'attendanceStatus': 'maybe'},
        {...valid, 'currentCountry': null},
        {...valid, 'createdAt': 'yesterday'},
      ]) {
        expect(
          () => GraduationRegistration.fromMap(broken),
          throwsFormatException,
          reason: '$broken',
        );
      }
    });

    test('normalizeLookupKey ignores case, whitespace and digit script', () {
      expect(normalizeLookupKey(' 12/LaMaNa(N) ၁၂၃ '), '12/lamana(n)123');
    });
  });
}
