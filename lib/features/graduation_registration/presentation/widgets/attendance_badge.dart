import 'package:flutter/material.dart';

import '../../../../app_theme.dart';
import '../../domain/entities/registration_enums.dart';

/// A small pill showing whether the graduate can attend. The icon backs up the
/// colour, so the status is readable without telling green from red.
class AttendanceBadge extends StatelessWidget {
  const AttendanceBadge({super.key, required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final canAttend = status == AttendanceStatus.canAttend;
    final colors = Theme.of(context).colorScheme;
    final app = context.appColors;
    final foreground = canAttend ? app.onSuccessContainer : colors.error;
    final background = canAttend ? app.successContainer : colors.errorContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md - 2,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              canAttend ? Icons.check_circle_outline : Icons.highlight_off,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                status.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
