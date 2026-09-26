import 'package:flutter/material.dart';

import '../../graduation_registration/presentation/widgets/state_message.dart';
import '../domain/admin_session.dart';
import 'admin_pin_dialogs.dart';
import 'admin_scope.dart';

/// Shows [child] only while Admin Mode is on.
///
/// Put around a whole page. The page is not even built while Admin Mode is
/// off, so it never loads or shows protected data. And when Admin Mode ends
/// while the page is open, the protected content disappears in that same frame
/// and the app returns to its first page, the public form.
class AdminGuard extends StatefulWidget {
  const AdminGuard({super.key, required this.child});

  final Widget child;

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  AdminSession? _session;
  var _wasAdmin = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AdminScope.of(context);
    if (!identical(session, _session)) {
      _session?.removeListener(_changed);
      _session = session..addListener(_changed);
      _wasAdmin = session.isAdmin;
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final session = _session!;
    final wasAdmin = _wasAdmin;
    _wasAdmin = session.isAdmin;
    if (wasAdmin && !session.isAdmin) {
      // Leave after this frame, which already hides the protected content.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScope.of(context).isAdmin
        ? widget.child
        : const _AdminRequired();
  }
}

/// What a protected page shows to someone who is not in Admin Mode. It is not
/// reachable from the app's own buttons; it is a safety net.
class _AdminRequired extends StatelessWidget {
  const _AdminRequired();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin access required')),
      body: StateMessage(
        icon: Icons.lock_outline,
        title: 'Admin access required',
        message: 'This page is only available in Admin Mode.',
        actionLabel: 'Enter Admin PIN',
        actionIcon: Icons.admin_panel_settings_outlined,
        onAction: () => requestAdminAccess(context),
        secondaryLabel: 'Back to registration',
        secondaryIcon: Icons.arrow_back,
        onSecondaryAction: () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
      ),
    );
  }
}
