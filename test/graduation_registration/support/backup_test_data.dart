import 'dart:convert';
import 'dart:typed_data';

import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';

import 'sample_registrations.dart';

/// The JSON map of one backup record, as a backup file holds it.
///
/// Pass [overrides] to change or add fields, and use [remove] to leave some
/// out, to make a record that is wrong in a specific way.
Map<String, Object?> recordJson({
  String id = 'r1',
  String name = 'Aung Aung',
  String rollNo = 'CS-001',
  String nrc = '12/LAMANA(N)111111',
  Map<String, Object?> overrides = const {},
  Iterable<String> remove = const [],
}) {
  final map = sampleRegistration(
    id: id,
    name: name,
    rollNo: rollNo,
    nrc: nrc,
  ).toMap()..addAll(overrides);
  for (final key in remove) {
    map.remove(key);
  }
  return map;
}

/// The JSON map of a whole backup file.
///
/// Every part can be replaced to make a file that is wrong in one way. Pass
/// [omit] to leave top-level keys out altogether.
Map<String, Object?> backupJson(
  List<Object?> records, {
  Object? format = 'graduation-registration-backup',
  Object? version = 1,
  Object? exportedAt = '2026-09-25T08:30:00.000Z',
  Object? recordCount = _useLength,
  Iterable<String> omit = const [],
}) {
  final map = <String, Object?>{
    'format': format,
    'version': version,
    'exportedAt': exportedAt,
    'recordCount': identical(recordCount, _useLength)
        ? records.length
        : recordCount,
    'records': records,
  };
  for (final key in omit) {
    map.remove(key);
  }
  return map;
}

const Object _useLength = Object();

/// The bytes of [json] as a UTF-8 file.
Uint8List jsonBytes(Object? json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// The bytes of [text] as a UTF-8 file.
Uint8List textBytes(String text) => Uint8List.fromList(utf8.encode(text));

/// [registration]'s JSON map, for building records from entities.
Map<String, Object?> recordOf(GraduationRegistration registration) =>
    registration.toMap();
