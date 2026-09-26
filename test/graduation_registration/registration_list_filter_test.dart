import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/logic/registration_list_filter.dart';

import 'support/sample_registrations.dart';

void main() {
  final all = sampleRegistrations();

  List<String> namesOf(RegistrationListFilter filter) =>
      filter.apply(all).map((row) => row.registration.name).toList();

  group('no filter', () {
    test('returns every registration in order, numbered from 1', () {
      const filter = RegistrationListFilter();

      final rows = filter.apply(all);

      expect(rows.map((r) => r.number), [1, 2, 3, 4]);
      expect(rows.map((r) => r.registration.id), ['r1', 'r2', 'r3', 'r4']);
      expect(filter.isActive, isFalse);
      expect(filter.dropdownFilterCount, 0);
    });

    test('a blank search does not count as a filter', () {
      const filter = RegistrationListFilter(query: '   ');

      expect(filter.isActive, isFalse);
      expect(filter.apply(all), hasLength(4));
    });

    test('an empty list gives an empty result', () {
      expect(const RegistrationListFilter().apply([]), isEmpty);
    });
  });

  group('search', () {
    test('matches the name, ignoring case and spacing', () {
      expect(namesOf(const RegistrationListFilter(query: 'AUNG')), [
        'Aung Aung',
      ]);
      expect(namesOf(const RegistrationListFilter(query: ' mya  mya ')), [
        'Mya Mya',
      ]);
    });

    test('matches the NRC', () {
      expect(namesOf(const RegistrationListFilter(query: '333333')), [
        'Kyaw Kyaw',
      ]);
      expect(namesOf(const RegistrationListFilter(query: '12/lamana(n)4')), [
        'Su Su',
      ]);
    });

    test('matches the Roll No.', () {
      expect(namesOf(const RegistrationListFilter(query: 'lw-')), [
        'Kyaw Kyaw',
        'Su Su',
      ]);
      expect(namesOf(const RegistrationListFilter(query: 'CS-002')), [
        'Mya Mya',
      ]);
    });

    test('matches the phone as written', () {
      expect(namesOf(const RegistrationListFilter(query: '0977')), [
        'Kyaw Kyaw',
      ]);
    });

    test('matches the phone across formats', () {
      // Stored as "09-123-456-789" and "+81 90 1234 5678".
      expect(namesOf(const RegistrationListFilter(query: '0912 345')), [
        'Aung Aung',
      ]);
      expect(namesOf(const RegistrationListFilter(query: '+8190')), [
        'Mya Mya',
      ]);
      expect(namesOf(const RegistrationListFilter(query: '90-1234')), [
        'Mya Mya',
      ]);
    });

    test('digits inside a text query do not match phone numbers', () {
      // "cs 9" has a 9 in it, and Aung Aung's phone has a 9, but the query is
      // not phone-like, so only the text fields are searched.
      expect(namesOf(const RegistrationListFilter(query: 'cs 9')), isEmpty);
    });

    test('Myanmar digits match ASCII digits', () {
      expect(namesOf(const RegistrationListFilter(query: '၃၃၃၃၃၃')), [
        'Kyaw Kyaw',
      ]);
    });

    test('does not search other fields', () {
      // Father name, city and remark are not searchable.
      expect(namesOf(const RegistrationListFilter(query: 'Yangon')), isEmpty);
      expect(namesOf(const RegistrationListFilter(query: 'guests')), isEmpty);
      expect(namesOf(const RegistrationListFilter(query: 'U Hla')), isEmpty);
    });

    test('finds nothing for an unknown value', () {
      expect(namesOf(const RegistrationListFilter(query: 'zzz')), isEmpty);
    });
  });

  group('filters', () {
    test('by major, ignoring case', () {
      expect(namesOf(const RegistrationListFilter(major: 'Law')), [
        'Kyaw Kyaw',
        'Su Su',
      ]);
      expect(
        namesOf(const RegistrationListFilter(major: 'COMPUTER  science')),
        ['Aung Aung', 'Mya Mya'],
      );
    });

    test('by attendance status', () {
      expect(
        namesOf(
          const RegistrationListFilter(attendance: AttendanceStatus.canAttend),
        ),
        ['Aung Aung', 'Kyaw Kyaw'],
      );
      expect(
        namesOf(
          const RegistrationListFilter(
            attendance: AttendanceStatus.cannotAttend,
          ),
        ),
        ['Mya Mya', 'Su Su'],
      );
    });

    test('by country', () {
      expect(
        namesOf(const RegistrationListFilter(country: CurrentCountry.japan)),
        ['Mya Mya'],
      );
      expect(
        namesOf(const RegistrationListFilter(country: CurrentCountry.other)),
        ['Kyaw Kyaw'],
      );
      expect(
        namesOf(
          const RegistrationListFilter(country: CurrentCountry.singapore),
        ),
        isEmpty,
      );
    });

    test('combine with each other and with the search', () {
      expect(
        namesOf(
          const RegistrationListFilter(
            major: 'Law',
            attendance: AttendanceStatus.cannotAttend,
          ),
        ),
        ['Su Su'],
      );
      expect(
        namesOf(
          const RegistrationListFilter(
            query: 'lw',
            country: CurrentCountry.other,
          ),
        ),
        ['Kyaw Kyaw'],
      );
      expect(
        namesOf(
          const RegistrationListFilter(
            major: 'Law',
            attendance: AttendanceStatus.canAttend,
            country: CurrentCountry.korea,
          ),
        ),
        isEmpty,
      );
    });

    test('counts the filters that are set', () {
      const filter = RegistrationListFilter(
        major: 'Law',
        country: CurrentCountry.korea,
      );

      expect(filter.dropdownFilterCount, 2);
      expect(filter.isActive, isTrue);
      expect(const RegistrationListFilter(query: 'a').isActive, isTrue);
    });
  });

  group('numbering', () {
    test('stays the same when the list is filtered', () {
      final rows = const RegistrationListFilter(major: 'Law').apply(all);

      expect(rows.map((r) => r.number), [3, 4]);
    });
  });

  group('majorOptions', () {
    test('lists each major once, sorted, spelled as first written', () {
      expect(RegistrationListFilter.majorOptions(all), [
        'Computer Science',
        'Law',
      ]);
    });

    test('ignores blank majors and an empty list', () {
      expect(RegistrationListFilter.majorOptions([]), isEmpty);
      expect(
        RegistrationListFilter.majorOptions([sampleRegistration(major: '  ')]),
        isEmpty,
      );
    });
  });
}
