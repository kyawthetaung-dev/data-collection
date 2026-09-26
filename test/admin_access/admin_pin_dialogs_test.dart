import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_mode_button.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_pin_dialogs.dart';
import 'package:ucss_data_collection/app_theme.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_scope.dart';

import '../graduation_registration/support/test_fonts.dart';
import 'support/admin_test_support.dart';
import 'support/fake_admin_pin_store.dart';

const _desktop = Size(1280, 900);
const _phone = Size(390, 800);

/// What the launcher's last request for Admin Mode resolved to.
bool? _granted;

/// A page with one button that asks for Admin Mode, and a place for the
/// AppBar control, so both ways in are covered.
Future<AdminSession> pumpLauncher(
  WidgetTester tester, {
  bool hasPin = true,
  Size size = _desktop,
  double textScale = 1,
  FakeAdminPinStore? store,
  DateTime Function()? now,
  bool signedIn = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _granted = null;

  final session = await adminSession(
    tester,
    signedIn: hasPin || signedIn,
    store: store,
    now: now,
  );
  // Has a PIN, but is logged out, like a visitor after a refresh.
  if (hasPin && !signedIn) session.logout();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => AdminScope(
        session: session,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(actions: const [AdminModeButton()]),
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () async =>
                  _granted = await requestAdminAccess(context),
              child: const Text('Open Admin'),
            ),
          ),
        ),
      ),
    ),
  );
  return session;
}

/// Lets real asynchronous work (the hashing) finish, then settles the frames.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<void> openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open Admin'));
  await settle(tester);
}

Finder pinField([String? label]) => label == null
    ? find.byType(TextField)
    : find.widgetWithText(TextField, label);

Future<void> typePin(WidgetTester tester, String pin, [String? label]) async {
  await tester.enterText(pinField(label), pin);
  await tester.pump();
}

Future<void> tapLogin(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Login'));
  await settle(tester);
}

Finder dialog() => find.byType(AlertDialog);

/// The dialog's visible surface. The `AlertDialog` widget itself spans the whole
/// screen, because it includes the margin around the card.
Finder dialogSurface() =>
    find.descendant(of: dialog(), matching: find.byType(Material)).first;

/// What the text fields really draw, one entry per field.
List<String> drawnFieldText(WidgetTester tester) => [
  for (final element
      in find
          .byElementPredicate((e) => e.renderObject is RenderEditable)
          .evaluate())
    (element.renderObject! as RenderEditable).text!.toPlainText(),
];

Finder dialogText(String text) =>
    find.descendant(of: dialog(), matching: find.text(text));

