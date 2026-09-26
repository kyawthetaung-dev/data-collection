import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app_theme.dart';
import '../../../admin_access/presentation/admin_guard.dart';
import '../../../admin_access/presentation/admin_mode_button.dart';
import '../../../admin_access/presentation/admin_scope.dart';
import '../../data/export/export_result.dart';
import '../../data/export/registration_backup_service.dart';
import '../../data/export/registration_export_service.dart';
import '../../data/import/backup_file_picker.dart';
import '../../data/import/registration_backup_parser.dart';
import '../../data/import/registration_import_service.dart';
import '../../domain/entities/graduation_registration.dart';
import '../../domain/entities/registration_enums.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/graduation_registration_repository.dart';
import '../logic/registration_list_filter.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/data_actions_menu.dart';
import '../widgets/import_backup_dialogs.dart';
import '../widgets/list_header.dart';
import '../widgets/list_loading_skeleton.dart';
import '../widgets/registration_card.dart';
import '../widgets/registration_detail_view.dart';
import '../widgets/registration_filter_bar.dart';
import '../widgets/registration_table.dart';
import '../widgets/state_message.dart';
import 'registration_form_page.dart';

/// Lists every saved registration, with search, filters, details, edit, delete,
/// export, backup and import.
///
/// **Admin only.** Every one of those is management, so the whole page sits
/// behind an [AdminGuard]: it is not built, and reads no data, unless Admin
/// Mode is on, and it closes as soon as Admin Mode ends.
///
/// The layout follows the screen: a table on laptops and desktops, two columns
/// of cards on tablets, one column of cards on phones. The data is read once
/// from the repository and searched and filtered in memory.
class RegistrationListPage extends StatelessWidget {
  const RegistrationListPage({
    super.key,
    required this.repository,
    this.exportService,
    this.backupService,
    this.importService,
    this.filePicker,
  });

  /// From this width up the list is a table; below it, cards.
  static const tableBreakpoint = 1100.0;

  /// A table needs room for its fixed columns. Once the user has enlarged the
  /// text beyond this, cards fit better, even on a wide screen.
  static const tableMaxTextScale = 1.3;

  /// From this width up, cards sit in two columns.
  static const twoColumnBreakpoint = 720.0;

  /// From this width up, the export and import buttons sit in the list header
  /// instead of the app bar menu.
  static const inlineActionsBreakpoint = 720.0;

  /// From this width up, the search box and the filters share one row.
  static const filterRowBreakpoint = 900.0;

  static const maxTableWidth = 1280.0;
  static const maxCardGridWidth = 1080.0;
  static const maxCardListWidth = 720.0;

  final GraduationRegistrationRepository repository;

  /// Creates the Excel report and the JSON backup, and imports a backup, with
  /// the file chooser it needs. They default to the real ones; tests pass their
  /// own.
  final RegistrationExportService? exportService;
  final RegistrationBackupService? backupService;
  final RegistrationImportService? importService;
  final BackupFilePicker? filePicker;

  @override
  Widget build(BuildContext context) =>
      AdminGuard(child: _RegistrationListView(this));
}

/// The list itself, built only while Admin Mode is on.
class _RegistrationListView extends StatefulWidget {
  const _RegistrationListView(this.page);

  final RegistrationListPage page;

  @override
  State<_RegistrationListView> createState() => _RegistrationListViewState();
}

/// How the list is laid out at the current width and text size.
class _ListLayout {
  const _ListLayout({
    required this.table,
    required this.cardColumns,
    required this.inlineActions,
    required this.filterRow,
    required this.padding,
  });

  factory _ListLayout.of(double width, double textScale) {
    final table =
        width >= RegistrationListPage.tableBreakpoint &&
        textScale <= RegistrationListPage.tableMaxTextScale;
    return _ListLayout(
      table: table,
      cardColumns: !table && width >= RegistrationListPage.twoColumnBreakpoint
          ? 2
          : 1,
      inlineActions: width >= RegistrationListPage.inlineActionsBreakpoint,
      // Four fields in a row need room; enlarged text needs more of it.
      filterRow:
          width >= RegistrationListPage.filterRowBreakpoint &&
          textScale <= RegistrationListPage.tableMaxTextScale,
      padding: width >= 600 ? AppSpacing.xl : AppSpacing.lg,
    );
  }

  final bool table;
  final int cardColumns;
  final bool inlineActions;
  final bool filterRow;
  final double padding;

