import 'package:flutter/material.dart';

import 'admin_pin_dialogs.dart';
import 'admin_scope.dart';

/// The Admin control for an app bar.
///
/// * **Not in Admin Mode:** a small, quiet Admin icon. It leads to the PIN
///   dialog and nothing else, so the public form stays simple.
/// * **In Admin Mode:** an "Admin mode" button that opens a menu with
///   **Change PIN** and **Exit Admin Mode**. On a phone it is an icon, so the
///   page title keeps its room.
class AdminModeButton extends StatelessWidget {
  const AdminModeButton({super.key});

  static const signedOutTooltip = 'Admin';
  static const signedInTooltip = 'Admin mode';

  @override
  Widget build(BuildContext context) {
    // Depends on the session, so it rebuilds when Admin Mode turns on or off.
    final admin = AdminScope.of(context).isAdmin;

    if (!admin) {
      return IconButton(
        tooltip: signedOutTooltip,
        icon: const Icon(Icons.admin_panel_settings_outlined),
        onPressed: () => requestAdminAccess(context),
      );
    }

    final compact = MediaQuery.sizeOf(context).width < 600;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.password),
          onPressed: () => showChangePinDialog(context),
          child: const Text('Change PIN'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => exitAdminMode(context),
          child: const Text('Exit Admin Mode'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        return compact
            ? IconButton.filledTonal(
                tooltip: signedInTooltip,
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: toggle,
              )
            : FilledButton.tonalIcon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Admin mode'),
                onPressed: toggle,
              );
      },
    );
  }
}

/// A slim coloured line under the app bar while Admin Mode is on, so it is
/// obvious on every page and at every screen size. It keeps its height when
/// Admin Mode is off, so turning it on does not move the page.
class AdminModeBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminModeBar({super.key});

  static const height = 3.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context).isAdmin;
    return Semantics(
      label: admin ? 'Admin mode is on' : null,
      child: ColoredBox(
        color: admin
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        child: const SizedBox(height: height, width: double.infinity),
      ),
    );
  }
}
