import 'registration_enums.dart';

/// A graduation registration.
///
/// [id], [createdAt] and [updatedAt] are owned by the repository: it assigns
/// them on create and refreshes [updatedAt] on every update.
class GraduationRegistration {
  const GraduationRegistration({
    required this.id,
    required this.name,
    required this.fatherName,
    this.motherName,
    required this.phoneNo,
    required this.nrc,
    required this.rollNo,
    required this.major,
    required this.attendanceStatus,
    required this.currentCountry,
    this.otherCountry,
    this.currentCity,
    this.email,
    this.remark,
    required this.createdAt,
    required this.updatedAt,
  });

  /// A registration that has not been saved yet, for passing to
  /// `GraduationRegistrationRepository.create`. The placeholder [id] and
  /// timestamps are ignored there and replaced with real values.
  GraduationRegistration.draft({
    required this.name,
    required this.fatherName,
    this.motherName,
    required this.phoneNo,
    required this.nrc,
    required this.rollNo,
    required this.major,
    required this.attendanceStatus,
    required this.currentCountry,
    this.otherCountry,
    this.currentCity,
    this.email,
    this.remark,
  }) : id = '',
       createdAt = DateTime.utc(1970),
       updatedAt = DateTime.utc(1970);

  /// Rebuilds a registration from [toMap] output. Extra keys are ignored.
  ///
  /// Throws a [FormatException] if a required key is missing or malformed.
  factory GraduationRegistration.fromMap(Map<String, Object?> map) {
    return GraduationRegistration(
      id: _requiredString(map, 'id'),
      name: _requiredString(map, 'name'),
      fatherName: _requiredString(map, 'fatherName'),
      motherName: _optionalString(map, 'motherName'),
      phoneNo: _requiredString(map, 'phoneNo'),
      nrc: _requiredString(map, 'nrc'),
      rollNo: _requiredString(map, 'rollNo'),
      major: _requiredString(map, 'major'),
      attendanceStatus:
          AttendanceStatus.tryParse(map['attendanceStatus']) ??
          _invalid('attendanceStatus'),
      currentCountry:
          CurrentCountry.tryParse(map['currentCountry']) ??
          _invalid('currentCountry'),
      otherCountry: _optionalString(map, 'otherCountry'),
      currentCity: _optionalString(map, 'currentCity'),
      email: _optionalString(map, 'email'),
      remark: _optionalString(map, 'remark'),
      createdAt: _requiredDate(map, 'createdAt'),
      updatedAt: _requiredDate(map, 'updatedAt'),
    );
  }

  final String id;
  final String name;
  final String fatherName;
  final String? motherName;
  final String phoneNo;
  final String nrc;
  final String rollNo;
  final String major;
  final AttendanceStatus attendanceStatus;
  final CurrentCountry currentCountry;

  /// Only meaningful when [currentCountry] is [CurrentCountry.other].
  final String? otherCountry;
  final String? currentCity;
  final String? email;
  final String? remark;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Copies this registration with the given fields replaced.
  ///
  /// A `null` argument keeps the current value. To clear an optional text
  /// field, pass an empty string: blank optional text is stored as `null`.
  GraduationRegistration copyWith({
    String? id,
    String? name,
    String? fatherName,
    String? motherName,
    String? phoneNo,
    String? nrc,
    String? rollNo,
    String? major,
    AttendanceStatus? attendanceStatus,
    CurrentCountry? currentCountry,
    String? otherCountry,
    String? currentCity,
    String? email,
    String? remark,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GraduationRegistration(
      id: id ?? this.id,
      name: name ?? this.name,
      fatherName: fatherName ?? this.fatherName,
      motherName: motherName ?? this.motherName,
      phoneNo: phoneNo ?? this.phoneNo,
      nrc: nrc ?? this.nrc,
      rollNo: rollNo ?? this.rollNo,
      major: major ?? this.major,
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
      currentCountry: currentCountry ?? this.currentCountry,
      otherCountry: otherCountry ?? this.otherCountry,
      currentCity: currentCity ?? this.currentCity,
      email: email ?? this.email,
      remark: remark ?? this.remark,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns a copy that is ready to be validated and stored:
  ///
  /// * text is trimmed;
  /// * blank optional text becomes `null`;
  /// * [otherCountry] is dropped unless [currentCountry] is
  ///   [CurrentCountry.other].
  GraduationRegistration normalized() {
    return GraduationRegistration(
      id: id.trim(),
      name: name.trim(),
      fatherName: fatherName.trim(),
      motherName: _blankToNull(motherName),
      phoneNo: phoneNo.trim(),
      nrc: nrc.trim(),
      rollNo: rollNo.trim(),
      major: major.trim(),
      attendanceStatus: attendanceStatus,
      currentCountry: currentCountry,
      otherCountry: currentCountry == CurrentCountry.other
          ? _blankToNull(otherCountry)
          : null,
      currentCity: _blankToNull(currentCity),
      email: _blankToNull(email),
      remark: _blankToNull(remark),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// A JSON-compatible map. Dates are ISO-8601 UTC strings and enums use their
  /// [AttendanceStatus.storageValue] / [CurrentCountry.storageValue].
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'fatherName': fatherName,
      'motherName': motherName,
      'phoneNo': phoneNo,
      'nrc': nrc,
      'rollNo': rollNo,
      'major': major,
      'attendanceStatus': attendanceStatus.storageValue,
      'currentCountry': currentCountry.storageValue,
      'otherCountry': otherCountry,
      'currentCity': currentCity,
      'email': email,
      'remark': remark,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraduationRegistration &&
          other.id == id &&
          other.name == name &&
          other.fatherName == fatherName &&
          other.motherName == motherName &&
          other.phoneNo == phoneNo &&
          other.nrc == nrc &&
          other.rollNo == rollNo &&
          other.major == major &&
          other.attendanceStatus == attendanceStatus &&
          other.currentCountry == currentCountry &&
          other.otherCountry == otherCountry &&
          other.currentCity == currentCity &&
          other.email == email &&
          other.remark == remark &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    fatherName,
    motherName,
    phoneNo,
    nrc,
    rollNo,
    major,
    attendanceStatus,
    currentCountry,
    otherCountry,
    currentCity,
    email,
    remark,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'GraduationRegistration($id, $rollNo, $name)';
}

final _whitespace = RegExp(r'\s+');
final _myanmarDigit = RegExp('[၀-၉]');

/// The form of a Roll No. or NRC used to detect duplicates.
///
/// Whitespace is removed, Myanmar digits become ASCII digits and letters are
/// lowercased, so `12/LaMaNa(N) 123456` and `12/lamana(n)123456` collide.
/// The value the user typed is stored unchanged.
String normalizeLookupKey(String value) {
  return value
      .replaceAll(_whitespace, '')
      .replaceAllMapped(
        _myanmarDigit,
        (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0x1040 + 0x30),
      )
      .toLowerCase();
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Never _invalid(String key) => throw FormatException('Invalid "$key"');

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) return value;
  return _invalid(key);
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is String) return value;
  return _invalid(key);
}

DateTime _requiredDate(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  return _invalid(key);
}
