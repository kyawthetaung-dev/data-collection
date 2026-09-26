import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/graduation_registration.dart';
import '../logic/registration_list_filter.dart';
import '../utils/registration_formatters.dart';
import 'attendance_badge.dart';

/// The desktop list: a header row above lazily built, fixed-height rows.
///
/// Columns share the available width, so nothing scrolls sideways. Long text
/// wraps to a second line and is then cut with an ellipsis.
class RegistrationTable extends StatelessWidget {
  const RegistrationTable({
    super.key,
    required this.rows,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  static const rowHeight = 64.0;
  static const headerHeight = 48.0;

  final List<NumberedRegistration> rows;
  final ValueChanged<GraduationRegistration> onView;
  final ValueChanged<GraduationRegistration> onEdit;
  final ValueChanged<GraduationRegistration> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hug a short list instead of stretching the card to the screen.
        final contentHeight = headerHeight + rows.length * rowHeight + 2;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: math.min(constraints.maxHeight, contentHeight),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const _HeaderRow(),
                  Expanded(
                    child: ListView.builder(
                      itemExtent: rowHeight,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return _DataRow(
                          row: row,
                          isLast: index == rows.length - 1,
                          onView: () => onView(row.registration),
                          onEdit: () => onEdit(row.registration),
                          onDelete: () => onDelete(row.registration),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Column widths shared by the header and every row so they line up.
class _RowLayout extends StatelessWidget {
  const _RowLayout({
    required this.number,
    required this.name,
    required this.rollNo,
    required this.major,
    required this.phone,
    required this.attendance,
    required this.country,
    required this.created,
    required this.actions,
  });

  static const numberWidth = 48.0;

  /// Wide enough for the longest badge, "Cannot Attend", plus the gap.
  static const attendanceWidth = 148.0;
  static const actionsWidth = 132.0;

  final Widget number;
  final Widget name;
  final Widget rollNo;
  final Widget major;
  final Widget phone;
  final Widget attendance;
  final Widget country;
  final Widget created;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    Widget cell(int flex, Widget child) => Expanded(
      flex: flex,
      child: Padding(padding: const EdgeInsets.only(right: 12), child: child),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          SizedBox(width: numberWidth, child: number),
          cell(3, name),
          cell(2, rollNo),
          cell(3, major),
          cell(3, phone),
          SizedBox(
            width: attendanceWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: attendance,
            ),
          ),
          cell(2, country),
          cell(3, created),
          SizedBox(width: actionsWidth, child: actions),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget label(String text) => Text(text, style: style);

    return Container(
      height: RegistrationTable.headerHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: _RowLayout(
        number: label('No.'),
        name: label('Name'),
        rollNo: label('Roll No.'),
        major: label('Major'),
        phone: label('Phone'),
        attendance: label('Attendance'),
        country: label('Country'),
        created: label('Created Date'),
        actions: const SizedBox.shrink(),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.row,
    required this.isLast,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final NumberedRegistration row;

  /// The last row leaves out its divider; the card's own border closes it.
  final bool isLast;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = row.registration;
    final style = theme.textTheme.bodyMedium;
    Widget text(String value, {TextStyle? textStyle}) => Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: textStyle ?? style,
    );

    return InkWell(
      onTap: onView,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
        ),
        child: _RowLayout(
          number: text('${row.number}'),
          name: text(
            r.name,
            textStyle: style?.copyWith(fontWeight: FontWeight.w600),
          ),
          rollNo: text(r.rollNo),
          major: text(r.major),
          phone: text(r.phoneNo),
          attendance: Align(
            alignment: Alignment.centerLeft,
            child: AttendanceBadge(status: r.attendanceStatus),
          ),
          country: text(countryLabel(r)),
          created: text(formatDate(r.createdAt)),
          actions: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'View details',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.visibility_outlined),
                onPressed: onView,
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.error,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
