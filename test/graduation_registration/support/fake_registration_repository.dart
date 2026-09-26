import 'dart:async';

import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/failures.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/repositories/graduation_registration_repository.dart';

/// An in-memory repository for widget tests.
///
/// It applies the same duplicate rules as the real one but leaves validation
/// to the code under test. Set an `…Error` to make that call fail, or a
/// `…Gate` to hold that call open until the test completes it.
class FakeRegistrationRepository implements GraduationRegistrationRepository {
  FakeRegistrationRepository([
    Iterable<GraduationRegistration> initial = const [],
  ]) : items = List.of(initial);

  final List<GraduationRegistration> items;
  Object? createError;
  Completer<void>? createGate;
  Object? getAllError;
  Completer<void>? getAllGate;
  Object? deleteError;
  Object? restoreError;
  Completer<void>? restoreGate;

  /// How many times each kind of call was made, so tests can prove that a
  /// feature only reads.
  var getAllCalls = 0;
  var writeCalls = 0;
  var _nextId = 1;

  @override
  Future<GraduationRegistration> create(
    GraduationRegistration registration,
  ) async {
    writeCalls++;
    await createGate?.future;
    if (createError != null) throw createError!;
    final candidate = registration.normalized();
    if (await isRollNoTaken(candidate.rollNo)) {
      throw DuplicateRollNoFailure(candidate.rollNo);
    }
    if (await isNrcTaken(candidate.nrc)) {
      throw DuplicateNrcFailure(candidate.nrc);
    }
    final now = DateTime.now().toUtc();
    final saved = candidate.copyWith(
      id: 'new-${_nextId++}',
      createdAt: now,
      updatedAt: now,
    );
    items.add(saved);
    return saved;
  }

  @override
  Future<List<GraduationRegistration>> getAll() async {
    getAllCalls++;
    await getAllGate?.future;
    if (getAllError != null) throw getAllError!;
    return List.of(items);
  }

  @override
  Future<GraduationRegistration?> getById(String id) async =>
      items.where((r) => r.id == id).firstOrNull;

  @override
  Future<GraduationRegistration> update(
    GraduationRegistration registration,
  ) async {
    writeCalls++;
    final candidate = registration.normalized();
    final index = items.indexWhere((r) => r.id == candidate.id);
    if (index < 0) throw NotFoundFailure(candidate.id);
    if (await isRollNoTaken(candidate.rollNo, excludeId: candidate.id)) {
      throw DuplicateRollNoFailure(candidate.rollNo);
    }
    if (await isNrcTaken(candidate.nrc, excludeId: candidate.id)) {
      throw DuplicateNrcFailure(candidate.nrc);
    }
    final saved = candidate.copyWith(
      createdAt: items[index].createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    items[index] = saved;
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    writeCalls++;
    if (deleteError != null) throw deleteError!;
    final index = items.indexWhere((r) => r.id == id);
    if (index < 0) throw NotFoundFailure(id);
    items.removeAt(index);
  }

  @override
  Future<void> restoreAll(List<GraduationRegistration> registrations) async {
    writeCalls++;
    await restoreGate?.future;
    if (restoreError != null) throw restoreError!;
    // Check the whole batch first, so a clash stores nothing (all or nothing).
    final ids = {for (final r in items) r.id};
    final rollKeys = {for (final r in items) normalizeLookupKey(r.rollNo)};
    final nrcKeys = {for (final r in items) normalizeLookupKey(r.nrc)};
    for (final r in registrations) {
      if (!ids.add(r.id)) throw DuplicateIdFailure(r.id);
      if (!rollKeys.add(normalizeLookupKey(r.rollNo))) {
        throw DuplicateRollNoFailure(r.rollNo);
      }
      if (!nrcKeys.add(normalizeLookupKey(r.nrc))) {
        throw DuplicateNrcFailure(r.nrc);
      }
    }
    items.addAll(registrations.map((r) => r.normalized()));
  }

  @override
  Future<bool> isRollNoTaken(String rollNo, {String? excludeId}) async {
    final key = normalizeLookupKey(rollNo);
    return key.isNotEmpty &&
        items.any(
          (r) => r.id != excludeId && normalizeLookupKey(r.rollNo) == key,
        );
  }

  @override
  Future<bool> isNrcTaken(String nrc, {String? excludeId}) async {
    final key = normalizeLookupKey(nrc);
    return key.isNotEmpty &&
        items.any((r) => r.id != excludeId && normalizeLookupKey(r.nrc) == key);
  }
}
