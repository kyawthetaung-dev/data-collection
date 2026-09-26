import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_mode_button.dart';
import 'package:ucss_data_collection/main.dart';

import 'admin_access/support/admin_test_support.dart';
import 'graduation_registration/support/fake_registration_repository.dart';

void main() {
  testWidgets('App opens on the public registration form', (
    WidgetTester tester,
  ) async {
    final session = await adminSession(tester, signedIn: false);
    await tester.pumpWidget(
      GraduationApp(
        repository: FakeRegistrationRepository(),
        adminSession: session,
      ),
    );

    expect(find.text('Graduation Registration'), findsOneWidget);
    expect(find.text('Registration Form'), findsOneWidget);
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Submit Registration'), findsOneWidget);
    // Only a quiet Admin icon: nothing of the management side shows.
    expect(find.byTooltip(AdminModeButton.signedOutTooltip), findsOneWidget);
    expect(find.text('Registrations'), findsNothing);
    expect(find.byIcon(Icons.list_alt), findsNothing);
  });
}
