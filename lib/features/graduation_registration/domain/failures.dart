import 'entities/registration_enums.dart';

/// Base type for every expected failure raised by the registration repository.
sealed class RegistrationFailure implements Exception {
  const RegistrationFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// One or more fields are missing or malformed.
final class ValidationFailure extends RegistrationFailure {
  ValidationFailure(Map<RegistrationField, String> errors)
    : errors = Map.unmodifiable(errors),
      super('Registration is invalid: ${errors.values.join('; ')}');

  final Map<RegistrationField, String> errors;
}

/// A registration with this id already exists.
final class DuplicateIdFailure extends RegistrationFailure {
  const DuplicateIdFailure(this.id)
    : super('A registration with id "$id" already exists.');

  final String id;
}

/// Another registration already uses this Roll No.
final class DuplicateRollNoFailure extends RegistrationFailure {
  const DuplicateRollNoFailure(this.rollNo)
    : super('Roll No. "$rollNo" is already registered.');

  final String rollNo;
}

/// Another registration already uses this NRC.
final class DuplicateNrcFailure extends RegistrationFailure {
  const DuplicateNrcFailure(this.nrc)
    : super('NRC "$nrc" is already registered.');

  final String nrc;
}

/// There is nothing to export or back up, because no registrations are saved.
final class NothingToExportFailure extends RegistrationFailure {
  const NothingToExportFailure(super.message);
}

/// No registration exists with the given id.
final class NotFoundFailure extends RegistrationFailure {
  const NotFoundFailure(this.id) : super('Registration "$id" was not found.');

  final String id;
}
