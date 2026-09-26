import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';

GraduationRegistration sampleRegistration({
  String id = 'r1',
  String name = 'Aung Aung',
  String fatherName = 'U Kyaw',
  String? motherName,
  String phoneNo = '09-123-456-789',
  String nrc = '12/LAMANA(N)111111',
  String rollNo = 'CS-001',
  String major = 'Computer Science',
  AttendanceStatus attendanceStatus = AttendanceStatus.canAttend,
  CurrentCountry currentCountry = CurrentCountry.myanmar,
  String? otherCountry,
  String? currentCity,
  String? email,
  String? remark,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 9, 1, 12);
  return GraduationRegistration(
    id: id,
    name: name,
    fatherName: fatherName,
    motherName: motherName,
    phoneNo: phoneNo,
    nrc: nrc,
    rollNo: rollNo,
    major: major,
    attendanceStatus: attendanceStatus,
    currentCountry: currentCountry,
    otherCountry: otherCountry,
    currentCity: currentCity,
    email: email,
    remark: remark,
    createdAt: created,
    updatedAt: updatedAt ?? created,
  );
}

/// Four registrations, oldest first, that between them cover both attendance
/// statuses, several countries, and a major written two ways.
List<GraduationRegistration> sampleRegistrations() => [
  sampleRegistration(
    motherName: 'Daw Mya',
    email: 'aung@example.com',
    currentCity: 'Yangon',
    remark: 'Bringing two guests',
  ),
  sampleRegistration(
    id: 'r2',
    name: 'Mya Mya',
    fatherName: 'U Hla',
    phoneNo: '+81 90 1234 5678',
    nrc: '12/LAMANA(N)222222',
    rollNo: 'CS-002',
    major: 'computer science',
    attendanceStatus: AttendanceStatus.cannotAttend,
    currentCountry: CurrentCountry.japan,
    currentCity: 'Tokyo',
    createdAt: DateTime.utc(2026, 9, 2, 12),
  ),
  sampleRegistration(
    id: 'r3',
    name: 'Kyaw Kyaw',
    fatherName: 'U Ba',
    phoneNo: '0977777777',
    nrc: '12/LAMANA(N)333333',
    rollNo: 'LW-001',
    major: 'Law',
    currentCountry: CurrentCountry.other,
    otherCountry: 'Thailand',
    createdAt: DateTime.utc(2026, 9, 3, 12),
  ),
  sampleRegistration(
    id: 'r4',
    name: 'Su Su',
    fatherName: 'U Tun',
    phoneNo: '09-444-555-666',
    nrc: '12/LAMANA(N)444444',
    rollNo: 'LW-002',
    major: 'Law',
    attendanceStatus: AttendanceStatus.cannotAttend,
    currentCountry: CurrentCountry.korea,
    createdAt: DateTime.utc(2026, 9, 4, 12),
  ),
];
