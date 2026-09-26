import 'package:flutter/material.dart';

import '../logic/registration_list_filter.dart';
import '../utils/registration_formatters.dart';
import 'attendance_badge.dart';

/// The mobile list item: one registration as a tappable card.
///
/// Tapping the card opens the details; the icon buttons are 48px targets.
class RegistrationCard extends StatelessWidget {
  const RegistrationCard({
    super.key,
    required this.row,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  /// Icon buttons default to 40px; a finger needs 48.
  static final _tapTarget = IconButton.styleFrom(
    minimumSize: const Size.square(48),
  );

  final NumberedRegistration row;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final r = row.registration;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Roll No. ${r.rollNo} · ${r.major}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No. ${row.number}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Detail(icon: Icons.phone_outlined, text: r.phoneNo),
                    _Detail(icon: Icons.public, text: countryLabel(r)),
                    _Detail(
                      icon: Icons.event_outlined,
                      text: formatDate(r.createdAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // A Wrap, not a Row: with enlarged text the badge and the three
              // buttons no longer fit side by side, and the buttons then drop
              // to their own line instead of squeezing the badge.
              SizedBox(
                // Full width, so the buttons sit at the card's right edge.
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AttendanceBadge(status: r.attendanceStatus),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'View details',
                          style: _tapTarget,
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: onView,
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          style: _tapTarget,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: onEdit,
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          style: _tapTarget,
                          color: colors.error,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
