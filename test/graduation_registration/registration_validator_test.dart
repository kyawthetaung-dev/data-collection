import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/validators/registration_validator.dart';

GraduationRegistration registration({
  String name = 'Aung Aung',
  String fatherName = 'U Kyaw',
  String phoneNo = '+95 9 123 456 789',
  String nrc = '12/LAMANA(N)123456',
  String rollNo = 'CS-001',
  String major = 'Computer Science',
  CurrentCountry currentCountry = CurrentCountry.myanmar,
  String? otherCountry,
  String? email,
}) {
  return GraduationRegistration.draft(
    name: name,
    fatherName: fatherName,
    phoneNo: phoneNo,
    nrc: nrc,
    rollNo: rollNo,
    major: major,
    attendanceStatus: AttendanceStatus.canAttend,
    currentCountry: currentCountry,
    otherCountry: otherCountry,
    email: email,
  ).normalized();
}

void main() {
  const validator = RegistrationValidator();

  Map<RegistrationField, String> validate(GraduationRegistration r) =>
      validator.validate(r);

  test('accepts a complete registration', () {
    expect(validate(registration()), isEmpty);
  });

  test('optional fields may be left out', () {
    final r = GraduationRegistration.draft(
      name: 'Aung Aung',
      fatherName: 'U Kyaw',
      phoneNo: '0912345678',
      nrc: '12/LAMANA(N)123456',
      rollNo: 'CS-001',
      major: 'Computer Science',
      attendanceStatus: AttendanceStatus.cannotAttend,
      currentCountry: CurrentCountry.japan,
    );
    expect(validate(r), isEmpty);
  });

  group('required text', () {
    test('every required field is reported when blank', () {
      final errors = validate(
        registration(
          name: ' ',
          fatherName: '',
          phoneNo: '  ',
          nrc: '',
          rollNo: '\t',
          major: ' ',
        ),
      );
      expect(errors.keys, {
        RegistrationField.name,
        RegistrationField.fatherName,
        RegistrationField.phoneNo,
        RegistrationField.nrc,
        RegistrationField.rollNo,
        RegistrationField.major,
      });
    });
  });

  group('phone', () {
    test('accepts international and local formats', () {
      for (final phone in [
        '+95 9 123 456 789',
        '09-123-456-789',
        '(09)12345678',
      ]) {
        expect(validate(registration(phoneNo: phone)), isEmpty, reason: phone);
      }
    });

    test('accepts Myanmar digits', () {
      expect(validate(registration(phoneNo: '၀၉၁၂၃၄၅၆၇၈')), isEmpty);
    });

    test('rejects letters and implausible lengths', () {
      for (final phone in ['abc12345678', '12345', '1234567890123456']) {
        expect(validate(registration(phoneNo: phone)).keys, [
          RegistrationField.phoneNo,
        ], reason: phone);
      }
    });
  });

  group('other country', () {
    test('is required when the country is Other', () {
      final errors = validate(
        registration(currentCountry: CurrentCountry.other),
      );
      expect(errors.keys, [RegistrationField.otherCountry]);
    });

    test('is accepted when the country is Other', () {
      final r = registration(
        currentCountry: CurrentCountry.other,
        otherCountry: 'Thailand',
      );
      expect(validate(r), isEmpty);
    });

    test('is not required for other countries', () {
      final r = registration(currentCountry: CurrentCountry.korea);
      expect(validate(r), isEmpty);
    });
  });

  group('email', () {
    test('accepts a valid address', () {
      expect(validate(registration(email: 'aung@example.com')), isEmpty);
    });

    test('rejects a malformed address', () {
      for (final email in [
        'aung',
        'aung@',
        'aung@example',
        'a b@example.com',
      ]) {
        expect(validate(registration(email: email)).keys, [
          RegistrationField.email,
        ], reason: email);
      }
    });
  });
}
