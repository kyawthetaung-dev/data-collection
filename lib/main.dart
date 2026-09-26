import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'features/admin_access/data/indexed_db_admin_pin_store.dart';
import 'features/admin_access/domain/admin_session.dart';
import 'features/admin_access/presentation/admin_scope.dart';
import 'features/graduation_registration/data/datasources/graduation_registration_local_datasource.dart';
import 'features/graduation_registration/data/local/app_database.dart';
import 'features/graduation_registration/data/repositories/graduation_registration_repository_impl.dart';
import 'features/graduation_registration/domain/repositories/graduation_registration_repository.dart';
import 'features/graduation_registration/presentation/pages/registration_form_page.dart';

void main() {
  final repository = GraduationRegistrationRepositoryImpl(
    GraduationRegistrationLocalDataSource(AppDatabase()),
  );
  runApp(GraduationApp(repository: repository));
}

class GraduationApp extends StatefulWidget {
  const GraduationApp({super.key, required this.repository, this.adminSession});

  final GraduationRegistrationRepository repository;

  /// Whether Admin Mode is on. Defaults to one that keeps its PIN in the
  /// browser's IndexedDB; tests pass their own.
  final AdminSession? adminSession;

  @override
  State<GraduationApp> createState() => _GraduationAppState();
}

class _GraduationAppState extends State<GraduationApp> {
  late final AdminSession _admin =
      widget.adminSession ?? AdminSession(store: IndexedDbAdminPinStore());

  @override
  void dispose() {
    // Only a session created here is ours to dispose.
    if (widget.adminSession == null) _admin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Graduation Registration',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Above the navigator, so every page and dialog can reach it.
      builder: (context, child) => AdminScope(session: _admin, child: child!),
      home: RegistrationFormPage(repository: widget.repository),
    );
  }
}
