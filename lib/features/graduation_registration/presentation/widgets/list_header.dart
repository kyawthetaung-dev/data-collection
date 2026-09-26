import 'package:flutter/material.dart';

import '../../../../app_theme.dart';
import 'data_actions_menu.dart';

/// The top of the registration list: how many registrations there are, and on
/// wide screens the buttons to export and import them.
///
/// On narrow screens the actions live in the app bar menu instead
/// ([DataActionsMenu]), so only the count is shown here.
class ListHeader extends StatelessWidget {
  const ListHeader({
    super.key,
    required this.total,
    required this.shown,
    required this.showActions,
    required this.running,
    required this.canExport,
    required this.onAction,
  });

  final int total;

  /// The number of matches, or `null` when nothing is being filtered.
  final int? shown;

  /// Whether to show the action buttons: on wide screens.
  final bool showActions;

  /// The action in progress, if any. Every button is disabled meanwhile.
  final DataAction? running;

  /// Whether there are registrations to export.
  final bool canExport;
  final ValueChanged<DataAction> onAction;

  @override
  Widget build(BuildContext context) {
    // A Wrap, so on a mid-sized screen the buttons drop under the count
    // instead of squeezing it.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      children: [
        _Count(total: total, shown: shown),
        if (showActions)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final action in DataAction.values)
                _ActionButton(
                  action: action,
                  running: running,
                  canExport: canExport,
                  onPressed: () => onAction(action),
                ),
            ],
          ),
      ],
    );
  }
}

/// "Total registrations: N", plus "Showing X of N" while filtering.
class _Count extends StatelessWidget {
  const _Count({required this.total, required this.shown});

  final int total;
  final int? shown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: 2,
      children: [
        Text('Total registrations: $total', style: theme.textTheme.titleMedium),
        if (shown != null)
          Text(
            'Showing $shown of $total',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.running,
    required this.canExport,
    required this.onPressed,
  });

  final DataAction action;
  final DataAction? running;
  final bool canExport;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled =
        running == null && (canExport || !action.needsRegistrations);
    final button = OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: running == action
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(action.icon),
      label: Text(action.label),
    );
    final explainDisabled =
        running == null && !canExport && action.needsRegistrations;
    return explainDisabled
        ? Tooltip(message: nothingToExportTooltip, child: button)
        : button;
  }
}
