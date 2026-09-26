import 'package:flutter/material.dart';

/// The actions on the registration data: reports, backups and restoring.
enum DataAction { exportExcel, exportBackup, importBackup }

/// Wording and icons shared by the buttons on wide screens and the menu on
/// narrow ones, so the two never drift apart.
extension DataActionInfo on DataAction {
  String get label => switch (this) {
    DataAction.exportExcel => 'Export Excel',
    DataAction.exportBackup => 'Export JSON Backup',
    DataAction.importBackup => 'Import Backup',
  };

  IconData get icon => switch (this) {
    DataAction.exportExcel => Icons.table_chart_outlined,
    DataAction.exportBackup => Icons.data_object,
    DataAction.importBackup => Icons.upload_file_outlined,
  };

  /// Exports need registrations to export; importing never does.
  bool get needsRegistrations => this != DataAction.importBackup;
}

/// The tooltip of a disabled export action.
const nothingToExportTooltip = 'No registrations to export';

/// The data actions as one icon menu, for narrow screens where there is no room
/// for three buttons. Wide screens show the actions as buttons in the list
/// header instead.
class DataActionsMenu extends StatelessWidget {
  const DataActionsMenu({
    super.key,
    required this.running,
    required this.canExport,
    required this.onAction,
  });

  static const menuTooltip = 'Export, back up or import data';

  /// The action in progress, if any. The menu cannot be opened meanwhile.
  final DataAction? running;

  /// Whether there are registrations to export. Without them the export
  /// entries are disabled. Importing is always possible.
  final bool canExport;
  final ValueChanged<DataAction> onAction;

  @override
  Widget build(BuildContext context) {
    Widget item(DataAction action) {
      final enabled = canExport || !action.needsRegistrations;
      final button = MenuItemButton(
        leadingIcon: Icon(action.icon),
        onPressed: enabled ? () => onAction(action) : null,
        child: Text(action.label),
      );
      return enabled
          ? button
          : Tooltip(message: nothingToExportTooltip, child: button);
    }

    return MenuAnchor(
      menuChildren: [
        item(DataAction.exportExcel),
        item(DataAction.exportBackup),
        const Divider(height: 1),
        item(DataAction.importBackup),
      ],
      builder: (context, controller, _) {
        return IconButton(
          tooltip: menuTooltip,
          onPressed: running != null
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          icon: running != null
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.import_export),
        );
      },
    );
  }
}
