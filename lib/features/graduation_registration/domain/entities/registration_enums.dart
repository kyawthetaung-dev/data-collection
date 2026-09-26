/// Whether the graduate can attend the graduation ceremony.
enum AttendanceStatus {
  canAttend('Can Attend'),
  cannotAttend('Cannot Attend');

  const AttendanceStatus(this.label);

  final String label;

  /// The value written to storage and JSON backups.
  String get storageValue => name;

  /// Returns the status stored as [value], or `null` if it is unknown.
  static AttendanceStatus? tryParse(Object? value) => values.asNameMap()[value];
}

/// The country the graduate currently lives in.
enum CurrentCountry {
  myanmar('Myanmar'),
  japan('Japan'),
  singapore('Singapore'),
  korea('Korea'),
  other('Other');

  const CurrentCountry(this.label);

  final String label;

  /// The value written to storage and JSON backups.
  String get storageValue => name;

  /// Returns the country stored as [value], or `null` if it is unknown.
  static CurrentCountry? tryParse(Object? value) => values.asNameMap()[value];
}

/// Identifies a form field, so validation errors can be shown next to it.
enum RegistrationField {
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
}
