import 'package:flutter/material.dart';

import '../../domain/entities/graduation_registration.dart';

/// Asks the user to confirm deleting [registration]. Resolves to `true` only
/// if they choose Delete.
Future<bool> confirmDeleteRegistration(
  BuildContext context,
  GraduationRegistration registration,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.delete_outline, color: colors.error),
        title: const Text('Delete registration?'),
        content: Text(
          '${registration.name} (Roll No. ${registration.rollNo}) will be '
          'permanently deleted. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
