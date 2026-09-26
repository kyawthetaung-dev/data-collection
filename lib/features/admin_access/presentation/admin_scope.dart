import 'package:flutter/widgets.dart';

import '../domain/admin_session.dart';

/// Makes the [AdminSession] available to every widget below it.
///
/// Placed above the app's navigator, so pages and dialogs alike can reach it.
class AdminScope extends InheritedNotifier<AdminSession> {
  const AdminScope({
    super.key,
    required AdminSession session,
    required super.child,
  }) : super(notifier: session);

  /// The session, and rebuilds the caller whenever Admin Mode turns on or off.
  /// Use it in `build`.
  static AdminSession of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdminScope>();
    assert(scope != null, 'There is no AdminScope above this widget.');
    return scope!.notifier!;
  }

  /// The session, without rebuilding when it changes. Use it in event handlers.
  static AdminSession read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AdminScope>();
    assert(scope != null, 'There is no AdminScope above this widget.');
    return scope!.notifier!;
  }
}
