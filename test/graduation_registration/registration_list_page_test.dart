import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_excel_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_service.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_export_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/backup_file_picker.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_backup_parser.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_import_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_form_page.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_list_page.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/utils/registration_formatters.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/data_actions_menu.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/list_loading_skeleton.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/registration_card.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/registration_filter_bar.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/registration_table.dart';

import 'support/fake_file_downloader.dart';
import '../admin_access/support/admin_test_support.dart';
import 'support/backup_test_data.dart';
import 'support/fake_backup_file_picker.dart';
import 'support/fake_registration_repository.dart';
import 'support/sample_registrations.dart';
import 'support/test_fonts.dart';

const _desktop = Size(1280, 2400);
const _phone = Size(390, 2400);

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<FakeRegistrationRepository> pumpList(
  WidgetTester tester, {
  FakeRegistrationRepository? repository,
  Size size = _desktop,
  RegistrationExportService? exportService,
  RegistrationBackupService? backupService,
  RegistrationImportService? importService,
  BackupFilePicker? filePicker,
  AdminSession? admin,
}) async {
  final repo = repository ?? FakeRegistrationRepository(sampleRegistrations());
  setSize(tester, size);
  await tester.pumpWidget(
    adminApp(
      admin ?? await adminSession(tester),
      RegistrationListPage(
        repository: repo,
        exportService: exportService,
        backupService: backupService,
        importService: importService,
        filePicker: filePicker,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> chooseFilter(WidgetTester tester, Key key, String option) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  // The open menu is the last thing in the tree; the same text may also be in
  // the list behind it.
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

Finder inDialog(Finder finder) =>
    find.descendant(of: find.byType(Dialog), matching: finder);

Finder nameField() => find.widgetWithText(TextFormField, 'Name *');

/// Whether every widget matching [finder] shows its whole text, on one line.
///
/// A `Text` cut off with an ellipsis is still found by `find.text`, so this
/// measures the drawn text against the text laid out without any limit.
void expectNotTruncated(WidgetTester tester, Finder finder, String reason) {
  final widgets = finder.evaluate().toList();
  expect(widgets, isNotEmpty, reason: '$reason: nothing to measure');
  for (var i = 0; i < widgets.length; i++) {
    final paragraph = tester.renderObject<RenderParagraph>(finder.at(i));
    final full = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
    )..layout();
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(full.width - 0.5),
      reason: '$reason is cut off',
    );
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(full.height + 0.5),
      reason: '$reason wraps',
    );
  }
}

String textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextFormField>(field).controller!.text;

/// Runs a data action the way a user would on the current screen: press its
/// button on a wide screen, or open the menu and pick it on a narrow one.
Future<void> chooseAction(WidgetTester tester, String label) async {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  );
  if (button.evaluate().isEmpty) {
    await tester.tap(find.byTooltip(DataActionsMenu.menuTooltip));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Whether the data action [label] can be used, as a button (wide screens) or
/// as an entry of the menu, which must already be open (narrow screens).
bool actionEnabled(WidgetTester tester, String label) {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  );
  if (button.evaluate().isNotEmpty) {
    return tester.widget<ButtonStyleButton>(button).onPressed != null;
  }
  return tester
          .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, label))
          .onPressed !=
      null;
}

