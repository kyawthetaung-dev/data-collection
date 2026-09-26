import 'package:idb_shim/idb_shim.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/graduation_registration.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/graduation_registration_repository.dart';
import '../../domain/validators/registration_validator.dart';
import '../datasources/graduation_registration_local_datasource.dart';

class GraduationRegistrationRepositoryImpl
    implements GraduationRegistrationRepository {
  /// [now] and [generateId] can be replaced to make tests deterministic.
  GraduationRegistrationRepositoryImpl(
    this._dataSource, {
    this._validator = const RegistrationValidator(),
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now ?? DateTime.now,
       _generateId = generateId ?? const Uuid().v4;

  final GraduationRegistrationLocalDataSource _dataSource;
  final RegistrationValidator _validator;
  final DateTime Function() _now;
  final String Function() _generateId;

  @override
  Future<GraduationRegistration> create(
    GraduationRegistration registration,
  ) async {
    final candidate = registration.normalized();
    _validate(candidate);
    await _ensureUnique(candidate);

    final timestamp = _now().toUtc();
    final saved = candidate.copyWith(
      id: _generateId(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _write(saved, () => _dataSource.insert(saved));
    return saved;
  }

  @override
  Future<List<GraduationRegistration>> getAll() => _dataSource.getAll();

  @override
  Future<GraduationRegistration?> getById(String id) => _dataSource.getById(id);

  @override
  Future<GraduationRegistration> update(
    GraduationRegistration registration,
  ) async {
    final candidate = registration.normalized();
    final existing = await _dataSource.getById(candidate.id);
    if (existing == null) throw NotFoundFailure(candidate.id);
    _validate(candidate);
    await _ensureUnique(candidate, excludeId: candidate.id);

    final saved = candidate.copyWith(
      createdAt: existing.createdAt,
      updatedAt: _now().toUtc(),
    );
    await _write(saved, () => _dataSource.update(saved));
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    final existed = await _dataSource.delete(id);
    if (!existed) throw NotFoundFailure(id);
  }

  @override
  Future<void> restoreAll(List<GraduationRegistration> registrations) async {
    if (registrations.isEmpty) return;
    final prepared = [for (final r in registrations) r.normalized()];
    for (final registration in prepared) {
      if (registration.id.isEmpty) {
        throw ArgumentError.value(
          registration.id,
          'id',
          'A restored registration needs an id.',
        );
      }
      _validate(registration);
    }
    await _ensureNoClashes(prepared);

    try {
      await _dataSource.insertAll(prepared);
    } on DatabaseError {
      // Another tab can store a clashing record after the check above. The
      // database's unique indexes then reject the whole batch; report which
      // record clashed.
      await _ensureNoClashes(prepared);
      rethrow;
    }
  }

  /// Throws if a record of [batch] clashes with a stored registration, or with
  /// an earlier record of the batch, on its id, Roll No. or NRC.
  Future<void> _ensureNoClashes(List<GraduationRegistration> batch) async {
    final ids = <String>{};
    final rollKeys = <String>{};
    final nrcKeys = <String>{};
    for (final stored in await _dataSource.getAll()) {
      ids.add(stored.id);
      rollKeys.add(normalizeLookupKey(stored.rollNo));
      nrcKeys.add(normalizeLookupKey(stored.nrc));
    }
    for (final registration in batch) {
      if (!ids.add(registration.id)) {
        throw DuplicateIdFailure(registration.id);
      }
      if (!rollKeys.add(normalizeLookupKey(registration.rollNo))) {
        throw DuplicateRollNoFailure(registration.rollNo);
      }
      if (!nrcKeys.add(normalizeLookupKey(registration.nrc))) {
        throw DuplicateNrcFailure(registration.nrc);
      }
    }
  }

  @override
  Future<bool> isRollNoTaken(String rollNo, {String? excludeId}) async {
    final ownerId = await _dataSource.findIdByRollNo(rollNo);
    return ownerId != null && ownerId != excludeId;
  }

  @override
  Future<bool> isNrcTaken(String nrc, {String? excludeId}) async {
    final ownerId = await _dataSource.findIdByNrc(nrc);
    return ownerId != null && ownerId != excludeId;
  }

  void _validate(GraduationRegistration registration) {
    final errors = _validator.validate(registration);
    if (errors.isNotEmpty) throw ValidationFailure(errors);
  }

  Future<void> _ensureUnique(
    GraduationRegistration registration, {
    String? excludeId,
  }) async {
    if (await isRollNoTaken(registration.rollNo, excludeId: excludeId)) {
      throw DuplicateRollNoFailure(registration.rollNo);
    }
    if (await isNrcTaken(registration.nrc, excludeId: excludeId)) {
      throw DuplicateNrcFailure(registration.nrc);
    }
  }

  /// Runs [action], the database write for [registration].
  ///
  /// The duplicate check and the write are separate transactions, so another
  /// browser tab can take the Roll No. or NRC in between. The database's
  /// unique index then rejects the write; this turns that rejection into the
  /// matching [RegistrationFailure].
  Future<void> _write(
    GraduationRegistration registration,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on DatabaseError {
      await _ensureUnique(registration, excludeId: registration.id);
      rethrow;
    }
  }
}
