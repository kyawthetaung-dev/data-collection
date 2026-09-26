import '../../domain/entities/graduation_registration.dart';
import '../../domain/entities/registration_enums.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `25 Sep 2026`, in the viewer's local time zone.
String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `25 Sep 2026, 14:30`, in the viewer's local time zone.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${formatDate(local)}, ${_twoDigits(local.hour)}:'
      '${_twoDigits(local.minute)}';
}

/// The country to show: `Japan`, or `Other (Thailand)`.
String countryLabel(GraduationRegistration registration) {
  final other = registration.otherCountry;
  if (registration.currentCountry == CurrentCountry.other &&
      other != null &&
      other.isNotEmpty) {
    return 'Other ($other)';
  }
  return registration.currentCountry.label;
}
