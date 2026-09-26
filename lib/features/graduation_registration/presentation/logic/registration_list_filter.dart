import '../../domain/entities/graduation_registration.dart';
import '../../domain/entities/registration_enums.dart';

/// A registration together with its position in the full, unfiltered list.
///
/// The number stays the same whatever is searched or filtered, so "No. 12" is
/// always the twelfth registration.
class NumberedRegistration {
  const NumberedRegistration(this.number, this.registration);

  final int number;
  final GraduationRegistration registration;
}

/// The search text and filters applied to the registration list.
class RegistrationListFilter {
  const RegistrationListFilter({
    this.query = '',
    this.major,
    this.attendance,
    this.country,
  });

  /// Free text matched against name, NRC, Roll No. and phone.
  final String query;

  /// Only registrations with this major (case and spacing are ignored).
  final String? major;
  final AttendanceStatus? attendance;
  final CurrentCountry? country;

  static final _phoneLike = RegExp(r'^[+0-9၀-၉\s\-()]+$');
  static final _notDigit = RegExp(r'[^0-9]');

  bool get hasSearch => normalizeLookupKey(query).isNotEmpty;

  /// How many of the Major, Attendance and Country filters are set.
  int get dropdownFilterCount =>
      (major == null ? 0 : 1) +
      (attendance == null ? 0 : 1) +
      (country == null ? 0 : 1);

  bool get isActive => hasSearch || dropdownFilterCount > 0;

  /// The registrations in [all] that match, in their original order.
  List<NumberedRegistration> apply(List<GraduationRegistration> all) {
    final queryKey = normalizeLookupKey(query);
    // A query that looks like a phone number also matches across formats, so
    // "0912 345" finds "09-123-456-789".
    final queryDigits = _phoneLike.hasMatch(query.trim())
        ? queryKey.replaceAll(_notDigit, '')
        : '';
    final majorKey = major == null ? null : normalizeLookupKey(major!);

    final result = <NumberedRegistration>[];
    for (var i = 0; i < all.length; i++) {
      final r = all[i];
      if (attendance != null && r.attendanceStatus != attendance) continue;
      if (country != null && r.currentCountry != country) continue;
      if (majorKey != null && normalizeLookupKey(r.major) != majorKey) continue;
      if (queryKey.isNotEmpty && !_matches(r, queryKey, queryDigits)) continue;
      result.add(NumberedRegistration(i + 1, r));
    }
    return result;
  }

  static bool _matches(
    GraduationRegistration r,
    String queryKey,
    String queryDigits,
  ) {
    bool contains(String value) => normalizeLookupKey(value).contains(queryKey);

    if (contains(r.name) ||
        contains(r.nrc) ||
        contains(r.rollNo) ||
        contains(r.phoneNo)) {
      return true;
    }
    return queryDigits.isNotEmpty &&
        normalizeLookupKey(
          r.phoneNo,
        ).replaceAll(_notDigit, '').contains(queryDigits);
  }

  /// The distinct majors in [all], sorted. Spelling variants that differ only
  /// in case or spacing are merged and shown as first written.
  static List<String> majorOptions(List<GraduationRegistration> all) {
    final byKey = <String, String>{};
    for (final r in all) {
      final label = r.major.trim();
      final key = normalizeLookupKey(label);
      if (key.isNotEmpty) byKey.putIfAbsent(key, () => label);
    }
    return byKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
