import '../entities/graduation_registration.dart';
import '../entities/registration_enums.dart';

/// Checks a registration against the business rules.
///
/// Expects a registration that has already been through
/// [GraduationRegistration.normalized].
class RegistrationValidator {
  const RegistrationValidator();

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _phoneChars = RegExp(r'^\+?[0-9၀-၉\s\-()]+$');
  static final _phoneDigit = RegExp(r'[0-9၀-၉]');

  static const minPhoneDigits = 6;
  static const maxPhoneDigits = 15;

  /// Returns the error for each invalid field, or an empty map if valid.
  Map<RegistrationField, String> validate(GraduationRegistration r) {
    final errors = <RegistrationField, String>{};

    void requireText(RegistrationField field, String value, String label) {
      if (value.isEmpty) errors[field] = '$label is required.';
    }

    requireText(RegistrationField.name, r.name, 'Name');
    requireText(RegistrationField.fatherName, r.fatherName, 'Father Name');
    requireText(RegistrationField.nrc, r.nrc, 'NRC');
    requireText(RegistrationField.rollNo, r.rollNo, 'Roll No.');
    requireText(RegistrationField.major, r.major, 'Major');

    if (r.phoneNo.isEmpty) {
      errors[RegistrationField.phoneNo] = 'Phone No. is required.';
    } else if (!_isPlausiblePhone(r.phoneNo)) {
      errors[RegistrationField.phoneNo] = 'Phone No. is not valid.';
    }

    if (r.currentCountry == CurrentCountry.other &&
        (r.otherCountry == null || r.otherCountry!.isEmpty)) {
      errors[RegistrationField.otherCountry] =
          'Other Country is required when Current Country is Other.';
    }

    final email = r.email;
    if (email != null && !_email.hasMatch(email)) {
      errors[RegistrationField.email] = 'Email is not valid.';
    }

    return errors;
  }

  bool _isPlausiblePhone(String value) {
    if (!_phoneChars.hasMatch(value)) return false;
    final digits = _phoneDigit.allMatches(value).length;
    return digits >= minPhoneDigits && digits <= maxPhoneDigits;
  }
}