  double get maxWidth => table
      ? RegistrationListPage.maxTableWidth
      : cardColumns == 2
      ? RegistrationListPage.maxCardGridWidth
      : RegistrationListPage.maxCardListWidth;
}

class _RegistrationListViewState extends State<_RegistrationListView> {
  final _searchController = TextEditingController();
  late final RegistrationExportService _exportService =
      widget.page.exportService ??
      RegistrationExportService(repository: widget.page.repository);
  late final RegistrationBackupService _backupService =
      widget.page.backupService ??
      RegistrationBackupService(repository: widget.page.repository);
  late final RegistrationImportService _importService =
      widget.page.importService ??
      RegistrationImportService(repository: widget.page.repository);
  late final BackupFilePicker _filePicker =
      widget.page.filePicker ?? createBackupFilePicker();

  /// `null` until the first load finishes.
  List<GraduationRegistration>? _all;
  Object? _loadError;
  bool _loading = false;

  /// The export, backup or import in progress, if any. One at a time.
  DataAction? _running;

  String _query = '';
  String? _major;
  AttendanceStatus? _attendance;
  CurrentCountry? _country;
  bool _filtersExpanded = false;

  bool get _canExport => _all != null && _all!.isNotEmpty;

  /// Whether Admin Mode is still on. The guard already hides this page when it
  /// ends; this is a second check in every protected action, so a stale button
  /// cannot do anything either.
  bool get _adminOn => AdminScope.read(context).isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      if (_all == null) _loadError = null;
    });
    try {
      final all = await widget.page.repository.getAll();
      if (!mounted) return;
      setState(() {
        _all = all;
        _loadError = null;
        _dropStaleMajor(all);
      });
    } catch (error, stackTrace) {
      debugPrint('Loading registrations failed: $error\n$stackTrace');
      if (!mounted) return;
      if (_all == null) {
        setState(() => _loadError = error);
      } else {
        _showMessage(
          'Could not refresh the list.',
          kind: AppSnackBarKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A deleted or renamed major must not leave an invisible filter behind.
  void _dropStaleMajor(List<GraduationRegistration> all) {
    final major = _major;
    if (major == null) return;
    final key = normalizeLookupKey(major);
    final stillExists = RegistrationListFilter.majorOptions(
      all,
    ).any((option) => normalizeLookupKey(option) == key);
    if (!stillExists) _major = null;
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _major = null;
      _attendance = null;
      _country = null;
    });
  }

  Future<void> _view(GraduationRegistration registration) async {
    if (!_adminOn) return;
    final action = await showRegistrationDetail(context, registration);
    if (!mounted) return;
    switch (action) {
      case RegistrationDetailAction.edit:
        await _edit(registration);
      case RegistrationDetailAction.delete:
        await _delete(registration);
      case null:
        break;
    }
  }

  Future<void> _edit(GraduationRegistration registration) async {
    if (!_adminOn) return;
    final saved = await Navigator.of(context).push<GraduationRegistration>(
      MaterialPageRoute(
        builder: (_) => RegistrationFormPage(
          repository: widget.page.repository,
          initialRegistration: registration,
        ),
      ),
    );
    if (saved == null || !mounted) return;
    await _load();
    if (mounted) {
      _showMessage('Updated ${saved.name} (Roll No. ${saved.rollNo}).');
    }
  }

  Future<void> _delete(GraduationRegistration registration) async {
    if (!_adminOn) return;
    final confirmed = await confirmDeleteRegistration(context, registration);
    if (!confirmed || !mounted) return;
    try {
      await widget.page.repository.delete(registration.id);
    } on NotFoundFailure {
      // Already gone, for example deleted in another tab. Nothing to undo.
    } catch (error, stackTrace) {
      debugPrint('Deleting a registration failed: $error\n$stackTrace');
      if (mounted) {
        _showMessage(
          'Could not delete ${registration.name}. Please try again.',
          kind: AppSnackBarKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    await _load();
    if (mounted) {
      _showMessage(
        'Deleted ${registration.name} (Roll No. ${registration.rollNo}).',
      );
    }
  }

  void _runAction(DataAction action) => switch (action) {
    DataAction.exportExcel => _exportExcel(),
    DataAction.exportBackup => _exportBackup(),
    DataAction.importBackup => _importBackup(),
  };

  Future<void> _exportExcel() => _runExport(
    action: DataAction.exportExcel,
    export: _exportService.exportAll,
    successMessage: (result) =>
        'Exported ${_registrations(result.count)} to ${result.fileName}.',
    failureMessage: 'Could not create the Excel file. Please try again.',
  );

  Future<void> _exportBackup() => _runExport(
    action: DataAction.exportBackup,
    export: _backupService.exportAll,
    successMessage: (result) =>
        'Backup downloaded: ${result.fileName} '
        '(${_registrations(result.count)}).',
    failureMessage: 'Could not create the backup. Please try again.',
  );

  String _registrations(int count) =>
      '$count ${count == 1 ? 'registration' : 'registrations'}';

  /// Runs one export or backup: only one action at a time, with the same
  /// feedback for "nothing to export" and for failures. It only reads from the
  /// database.
  Future<void> _runExport({
    required DataAction action,
    required Future<ExportResult> Function() export,
    required String Function(ExportResult result) successMessage,
    required String failureMessage,
  }) async {
    if (_running != null || !_adminOn) return;
    setState(() => _running = action);
    try {
      final result = await export();
      if (mounted) _showMessage(successMessage(result));
    } on NothingToExportFailure catch (failure) {
      if (mounted) _showMessage(failure.message, kind: AppSnackBarKind.info);
    } catch (error, stackTrace) {
      debugPrint('Exporting failed: $error\n$stackTrace');
      if (mounted) _showMessage(failureMessage, kind: AppSnackBarKind.error);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  /// Imports a JSON backup: choose the file, read and check it, show what
  /// would happen, and only after the user confirms, add the new records.
  ///
  /// Nothing is written before the confirmation, and import only ever adds:
  /// it never overwrites or deletes a registration.
  Future<void> _importBackup() async {
    if (_running != null || !_adminOn) return;

    final PickedBackupFile? file;
    try {
      file = await _filePicker.pickBackupFile();
    } on BackupFileException catch (error) {
      if (mounted) {
        await showImportErrorDialog(
          context,
          title: 'This file can\'t be imported',
          message: error.message,
        );
      }
      return;
    } catch (error, stackTrace) {
      debugPrint('Choosing the backup file failed: $error\n$stackTrace');
      if (mounted) {
        _showMessage(
          'Could not open the file. Please try again.',
          kind: AppSnackBarKind.error,
        );
      }
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _running = DataAction.importBackup);
    final ImportPreview preview;
    try {
      preview = await _importService.prepare(
        fileName: file.name,
        bytes: file.bytes,
      );
    } on BackupFileException catch (error) {
      if (mounted) {
        setState(() => _running = null);
        await showImportErrorDialog(
          context,
          title: 'This file can\'t be imported',
          message: error.message,
        );
      }
      return;
    } catch (error, stackTrace) {
      debugPrint('Reading the backup failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _running = null);
        _showMessage(
          'Could not read the backup. Nothing was changed.',
          kind: AppSnackBarKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _running = null);

    final confirmed = await showImportSummaryDialog(context, preview);
    if (!confirmed || !mounted) return;

    setState(() => _running = DataAction.importBackup);
    final ImportResult result;
    try {
      result = await _importService.commit(preview);
    } catch (error, stackTrace) {
      debugPrint('Importing the backup failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _running = null);
        await showImportErrorDialog(
          context,
          title: 'Import failed',
          message:
              'The backup could not be imported, and nothing was changed. '
              'Please try again.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _running = null);

    await _load();
    if (mounted) await showImportResultDialog(context, result);
  }

  void _showMessage(
    String message, {
    AppSnackBarKind kind = AppSnackBarKind.success,
  }) => showAppSnackBar(context, message, kind: kind);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _ListLayout.of(
          constraints.maxWidth,
          MediaQuery.textScalerOf(context).scale(1),
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text('Registrations'),
            actions: [
              if (!layout.inlineActions)
                DataActionsMenu(
                  running: _running,
                  canExport: _canExport,
                  onAction: _runAction,
                ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _load,
              ),
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: AdminModeButton(),
              ),
            ],
            bottom: const AdminModeBar(),
          ),
          body: SafeArea(child: _buildBody(layout)),
        );
      },
    );
  }

  /// Keeps the content centered, capped in width, and padded.
  Widget _frame(_ListLayout layout, Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.maxWidth),
        child: Padding(padding: EdgeInsets.all(layout.padding), child: child),
      ),
    );
  }

  Widget _buildBody(_ListLayout layout) {
    final all = _all;
    if (all == null) {
      if (_loadError != null) {
        return StateMessage(
          icon: Icons.error_outline,
          isError: true,
          title: 'Could not load registrations',
          message:
              'Something went wrong while reading the saved data. Your data '
              'is not affected.',
          actionLabel: 'Try again',
          actionIcon: Icons.refresh,
          onAction: _load,
        );
      }
      return _frame(
        layout,
        ListLoadingSkeleton(asTable: layout.table, columns: layout.cardColumns),
      );
    }

    final filter = RegistrationListFilter(
      query: _query,
      major: _major,
      attendance: _attendance,
      country: _country,
    );
    final results = filter.apply(all);

    final header = ListHeader(
      total: all.length,
      shown: filter.isActive ? results.length : null,
      showActions: layout.inlineActions,
      running: _running,
      canExport: _canExport,
      onAction: _runAction,
    );
    final filterBar = RegistrationFilterBar(
      wide: layout.filterRow,
      searchController: _searchController,
      majorOptions: RegistrationListFilter.majorOptions(all),
      major: _major,
      attendance: _attendance,
      country: _country,
      filtersExpanded: _filtersExpanded,
      hasActiveFilters: filter.isActive,
      onQueryChanged: (value) => setState(() => _query = value),
      onMajorChanged: (value) => setState(() => _major = value),
      onAttendanceChanged: (value) => setState(() => _attendance = value),
      onCountryChanged: (value) => setState(() => _country = value),
      onFiltersExpandedChanged: (value) =>
          setState(() => _filtersExpanded = value),
      onClear: _clearFilters,
    );

    final Widget? message = all.isEmpty
        ? StateMessage(
            icon: Icons.inbox_outlined,
            title: 'No registrations yet',
            message:
                'Registrations are saved in this browser. Once someone '
                'registers, they will appear here.',
            actionLabel: 'Register someone',
            actionIcon: Icons.person_add_alt_1_outlined,
            onAction: () => Navigator.of(context).maybePop(),
            // Restoring into a new browser starts from an empty list.
            secondaryLabel: 'Import a backup',
            secondaryIcon: Icons.upload_file_outlined,
            onSecondaryAction: _running != null ? null : _importBackup,
          )
        : results.isEmpty
        ? StateMessage(
            icon: Icons.search_off,
            title: 'No registrations match',
            message: 'Try a different search or remove some filters.',
            actionLabel: 'Clear search and filters',
            actionIcon: Icons.filter_alt_off_outlined,
            onAction: _clearFilters,
          )
        : null;

    final content = layout.table
        ? _buildTable(all, header, filterBar, results, message, layout)
        : _buildCards(all, header, filterBar, results, message, layout);
    return Column(
      children: [
        // A slim bar while the list reloads, after a refresh or an import.
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildTable(
    List<GraduationRegistration> all,
    Widget header,
    Widget filterBar,
    List<NumberedRegistration> results,
    Widget? message,
    _ListLayout layout,
  ) {
    return _frame(
      layout,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (all.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            filterBar,
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child:
                message ??
                RegistrationTable(
                  rows: results,
                  onView: _view,
                  onEdit: _edit,
                  onDelete: _delete,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(
    List<GraduationRegistration> all,
    Widget header,
    Widget filterBar,
    List<NumberedRegistration> results,
    Widget? message,
    _ListLayout layout,
  ) {
    final columns = layout.cardColumns;
    final cardRows = message != null ? 1 : (results.length / columns).ceil();

    Widget cardFor(NumberedRegistration row) => RegistrationCard(
      row: row,
      onView: () => _view(row.registration),
      onEdit: () => _edit(row.registration),
      onDelete: () => _delete(row.registration),
    );

    return _frame(
      layout,
      ListView.builder(
        itemCount: 1 + cardRows,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  if (all.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    filterBar,
                  ],
                ],
              ),
            );
          }
          if (message != null) return message;

          final start = (index - 1) * columns;
          final rowItems = results.sublist(
            start,
            math.min(start + columns, results.length),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: columns == 1
                ? cardFor(rowItems.single)
                // Cards in a row share the height of the taller one.
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.md,
                      children: [
                        for (var i = 0; i < columns; i++)
                          Expanded(
                            child: i < rowItems.length
                                ? cardFor(rowItems[i])
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}
