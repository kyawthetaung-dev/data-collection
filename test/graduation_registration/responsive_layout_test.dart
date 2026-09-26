import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/app_theme.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_scope.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/export/registration_backup_builder.dart';
import 'package:ucss_data_collection/features/graduation_registration/data/import/registration_import_service.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_form_page.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_list_page.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/data_actions_menu.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/list_loading_skeleton.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/registration_card.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/widgets/registration_table.dart';

import '../admin_access/support/admin_test_support.dart';
import 'support/backup_test_data.dart';
import 'support/fake_backup_file_picker.dart';
import 'support/fake_registration_repository.dart';
import 'support/sample_registrations.dart';
import 'support/test_fonts.dart';

/// Every screen and dialog is checked at these screen widths (phones, tablets,
/// laptops, desktops) and at these text sizes (the user's own setting, up to
/// double).
const _widths = [
  320.0,
  360.0,
  390.0,
  600.0,
  768.0,
  1024.0,
  1100.0,
  1280.0,
  1920.0,
];
const _textScales = [1.0, 1.5, 2.0];
const _height = 900.0;

/// Registrations whose text is far longer than any real one, to stress every
/// layout.
final _longRegistration = sampleRegistration(
  id: 'long',
  name: 'Maung Maung Aung Kyaw Zaw Win Htet Naing Oo Thura Hlaing Min',
  fatherName: 'U Kyaw Zaw Win Htet Naing Oo Thura Hlaing Min Maung',
  motherName: 'Daw Mya Mya Aye Aye Khin Khin Soe Soe Win Win Nu',
  major: 'Computer Engineering and Information Technology Studies',
  rollNo: 'UCSS-2019-COMPUTER-ENGINEERING-0001',
  nrc: '12/LAMANA(N)123456-EXTRA-LONG-NRC-VALUE',
  phoneNo: '+95 9 123 456 789 ext 1234567',
  currentCountry: CurrentCountry.other,
  otherCountry: 'United Kingdom of Great Britain and Northern Ireland',
  currentCity: 'Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch',
  email:
      'a.very.long.email.address.for.testing.purposes@some.long.domain.example.com',
  remark:
      'A long remark that keeps going on and on to check that a paragraph of '
          'text wraps inside its card instead of running out of the screen. ' *
      3,
  createdAt: DateTime.utc(2026, 9, 1, 12),
);

List<GraduationRegistration> _data() => [
  ...sampleRegistrations(),
  _longRegistration,
];