void main() {
  late bool realFonts;
  setUpAll(() async => realFonts = await loadRealFonts());

  group('logging in', () {
    testWidgets('asks for the PIN when one is set', (tester) async {
      await pumpLauncher(tester);

      await openDialog(tester);

      expect(dialogText('Admin PIN'), findsOneWidget);
      expect(pinField('PIN'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
    });

    testWidgets('masks the PIN', (tester) async {
      await pumpLauncher(tester);
      await openDialog(tester);

      await typePin(tester, '4815');

      expect(tester.widget<TextField>(pinField()).obscureText, isTrue);
      // What is drawn is bullets, not the digits.
      expect(drawnFieldText(tester), ['••••']);
      // And no ordinary text on the screen holds the PIN.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains('4815'),
        ),
        findsNothing,
      );
    });

    testWidgets('has no way to reveal the PIN', (tester) async {
      await pumpLauncher(tester);
      await openDialog(tester);

      expect(find.byIcon(Icons.visibility), findsNothing);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
      expect(
        tester.widget<TextField>(pinField()).decoration!.suffixIcon,
        isNull,
      );
    });

    testWidgets('takes digits only, up to 12', (tester) async {
      await pumpLauncher(tester);
      await openDialog(tester);

      await typePin(tester, 'ab12 cd34-.');
      expect(tester.widget<TextField>(pinField()).controller!.text, '1234');

      await typePin(tester, '9' * 20);
      expect(
        tester.widget<TextField>(pinField()).controller!.text,
        '9' * AdminPinRules.maxLength,
      );
    });

    testWidgets('opens the number keypad on a phone', (tester) async {
      await pumpLauncher(tester, size: _phone);
      await openDialog(tester);

      expect(
        tester.widget<TextField>(pinField()).keyboardType,
        TextInputType.number,
      );
    });

    testWidgets('with the right PIN turns Admin Mode on and closes', (
      tester,
    ) async {
      final session = await pumpLauncher(tester);
      await openDialog(tester);

      await typePin(tester, testPin);
      await tapLogin(tester);

      expect(session.isAdmin, isTrue);
      expect(dialog(), findsNothing);
      expect(_granted, isTrue);
      expect(find.text('Admin mode is on.'), findsOneWidget);
    });

    testWidgets('the Enter key logs in too', (tester) async {
      final session = await pumpLauncher(tester);
      await openDialog(tester);

      await typePin(tester, testPin);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(session.isAdmin, isTrue);
      expect(dialog(), findsNothing);
    });

    testWidgets('with a wrong PIN shows an error and stays logged out', (
      tester,
    ) async {
      final session = await pumpLauncher(tester);
      await openDialog(tester);

      await typePin(tester, '0000');
      await tapLogin(tester);

      expect(dialogText('Incorrect PIN.'), findsOneWidget);
      expect(session.isAdmin, isFalse);
      expect(dialog(), findsOneWidget);
      // The wrong PIN is not left in the field.
      expect(tester.widget<TextField>(pinField()).controller!.text, isEmpty);
    });

    testWidgets('lets the user try again after a wrong PIN', (tester) async {
      final session = await pumpLauncher(tester);
      await openDialog(tester);
      await typePin(tester, '0000');
      await tapLogin(tester);

      await typePin(tester, testPin);
      await tapLogin(tester);

      expect(session.isAdmin, isTrue);
      expect(dialog(), findsNothing);
    });

    testWidgets('warns when few attempts are left', (tester) async {
      await pumpLauncher(tester);
      await openDialog(tester);

      for (final expected in [
        'Incorrect PIN.',
        'Incorrect PIN.',
        'Incorrect PIN. 2 attempts left.',
        'Incorrect PIN. 1 attempt left.',
      ]) {
        await typePin(tester, '0000');
        await tapLogin(tester);
        expect(dialogText(expected), findsOneWidget, reason: expected);
      }
    });

    testWidgets('clears the error as soon as the user types again', (
      tester,
    ) async {
      await pumpLauncher(tester);
      await openDialog(tester);
      await typePin(tester, '0000');
      await tapLogin(tester);
      expect(dialogText('Incorrect PIN.'), findsOneWidget);

      await typePin(tester, '1');

      expect(dialogText('Incorrect PIN.'), findsNothing);
    });

    testWidgets('asks for a PIN if the field is empty', (tester) async {
      final session = await pumpLauncher(tester);
      await openDialog(tester);

      await tapLogin(tester);

      expect(dialogText('Enter the PIN.'), findsOneWidget);
      expect(session.isAdmin, isFalse);
    });

    testWidgets('Cancel closes without turning Admin Mode on', (tester) async {
      final session = await pumpLauncher(tester);
      await openDialog(tester);
      await typePin(tester, testPin);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(dialog(), findsNothing);
      expect(session.isAdmin, isFalse);
      expect(_granted, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('is not closed by a tap outside it', (tester) async {
      await pumpLauncher(tester);
      await openDialog(tester);
      await typePin(tester, '48');

      await tester.tapAt(const Offset(5, 5));
      await settle(tester);

      expect(dialog(), findsOneWidget);
      expect(tester.widget<TextField>(pinField()).controller!.text, '48');
    });

    testWidgets('reports a storage problem', (tester) async {
      final store = FakeAdminPinStore();
      await pumpLauncher(tester, store: store);
      store.readError = StateError('blocked');

      await openDialog(tester);

      expect(dialog(), findsNothing);
      expect(
        find.text('Could not open the Admin settings. Please try again.'),
        findsOneWidget,
      );
      expect(_granted, isFalse);
    });

    testWidgets('does nothing more if Admin Mode is already on', (
      tester,
    ) async {
      final session = await pumpLauncher(tester, signedIn: true);
      expect(session.isAdmin, isTrue);

      await tester.tap(find.text('Open Admin'));
      await settle(tester);

      expect(dialog(), findsNothing);
      expect(_granted, isTrue);
    });
  });

  group('too many wrong PINs', () {
    late DateTime clock;

    setUp(() => clock = DateTime(2026, 9, 25, 10));

    Future<void> failFiveTimes(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '0000');
        await tapLogin(tester);
      }
    }

    testWidgets('lock the dialog for a while, with a countdown', (
      tester,
    ) async {
      await pumpLauncher(tester, now: () => clock);
      await openDialog(tester);

      await failFiveTimes(tester);

      expect(
        dialogText('Too many wrong attempts. Try again in 30 seconds.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Login'))
            .onPressed,
        isNull,
      );

      clock = clock.add(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      expect(
        dialogText('Too many wrong attempts. Try again in 18 seconds.'),
        findsOneWidget,
      );
    });

    testWidgets('refuse even the right PIN while locked', (tester) async {
      final session = await pumpLauncher(tester, now: () => clock);
      await openDialog(tester);
      await failFiveTimes(tester);

      await typePin(tester, testPin);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(session.isAdmin, isFalse);
    });

    testWidgets('end, and the right PIN then works', (tester) async {
      final session = await pumpLauncher(tester, now: () => clock);
      await openDialog(tester);
      await failFiveTimes(tester);

      clock = clock.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(
        dialogText('Too many wrong attempts. Try again in 30 seconds.'),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Login'))
            .onPressed,
        isNotNull,
      );

      await typePin(tester, testPin);
      await tapLogin(tester);

      expect(session.isAdmin, isTrue);
    });
  });

  group('setting the first PIN', () {
    testWidgets('is asked for when no PIN exists', (tester) async {
      await pumpLauncher(tester, hasPin: false);

      await openDialog(tester);

      expect(dialogText('Set an Admin PIN'), findsOneWidget);
      expect(pinField('New PIN'), findsOneWidget);
      expect(pinField('Confirm PIN'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Set PIN'), findsOneWidget);
    });

    testWidgets('warns that a forgotten PIN cannot be recovered', (
      tester,
    ) async {
      await pumpLauncher(tester, hasPin: false);

      await openDialog(tester);

      expect(find.textContaining('If you forget it'), findsOneWidget);
      expect(find.textContaining('deletes the registrations'), findsOneWidget);
      expect(find.textContaining('JSON backup'), findsOneWidget);
    });

    testWidgets('masks both fields', (tester) async {
      await pumpLauncher(tester, hasPin: false);
      await openDialog(tester);

      await typePin(tester, '4815', 'New PIN');
      await typePin(tester, '4815', 'Confirm PIN');

      for (final label in ['New PIN', 'Confirm PIN']) {
        expect(tester.widget<TextField>(pinField(label)).obscureText, isTrue);
      }
      expect(drawnFieldText(tester), ['••••', '••••']);
    });

    testWidgets('sets the PIN, turns Admin Mode on and closes', (tester) async {
      final store = FakeAdminPinStore();
      final session = await pumpLauncher(tester, hasPin: false, store: store);
      await openDialog(tester);

      await typePin(tester, '246810', 'New PIN');
      await typePin(tester, '246810', 'Confirm PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(session.isAdmin, isTrue);
      expect(store.record, isNotNull);
      expect(store.record!.toMap().toString().contains('246810'), isFalse);
      expect(dialog(), findsNothing);
      expect(_granted, isTrue);
      expect(find.text('Admin mode is on.'), findsOneWidget);
    });

    testWidgets('rejects a PIN that is too short', (tester) async {
      final store = FakeAdminPinStore();
      final session = await pumpLauncher(tester, hasPin: false, store: store);
      await openDialog(tester);

      await typePin(tester, '12', 'New PIN');
      await typePin(tester, '12', 'Confirm PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(dialogText('The PIN must be at least 4 digits.'), findsOneWidget);
      expect(store.record, isNull);
      expect(session.isAdmin, isFalse);
    });

    testWidgets('rejects an empty PIN', (tester) async {
      await pumpLauncher(tester, hasPin: false);
      await openDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(dialogText('Enter a PIN.'), findsOneWidget);
    });

    testWidgets('rejects PINs that do not match', (tester) async {
      final store = FakeAdminPinStore();
      await pumpLauncher(tester, hasPin: false, store: store);
      await openDialog(tester);

      await typePin(tester, '4815', 'New PIN');
      await typePin(tester, '4816', 'Confirm PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(dialogText('The PINs do not match.'), findsOneWidget);
      expect(store.record, isNull);
    });

    testWidgets('Cancel stores nothing', (tester) async {
      final store = FakeAdminPinStore();
      final session = await pumpLauncher(tester, hasPin: false, store: store);
      await openDialog(tester);
      await typePin(tester, '4815', 'New PIN');
      await typePin(tester, '4815', 'Confirm PIN');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(dialog(), findsNothing);
      expect(store.record, isNull);
      expect(session.isAdmin, isFalse);
      expect(_granted, isFalse);
    });

    testWidgets('does not replace a PIN set in another tab', (tester) async {
      final store = FakeAdminPinStore();
      final session = await pumpLauncher(tester, hasPin: false, store: store);
      await openDialog(tester);
      await typePin(tester, '4815', 'New PIN');
      await typePin(tester, '4815', 'Confirm PIN');
      // Another tab sets a PIN while this dialog is open.
      store.record = await AdminPinHasher(iterations: 1000).hash('9999');
      final other = store.record;

      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(find.textContaining('already set in another tab'), findsOneWidget);
      expect(store.record, same(other));
      expect(session.isAdmin, isFalse);
    });

    testWidgets('reports a storage failure', (tester) async {
      final store = FakeAdminPinStore();
      final session = await pumpLauncher(tester, hasPin: false, store: store);
      await openDialog(tester);
      await typePin(tester, '4815', 'New PIN');
      await typePin(tester, '4815', 'Confirm PIN');
      store.writeError = StateError('disk full');

      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);

      expect(
        dialogText('Could not save the PIN. Please try again.'),
        findsOneWidget,
      );
      expect(session.isAdmin, isFalse);
    });
  });

  group('the Admin control', () {
    testWidgets('is a quiet icon before login', (tester) async {
      await pumpLauncher(tester);

      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsOneWidget);
      expect(find.text('Admin mode'), findsNothing);
      expect(find.byType(MenuAnchor), findsNothing);
    });

    testWidgets('opens the PIN dialog', (tester) async {
      await pumpLauncher(tester);

      await tester.tap(find.byTooltip(AdminModeButton.signedOutTooltip));
      await settle(tester);

      expect(dialogText('Admin PIN'), findsOneWidget);
    });

    testWidgets('shows a labelled Admin mode button once logged in', (
      tester,
    ) async {
      await pumpLauncher(tester, signedIn: true);

      expect(find.widgetWithText(FilledButton, 'Admin mode'), findsOneWidget);
      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsNothing);
    });

    testWidgets('is an icon on a phone', (tester) async {
      await pumpLauncher(tester, signedIn: true, size: _phone);

      expect(find.text('Admin mode'), findsNothing);
      expect(find.byTooltip(AdminModeButton.signedInTooltip), findsOneWidget);
    });

    testWidgets('offers Change PIN and Exit Admin Mode', (tester) async {
      await pumpLauncher(tester, signedIn: true);

      await tester.tap(find.text('Admin mode'));
      await settle(tester);

      expect(find.text('Change PIN'), findsOneWidget);
      expect(find.text('Exit Admin Mode'), findsOneWidget);
    });

    testWidgets('Exit Admin Mode turns it off and the icon comes back', (
      tester,
    ) async {
      final session = await pumpLauncher(tester, signedIn: true);
      await tester.tap(find.text('Admin mode'));
      await settle(tester);

      await tester.tap(find.text('Exit Admin Mode'));
      await settle(tester);

      expect(session.isAdmin, isFalse);
      expect(find.text('Admin mode is off.'), findsOneWidget);
      expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsOneWidget);
      expect(find.text('Admin mode'), findsNothing);
    });

    testWidgets('the bar under the app bar shows only in Admin Mode', (
      tester,
    ) async {
      final session = await pumpLauncher(tester, hasPin: false);
      Color barColor() => tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(AdminModeBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;

      // Placed in an app bar, as the pages do.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) =>
              AdminScope(session: session, child: child!),
          home: Scaffold(appBar: AppBar(bottom: const AdminModeBar())),
        ),
      );
      expect(barColor(), Colors.transparent);

      await tester.runAsync(() => session.setUpPin(testPin));
      await tester.pump();

      expect(barColor(), AppTheme.light().colorScheme.primary);
    });
  });

  group('changing the PIN', () {
    Future<void> openChangeDialog(WidgetTester tester) async {
      await tester.tap(find.text('Admin mode'));
      await settle(tester);
      await tester.tap(find.text('Change PIN'));
      await settle(tester);
    }

    testWidgets('asks for the current PIN and the new one twice', (
      tester,
    ) async {
      await pumpLauncher(tester, signedIn: true);

      await openChangeDialog(tester);

      expect(dialogText('Change Admin PIN'), findsOneWidget);
      for (final label in ['Current PIN', 'New PIN', 'Confirm new PIN']) {
        expect(pinField(label), findsOneWidget, reason: label);
        expect(tester.widget<TextField>(pinField(label)).obscureText, isTrue);
      }
    });

    testWidgets('replaces the PIN', (tester) async {
      final session = await pumpLauncher(tester, signedIn: true);
      await openChangeDialog(tester);

      await typePin(tester, testPin, 'Current PIN');
      await typePin(tester, '2468', 'New PIN');
      await typePin(tester, '2468', 'Confirm new PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Change PIN'));
      await settle(tester);

      expect(dialog(), findsNothing);
      expect(find.text('Admin PIN changed.'), findsOneWidget);
      expect(session.isAdmin, isTrue);
      session.logout();
      expect(
        (await tester.runAsync(() => session.login(testPin)))!.succeeded,
        isFalse,
      );
      expect(
        (await tester.runAsync(() => session.login('2468')))!.succeeded,
        isTrue,
      );
    });

    testWidgets('rejects a wrong current PIN', (tester) async {
      final store = FakeAdminPinStore();
      await pumpLauncher(tester, signedIn: true, store: store);
      final before = store.record;
      await openChangeDialog(tester);

      await typePin(tester, '0000', 'Current PIN');
      await typePin(tester, '2468', 'New PIN');
      await typePin(tester, '2468', 'Confirm new PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Change PIN'));
      await settle(tester);

      expect(dialogText('Incorrect PIN.'), findsOneWidget);
      expect(store.record, same(before));
    });

    testWidgets('rejects a bad new PIN and a mismatch', (tester) async {
      final store = FakeAdminPinStore();
      await pumpLauncher(tester, signedIn: true, store: store);
      final before = store.record;
      await openChangeDialog(tester);

      await typePin(tester, testPin, 'Current PIN');
      await typePin(tester, '12', 'New PIN');
      await typePin(tester, '12', 'Confirm new PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Change PIN'));
      await settle(tester);
      expect(dialogText('The PIN must be at least 4 digits.'), findsOneWidget);

      await typePin(tester, '2468', 'New PIN');
      await typePin(tester, '2469', 'Confirm new PIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Change PIN'));
      await settle(tester);
      expect(dialogText('The PINs do not match.'), findsOneWidget);

      expect(store.record, same(before));
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final store = FakeAdminPinStore();
      await pumpLauncher(tester, signedIn: true, store: store);
      final before = store.record;
      await openChangeDialog(tester);
      await typePin(tester, '2468', 'New PIN');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(dialog(), findsNothing);
      expect(store.record, same(before));
    });
  });

  group('the dialogs fit every screen', () {
    Future<void> fits(WidgetTester tester, Size size, double scale) async {
      await pumpLauncher(tester, hasPin: false, size: size, textScale: scale);
      await openDialog(tester);
      expect(tester.takeException(), isNull, reason: '$size at $scale');

      // Trigger every error message at once, the tallest state.
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'errors at $size $scale');
    }

    for (final size in const [
      Size(320, 568),
      Size(390, 800),
      Size(768, 1024),
      Size(1280, 900),
      Size(1920, 1080),
    ]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets(
          '${size.width.toInt()} px, text ${(scale * 100).toInt()}%',
          (tester) async {
            if (!realFonts) {
              markTestSkipped('Flutter SDK fonts not found');
              return;
            }
            await fits(tester, size, scale);
          },
        );
      }
    }

    testWidgets('keep the buttons reachable above the keyboard', (
      tester,
    ) async {
      if (!realFonts) {
        markTestSkipped('Flutter SDK fonts not found');
        return;
      }
      await pumpLauncher(tester, hasPin: false, size: const Size(360, 640));
      // An on-screen keyboard taking the bottom half of the screen.
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await openDialog(tester);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'Set PIN'),
      );
      expect(button.bottom, lessThanOrEqualTo(640 - 320));
    });

    testWidgets('have one comfortable width on tablets and desktops', (
      tester,
    ) async {
      final widths = <double>{};
      for (final size in const [
        Size(768, 1024),
        Size(1280, 900),
        Size(1920, 1080),
      ]) {
        await pumpLauncher(tester, hasPin: false, size: size);
        await openDialog(tester);
        widths.add(tester.getSize(dialogSurface()).width);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await settle(tester);
      }

      expect(widths, hasLength(1));
      expect(widths.single, inInclusiveRange(360, 460));
    });

    testWidgets('use the width of a phone, less a margin', (tester) async {
      await pumpLauncher(tester, hasPin: false, size: const Size(320, 640));
      await openDialog(tester);

      final rect = tester.getRect(dialogSurface());
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(320 - 16));
    });
  });
}
