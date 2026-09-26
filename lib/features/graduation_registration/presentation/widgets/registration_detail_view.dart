import 'package:flutter/material.dart';

import '../../domain/entities/graduation_registration.dart';
import '../utils/registration_formatters.dart';
import 'attendance_badge.dart';
import 'responsive_field_grid.dart';

/// What the user asked for from the details view.
enum RegistrationDetailAction { edit, delete }

/// Shows every field of [registration] and resolves to the action the user
/// chose, or `null` if they just closed it.
///
/// A dialog on wide screens and a bottom sheet on narrow ones.
Future<RegistrationDetailAction?> showRegistrationDetail(
  BuildContext context,
  GraduationRegistration registration,
) {
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<RegistrationDetailAction>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RegistrationDetailView(registration: registration),
        ),
      ),
    );
  }
  return showModalBottomSheet<RegistrationDetailAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => RegistrationDetailView(registration: registration),
  );
}

class RegistrationDetailView extends StatelessWidget {
  const RegistrationDetailView({super.key, required this.registration});

  final GraduationRegistration registration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final r = registration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Semantics(
            header: true,
            child: Text(
              'Registration Details',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 20,
              children: [
                _Section(
                  title: 'Personal Information',
                  fields: [
                    _Field('Name', r.name),
                    _Field('Father Name', r.fatherName),
                    _Field('Mother Name', r.motherName),
                    _Field('NRC', r.nrc),
                    _Field('Roll No.', r.rollNo),
                    _Field('Major', r.major),
                  ],
                ),
                _Section(
                  title: 'Contact Information',
                  fields: [
                    _Field('Phone No.', r.phoneNo),
                    _Field('Email', r.email),
                    _Field('Current City', r.currentCity),
                  ],
                ),
                _Section(
                  title: 'Attendance and Location',
                  fields: [
                    _Field(
                      'Attendance Status',
                      r.attendanceStatus.label,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AttendanceBadge(status: r.attendanceStatus),
                      ),
                    ),
                    _Field('Current Country', countryLabel(r)),
                  ],
                ),
                _Section(
                  title: 'Additional Information',
                  fields: [_Field('Remark', r.remark, fullWidth: true)],
                ),
                _Section(
                  title: 'Record',
                  fields: [
                    _Field('Created Date', formatDateTime(r.createdAt)),
                    _Field('Updated Date', formatDateTime(r.updatedAt)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.error),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(RegistrationDetailAction.delete),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(RegistrationDetailAction.edit),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.fields});

  final String title;
  final List<_Field> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ResponsiveFieldGrid(
          twoColumnMinWidth: 400,
          children: [
            for (final field in fields)
              field.fullWidth ? FullWidth(child: field) : field,
          ],
        ),
      ],
    );
  }
}

/// A label above a value. A missing value shows as an em dash. [child]
/// replaces the text value when a richer display is wanted.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.child, this.fullWidth = false});

  final String label;
  final String? value;
  final Widget? child;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value == null || value!.isEmpty ? '—' : value!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        child ?? SelectableText(text, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}
