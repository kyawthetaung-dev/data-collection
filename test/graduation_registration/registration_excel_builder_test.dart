import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_excel_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';

import 'support/sample_registrations.dart';

const _builder = RegistrationExcelBuilder();

Sheet sheetOf(Uint8List bytes) {
  final tables = Excel.decodeBytes(bytes).tables;
  return tables[RegistrationExcelBuilder.sheetName]!;
}

/// The text of every cell in [row]; empty cells are `null`.
List<String?> textRow(Sheet sheet, int row) => [
  for (final cell in sheet.rows[row]) cell?.value?.toString(),
];

void main() {
  final all = sampleRegistrations();

  group('layout', () {
    test('has a single sheet named Registrations', () {
      final excel = Excel.decodeBytes(_builder.build(all));

      expect(excel.tables.keys, ['Registrations']);
    });

    test('starts with the header row, in the required column order', () {
      final sheet = sheetOf(_builder.build(all));

      expect(textRow(sheet, 0), [
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
      ]);
      expect(RegistrationExcelBuilder.headers, hasLength(16));
    });

    test('has one row per registration under the header', () {
      final sheet = sheetOf(_builder.build(all));

      expect(sheet.maxRows, all.length + 1);
      expect(sheet.maxColumns, 16);
    });

    test('has only the header row when there are no registrations', () {
      final sheet = sheetOf(_builder.build([]));

      expect(sheet.maxRows, 1);
      expect(textRow(sheet, 0).first, 'No.');
    });

    test('makes the header bold', () {
      final sheet = sheetOf(_builder.build(all));

      for (final cell in sheet.rows[0]) {
        expect(cell!.cellStyle?.isBold, isTrue, reason: '${cell.value}');
      }
    });

    test('keeps the order it is given', () {
      final reversed = all.reversed.toList();

      final sheet = sheetOf(_builder.build(reversed));

      expect(
        [for (var i = 1; i <= 4; i++) sheet.rows[i][1]!.value.toString()],
        ['Su Su', 'Kyaw Kyaw', 'Mya Mya', 'Aung Aung'],
      );
    });
  });

  group('cells', () {
    test('writes every field of a registration in its column', () {
      final sheet = sheetOf(_builder.build(all));

      // Row 1 is Aung Aung, who has every optional field filled in.
      final row = sheet.rows[1];
      expect(row[0]!.value, IntCellValue(1));
      expect(
        [for (var i = 1; i <= 13; i++) row[i]?.value.toString()],
        [
          'Aung Aung',
          'U Kyaw',
          'Daw Mya',
          '09-123-456-789',
          '12/LAMANA(N)111111',
          'CS-001',
          'Computer Science',
          'Can Attend',
          'Myanmar',
          null,
          'Yangon',
          'aung@example.com',
          'Bringing two guests',
        ],
      );
    });

    test('numbers the rows from 1', () {
      final sheet = sheetOf(_builder.build(all));

      expect(
        [for (var i = 1; i <= 4; i++) sheet.rows[i][0]!.value],
        [IntCellValue(1), IntCellValue(2), IntCellValue(3), IntCellValue(4)],
      );
    });

    test('writes the attendance status and country as labels', () {
      final sheet = sheetOf(_builder.build(all));

      expect(sheet.rows[2][8]!.value.toString(), 'Cannot Attend');
      expect(sheet.rows[2][9]!.value.toString(), 'Japan');
    });

    test('fills Other Country only for the country Other', () {
      final sheet = sheetOf(_builder.build(all));

      expect(sheet.rows[3][9]!.value.toString(), 'Other');
      expect(sheet.rows[3][10]!.value.toString(), 'Thailand');
      expect(sheet.rows[1][10], isNull);
      expect(sheet.rows[2][10], isNull);
    });

    test('ignores a stray Other Country when the country is not Other', () {
      final registration = sampleRegistration(
        currentCountry: CurrentCountry.korea,
        otherCountry: 'Thailand',
      );

      final sheet = sheetOf(_builder.build([registration]));

      expect(sheet.rows[1][9]!.value.toString(), 'Korea');
      expect(sheet.rows[1][10], isNull);
    });

    test('leaves empty optional fields as empty cells', () {
      final sheet = sheetOf(_builder.build(all));

      // Su Su has no mother name, city, email or remark.
      final row = sheet.rows[4];
      expect(row[3], isNull);
      expect(row[11], isNull);
      expect(row[12], isNull);
      expect(row[13], isNull);
      expect(row[1]!.value.toString(), 'Su Su');
    });
  });

  group('text is kept exactly as typed', () {
    Sheet single({
      String phoneNo = '09-123-456-789',
      String nrc = '12/LAMANA(N)111111',
      String rollNo = 'CS-001',
      String? remark,
    }) => sheetOf(
      _builder.build([
        sampleRegistration(
          phoneNo: phoneNo,
          nrc: nrc,
          rollNo: rollNo,
          remark: remark,
        ),
      ]),
    );

    test('a phone number keeps its leading zero and stays text', () {
      final cell = single(phoneNo: '0912345678').rows[1][4]!;

      expect(cell.value, isA<TextCellValue>());
      expect(cell.value.toString(), '0912345678');
    });

    test('a phone number starting with + stays text', () {
      final cell = single(phoneNo: '+95 9 123 456 789').rows[1][4]!;

      expect(cell.value, isA<TextCellValue>());
      expect(cell.value.toString(), '+95 9 123 456 789');
    });

    test('NRC and Roll No. stay text, not dates or numbers', () {
      final sheet = single(nrc: '12/3/2026', rollNo: '001');

      expect(sheet.rows[1][5]!.value, isA<TextCellValue>());
      expect(sheet.rows[1][5]!.value.toString(), '12/3/2026');
      expect(sheet.rows[1][6]!.value, isA<TextCellValue>());
      expect(sheet.rows[1][6]!.value.toString(), '001');
    });

    test('text that looks like a formula is not turned into one', () {
      for (final text in [
        '=1+1',
        '+SUM(A1)',
        '-2+3',
        '@A1',
        '=HYPERLINK("x")',
      ]) {
        final cell = single(remark: text).rows[1][13]!;

        expect(cell.value, isA<TextCellValue>(), reason: text);
        expect(cell.value.toString(), text);
      }
    });

    test('Burmese text and line breaks survive', () {
      final registration = sampleRegistration(
        name: 'မောင်မောင်',
        nrc: '၁၂/မမန(နိုင်)၁၂၃၄၅၆',
        remark: 'ပထမလိုင်း\nဒုတိယလိုင်း',
      );

      final row = sheetOf(_builder.build([registration])).rows[1];

      expect(row[1]!.value.toString(), 'မောင်မောင်');
      expect(row[5]!.value.toString(), '၁၂/မမန(နိုင်)၁၂၃၄၅၆');
      expect(row[13]!.value.toString(), 'ပထမလိုင်း\nဒုတိယလိုင်း');
    });
  });

  group('dates', () {
    test('are real Excel date-times in local time', () {
      final registration = sampleRegistration(
        createdAt: DateTime.utc(2026, 9, 1, 12, 30, 15),
        updatedAt: DateTime.utc(2026, 9, 2, 8),
      );

      final row = sheetOf(_builder.build([registration])).rows[1];

      final created = row[14]!.value as DateTimeCellValue;
      final updated = row[15]!.value as DateTimeCellValue;
      expect(created.asDateTimeLocal(), registration.createdAt.toLocal());
      expect(updated.asDateTimeLocal(), registration.updatedAt.toLocal());
    });

    test('are shown as yyyy-mm-dd hh:mm:ss', () {
      final row = sheetOf(_builder.build(all)).rows[1];

      for (final cell in [row[14]!, row[15]!]) {
        expect(cell.cellStyle?.numberFormat.formatCode, 'yyyy-mm-dd hh:mm:ss');
      }
    });
  });

  group('fileName', () {
    test('is graduation_registrations_YYYY-MM-DD.xlsx', () {
      expect(
        RegistrationExcelBuilder.fileName(DateTime(2026, 9, 25, 14, 30)),
        'graduation_registrations_2026-09-25.xlsx',
      );
    });

    test('pads the month and day', () {
      expect(
        RegistrationExcelBuilder.fileName(DateTime(2026, 1, 5)),
        'graduation_registrations_2026-01-05.xlsx',
      );
    });

    test('uses the local date', () {
      // Just before midnight UTC is already tomorrow in a UTC+ time zone, so
      // compare with the local date of the same instant.
      final instant = DateTime.utc(2026, 9, 25, 23, 59);
      final local = instant.toLocal();

      expect(
        RegistrationExcelBuilder.fileName(instant),
        'graduation_registrations_'
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}.xlsx',
      );
    });
  });

  test('builds a large export', () {
    final many = [
      for (var i = 0; i < 1500; i++)
        sampleRegistration(
          id: 'id-$i',
          name: 'Person $i',
          rollNo: 'CS-$i',
          nrc: '12/LAMANA(N)$i',
        ),
    ];

    final sheet = sheetOf(_builder.build(many));

    expect(sheet.maxRows, 1501);
    expect(sheet.rows[1500][1]!.value.toString(), 'Person 1499');
    expect(sheet.rows[1500][0]!.value, IntCellValue(1500));
  });
}
