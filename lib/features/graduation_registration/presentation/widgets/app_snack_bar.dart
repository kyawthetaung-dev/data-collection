import 'package:flutter/material.dart';

/// What a SnackBar reports: something that worked, something that went wrong,
/// or a neutral note.
enum AppSnackBarKind { success, error, info }

/// Shows a short message at the bottom of the screen, replacing any message
/// already showing.
///
/// One helper for the whole app, so every confirmation and error looks and
/// behaves the same: floating, with an icon, a close button, and a width capped
/// on wide screens. Errors stay a little longer.
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackBarKind kind = AppSnackBarKind.success,
}) {
  final colors = Theme.of(context).colorScheme;
  final wide = MediaQuery.sizeOf(context).width > 600;
  // The bar itself is dark, so the icons use light tones.
  final (icon, color) = switch (kind) {
    AppSnackBarKind.success => (Icons.check_circle, const Color(0xFF8BD19B)),
    AppSnackBarKind.error => (Icons.error_outline, colors.errorContainer),
    AppSnackBarKind.info => (Icons.info_outline, colors.inversePrimary),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: wide ? 480 : null,
        showCloseIcon: true,
        duration: kind == AppSnackBarKind.error
            ? const Duration(seconds: 6)
            : const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