void main() {
  late bool realFonts;
  setUpAll(() async => realFonts = await loadRealFonts());

  group('table (wide screens)', () {
    testWidgets('shows the total and a row per registration', (tester) async {
      await pumpList(tester);

      expect(find.text('Total registrations: 4'), findsOneWidget);
      expect(find.byType(RegistrationTable), findsOneWidget);
      expect(find.byType(RegistrationCard), findsNothing);
      // 'Showing X of N' appears only while filtering.
      expect(find.textContaining('Showing'), findsNothing);
    });

    testWidgets('shows the important fields of each registration', (
      tester,
    ) async {
      await pumpList(tester);

      // 'Major', 'Attendance' and 'Country' are also filter labels, so look
      // for the column headers inside the table.
      for (final header in [
        'No.',
        'Name',
        'Roll No.',
        'Major',
        'Phone',
        'Attendance',
        'Country',
        'Created Date',
      ]) {
        expect(
          find.descendant(
            of: find.byType(RegistrationTable),
            matching: find.text(header),
          ),
          findsOneWidget,
          reason: header,
        );
      }
      final first = sampleRegistrations().first;
      for (final value in [
        'Aung Aung',
        'CS-001',
        'Computer Science',
        '09-123-456-789',
        'Myanmar',
        formatDate(first.createdAt),
        'Mya Mya',
        'Kyaw Kyaw',
        'Su Su',
        'Other (Thailand)',
        'Japan',
        'Korea',
      ]) {
        expect(find.text(value), findsOneWidget, reason: value);
      }
      expect(find.text('Can Attend'), findsNWidgets(2));
      expect(find.text('Cannot Attend'), findsNWidgets(2));
      for (final number in ['1', '2', '3', '4']) {
        expect(find.text(number), findsOneWidget, reason: 'No. $number');
      }
    });

    testWidgets('numbers rows from the oldest registration', (tester) async {
      await pumpList(tester);

      final rowOf = {
        for (final name in ['Aung Aung', 'Mya Mya', 'Kyaw Kyaw', 'Su Su'])
          name: tester.getTopLeft(find.text(name)).dy,
      };
      final ys = rowOf.values.toList();
      expect(ys, [...ys]..sort());
      expect(rowOf.values.toSet(), hasLength(4));
    });

    testWidgets('does not overflow at any desktop width', (tester) async {
      await pumpList(tester, size: const Size(1100, 900));

      for (final width in [
        RegistrationListPage.tableBreakpoint,
        1280.0,
        1920.0,
      ]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
        expect(find.byType(RegistrationTable), findsOneWidget);
      }
    });

    testWidgets('keeps very long text inside its cell', (tester) async {
      final repository = FakeRegistrationRepository([
        sampleRegistration(
          name: 'Maung Maung Aung Kyaw Zaw Win Htet Naing Oo Thura',
          major: 'Computer Engineering and Information Technology Studies',
          rollNo: 'UCSS-2019-COMPUTER-ENGINEERING-0001',
          phoneNo: '+95 9 123 456 789 ext 1234567',
          currentCountry: sampleRegistrations()[2].currentCountry,
          otherCountry: 'United Kingdom of Great Britain and Northern Ireland',
        ),
      ]);

      await pumpList(
        tester,
        repository: repository,
        size: const Size(RegistrationListPage.tableBreakpoint, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('never cuts off the attendance badge', (tester) async {
      if (!realFonts) {
        markTestSkipped('Flutter SDK fonts not found');
        return;
      }
      for (final width in [RegistrationListPage.tableBreakpoint, 1280.0]) {
        await pumpList(tester, size: Size(width, 900));

        expectNotTruncated(tester, find.text('Can Attend'), 'badge at $width');
        expectNotTruncated(
          tester,
          find.text('Cannot Attend'),
          'badge at $width',
        );
      }
    });

    testWidgets('a short list does not stretch to the screen height', (
      tester,
    ) async {
      await pumpList(tester);

      final card = tester.getRect(
        find.ancestor(of: find.text('No.'), matching: find.byType(Card)),
      );
      expect(card.height, lessThan(400));
    });
  });

  group('cards (narrow screens)', () {
    testWidgets('shows cards instead of a table', (tester) async {
      await pumpList(tester, size: _phone);

      expect(find.byType(RegistrationCard), findsNWidgets(4));
      expect(find.byType(RegistrationTable), findsNothing);
      expect(find.text('Total registrations: 4'), findsOneWidget);
    });

    testWidgets('shows the important fields on each card', (tester) async {
      await pumpList(tester, size: _phone);

      final first = sampleRegistrations().first;
      for (final value in [
        'Aung Aung',
        'Roll No. CS-001 · Computer Science',
        '09-123-456-789',
        'Myanmar',
        formatDate(first.createdAt),
        'No. 1',
        'Other (Thailand)',
      ]) {
        expect(find.text(value), findsOneWidget, reason: value);
      }
      expect(find.text('Can Attend'), findsNWidgets(2));
      expect(find.text('Cannot Attend'), findsNWidgets(2));
    });

    testWidgets('does not overflow at any phone or tablet width', (
      tester,
    ) async {
      await pumpList(tester, size: const Size(320, 2400));

      for (final width in [
        320.0,
        360.0,
        390.0,
        600.0,
        800.0,
        RegistrationListPage.tableBreakpoint - 1,
      ]) {
        tester.view.physicalSize = Size(width, 2400);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
        expect(find.byType(RegistrationCard), findsNWidgets(4));
      }
    });

    testWidgets('keeps very long text inside the card', (tester) async {
      final repository = FakeRegistrationRepository([
        sampleRegistration(
          name: 'Maung Maung Aung Kyaw Zaw Win Htet Naing Oo Thura',
          major: 'Computer Engineering and Information Technology Studies',
          rollNo: 'UCSS-2019-COMPUTER-ENGINEERING-0001',
          phoneNo: '+95 9 123 456 789 ext 1234567',
          otherCountry: 'United Kingdom of Great Britain and Northern Ireland',
          currentCountry: sampleRegistrations()[2].currentCountry,
        ),
      ]);

      await pumpList(
        tester,
        repository: repository,
        size: const Size(320, 1200),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('never cuts off the attendance badge', (tester) async {
      if (!realFonts) {
        markTestSkipped('Flutter SDK fonts not found');
        return;
      }
      await pumpList(tester, size: const Size(320, 2400));

      for (final width in [320.0, 360.0, 390.0, 600.0]) {
        tester.view.physicalSize = Size(width, 2400);
        await tester.pumpAndSettle();

        expectNotTruncated(tester, find.text('Can Attend'), 'badge at $width');
        expectNotTruncated(
          tester,
          find.text('Cannot Attend'),
          'badge at $width',
        );
      }
    });

    testWidgets('action buttons are large enough to tap', (tester) async {
      await pumpList(tester, size: _phone);

      for (final tooltip in ['View details', 'Edit', 'Delete']) {
        final size = tester.getSize(find.byTooltip(tooltip).first);
        expect(size.width, greaterThanOrEqualTo(48), reason: tooltip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tooltip);
      }
    });

    testWidgets('folds the filters behind a button', (tester) async {
      await pumpList(tester, size: _phone);
      expect(find.byKey(RegistrationFilterBar.majorFilterKey), findsNothing);

      await tester.tap(find.byKey(RegistrationFilterBar.filtersButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(RegistrationFilterBar.majorFilterKey), findsOneWidget);
      expect(
        find.byKey(RegistrationFilterBar.attendanceFilterKey),
        findsOneWidget,
      );
      expect(
        find.byKey(RegistrationFilterBar.countryFilterKey),
        findsOneWidget,
      );

      await chooseFilter(tester, RegistrationFilterBar.majorFilterKey, 'Law');

      expect(find.byType(RegistrationCard), findsNWidgets(2));
      expect(find.text('Showing 2 of 4'), findsOneWidget);
      // The badge on the filters button counts the filters that are set.
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('by name', (tester) async {
      await pumpList(tester);

      await search(tester, 'mya');

      expect(find.text('Mya Mya'), findsOneWidget);
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
      expect(find.text('Total registrations: 4'), findsOneWidget);
    });

    testWidgets('by NRC', (tester) async {
      await pumpList(tester);

      await search(tester, '333333');

      expect(find.text('Kyaw Kyaw'), findsOneWidget);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
    });

    testWidgets('by Roll No.', (tester) async {
      await pumpList(tester);

      await search(tester, 'LW-');

      expect(find.text('Kyaw Kyaw'), findsOneWidget);
      expect(find.text('Su Su'), findsOneWidget);
      expect(find.text('Showing 2 of 4'), findsOneWidget);
    });

    testWidgets('by phone, whatever the formatting', (tester) async {
      await pumpList(tester);

      await search(tester, '0912 345');

      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
    });

    testWidgets('on a phone', (tester) async {
      await pumpList(tester, size: _phone);

      await search(tester, 'su su');

      expect(find.byType(RegistrationCard), findsOneWidget);
      expect(find.text('Su Su'), findsOneWidget);
    });

    testWidgets('the clear button in the search box resets it', (tester) async {
      await pumpList(tester);
      await search(tester, 'mya');

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.textContaining('Showing'), findsNothing);
      expect(find.byTooltip('Clear search'), findsNothing);
    });
  });

  group('filters', () {
    testWidgets('by major, merging spelling variants', (tester) async {
      await pumpList(tester);

      await tester.tap(find.byKey(RegistrationFilterBar.majorFilterKey));
      await tester.pumpAndSettle();
      // "Computer Science" and "computer science" are one menu option. The
      // lowercase spelling is left only in Mya Mya's own row.
      expect(find.text('Computer Science'), findsWidgets);
      expect(find.text('computer science'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RegistrationTable),
          matching: find.text('computer science'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Law').last);
      await tester.pumpAndSettle();

      expect(find.text('Kyaw Kyaw'), findsOneWidget);
      expect(find.text('Su Su'), findsOneWidget);
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Showing 2 of 4'), findsOneWidget);
    });

    testWidgets('by attendance status', (tester) async {
      await pumpList(tester);

      await chooseFilter(
        tester,
        RegistrationFilterBar.attendanceFilterKey,
        'Cannot Attend',
      );

      expect(find.text('Mya Mya'), findsOneWidget);
      expect(find.text('Su Su'), findsOneWidget);
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Showing 2 of 4'), findsOneWidget);
    });

    testWidgets('by country', (tester) async {
      await pumpList(tester);

      await chooseFilter(
        tester,
        RegistrationFilterBar.countryFilterKey,
        'Japan',
      );

      expect(find.text('Mya Mya'), findsOneWidget);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
    });

    testWidgets('combine with each other and with the search', (tester) async {
      await pumpList(tester);

      await chooseFilter(tester, RegistrationFilterBar.majorFilterKey, 'Law');
      await chooseFilter(
        tester,
        RegistrationFilterBar.attendanceFilterKey,
        'Cannot Attend',
      );
      expect(find.text('Su Su'), findsOneWidget);
      expect(find.text('Kyaw Kyaw'), findsNothing);
      expect(find.text('Showing 1 of 4'), findsOneWidget);

      await search(tester, 'lw-001');
      expect(find.text('No registrations match'), findsOneWidget);
    });

    testWidgets('"All" removes a filter again', (tester) async {
      await pumpList(tester);
      await chooseFilter(tester, RegistrationFilterBar.majorFilterKey, 'Law');

      await chooseFilter(
        tester,
        RegistrationFilterBar.majorFilterKey,
        'All majors',
      );

      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.textContaining('Showing'), findsNothing);
    });

    testWidgets('Clear removes the search and every filter', (tester) async {
      await pumpList(tester);
      await search(tester, 'su');
      await chooseFilter(tester, RegistrationFilterBar.majorFilterKey, 'Law');
      expect(find.text('Showing 1 of 4'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.textContaining('Showing'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  });

  group('empty and error states', () {
    testWidgets('no registrations yet', (tester) async {
      await pumpList(tester, repository: FakeRegistrationRepository());

      expect(find.text('No registrations yet'), findsOneWidget);
      expect(find.text('Total registrations: 0'), findsOneWidget);
      expect(find.text('Register someone'), findsOneWidget);
      // Nothing to search or filter yet.
      expect(find.byType(RegistrationFilterBar), findsNothing);
      expect(find.byType(RegistrationTable), findsNothing);
    });

    testWidgets('no registrations yet, on a phone', (tester) async {
      await pumpList(
        tester,
        repository: FakeRegistrationRepository(),
        size: _phone,
      );

      expect(find.text('No registrations yet'), findsOneWidget);
      expect(find.text('Total registrations: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing matches the search', (tester) async {
      await pumpList(tester);

      await search(tester, 'zzz');

      expect(find.text('No registrations match'), findsOneWidget);
      expect(find.text('Showing 0 of 4'), findsOneWidget);
      expect(find.byType(RegistrationTable), findsNothing);

      await tester.tap(find.text('Clear search and filters'));
      await tester.pumpAndSettle();

      expect(find.text('No registrations match'), findsNothing);
      expect(find.text('Aung Aung'), findsOneWidget);
    });

    testWidgets('nothing matches, on a phone', (tester) async {
      await pumpList(tester, size: _phone);

      await search(tester, 'zzz');

      expect(find.text('No registrations match'), findsOneWidget);
      expect(find.byType(RegistrationCard), findsNothing);
    });

    Finder skeletonShapes() => find.descendant(
      of: find.byType(ListLoadingSkeleton),
      matching: find.byType(Card),
    );

    testWidgets('shows a placeholder if loading takes a while', (tester) async {
      final repository = FakeRegistrationRepository(sampleRegistrations())
        ..getAllGate = Completer<void>();
      setSize(tester, _desktop);
      await tester.pumpWidget(
        adminApp(
          await adminSession(tester),
          RegistrationListPage(repository: repository),
        ),
      );

      // Not at first: a quick load must not flash a placeholder.
      await tester.pump(const Duration(milliseconds: 100));
      expect(skeletonShapes(), findsNothing);
      expect(find.text('No registrations yet'), findsNothing);

      await tester.pump(ListLoadingSkeleton.showDelay);
      expect(skeletonShapes(), findsWidgets);

      repository.getAllGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ListLoadingSkeleton), findsNothing);
      expect(find.text('Total registrations: 4'), findsOneWidget);
    });

    testWidgets('never shows the placeholder for a quick load', (tester) async {
      setSize(tester, _desktop);
      await tester.pumpWidget(
        adminApp(
          await adminSession(tester),
          RegistrationListPage(
            repository: FakeRegistrationRepository(sampleRegistrations()),
          ),
        ),
      );
      await tester.pump();

      expect(skeletonShapes(), findsNothing);
      expect(find.byType(ListLoadingSkeleton), findsNothing);
      expect(find.text('Total registrations: 4'), findsOneWidget);
    });

    testWidgets('the placeholder matches the layout: table, cards, grid', (
      tester,
    ) async {
      for (final (size, columns) in [
        (_desktop, 1),
        (const Size(900, 1200), 2),
        (_phone, 1),
      ]) {
        final repository = FakeRegistrationRepository(sampleRegistrations())
          ..getAllGate = Completer<void>();
        setSize(tester, size);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          adminApp(
            await adminSession(tester),
            RegistrationListPage(repository: repository),
          ),
        );
        await tester.pump(ListLoadingSkeleton.showDelay);
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull, reason: '$size');
        final skeleton = tester.widget<ListLoadingSkeleton>(
          find.byType(ListLoadingSkeleton),
        );
        expect(skeleton.asTable, size.width >= 1100, reason: '$size');
        expect(skeleton.columns, columns, reason: '$size');
        repository.getAllGate!.complete();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a load failure can be retried', (tester) async {
      final repository = FakeRegistrationRepository(sampleRegistrations())
        ..getAllError = StateError('IndexedDB is unavailable');
      await pumpList(tester, repository: repository);

      expect(find.text('Could not load registrations'), findsOneWidget);
      expect(find.text('Aung Aung'), findsNothing);

      repository.getAllError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load registrations'), findsNothing);
      expect(find.text('Total registrations: 4'), findsOneWidget);
    });

    testWidgets('Refresh picks up new registrations', (tester) async {
      final repository = await pumpList(tester);
      repository.items.add(
        sampleRegistration(
          id: 'r5',
          name: 'New Person',
          rollNo: 'CS-005',
          nrc: '12/LAMANA(N)555555',
        ),
      );

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('Total registrations: 5'), findsOneWidget);
      expect(find.text('New Person'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the list and says so', (tester) async {
      final repository = await pumpList(tester);
      repository.getAllError = StateError('IndexedDB is unavailable');

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.text('Could not refresh the list.'), findsOneWidget);
      expect(find.text('Could not load registrations'), findsNothing);
    });
  });

  group('details', () {
    testWidgets('open from a row and show every field', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Aung Aung'));
      await tester.pumpAndSettle();

      final first = sampleRegistrations().first;
      expect(find.byType(Dialog), findsOneWidget);
      expect(inDialog(find.text('Registration Details')), findsOneWidget);
      for (final value in [
        'Aung Aung',
        'U Kyaw',
        'Daw Mya',
        '12/LAMANA(N)111111',
        'CS-001',
        'Computer Science',
        '09-123-456-789',
        'aung@example.com',
        'Yangon',
        'Can Attend',
        'Myanmar',
        'Bringing two guests',
        formatDateTime(first.createdAt),
        formatDateTime(first.updatedAt),
      ]) {
        expect(inDialog(find.text(value)), findsWidgets, reason: value);
      }
      for (final label in [
        'Father Name',
        'Mother Name',
        'NRC',
        'Phone No.',
        'Email',
        'Current City',
        'Attendance Status',
        'Current Country',
        'Remark',
        'Created Date',
        'Updated Date',
      ]) {
        expect(inDialog(find.text(label)), findsOneWidget, reason: label);
      }
    });

    testWidgets('show a dash for empty optional fields', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Su Su'));
      await tester.pumpAndSettle();

      // Mother name, email, city and remark are all empty for Su Su.
      expect(inDialog(find.text('—')), findsNWidgets(4));
    });

    testWidgets('show the other country', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Kyaw Kyaw'));
      await tester.pumpAndSettle();

      expect(inDialog(find.text('Other (Thailand)')), findsOneWidget);
    });

    testWidgets('open from the view button and close again', (tester) async {
      await pumpList(tester);

      await tester.tap(find.byTooltip('View details').at(1));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Mya Mya')), findsWidgets);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('open as a bottom sheet on a phone', (tester) async {
      await pumpList(tester, size: _phone);

      await tester.tap(find.text('Aung Aung'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Registration Details'), findsOneWidget);
      expect(find.text('Daw Mya'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('delete', () {
    testWidgets('asks first and keeps the registration on Cancel', (
      tester,
    ) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();

      expect(find.text('Delete registration?'), findsOneWidget);
      expect(
        find.textContaining('Aung Aung (Roll No. CS-001) will be permanently'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.items, hasLength(4));
      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('removes the registration and updates the count', (
      tester,
    ) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.items.map((r) => r.id), ['r2', 'r3', 'r4']);
      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Total registrations: 3'), findsOneWidget);
      expect(find.text('Deleted Aung Aung (Roll No. CS-001).'), findsOneWidget);
    });

    testWidgets('works from a card on a phone', (tester) async {
      final repository = await pumpList(tester, size: _phone);

      await tester.tap(find.byTooltip('Delete').at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.items.map((r) => r.id), ['r1', 'r2', 'r4']);
      expect(find.byType(RegistrationCard), findsNWidgets(3));
    });

    testWidgets('works from the details view', (tester) async {
      final repository = await pumpList(tester);
      await tester.tap(find.text('Mya Mya'));
      await tester.pumpAndSettle();

      await tester.tap(inDialog(find.text('Delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete registration?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.items.map((r) => r.id), ['r1', 'r3', 'r4']);
      expect(find.text('Mya Mya'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('reports a failure and keeps the registration', (tester) async {
      final repository = await pumpList(tester);
      repository.deleteError = StateError('IndexedDB is unavailable');

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not delete Aung Aung. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Aung Aung'), findsOneWidget);
      expect(repository.items, hasLength(4));
    });

    testWidgets('a registration already deleted elsewhere just disappears', (
      tester,
    ) async {
      final repository = await pumpList(tester);
      // Removed in another tab after this list was loaded.
      repository.items.removeAt(0);

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Aung Aung'), findsNothing);
      expect(find.text('Total registrations: 3'), findsOneWidget);
    });

    testWidgets('clears a filter whose major no longer exists', (tester) async {
      final repository = await pumpList(tester);
      await chooseFilter(tester, RegistrationFilterBar.majorFilterKey, 'Law');
      repository.items.removeWhere((r) => r.major == 'Law');

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      // Not stuck on an invisible "Law" filter with zero results.
      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.text('No registrations match'), findsNothing);
      expect(find.textContaining('Showing'), findsNothing);
    });
  });

  group('edit', () {
    testWidgets('opens the form filled in', (tester) async {
      await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationFormPage), findsOneWidget);
      expect(find.text('Edit Registration'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Submit Registration'), findsNothing);
      // The list button is only for the create form.
      expect(find.text('Registrations'), findsNothing);
      expect(textOf(tester, nameField()), 'Aung Aung');
      expect(
        textOf(tester, find.widgetWithText(TextFormField, 'Roll No. *')),
        'CS-001',
      );
      expect(
        textOf(tester, find.widgetWithText(TextFormField, 'Mother Name')),
        'Daw Mya',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Can Attend'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Myanmar'))
            .selected,
        isTrue,
      );
    });

    testWidgets('shows the other country when it was Other', (tester) async {
      await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').at(2));
      await tester.pumpAndSettle();

      expect(
        textOf(tester, find.widgetWithText(TextFormField, 'Other Country *')),
        'Thailand',
      );
    });

    testWidgets('saves the changes and returns to the refreshed list', (
      tester,
    ) async {
      final repository = await pumpList(tester);
      final original = repository.items.first;

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(nameField(), 'Aung Aung Updated');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsOneWidget);
      expect(find.text('Aung Aung Updated'), findsOneWidget);
      expect(find.text('Aung Aung'), findsNothing);
      expect(
        find.text('Updated Aung Aung Updated (Roll No. CS-001).'),
        findsOneWidget,
      );
      final saved = repository.items.first;
      expect(saved.id, original.id);
      expect(saved.name, 'Aung Aung Updated');
      expect(saved.createdAt, original.createdAt);
      expect(saved.updatedAt.isAfter(original.updatedAt), isTrue);
      expect(repository.items, hasLength(4));
    });

    testWidgets('can change the attendance, country and optional fields', (
      tester,
    ) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cannot Attend'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Singapore'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mother Name'),
        '',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      final saved = repository.items.first;
      expect(saved.attendanceStatus.name, 'cannotAttend');
      expect(saved.currentCountry.name, 'singapore');
      expect(saved.motherName, isNull);
    });

    testWidgets('keeping the same Roll No. and NRC is not a duplicate', (
      tester,
    ) async {
      await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsOneWidget);
      expect(find.textContaining('already registered'), findsNothing);
    });

    testWidgets('rejects another registration\'s Roll No. and NRC', (
      tester,
    ) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Roll No. *'),
        'cs-002',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'NRC *'),
        '12/LAMANA(N)333333',
      );
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationFormPage), findsOneWidget);
      expect(find.text('This Roll No. is already registered.'), findsOneWidget);
      expect(find.text('This NRC is already registered.'), findsOneWidget);
      expect(repository.items.first.rollNo, 'CS-001');
    });

    testWidgets('validates like the create form', (tester) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(nameField(), '  ');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required.'), findsOneWidget);
      expect(find.byType(RegistrationFormPage), findsOneWidget);
      expect(repository.items.first.name, 'Aung Aung');
    });

    testWidgets('Cancel returns without saving', (tester) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(nameField(), 'Changed');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsOneWidget);
      expect(find.text('Aung Aung'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(repository.items.first.name, 'Aung Aung');
    });

    testWidgets('reports a registration deleted in the meantime', (
      tester,
    ) async {
      final repository = await pumpList(tester);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      repository.items.removeAt(0);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationFormPage), findsOneWidget);
      expect(
        find.textContaining('This registration no longer exists'),
        findsOneWidget,
      );
    });

    testWidgets('starts from the details view', (tester) async {
      await pumpList(tester);
      await tester.tap(find.text('Mya Mya'));
      await tester.pumpAndSettle();

      await tester.tap(inDialog(find.text('Edit')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Registration'), findsOneWidget);
      expect(textOf(tester, nameField()), 'Mya Mya');
    });

    testWidgets('works on a phone', (tester) async {
      final repository = await pumpList(tester, size: _phone);

      await tester.tap(find.byTooltip('Edit').at(1));
      await tester.pumpAndSettle();
      expect(textOf(tester, nameField()), 'Mya Mya');
      await tester.enterText(nameField(), 'Mya Mya Updated');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Mya Mya Updated'), findsOneWidget);
      expect(repository.items[1].name, 'Mya Mya Updated');
      expect(tester.takeException(), isNull);
    });
  });

  group('data menu', () {
    final exportTime = DateTime(2026, 9, 5, 9, 7);

    /// Pumps the list with export services that "download" into [downloader]
    /// instead of a browser.
    Future<FakeRegistrationRepository> pumpExports(
      WidgetTester tester,
      FakeFileDownloader downloader, {
      FakeRegistrationRepository? repository,
      Size size = _desktop,
    }) async {
      final repo =
          repository ?? FakeRegistrationRepository(sampleRegistrations());
      return pumpList(
        tester,
        repository: repo,
        size: size,
        exportService: RegistrationExportService(
          repository: repo,
          downloader: downloader,
          now: () => exportTime,
        ),
        backupService: RegistrationBackupService(
          repository: repo,
          downloader: downloader,
          now: () => exportTime,
        ),
      );
    }

    Future<void> choose(WidgetTester tester, String label) =>
        chooseAction(tester, label);

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip(DataActionsMenu.menuTooltip));
      await tester.pumpAndSettle();
    }

    group('on a wide screen', () {
      testWidgets('are three buttons in the list header', (tester) async {
        await pumpExports(tester, FakeFileDownloader());

        for (final action in DataAction.values) {
          expect(find.text(action.label), findsOneWidget, reason: action.label);
          expect(
            actionEnabled(tester, action.label),
            isTrue,
            reason: action.label,
          );
        }
        // The buttons are already visible, so there is no menu.
        expect(find.byTooltip(DataActionsMenu.menuTooltip), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('disable the exports, but not the import, without data', (
        tester,
      ) async {
        final downloader = FakeFileDownloader();
        await pumpExports(
          tester,
          downloader,
          repository: FakeRegistrationRepository(),
        );

        expect(actionEnabled(tester, 'Export Excel'), isFalse);
        expect(actionEnabled(tester, 'Export JSON Backup'), isFalse);
        expect(actionEnabled(tester, 'Import Backup'), isTrue);
        expect(find.byTooltip(nothingToExportTooltip), findsNWidgets(2));
        await tester.tap(find.text('Export Excel'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(downloader.downloads, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('appear once the list has loaded', (tester) async {
        final repository = FakeRegistrationRepository(sampleRegistrations())
          ..getAllGate = Completer<void>();
        setSize(tester, _desktop);
        await tester.pumpWidget(
          adminApp(
            await adminSession(tester),
            RegistrationListPage(repository: repository),
          ),
        );

        // The loading placeholder animates forever, so advance time by hand.
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Export Excel'), findsNothing);

        repository.getAllGate!.complete();
        await tester.pumpAndSettle();
        expect(actionEnabled(tester, 'Export Excel'), isTrue);
        expect(actionEnabled(tester, 'Import Backup'), isTrue);
      });
    });

    group('on a narrow screen', () {
      testWidgets('are one icon menu in the app bar', (tester) async {
        await pumpExports(tester, FakeFileDownloader(), size: _phone);

        expect(find.text('Export Excel'), findsNothing);
        expect(find.byTooltip(DataActionsMenu.menuTooltip), findsOneWidget);
        await openMenu(tester);

        for (final action in DataAction.values) {
          expect(find.text(action.label), findsOneWidget, reason: action.label);
          expect(
            actionEnabled(tester, action.label),
            isTrue,
            reason: action.label,
          );
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('disable the exports, but not the import, without data', (
        tester,
      ) async {
        final downloader = FakeFileDownloader();
        await pumpExports(
          tester,
          downloader,
          repository: FakeRegistrationRepository(),
          size: _phone,
        );

        await openMenu(tester);

        expect(actionEnabled(tester, 'Export Excel'), isFalse);
        expect(actionEnabled(tester, 'Export JSON Backup'), isFalse);
        expect(actionEnabled(tester, 'Import Backup'), isTrue);
        expect(find.byTooltip(nothingToExportTooltip), findsNWidgets(2));
        await tester.tap(find.text('Export Excel'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(downloader.downloads, isEmpty);
      });

      testWidgets('allow only the import while the list is loading', (
        tester,
      ) async {
        final repository = FakeRegistrationRepository(sampleRegistrations())
          ..getAllGate = Completer<void>();
        setSize(tester, _phone);
        await tester.pumpWidget(
          adminApp(
            await adminSession(tester),
            RegistrationListPage(repository: repository),
          ),
        );

        // The loading placeholder animates forever, so advance time by hand.
        await tester.tap(find.byTooltip(DataActionsMenu.menuTooltip));
        await tester.pump(const Duration(milliseconds: 300));
        expect(actionEnabled(tester, 'Export Excel'), isFalse);
        expect(actionEnabled(tester, 'Export JSON Backup'), isFalse);
        expect(actionEnabled(tester, 'Import Backup'), isTrue);

        repository.getAllGate!.complete();
        await tester.pumpAndSettle();
        expect(actionEnabled(tester, 'Export Excel'), isTrue);
      });
    });

    for (final kind in [
      _ExportKind(
        label: 'Export Excel',
        fileName: 'graduation_registrations_2026-09-05.xlsx',
        mimeType: RegistrationExcelBuilder.mimeType,
        success: (count) =>
            'Exported ${count == 1 ? '1 registration' : '$count registrations'}'
            ' to graduation_registrations_2026-09-05.xlsx.',
        emptyMessage: 'There are no registrations to export yet.',
        failureMessage: 'Could not create the Excel file. Please try again.',
        recordCount: (bytes) =>
            Excel.decodeBytes(bytes).tables['Registrations']!.maxRows - 1,
      ),
      _ExportKind(
        label: 'Export JSON Backup',
        fileName: 'graduation_backup_2026-09-05_09-07.json',
        mimeType: 'application/json',
        success: (count) =>
            'Backup downloaded: graduation_backup_2026-09-05_09-07.json '
            '(${count == 1 ? '1 registration' : '$count registrations'}).',
        emptyMessage: 'There are no registrations to back up yet.',
        failureMessage: 'Could not create the backup. Please try again.',
        recordCount: (bytes) =>
            (jsonDecode(utf8.decode(bytes))
                    as Map<String, Object?>)['recordCount']!
                as int,
      ),
    ]) {
      group(kind.label, () {
        testWidgets('downloads one named file of every registration', (
          tester,
        ) async {
          final downloader = FakeFileDownloader();
          await pumpExports(tester, downloader);

          await choose(tester, kind.label);

          expect(downloader.downloads, hasLength(1));
          final file = downloader.downloads.single;
          expect(file.fileName, kind.fileName);
          expect(file.mimeType, kind.mimeType);
          expect(kind.recordCount(file.bytes), 4);
          expect(find.text(kind.success(4)), findsOneWidget);
        });

        testWidgets('says "registration" for a single record', (tester) async {
          final downloader = FakeFileDownloader();
          await pumpExports(
            tester,
            downloader,
            repository: FakeRegistrationRepository([sampleRegistration()]),
          );

          await choose(tester, kind.label);

          expect(find.text(kind.success(1)), findsOneWidget);
        });

        testWidgets('exports everything, not just the filtered rows', (
          tester,
        ) async {
          final downloader = FakeFileDownloader();
          await pumpExports(tester, downloader);
          await search(tester, 'su su');
          expect(find.text('Showing 1 of 4'), findsOneWidget);

          await choose(tester, kind.label);

          expect(kind.recordCount(downloader.downloads.single.bytes), 4);
        });

        testWidgets('never changes the saved data', (tester) async {
          final downloader = FakeFileDownloader();
          final repository = await pumpExports(tester, downloader);
          final before = List.of(repository.items);

          await choose(tester, kind.label);

          expect(repository.writeCalls, 0);
          expect(repository.items, before);
          expect(find.text('Total registrations: 4'), findsOneWidget);
        });

        testWidgets('says so if the data was emptied after loading', (
          tester,
        ) async {
          final downloader = FakeFileDownloader();
          final repository = await pumpExports(tester, downloader);
          // Another tab deleted everything after this list was loaded.
          repository.items.clear();

          await choose(tester, kind.label);

          expect(find.text(kind.emptyMessage), findsOneWidget);
          expect(downloader.downloads, isEmpty);
        });

        testWidgets('reports a failure and can be retried', (tester) async {
          final downloader = FakeFileDownloader()
            ..error = StateError('blocked');
          await pumpExports(tester, downloader);

          await choose(tester, kind.label);

          expect(find.text(kind.failureMessage), findsOneWidget);
          expect(downloader.downloads, isEmpty);

          downloader.error = null;
          await choose(tester, kind.label);

          expect(downloader.downloads, hasLength(1));
        });

        testWidgets('shows progress and blocks every action meanwhile', (
          tester,
        ) async {
          final downloader = FakeFileDownloader()..gate = Completer<void>();
          await pumpExports(tester, downloader);

          // A spinner animates forever, so advance time by hand, not settle.
          await tester.tap(find.text(kind.label));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          for (final action in DataAction.values) {
            expect(
              actionEnabled(tester, action.label),
              isFalse,
              reason: action.label,
            );
          }

          downloader.gate!.complete();
          await tester.pumpAndSettle();

          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(downloader.downloads, hasLength(1));
          for (final action in DataAction.values) {
            expect(
              actionEnabled(tester, action.label),
              isTrue,
              reason: action.label,
            );
          }
        });

        testWidgets('shows progress in the menu icon on a phone', (
          tester,
        ) async {
          final downloader = FakeFileDownloader()..gate = Completer<void>();
          await pumpExports(tester, downloader, size: _phone);

          await openMenu(tester);
          await tester.tap(find.text(kind.label));
          // The menu runs the action a frame after the tap.
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          final menuButton = find.ancestor(
            of: find.byTooltip(DataActionsMenu.menuTooltip),
            matching: find.bySubtype<ButtonStyleButton>(),
          );
          expect(
            tester.widget<ButtonStyleButton>(menuButton).onPressed,
            isNull,
          );

          downloader.gate!.complete();
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            tester.widget<ButtonStyleButton>(menuButton).onPressed,
            isNotNull,
          );
        });

        testWidgets('works on a phone', (tester) async {
          final downloader = FakeFileDownloader();
          await pumpExports(tester, downloader, size: _phone);

          await choose(tester, kind.label);

          expect(downloader.downloads, hasLength(1));
          expect(find.text(kind.success(4)), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  });

  group('import backup', () {
    /// Pumps the list with an import service on the same fake repository and
    /// the given fake file chooser.
    Future<FakeRegistrationRepository> pumpImport(
      WidgetTester tester,
      FakeBackupFilePicker picker, {
      FakeRegistrationRepository? repository,
      Size size = _desktop,
    }) async {
      final repo =
          repository ?? FakeRegistrationRepository(sampleRegistrations());
      return pumpList(
        tester,
        repository: repo,
        size: size,
        importService: RegistrationImportService(repository: repo),
        filePicker: picker,
      );
    }

    Uint8List backupFile(List<GraduationRegistration> records) =>
        const RegistrationBackupBuilder().build(
          records,
          exportedAt: DateTime.utc(2026, 9, 25, 8, 30),
        );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip(DataActionsMenu.menuTooltip));
      await tester.pumpAndSettle();
    }

    /// Chooses Import Backup, the way a user would on this screen, and lets the
    /// flow run until a dialog is shown.
    Future<void> importFromMenu(WidgetTester tester) =>
        chooseAction(tester, 'Import Backup');

    Finder dialogText(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    Future<void> confirmImport(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(FilledButton, label));
      await tester.pumpAndSettle();
    }

    group('the import action', () {
      testWidgets('is a button in the header on a wide screen', (tester) async {
        await pumpImport(tester, FakeBackupFilePicker());

        expect(find.text('Import Backup'), findsOneWidget);
        expect(actionEnabled(tester, 'Import Backup'), isTrue);
      });

      testWidgets('is an entry of the menu on a phone', (tester) async {
        await pumpImport(tester, FakeBackupFilePicker(), size: _phone);

        expect(find.text('Import Backup'), findsNothing);
        await openMenu(tester);

        expect(find.text('Import Backup'), findsOneWidget);
        expect(actionEnabled(tester, 'Import Backup'), isTrue);
      });

      testWidgets('is available with no registrations', (tester) async {
        await pumpImport(
          tester,
          FakeBackupFilePicker(),
          repository: FakeRegistrationRepository(),
        );

        expect(actionEnabled(tester, 'Import Backup'), isTrue);
      });

      testWidgets('is available in the phone menu with no registrations', (
        tester,
      ) async {
        await pumpImport(
          tester,
          FakeBackupFilePicker(),
          repository: FakeRegistrationRepository(),
          size: _phone,
        );

        await openMenu(tester);

        expect(actionEnabled(tester, 'Import Backup'), isTrue);
      });
    });

    group('choosing the file', () {
      testWidgets('does nothing if the chooser is cancelled', (tester) async {
        final picker = FakeBackupFilePicker();
        final repository = await pumpImport(tester, picker);
        final before = List.of(repository.items);

        await importFromMenu(tester);

        expect(picker.calls, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(repository.items, before);
        expect(repository.writeCalls, 0);
      });

      testWidgets('reports a problem opening the file', (tester) async {
        final picker = FakeBackupFilePicker()..error = StateError('blocked');
        final repository = await pumpImport(tester, picker);

        await importFromMenu(tester);

        expect(
          find.text('Could not open the file. Please try again.'),
          findsOneWidget,
        );
        expect(repository.writeCalls, 0);
      });

      testWidgets('explains a file that is too large', (tester) async {
        final picker = FakeBackupFilePicker()
          ..error = const BackupFileException(
            'The file is too large to be a backup (over 20 MB).',
          );
        await pumpImport(tester, picker);

        await importFromMenu(tester);

        expect(dialogText('This file can\'t be imported'), findsOneWidget);
        expect(
          dialogText('The file is too large to be a backup (over 20 MB).'),
          findsOneWidget,
        );
      });
    });

    group('a file that cannot be imported', () {
      Future<void> expectRefused(
        WidgetTester tester,
        Uint8List bytes,
        String message,
      ) async {
        final picker = FakeBackupFilePicker()..choose('bad.json', bytes);
        final repository = await pumpImport(tester, picker);
        final before = List.of(repository.items);

        await importFromMenu(tester);

        expect(dialogText('This file can\'t be imported'), findsOneWidget);
        expect(find.textContaining(message), findsOneWidget);
        // No summary and no import button: there is nothing to confirm.
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Import '),
          ),
          findsNothing,
        );
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(repository.items, before);
        expect(repository.writeCalls, 0);
        expect(find.text('Total registrations: 4'), findsOneWidget);
      }

      testWidgets('not JSON', (tester) async {
        await expectRefused(
          tester,
          textBytes('name,roll\nAung,1'),
          'not valid JSON',
        );
      });

      testWidgets('not one of our backups', (tester) async {
        await expectRefused(
          tester,
          textBytes('{"hello": "world"}'),
          'not a graduation registration backup',
        );
      });

      testWidgets('from a newer version of the app', (tester) async {
        await expectRefused(
          tester,
          jsonBytes(backupJson([], version: 7)),
          'newer version of the app',
        );
      });

      testWidgets('empty', (tester) async {
        await expectRefused(tester, Uint8List(0), 'The file is empty.');
      });
    });

    group('the summary', () {
      testWidgets('shows what would happen and writes nothing yet', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('graduation_backup.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([sampleRegistrations()[0]]),
        );

        await importFromMenu(tester);

        expect(dialogText('Import backup?'), findsOneWidget);
        expect(dialogText('graduation_backup.json'), findsOneWidget);
        expect(find.textContaining('Backup version 1'), findsOneWidget);
        expect(dialogText('Records in backup'), findsOneWidget);
        expect(dialogText('New records'), findsOneWidget);
        expect(dialogText('Duplicate records'), findsOneWidget);
        expect(dialogText('Invalid records'), findsOneWidget);
        expect(dialogText('Already in the database'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Import 3 new records'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        // Nothing was written by showing the summary.
        expect(repository.writeCalls, 0);
        expect(repository.items, hasLength(1));
      });

      testWidgets('lists the numbers next to their labels', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose(
            'b.json',
            jsonBytes(
              backupJson([
                for (final r in sampleRegistrations()) recordOf(r),
                recordJson(id: 'bad', rollNo: 'BAD-1', overrides: {'name': ''}),
              ]),
            ),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([sampleRegistrations()[0]]),
        );

        await importFromMenu(tester);

        // Read each label's row: 5 in the backup, 3 new, 1 duplicate, 1 invalid.
        String countNextTo(String label) {
          final row = find.ancestor(
            of: dialogText(label),
            matching: find.byType(Row),
          );
          final texts = tester
              .widgetList<Text>(
                find.descendant(of: row.first, matching: find.byType(Text)),
              )
              .map((t) => t.data)
              .toList();
          return texts.last!;
        }

        expect(countNextTo('Records in backup'), '5');
        expect(countNextTo('New records'), '3');
        expect(countNextTo('Duplicate records'), '1');
        expect(countNextTo('Invalid records'), '1');
      });

      testWidgets('explains each kind of duplicate', (tester) async {
        final stored = [
          sampleRegistrations()[0], // identical: already present
          sampleRegistrations()[1].copyWith(
            name: 'Changed',
          ), // same id, different data
          sampleRegistration(
            id: 'x',
            rollNo: 'LW-001',
            nrc: 'nx',
          ), // Roll No. taken
          sampleRegistration(
            id: 'y',
            rollNo: 'Y-1',
            nrc: '12/LAMANA(N)444444',
          ), // NRC taken
        ];
        final picker = FakeBackupFilePicker()
          ..choose(
            'b.json',
            jsonBytes(
              backupJson([
                for (final r in sampleRegistrations()) recordOf(r),
                recordJson(id: 'r1', rollNo: 'DIFFERENT', nrc: 'different'),
              ]),
            ),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(stored),
        );

        await importFromMenu(tester);

        expect(dialogText('Already in the database'), findsOneWidget);
        expect(
          dialogText(
            'Same ID as a stored record, but different data (not overwritten)',
          ),
          findsNWidgets(1),
        );
        expect(
          dialogText('Roll No. already used by another registration'),
          findsOneWidget,
        );
        expect(
          dialogText('NRC already used by another registration'),
          findsOneWidget,
        );
        expect(dialogText('Repeated within the file'), findsNothing);
      });

      testWidgets('lists invalid records with the reason', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose(
            'b.json',
            jsonBytes(
              backupJson([
                recordOf(sampleRegistrations()[0]),
                recordJson(id: 'a', rollNo: 'CS-9', overrides: {'name': ''}),
                null,
              ]),
            ),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );

        await importFromMenu(tester);

        expect(
          dialogText('Record 2 (CS-9): Name is required.'),
          findsOneWidget,
        );
        expect(
          dialogText('Record 3: Not a record: expected an object.'),
          findsOneWidget,
        );
      });

      testWidgets('lists only the first ten invalid records', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose(
            'b.json',
            jsonBytes(backupJson([for (var i = 0; i < 14; i++) null])),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );

        await importFromMenu(tester);

        expect(
          dialogText('Record 10: Not a record: expected an object.'),
          findsOneWidget,
        );
        expect(
          dialogText('Record 11: Not a record: expected an object.'),
          findsNothing,
        );
        expect(dialogText('…and 4 more'), findsOneWidget);
      });

      testWidgets('warns when the file\'s record count is wrong', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose(
            'b.json',
            jsonBytes(
              backupJson([recordOf(sampleRegistrations()[0])], recordCount: 40),
            ),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );

        await importFromMenu(tester);

        expect(
          find.textContaining('The file says it holds 40 records'),
          findsOneWidget,
        );
        // A warning does not block the import.
        expect(
          find.widgetWithText(FilledButton, 'Import 1 new record'),
          findsOneWidget,
        );
      });

      testWidgets('says that existing records are never changed', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );

        await importFromMenu(tester);

        expect(find.textContaining('never changed or deleted'), findsOneWidget);
      });

      testWidgets('Cancel imports nothing', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );
        await importFromMenu(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(repository.items, isEmpty);
        expect(repository.writeCalls, 0);
        expect(find.text('Import completed.'), findsNothing);
      });

      testWidgets('offers only Close when nothing would be added', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(tester, picker);

        await importFromMenu(tester);

        expect(dialogText('Nothing to import'), findsOneWidget);
        expect(find.textContaining('Import 0'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        expect(dialogText('Already in the database'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(repository.writeCalls, 0);
      });
    });

    group('importing', () {
      testWidgets(
        'adds the new records, shows the result, refreshes the list',
        (tester) async {
          final picker = FakeBackupFilePicker()
            ..choose('b.json', backupFile(sampleRegistrations()));
          final repository = await pumpImport(
            tester,
            picker,
            repository: FakeRegistrationRepository([sampleRegistrations()[0]]),
          );
          expect(find.text('Total registrations: 1'), findsOneWidget);
          await importFromMenu(tester);

          await confirmImport(tester, 'Import 3 new records');

          expect(dialogText('Import completed.'), findsOneWidget);
          expect(dialogText('New records: 3'), findsOneWidget);
          expect(dialogText('Skipped duplicates: 1'), findsOneWidget);
          expect(dialogText('Invalid records: 0'), findsOneWidget);
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(repository.items, sampleRegistrations());
          expect(find.text('Total registrations: 4'), findsOneWidget);
          for (final name in ['Aung Aung', 'Mya Mya', 'Kyaw Kyaw', 'Su Su']) {
            expect(find.text(name), findsOneWidget, reason: name);
          }
        },
      );

      testWidgets('restores records exactly, ids and dates included', (
        tester,
      ) async {
        final original = [
          sampleRegistration(
            id: 'orig-1',
            createdAt: DateTime.utc(2020, 1, 2, 3, 4, 5),
            updatedAt: DateTime.utc(2021, 6, 7, 8, 9, 10),
          ),
        ];
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(original));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );
        await importFromMenu(tester);

        await confirmImport(tester, 'Import 1 new record');

        expect(repository.items, original);
      });

      testWidgets('reports skipped duplicates and invalid records', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose(
            'b.json',
            jsonBytes(
              backupJson([
                for (final r in sampleRegistrations()) recordOf(r),
                null,
                recordJson(id: 'bad', overrides: {'email': 'nope'}),
              ]),
            ),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([
            sampleRegistrations()[0],
            sampleRegistrations()[1],
          ]),
        );
        await importFromMenu(tester);

        await confirmImport(tester, 'Import 2 new records');

        expect(dialogText('New records: 2'), findsOneWidget);
        expect(dialogText('Skipped duplicates: 2'), findsOneWidget);
        expect(dialogText('Invalid records: 2'), findsOneWidget);
      });

      testWidgets('never changes or deletes what is already stored', (
        tester,
      ) async {
        final mine = sampleRegistration(
          id: 'mine',
          name: 'Only Here',
          rollNo: 'MINE-1',
          nrc: '12/MINE(N)1',
        );
        final changed = sampleRegistrations()[0].copyWith(name: 'Changed Here');
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([mine, changed]),
        );
        await importFromMenu(tester);

        await confirmImport(tester, 'Import 3 new records');

        expect(repository.items, containsAll([mine, changed]));
        expect(repository.items, hasLength(5));
        expect(find.text('Changed Here'), findsOneWidget);
      });

      testWidgets('keeps the search and filters in place', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([sampleRegistrations()[0]]),
        );
        // Roll No. LW-001 and LW-002 are the two law students.
        await search(tester, 'lw-');
        expect(find.text('No registrations match'), findsOneWidget);
        await importFromMenu(tester);

        await confirmImport(tester, 'Import 3 new records');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // Only the law students are shown, out of all four.
        expect(find.text('Showing 2 of 4'), findsOneWidget);
        expect(find.text('Kyaw Kyaw'), findsOneWidget);
        expect(find.text('Aung Aung'), findsNothing);
      });

      testWidgets('leaves everything as it was if the write fails', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([sampleRegistrations()[0]]),
        );
        repository.restoreError = StateError('disk full');
        await importFromMenu(tester);

        await confirmImport(tester, 'Import 3 new records');

        expect(dialogText('Import failed'), findsOneWidget);
        expect(find.textContaining('nothing was changed'), findsOneWidget);
        expect(find.text('Import completed.'), findsNothing);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(repository.items, [sampleRegistrations()[0]]);
        expect(find.text('Total registrations: 1'), findsOneWidget);
      });

      testWidgets('can be retried after a failure', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );
        repository.restoreError = StateError('disk full');
        await importFromMenu(tester);
        await confirmImport(tester, 'Import 4 new records');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        repository.restoreError = null;
        await importFromMenu(tester);
        await confirmImport(tester, 'Import 4 new records');

        expect(dialogText('New records: 4'), findsOneWidget);
        expect(repository.items, hasLength(4));
      });

      testWidgets('skips a record another tab stored in the meantime', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );
        await importFromMenu(tester);
        expect(
          find.widgetWithText(FilledButton, 'Import 4 new records'),
          findsOneWidget,
        );
        // Another tab registers someone with a Roll No. from the backup.
        repository.items.add(
          sampleRegistration(id: 'other-tab', rollNo: 'CS-001', nrc: 'nx'),
        );

        await confirmImport(tester, 'Import 4 new records');

        // The result tells the truth: one fewer was added.
        expect(dialogText('New records: 3'), findsOneWidget);
        expect(dialogText('Skipped duplicates: 1'), findsOneWidget);
        expect(repository.items, hasLength(4));
      });

      testWidgets('blocks every action while the file is being read', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(tester, picker);
        repository.getAllGate = Completer<void>();

        await tester.tap(find.text('Import Backup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // The spinner animates forever, so advance time by hand.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        for (final action in DataAction.values) {
          expect(
            actionEnabled(tester, action.label),
            isFalse,
            reason: action.label,
          );
        }

        repository.getAllGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(dialogText('Nothing to import'), findsOneWidget);
      });
    });

    group('from the empty list', () {
      testWidgets('offers Import a backup next to Register someone', (
        tester,
      ) async {
        await pumpImport(
          tester,
          FakeBackupFilePicker(),
          repository: FakeRegistrationRepository(),
        );

        expect(find.text('Register someone'), findsOneWidget);
        expect(find.text('Import a backup'), findsOneWidget);
      });

      testWidgets('restores a whole backup into a fresh browser', (
        tester,
      ) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
        );

        await tester.tap(find.text('Import a backup'));
        await tester.pumpAndSettle();
        expect(dialogText('Import backup?'), findsOneWidget);
        await confirmImport(tester, 'Import 4 new records');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(repository.items, sampleRegistrations());
        expect(find.text('Total registrations: 4'), findsOneWidget);
        expect(find.text('No registrations yet'), findsNothing);
        // The list is not empty any more, so exporting is possible too.
        expect(actionEnabled(tester, 'Export Excel'), isTrue);
      });

      testWidgets('works on a phone', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose('b.json', backupFile(sampleRegistrations()));
        final repository = await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository(),
          size: _phone,
        );

        await tester.tap(find.text('Import a backup'));
        await tester.pumpAndSettle();
        await confirmImport(tester, 'Import 4 new records');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(repository.items, hasLength(4));
        expect(find.byType(RegistrationCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    });

    group('on small screens', () {
      testWidgets('the summary and result do not overflow', (tester) async {
        final picker = FakeBackupFilePicker()
          ..choose(
            'a_rather_long_backup_file_name_from_the_graduation_office_2026.json',
            jsonBytes(
              backupJson([
                for (final r in sampleRegistrations()) recordOf(r),
                for (var i = 0; i < 12; i++)
                  recordJson(
                    id: 'bad-$i',
                    rollNo: 'A-VERY-LONG-ROLL-NUMBER-$i',
                    overrides: {'email': 'not-an-email', 'phoneNo': 'abc'},
                  ),
              ], recordCount: 99),
            ),
          );
        await pumpImport(
          tester,
          picker,
          repository: FakeRegistrationRepository([sampleRegistrations()[0]]),
          size: const Size(320, 640),
        );

        await importFromMenu(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.dragUntilVisible(
          find.widgetWithText(FilledButton, 'Import 3 new records'),
          find.byType(AlertDialog),
          const Offset(0, -100),
        );
        await confirmImport(tester, 'Import 3 new records');

        expect(tester.takeException(), isNull);
        expect(dialogText('Import completed.'), findsOneWidget);
      });
    });
  });

  group('navigation', () {
    testWidgets('opens from the form page and goes back', (tester) async {
      final repository = FakeRegistrationRepository(sampleRegistrations());
      setSize(tester, _desktop);
      await tester.pumpWidget(
        adminApp(
          await adminSession(tester),
          RegistrationFormPage(repository: repository),
        ),
      );

      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsOneWidget);
      expect(find.text('Total registrations: 4'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsNothing);
      expect(find.text('Registration Form'), findsOneWidget);
    });

    testWidgets('opens from the form page on a phone', (tester) async {
      final repository = FakeRegistrationRepository(sampleRegistrations());
      setSize(tester, _phone);
      await tester.pumpWidget(
        adminApp(
          await adminSession(tester),
          RegistrationFormPage(repository: repository),
        ),
      );

      // Icon only, so the page title keeps its room.
      expect(find.text('Registrations'), findsNothing);
      expect(find.text('Graduation Registration'), findsOneWidget);
      await tester.tap(find.byTooltip('Registrations'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationListPage), findsOneWidget);
      expect(find.text('Total registrations: 4'), findsOneWidget);
    });

    testWidgets('"Register someone" goes back to the form', (tester) async {
      final repository = FakeRegistrationRepository();
      setSize(tester, _desktop);
      await tester.pumpWidget(
        adminApp(
          await adminSession(tester),
          RegistrationFormPage(repository: repository),
        ),
      );
      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Register someone'));
      await tester.pumpAndSettle();

      expect(find.text('Registration Form'), findsOneWidget);
    });

    testWidgets('shows a person registered a moment ago', (tester) async {
      final repository = FakeRegistrationRepository();
      setSize(tester, _desktop);
      await tester.pumpWidget(
        adminApp(
          await adminSession(tester),
          RegistrationFormPage(repository: repository),
        ),
      );
      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();
      expect(find.text('Total registrations: 0'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      repository.items.add(
        GraduationRegistration.draft(
          name: 'Late Comer',
          fatherName: 'U Late',
          phoneNo: '0912345678',
          nrc: '12/LAMANA(N)999999',
          rollNo: 'CS-999',
          major: 'Law',
          attendanceStatus: sampleRegistrations().first.attendanceStatus,
          currentCountry: sampleRegistrations().first.currentCountry,
        ).copyWith(id: 'late', createdAt: DateTime.utc(2026, 9, 9, 12)),
      );
      await tester.tap(find.text('Registrations'));
      await tester.pumpAndSettle();

      expect(find.text('Total registrations: 1'), findsOneWidget);
      expect(find.text('Late Comer'), findsOneWidget);
    });
  });
}

/// One kind of export, so the Excel report and the JSON backup are tested with
/// the same scenarios.
class _ExportKind {
  const _ExportKind({
    required this.label,
    required this.fileName,
    required this.mimeType,
    required this.success,
    required this.emptyMessage,
    required this.failureMessage,
    required this.recordCount,
  });

  /// The menu entry.
  final String label;
  final String fileName;
  final String mimeType;

  /// The success message for [count] registrations.
  final String Function(int count) success;
  final String emptyMessage;
  final String failureMessage;

  /// How many registrations the downloaded file holds.
  final int Function(Uint8List bytes) recordCount;
}
