import 'package:flutter/material.dart';

import '../../data/import/backup_import_planner.dart';
import '../../data/import/registration_import_service.dart';
import '../utils/registration_formatters.dart';

/// Shows what importing a backup would do and asks the user to confirm.
/// Resolves to `true` only if they choose to import.
///
/// Nothing has been written when this is shown. If there is nothing new to
/// import it only offers to close.
Future<bool> showImportSummaryDialog(
  BuildContext context,
  ImportPreview preview,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ImportSummaryDialog(preview: preview),
  );
  return confirmed ?? false;
}

/// Shows what an import did.
Future<void> showImportResultDialog(BuildContext context, ImportResult result) {
  return showDialog<void>(
    context: context,
    builder: (context) => ImportResultDialog(result: result),
  );
}

/// Explains a problem in a dialog, with an OK button.
Future<void> showImportErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.error_outline, color: colors.error),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

/// How many invalid records the summary lists before saying "and N more".
const _maxInvalidShown = 10;

class ImportSummaryDialog extends StatelessWidget {
  const ImportSummaryDialog({super.key, required this.preview});

  final ImportPreview preview;

  static String _reasonLabel(DuplicateReason reason) => switch (reason) {
    DuplicateReason.alreadyPresent => 'Already in the database',
    DuplicateReason.sameIdDifferentData =>
      'Same ID as a stored record, but different data (not overwritten)',
    DuplicateReason.rollNoTaken =>
      'Roll No. already used by another registration',
    DuplicateReason.nrcTaken => 'NRC already used by another registration',
    DuplicateReason.repeatedInFile => 'Repeated within the file',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final plan = preview.plan;
    final backup = preview.backup;
    final nothingNew = plan.newCount == 0;
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    final made = backup.exportedAt == null
        ? ''
        : ' · made ${formatDateTime(backup.exportedAt!)}';

    return AlertDialog(
      icon: Icon(
        nothingNew ? Icons.info_outline : Icons.upload_file,
        color: colors.primary,
      ),
      title: Text(nothingNew ? 'Nothing to import' : 'Import backup?'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.fileName, style: theme.textTheme.titleSmall),
            Text('Backup version ${backup.version}$made', style: quiet),
            const SizedBox(height: 16),
            _CountRow(label: 'Records in backup', count: plan.totalRecords),
            _CountRow(
              label: 'New records',
              count: plan.newCount,
              emphasis: plan.newCount > 0,
            ),
            _CountRow(label: 'Duplicate records', count: plan.duplicateCount),
            for (final reason in DuplicateReason.values)
              if (plan.duplicatesOf(reason) > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _CountRow(
                    label: _reasonLabel(reason),
                    count: plan.duplicatesOf(reason),
                    small: true,
                  ),
                ),
            _CountRow(
              label: 'Invalid records',
              count: plan.invalidCount,
              warn: plan.invalidCount > 0,
            ),
            if (plan.invalid.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final invalid in plan.invalid.take(_maxInvalidShown))
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(
                    '${invalid.description}: ${invalid.reasons.join(' ')}',
                    style: quiet,
                  ),
                ),
              if (plan.invalid.length > _maxInvalidShown)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(
                    '…and ${plan.invalid.length - _maxInvalidShown} more',
                    style: quiet,
                  ),
                ),
            ],
            if (backup.countWarning != null) ...[
              const SizedBox(height: 12),
              _Notice(message: backup.countWarning!),
            ],
            const SizedBox(height: 16),
            Text(
              nothingNew
                  ? 'Every record in this backup is already stored, is a '
                        'duplicate, or is invalid, so nothing would be added.'
                  : 'Only the new records are added. Existing registrations '
                        'are never changed or deleted.',
              style: quiet,
            ),
          ],
        ),
      ),
      scrollable: true,
      actions: [
        if (nothingNew)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              plan.newCount == 1
                  ? 'Import 1 new record'
                  : 'Import ${plan.newCount} new records',
            ),
          ),
        ],
      ],
    );
  }
}

class ImportResultDialog extends StatelessWidget {
  const ImportResultDialog({super.key, required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.check_circle_outline, color: colors.primary),
      title: const Text('Import completed.'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CountRow(
              label: 'New records',
              count: result.imported,
              emphasis: result.imported > 0,
              colon: true,
            ),
            _CountRow(
              label: 'Skipped duplicates',
              count: result.duplicates,
              colon: true,
            ),
            _CountRow(
              label: 'Invalid records',
              count: result.invalid,
              warn: result.invalid > 0,
              colon: true,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// A label with a count on the right. With [colon] the two are joined as one
/// line of text, "Label: 5", for a result read as a list.
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.count,
    this.emphasis = false,
    this.warn = false,
    this.small = false,
    this.colon = false,
  });

  final String label;
  final int count;
  final bool emphasis;
  final bool warn;
  final bool small;
  final bool colon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = small ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium;
    final color = warn
        ? colors.error
        : emphasis
        ? colors.primary
        : null;

    if (colon) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$label: $count',
          style: base?.copyWith(
            color: color,
            fontWeight: emphasis || warn ? FontWeight.w700 : null,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: base)),
          const SizedBox(width: 16),
          Text(
            '$count',
            style: base?.copyWith(
              color: color,
              fontWeight: emphasis || warn ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: colors.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
