import '../entities/graduation_registration.dart';

/// Stores graduation registrations.
///
/// Every method may throw a `RegistrationFailure` (see `failures.dart`).
abstract interface class GraduationRegistrationRepository {
  /// Validates and saves a new registration.
  ///
  /// The `id`, `createdAt` and `updatedAt` of [registration] are ignored: the
  /// repository assigns a new id and sets both dates to the current time. Use
  /// [GraduationRegistration.draft] to build the argument.
  ///
  /// Throws [ValidationFailure], [DuplicateRollNoFailure] or
  /// [DuplicateNrcFailure].
  Future<GraduationRegistration> create(GraduationRegistration registration);

  /// Every registration, oldest first.
  Future<List<GraduationRegistration>> getAll();

  /// The registration with [id], or `null` if there is none.
  Future<GraduationRegistration?> getById(String id);

  /// Validates and saves changes to an existing registration.
  ///
  /// `createdAt` is kept from the stored record and `updatedAt` is set to the
  /// current time, whatever the values on [registration].
  ///
  /// Throws [NotFoundFailure], [ValidationFailure], [DuplicateRollNoFailure]
  /// or [DuplicateNrcFailure].
  Future<GraduationRegistration> update(GraduationRegistration registration);

  /// Deletes the registration with [id].
  ///
  /// Throws [NotFoundFailure] if there is none.
  Future<void> delete(String id);

  /// Stores [registrations] exactly as given, ids and created and updated
  /// dates included, in a single all-or-nothing operation. This is how a backup
  /// is restored.
  ///
  /// Nothing that is already stored is changed or removed. If any record is
  /// invalid, or clashes with a stored record or with another record in
  /// [registrations], this throws and **nothing at all is stored**:
  /// [ValidationFailure], [DuplicateIdFailure], [DuplicateRollNoFailure] or
  /// [DuplicateNrcFailure].
  Future<void> restoreAll(List<GraduationRegistration> registrations);

  /// Whether a registration other than [excludeId] already uses [rollNo].
  Future<bool> isRollNoTaken(String rollNo, {String? excludeId});

  /// Whether a registration other than [excludeId] already uses [nrc].
  Future<bool> isNrcTaken(String nrc, {String? excludeId});
}
