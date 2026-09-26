import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../domain/entities/graduation_registration.dart';
import '../../domain/entities/registration_enums.dart';

/// Builds the Excel (.xlsx) report of registrations.
///
/// The report is an export only: it is never read back, and the IndexedDB
/// records stay the source of truth. Everything is written to a single sheet
/// with the header in row 1, so the file can be sorted, filtered or imported
/// into other tools as it is.
///
/// Phone No., NRC, Roll No. and every other text are written as text cells, so
/// Excel keeps leading zeros and never turns `12/LAMANA(N)123456` into a date
/// or a value starting with `=`, `+`, `-` or `@` into a formula.
class RegistrationExcelBuilder {
  const RegistrationExcelBuilder();

  static const sheetName = 'Registrations';

  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// The column titles, in column order.
  static const headers = [
    'No.',
    'Name',
    'Father Name',
    'Mother Name',
    'Phone No.',
    'NRC',
    'Roll No.',
    'Major',
    'Attendance Status',
    'Current Country',
    'Other Country',
    'Current City',
    'Email',
    'Remark',
    'Created Date',
    'Updated Date',
  ];

  /// Excel column widths (in characters) for [headers], in the same order.
  static const _columnWidths = <double>[
    6, 24, 24, 24, 20, 26, 14, 26, 18, 16, 18, 18, 28, 40, 20, 20, //
  ];

  static const _remarkColumn = 13;
  static const _dateColumns = {14, 15};
  static const _dateFormat = 'yyyy-mm-dd hh:mm:ss';

  /// `graduation_registrations_YYYY-MM-DD.xlsx`, using the local date.
  static String fileName(DateTime now) {
    final local = now.toLocal();
    return 'graduation_registrations_'
        '${local.year.toString().padLeft(4, '0')}-'
        '${_twoDigits(local.month)}-${_twoDigits(local.day)}.xlsx';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  /// The .xlsx file for [registrations], in the order given.
  ///
  /// Dates are real Excel date-times in the local time zone, because a
  /// spreadsheet has no time zone of its own.
  Uint8List build(List<GraduationRegistration> registrations) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E8EAF6'),
      verticalAlign: VerticalAlign.Center,
    );
    final dateStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: _dateFormat),
      horizontalAlign: HorizontalAlign.Left,
    );
    final wrapStyle = CellStyle(
      textWrapping: TextWrapping.WrapText,
      verticalAlign: VerticalAlign.Top,
    );

    void put(int row, int column, CellValue? value, [CellStyle? style]) {
      if (value == null) return;
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
        value,
        cellStyle: style,
      );
    }

    for (var column = 0; column < headers.length; column++) {
      put(0, column, TextCellValue(headers[column]), headerStyle);
      sheet.setColumnWidth(column, _columnWidths[column]);
    }

    for (var i = 0; i < registrations.length; i++) {
      final values = _row(i + 1, registrations[i]);
      for (var column = 0; column < values.length; column++) {
        put(
          i + 1,
          column,
          values[column],
          _dateColumns.contains(column)
              ? dateStyle
              : column == _remarkColumn
              ? wrapStyle
              : null,
        );
      }
    }

    final bytes = excel.encode();
    if (bytes == null) throw StateError('The Excel file could not be created.');
    return Uint8List.fromList(bytes);
  }

  /// The cells of one data row, in [headers] order. `null` is an empty cell.
  List<CellValue?> _row(int number, GraduationRegistration r) {
    CellValue? text(String? value) =>
        value == null || value.isEmpty ? null : TextCellValue(value);

    return [
      IntCellValue(number),
      TextCellValue(r.name),
      TextCellValue(r.fatherName),
      text(r.motherName),
      TextCellValue(r.phoneNo),
      TextCellValue(r.nrc),
      TextCellValue(r.rollNo),
      TextCellValue(r.major),
      TextCellValue(r.attendanceStatus.label),
      TextCellValue(r.currentCountry.label),
      text(r.currentCountry == CurrentCountry.other ? r.otherCountry : null),
      text(r.currentCity),
      text(r.email),
      text(r.remark),
      DateTimeCellValue.fromDateTime(r.createdAt.toLocal()),
      DateTimeCellValue.fromDateTime(r.updatedAt.toLocal()),
    ];
  }
}
