import 'package:flutter/material.dart';

import '../../../admin_access/presentation/admin_guard.dart';
import '../../../admin_access/presentation/admin_mode_button.dart';
import '../../../admin_access/presentation/admin_scope.dart';
import '../../domain/entities/graduation_registration.dart';
import '../../domain/repositories/graduation_registration_repository.dart';
import '../widgets/registration_form.dart';
import 'registration_list_page.dart';

/// The page that hosts the registration form: a scrollable column, centered
/// and capped at a comfortable reading width on large screens.
///
/// **Registering is public.** The app bar has only a quiet Admin icon; the
/// "Registrations" button that leads to the list appears only in Admin Mode.
///
/// Pass [initialRegistration] to edit an existing registration instead. That
/// is management, so it is only available in Admin Mode. The page then pops
/// with the saved registration, or with `null` if cancelled.
class RegistrationFormPage extends StatelessWidget {
  const RegistrationFormPage({
    super.key,
    required this.repository,
    this.initialRegistration,
  });

  static const maxContentWidth = 880.0;

  final GraduationRegistrationRepository repository;
  final GraduationRegistration? initialRegistration;

  @override
  Widget build(BuildContext context) {
    final page = Builder(builder: _buildPage);
    return initialRegistration == null ? page : AdminGuard(child: page);
  }

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final initial = initialRegistration;
    final isEditing = initial != null;
    final admin = AdminScope.of(context).isAdmin;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final horizontalPadding = compact ? 16.0 : 24.0;
    void openList() => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RegistrationListPage(repository: repository),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Registration' : 'Graduation Registration',
        ),
        actions: [
          if (!isEditing && admin)
            // Icon only on a phone, so the title is not squeezed.
            compact
                ? IconButton(
                    tooltip: 'Registrations',
                    icon: const Icon(Icons.list_alt),
                    onPressed: openList,
                  )
                : TextButton.icon(
                    onPressed: openList,
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Registrations'),
                  ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: AdminModeButton(),
          ),
        ],
        bottom: const AdminModeBar(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEditing ? initial.name : 'Registration Form',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEditing
                        ? 'Roll No. ${initial.rollNo} · Fields marked with * '
                              'are required.'
                        : 'Fields marked with * are required.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  RegistrationForm(
                    key: ValueKey(initial?.id),
                    repository: repository,
                    initialRegistration: initial,
                    onSaved: isEditing
                        ? (saved) => Navigator.of(context).pop(saved)
                        : null,
                    onCancel: isEditing
                        ? () => Navigator.of(context).maybePop()
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
