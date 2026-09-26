import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_pin_hasher.dart';
import 'package:ucss_data_collection/features/admin_access/domain/admin_session.dart';
import 'package:ucss_data_collection/features/admin_access/presentation/admin_scope.dart';

import 'fake_admin_pin_store.dart';

/// The PIN every test session uses.
const testPin = '4815';

/// A session over a fake store, with cheap hashing.
///
/// With [signedIn] (the default) it goes through the real flow: the PIN is set
/// up, which turns Admin Mode on. Without it the session is logged out, like a
/// visitor to the public form.
///
/// [store] can be shared between sessions, to act like the same browser after
/// a refresh.
Future<AdminSession> adminSession(
  WidgetTester tester, {
  bool signedIn = true,
  FakeAdminPinStore? store,
  DateTime Function()? now,
}) async {
  final session = AdminSession(
    store: store ?? FakeAdminPinStore(),
    hasher: AdminPinHasher(iterations: 1000),
    now: now,
  );
  addTearDown(session.dispose);
  if (signedIn) {
    // The hashing is real asynchronous work, so it needs the real clock.
    await tester.runAsync(() => session.setUpPin(testPin));
  }
  return session;
}

/// Puts [session] above the app's navigator, the way `GraduationApp` does.
TransitionBuilder adminScopeBuilder(AdminSession session) =>
    (context, child) => AdminScope(session: session, child: child!);

/// A bare `MaterialApp` showing [home] with Admin Mode provided by [session].
Widget adminApp(AdminSession session, Widget home) =>
    MaterialApp(builder: adminScopeBuilder(session), home: home);