void main() {
  late bool realFonts;
  setUpAll(() async => realFonts = await loadRealFonts());

  for (final width in _widths) {
    for (final scale in _textScales) {
      testWidgets(
        'no overflow at ${width.toInt()} px wide, text ${(scale * 100).toInt()}%',
        (tester) async {
          if (!realFonts) {
            markTestSkipped('Flutter SDK fonts not found');
            return;
          }
          tester.view.physicalSize = Size(width, _height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          // Signed in, so the admin-only pages can be shown; the public form is
          // also checked, with a session that is logged out.
          final admin = await adminSession(tester);
          final visitor = await adminSession(tester, signedIn: false);

          Future<void> show(
            Widget home, {
            bool settle = true,
            AdminSession? session,
          }) async {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => AdminScope(
                  session: session ?? admin,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                ),
                home: home,
              ),
            );
            if (settle) {
              await tester.pumpAndSettle();
            } else {
              await tester.pump(ListLoadingSkeleton.showDelay);
              await tester.pump(const Duration(milliseconds: 300));
            }
          }

          /// Fails, naming the screen, if anything overflowed or if the page
          /// scrolls sideways.
          void expectFits(String screen) {
            final reason = '$screen at ${width.toInt()} px, text $scale';
            expect(tester.takeException(), isNull, reason: reason);
            // A text field scrolls its own text sideways; that is not the page.
            final sideways = find
                .byWidgetPredicate(
                  (w) => w is Scrollable && w.axis == Axis.horizontal,
                )
                .evaluate()
                .where((element) {
                  var insideTextField = false;
                  element.visitAncestorElements((ancestor) {
                    if (ancestor.widget is EditableText) insideTextField = true;
                    return !insideTextField;
                  });
                  return !insideTextField;
                });
            expect(sideways, isEmpty, reason: '$reason scrolls sideways');
          }

          /// Uses a data action the way a user would on this screen.
          Future<void> useAction(String label) async {
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

          Widget list(
            FakeRegistrationRepository repo, {
            FakeBackupFilePicker? picker,
          }) => RegistrationListPage(
            repository: repo,
            importService: RegistrationImportService(repository: repo),
            filePicker: picker,
          );

          // ---- the registration form, as a visitor and as an admin
          final repo = FakeRegistrationRepository(_data());
          await show(RegistrationFormPage(repository: repo), session: visitor);
          expectFits('public registration form');

          await show(RegistrationFormPage(repository: repo));
          expectFits('registration form in Admin Mode');

          await tester.tap(find.text('Submit Registration'));
          await tester.pumpAndSettle();
          expectFits('registration form with every error showing');

          await tester.tap(find.widgetWithText(ChoiceChip, 'Other'));
          await tester.pumpAndSettle();
          expectFits('registration form with Other Country');

          await show(
            RegistrationFormPage(
              repository: repo,
              initialRegistration: _longRegistration,
            ),
          );
          expectFits('edit form with very long values');

          // ---- the list
          await show(list(repo));
          expectFits('list');
          final tableExpected = width >= 1100 && scale <= 1.3;
          expect(
            find.byType(RegistrationTable).evaluate().isNotEmpty,
            tableExpected,
            reason: 'table only on wide screens with normal text',
          );
          expect(
            find.byType(RegistrationCard).evaluate().isNotEmpty,
            !tableExpected,
            reason: 'cards everywhere else',
          );
          expect(
            find.text('Export Excel').evaluate().isNotEmpty,
            width >= 720,
            reason: 'action buttons only from tablet width; a menu below',
          );

          await show(list(FakeRegistrationRepository(_data())));
          await tester.tap(find.byTooltip('View details').first);
          await tester.pumpAndSettle();
          expectFits('registration details');
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Delete').first);
          await tester.pumpAndSettle();
          expectFits('delete confirmation');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          await show(list(FakeRegistrationRepository()));
          expectFits('empty list');

          await show(
            list(
              FakeRegistrationRepository(_data())
                ..getAllError = StateError('x'),
            ),
          );
          expectFits('list that failed to load');

          await show(
            list(
              FakeRegistrationRepository(_data())
                ..getAllGate = Completer<void>(),
            ),
            settle: false,
          );
          expectFits('list while loading');

          await show(list(FakeRegistrationRepository(_data())));
          await tester.enterText(find.byType(TextField), 'zzz');
          await tester.pumpAndSettle();
          expectFits('list with no search matches');

          // ---- importing
          final backup = const RegistrationBackupBuilder().build(
            _data(),
            exportedAt: DateTime.utc(2026, 9, 25, 8, 30),
          );
          final messy = jsonBytes(
            backupJson([
              for (final r in _data()) recordOf(r),
              for (var i = 0; i < 12; i++)
                recordJson(
                  id: 'bad-$i',
                  rollNo: 'A-VERY-LONG-ROLL-NUMBER-FOR-A-BROKEN-RECORD-$i',
                  overrides: {'email': 'not-an-email', 'phoneNo': 'abc'},
                ),
            ], recordCount: 99),
          );

          final picker = FakeBackupFilePicker()
            ..choose(
              'a_rather_long_backup_file_name_from_the_graduation_office_2026.json',
              messy,
            );
          await show(
            list(FakeRegistrationRepository([_data().first]), picker: picker),
          );
          await useAction('Import Backup');
          expectFits('import summary');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          picker.choose('b.json', backup);
          await show(list(FakeRegistrationRepository(), picker: picker));
          await useAction('Import Backup');
          await tester.tap(find.textContaining('Import ').last);
          await tester.pumpAndSettle();
          expectFits('import result');
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();

          picker.choose('notes.json', textBytes('{"hello": "world"}'));
          await show(list(FakeRegistrationRepository(_data()), picker: picker));
          await useAction('Import Backup');
          expectFits('import error');
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
