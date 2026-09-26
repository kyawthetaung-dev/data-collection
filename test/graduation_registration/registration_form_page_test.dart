import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/graduation_registration.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/entities/registration_enums.dart';
import 'package:ucss_data_collection/features/graduation_registration/domain/failures.dart';
import 'package:ucss_data_collection/features/graduation_registration/presentation/pages/registration_form_page.dart';

import '../admin_access/support/admin_test_support.dart';
import 'support/fake_registration_repository.dart';

const _desktop = Size(1280, 3000);
const _phone = Size(390, 4000);

Future<void> pumpForm(
  WidgetTester tester,
  FakeRegistrationRepository repository, {
  Size size = _desktop,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The public form: nobody is in Admin Mode.
  final session = await adminSession(tester, signedIn: false);
  await tester.pumpWidget(
    adminApp(session, RegistrationFormPage(repository: repository)),
  );
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> fillValidForm(
  WidgetTester tester, {
  String rollNo = 'CS-001',
  String nrc = '12/LAMANA(N)123456',
}) async {
  await tester.enterText(field('Name *'), 'Aung Aung');
  await tester.enterText(field('Father Name *'), 'U Kyaw');
  await tester.enterText(field('NRC *'), nrc);
  await tester.enterText(field('Roll No. *'), rollNo);
  await tester.enterText(field('Major *'), 'Computer Science');
  await tester.enterText(field('Phone No. *'), '+95 9 123 456 789');
  await tester.tap(find.widgetWithText(ChoiceChip, 'Can Attend'));
  await tester.tap(find.widgetWithText(ChoiceChip, 'Japan'));
  await tester.pump();
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.text('Submit Registration'));
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(field(label)).controller!.text;

GraduationRegistration existing({
  String rollNo = 'CS-001',
  String nrc = '12/LAMANA(N)123456',
}) => GraduationRegistration(
  id: 'existing-1',
  name: 'Existing Person',
  fatherName: 'U Existing',
  phoneNo: '0912345678',
  nrc: nrc,
  rollNo: rollNo,
  major: 'Law',
  attendanceStatus: AttendanceStatus.canAttend,
  currentCountry: CurrentCountry.myanmar,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

void main() {
  testWidgets('shows every section and field', (tester) async {
    await pumpForm(tester, FakeRegistrationRepository());

    for (final heading in [
      'Personal Information',
      'Contact Information',
      'Graduation Attendance',
      'Current Location',
      'Additional Information',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    for (final label in [
      'Name *',
      'Father Name *',
      'Mother Name',
      'NRC *',
      'Roll No. *',
      'Major *',
      'Phone No. *',
      'Email',
      'Current City',
      'Remark',
    ]) {
      expect(field(label), findsOneWidget, reason: label);
    }
    for (final chip in [
      'Can Attend',
      'Cannot Attend',
      'Myanmar',
      'Japan',
      'Singapore',
      'Korea',
      'Other',
    ]) {
      expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget);
    }
    expect(find.text('Submit Registration'), findsOneWidget);
  });

  group('layout', () {
    testWidgets('uses two columns on a wide screen', (tester) async {
      await pumpForm(tester, FakeRegistrationRepository());

      final name = tester.getTopLeft(field('Name *'));
      final father = tester.getTopLeft(field('Father Name *'));
      expect(father.dy, name.dy);
      expect(father.dx, greaterThan(name.dx));
    });

    testWidgets('uses one full-width column on a phone', (tester) async {
      await pumpForm(tester, FakeRegistrationRepository(), size: _phone);

      final name = tester.getRect(field('Name *'));
      final father = tester.getRect(field('Father Name *'));
      expect(father.left, name.left);
      expect(father.top, greaterThan(name.bottom));
      // Full width: the card padding is all that is left of the screen.
      expect(name.width, greaterThan(_phone.width - 2 * (16 + 20 + 1)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('caps the form width on a very wide screen', (tester) async {
      await pumpForm(
        tester,
        FakeRegistrationRepository(),
        size: const Size(2000, 3000),
      );

      final card = tester.getRect(
        find.ancestor(
          of: find.text('Personal Information'),
          matching: find.byType(Card),
        ),
      );
      expect(card.width, RegistrationFormPage.maxContentWidth);
      expect(card.center.dx, 1000);
    });

    testWidgets('submit button spans the width on a phone', (tester) async {
      await pumpForm(tester, FakeRegistrationRepository(), size: _phone);

      final button = tester.getRect(find.byType(FilledButton));
      expect(button.width, greaterThan(_phone.width - 2 * 16 - 1));
      expect(button.height, greaterThanOrEqualTo(48));
    });
  });

  group('Other Country', () {
    testWidgets('appears only when Other is selected', (tester) async {
      await pumpForm(tester, FakeRegistrationRepository());
      expect(field('Other Country *'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Other'));
      await tester.pumpAndSettle();
      expect(field('Other Country *'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Korea'));
      await tester.pumpAndSettle();
      expect(field('Other Country *'), findsNothing);
    });

    testWidgets('is required when Other is selected', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);
      await fillValidForm(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Other'));
      await tester.pumpAndSettle();

      await submit(tester);

      expect(
        find.text('Other Country is required when Current Country is Other.'),
        findsOneWidget,
      );
      expect(repository.items, isEmpty);
    });

    testWidgets('is saved when Other is selected', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);
      await fillValidForm(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Other'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Other Country *'), 'Thailand');

      await submit(tester);

      expect(repository.items.single.currentCountry, CurrentCountry.other);
      expect(repository.items.single.otherCountry, 'Thailand');
    });
  });

  group('validation', () {
    testWidgets('an empty submit reports every required field', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);

      await submit(tester);

      for (final message in [
        'Name is required.',
        'Father Name is required.',
        'NRC is required.',
        'Roll No. is required.',
        'Major is required.',
        'Phone No. is required.',
        'Attendance Status is required.',
        'Current Country is required.',
      ]) {
        expect(find.text(message), findsOneWidget, reason: message);
      }
      expect(repository.items, isEmpty);
    });

    testWidgets('rejects a malformed email and phone number', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);
      await fillValidForm(tester);
      await tester.enterText(field('Email'), 'not-an-email');
      await tester.enterText(field('Phone No. *'), 'abc');

      await submit(tester);

      expect(find.text('Email is not valid.'), findsOneWidget);
      expect(find.text('Phone No. is not valid.'), findsOneWidget);
      expect(repository.items, isEmpty);
    });

    testWidgets('optional fields may stay empty', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);
      await fillValidForm(tester);

      await submit(tester);

      final saved = repository.items.single;
      expect(saved.motherName, isNull);
      expect(saved.email, isNull);
      expect(saved.currentCity, isNull);
      expect(saved.remark, isNull);
    });
  });

  group('submit', () {
    testWidgets('saves, confirms and clears the form', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);
      await fillValidForm(tester);
      await tester.enterText(field('Mother Name'), 'Daw Mya');
      await tester.enterText(field('Email'), 'aung@example.com');
      await tester.enterText(field('Current City'), 'Tokyo');
      await tester.enterText(field('Remark'), 'Line 1\nLine 2');

      await submit(tester);

      final saved = repository.items.single;
      expect(saved.name, 'Aung Aung');
      expect(saved.fatherName, 'U Kyaw');
      expect(saved.motherName, 'Daw Mya');
      expect(saved.nrc, '12/LAMANA(N)123456');
      expect(saved.rollNo, 'CS-001');
      expect(saved.major, 'Computer Science');
      expect(saved.phoneNo, '+95 9 123 456 789');
      expect(saved.email, 'aung@example.com');
      expect(saved.currentCity, 'Tokyo');
      expect(saved.remark, 'Line 1\nLine 2');
      expect(saved.attendanceStatus, AttendanceStatus.canAttend);
      expect(saved.currentCountry, CurrentCountry.japan);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Registration saved'), findsOneWidget);
      expect(find.textContaining('CS-001'), findsOneWidget);

      for (final label in [
        'Name *',
        'Father Name *',
        'Mother Name',
        'NRC *',
        'Roll No. *',
        'Major *',
        'Phone No. *',
        'Email',
        'Current City',
        'Remark',
      ]) {
        expect(textOf(tester, label), isEmpty, reason: label);
      }
      for (final chip in tester.widgetList<ChoiceChip>(
        find.byType(ChoiceChip),
      )) {
        expect(chip.selected, isFalse);
      }
      // No validation errors right after the reset.
      expect(find.textContaining('is required'), findsNothing);
    });

    testWidgets('can register a second person straight after', (tester) async {
      final repository = FakeRegistrationRepository();
      await pumpForm(tester, repository);
      await fillValidForm(tester);
      await submit(tester);

      await fillValidForm(tester, rollNo: 'CS-002', nrc: '12/LAMANA(N)000002');
      await submit(tester);

      expect(repository.items.map((r) => r.rollNo), ['CS-001', 'CS-002']);
    });

    testWidgets('shows progress and blocks a second submit while saving', (
      tester,
    ) async {
      final repository = FakeRegistrationRepository()
        ..createGate = Completer<void>();
      await pumpForm(tester, repository);
      await fillValidForm(tester);

      await tester.tap(find.text('Submit Registration'));
      await tester.pump();

      expect(find.text('Saving…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Saving…'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNull);

      repository.createGate!.complete();
      await tester.pumpAndSettle();

      expect(repository.items, hasLength(1));
      expect(find.text('Submit Registration'), findsOneWidget);
    });

    testWidgets('keeps the data and shows an error when saving fails', (
      tester,
    ) async {
      final repository = FakeRegistrationRepository()
        ..createError = StateError('IndexedDB is unavailable');
      await pumpForm(tester, repository);
      await fillValidForm(tester);

      await submit(tester);

      expect(
        find.text('Could not save the registration. Please try again.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'Name *'), 'Aung Aung');
      expect(find.byType(SnackBar), findsNothing);

      // A retry works once the problem is gone.
      repository.createError = null;
      await submit(tester);

      expect(repository.items, hasLength(1));
      expect(
        find.text('Could not save the registration. Please try again.'),
        findsNothing,
      );
    });
  });

  group('duplicates', () {
    testWidgets('reports a duplicate Roll No. and NRC together', (
      tester,
    ) async {
      final repository = FakeRegistrationRepository([existing()]);
      await pumpForm(tester, repository);
      await fillValidForm(tester);

      await submit(tester);

      expect(find.text('This Roll No. is already registered.'), findsOneWidget);
      expect(find.text('This NRC is already registered.'), findsOneWidget);
      expect(repository.items, hasLength(1));
      expect(textOf(tester, 'Name *'), 'Aung Aung');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('reports only the Roll No. when only it is taken', (
      tester,
    ) async {
      final repository = FakeRegistrationRepository([existing()]);
      await pumpForm(tester, repository);
      await fillValidForm(tester, nrc: '12/LAMANA(N)999999');

      await submit(tester);

      expect(find.text('This Roll No. is already registered.'), findsOneWidget);
      expect(find.text('This NRC is already registered.'), findsNothing);
    });

    testWidgets('matches ignoring case and spacing', (tester) async {
      final repository = FakeRegistrationRepository([existing()]);
      await pumpForm(tester, repository);
      await fillValidForm(
        tester,
        rollNo: ' cs - 001 ',
        nrc: '12/lamana(n) 999',
      );

      await submit(tester);

      expect(find.text('This Roll No. is already registered.'), findsOneWidget);
    });

    testWidgets('clears the error once the field is edited', (tester) async {
      final repository = FakeRegistrationRepository([existing()]);
      await pumpForm(tester, repository);
      await fillValidForm(tester);
      await submit(tester);

      await tester.enterText(field('Roll No. *'), 'CS-002');
      await tester.pump();
      expect(find.text('This Roll No. is already registered.'), findsNothing);
      expect(find.text('This NRC is already registered.'), findsOneWidget);

      await tester.enterText(field('NRC *'), '12/LAMANA(N)000002');
      await submit(tester);

      expect(repository.items, hasLength(2));
    });

    testWidgets('reports a duplicate found only while saving', (tester) async {
      // Another tab takes the values after the form's own check passed, so
      // only the repository's write-time failure reports them.
      final repository = FakeRegistrationRepository()
        ..createError = const DuplicateNrcFailure('12/LAMANA(N)123456');
      await pumpForm(tester, repository);
      await fillValidForm(tester);

      await submit(tester);

      expect(find.text('This NRC is already registered.'), findsOneWidget);
      expect(find.text('This Roll No. is already registered.'), findsNothing);
      expect(
        find.text('Could not save the registration. Please try again.'),
        findsNothing,
      );
      expect(textOf(tester, 'Name *'), 'Aung Aung');
    });
  });
}
