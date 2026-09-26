import 'package:flutter/material.dart';

import '../../../../app_theme.dart';
import '../../domain/entities/graduation_registration.dart';
import '../../domain/entities/registration_enums.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/graduation_registration_repository.dart';
import '../../domain/validators/registration_validator.dart';
import 'app_snack_bar.dart';
import 'choice_form_field.dart';
import 'form_section_card.dart';
import 'responsive_field_grid.dart';

/// The graduation registration form.
///
/// Validates with the same [RegistrationValidator] the repository uses and
/// checks for a duplicate Roll No. and NRC before saving through [repository].
///
/// * **Create** (no [initialRegistration]): after saving it confirms with a
///   SnackBar and clears itself, ready for the next registration.
/// * **Edit** ([initialRegistration] set): starts filled in, saves with
///   `update`, and leaves the form as it is. The host decides what happens next
///   through [onSaved], and a Cancel button appears if [onCancel] is set.
class RegistrationForm extends StatefulWidget {
  const RegistrationForm({
    super.key,
    required this.repository,
    this.initialRegistration,
    this.onSaved,
    this.onCancel,
  });

  final GraduationRegistrationRepository repository;
  final GraduationRegistration? initialRegistration;

  /// Called with the stored registration after every successful save.
  final ValueChanged<GraduationRegistration>? onSaved;
  final VoidCallback? onCancel;

  @override
  State<RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<RegistrationForm> {
  static const _validator = RegistrationValidator();

  static const _textFields = [
    RegistrationField.name,
    RegistrationField.fatherName,
    RegistrationField.motherName,
    RegistrationField.nrc,
    RegistrationField.rollNo,
    RegistrationField.major,
    RegistrationField.phoneNo,
    RegistrationField.email,
    RegistrationField.currentCity,
    RegistrationField.otherCountry,
    RegistrationField.remark,
  ];

  /// Top-to-bottom order of the fields, used to reveal the first error.
  static const _revealOrder = [
    RegistrationField.name,
    RegistrationField.fatherName,
    RegistrationField.motherName,
    RegistrationField.nrc,
    RegistrationField.rollNo,
    RegistrationField.major,
    RegistrationField.phoneNo,
    RegistrationField.email,
    RegistrationField.currentCity,
    RegistrationField.attendanceStatus,
    RegistrationField.currentCountry,
    RegistrationField.otherCountry,
  ];

  final _formKey = GlobalKey<FormState>();
  final _attendanceKey = GlobalKey<FormFieldState<AttendanceStatus>>();
  final _countryKey = GlobalKey<FormFieldState<CurrentCountry>>();

  late final Map<RegistrationField, TextEditingController> _controllers = {
    for (final field in _textFields) field: TextEditingController(),
  };
  late final Map<RegistrationField, FocusNode> _focusNodes = {
    for (final field in _textFields) field: FocusNode(),
  };

  /// Errors reported by the repository (duplicates). Each one is cleared when
  /// the user edits its field.
  final Map<RegistrationField, String> _serverErrors = {};

  AttendanceStatus? _attendance;
  CurrentCountry? _country;
  bool _submitting = false;
  String? _submitError;

  bool get _isEditing => widget.initialRegistration != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRegistration;
    if (initial == null) return;
    void fill(RegistrationField field, String? value) =>
        _controllers[field]!.text = value ?? '';
    fill(RegistrationField.name, initial.name);
    fill(RegistrationField.fatherName, initial.fatherName);
    fill(RegistrationField.motherName, initial.motherName);
    fill(RegistrationField.nrc, initial.nrc);
    fill(RegistrationField.rollNo, initial.rollNo);
    fill(RegistrationField.major, initial.major);
    fill(RegistrationField.phoneNo, initial.phoneNo);
    fill(RegistrationField.email, initial.email);
    fill(RegistrationField.currentCity, initial.currentCity);
    fill(RegistrationField.otherCountry, initial.otherCountry);
    fill(RegistrationField.remark, initial.remark);
    _attendance = initial.attendanceStatus;
    _country = initial.currentCountry;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  /// The registration as currently typed. An unselected choice gets a
  /// placeholder, because those are checked by their own fields.
  GraduationRegistration _buildDraft() {
    String text(RegistrationField field) => _controllers[field]!.text;
    return GraduationRegistration.draft(
      name: text(RegistrationField.name),
      fatherName: text(RegistrationField.fatherName),
      motherName: text(RegistrationField.motherName),
      phoneNo: text(RegistrationField.phoneNo),
      nrc: text(RegistrationField.nrc),
      rollNo: text(RegistrationField.rollNo),
      major: text(RegistrationField.major),
      attendanceStatus: _attendance ?? AttendanceStatus.canAttend,
      currentCountry: _country ?? CurrentCountry.myanmar,
      otherCountry: text(RegistrationField.otherCountry),
      currentCity: text(RegistrationField.currentCity),
      email: text(RegistrationField.email),
      remark: text(RegistrationField.remark),
    ).normalized();
  }

  /// What gets saved: the typed values, carrying the identity and creation
  /// date of the registration being edited.
  GraduationRegistration _buildSubmission() {
    final draft = _buildDraft();
    final initial = widget.initialRegistration;
    if (initial == null) return draft;
    return draft.copyWith(
      id: initial.id,
      createdAt: initial.createdAt,
      updatedAt: initial.updatedAt,
    );
  }

  String? _errorFor(RegistrationField field) =>
      _serverErrors[field] ?? _validator.validate(_buildDraft())[field];

  bool _hasError(RegistrationField field) => switch (field) {
    RegistrationField.attendanceStatus => _attendance == null,
    RegistrationField.currentCountry => _country == null,
    _ => _errorFor(field) != null,
  };

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitError = null);

    if (!_formKey.currentState!.validate()) {
      _revealFirstError();
      return;
    }

    setState(() => _submitting = true);
    try {
      final submission = _buildSubmission();
      final ownId = widget.initialRegistration?.id;
      final rollNoTaken = await widget.repository.isRollNoTaken(
        submission.rollNo,
        excludeId: ownId,
      );
      final nrcTaken = await widget.repository.isNrcTaken(
        submission.nrc,
        excludeId: ownId,
      );
      if (!mounted) return;
      if (rollNoTaken || nrcTaken) {
        _showDuplicates(rollNo: rollNoTaken, nrc: nrcTaken);
        return;
      }

      final saved = _isEditing
          ? await widget.repository.update(submission)
          : await widget.repository.create(submission);
      if (!mounted) return;
      if (!_isEditing) {
        _showSaved(saved);
        _reset();
      }
      widget.onSaved?.call(saved);
    } on DuplicateRollNoFailure {
      // Another tab took it between the check above and the save.
      if (mounted) _showDuplicates(rollNo: true, nrc: false);
    } on DuplicateNrcFailure {
      if (mounted) _showDuplicates(rollNo: false, nrc: true);
    } on ValidationFailure catch (failure) {
      if (!mounted) return;
      _serverErrors.addAll(failure.errors);
      _formKey.currentState!.validate();
      _revealFirstError();
    } on NotFoundFailure {
      if (mounted) {
        setState(
          () => _submitError =
              'This registration no longer exists. It may have been deleted '
              'in another tab.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Saving the registration failed: $error\n$stackTrace');
      if (mounted) {
        setState(
          () => _submitError =
              'Could not save the registration. Please try '
              'again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showDuplicates({required bool rollNo, required bool nrc}) {
    if (rollNo) {
      _serverErrors[RegistrationField.rollNo] =
          'This Roll No. is already registered.';
    }
    if (nrc) {
      _serverErrors[RegistrationField.nrc] = 'This NRC is already registered.';
    }
    _formKey.currentState!.validate();
    _revealFirstError();
  }

  void _revealFirstError() {
    for (final field in _revealOrder) {
      if (!_hasError(field)) continue;
      final focusNode = _focusNodes[field];
      if (focusNode != null) {
        focusNode.requestFocus();
      } else {
        final key = field == RegistrationField.attendanceStatus
            ? _attendanceKey
            : _countryKey;
        final fieldContext = key.currentContext;
        if (fieldContext != null) {
          Scrollable.ensureVisible(
            fieldContext,
            alignment: 0.1,
            duration: const Duration(milliseconds: 250),
          );
        }
      }
      return;
    }
  }

  void _showSaved(GraduationRegistration saved) {
    showAppSnackBar(
      context,
      'Registration saved for ${saved.name} (Roll No. ${saved.rollNo}).',
    );
  }

  /// Clears every field and selection and scrolls back to the top.
  void _reset() {
    _serverErrors.clear();
    _attendance = null;
    _country = null;
    _formKey.currentState!.reset();
    setState(() => _submitError = null);
    Scrollable.maybeOf(context)?.position.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// A text field. [label] is written without the asterisk; a [required]
  /// field gets a red one. Plain text still reads "Label *".
  Widget _textField(
    RegistrationField field,
    String label, {
    bool required = false,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    bool autocorrect = true,
    int minLines = 1,
    int maxLines = 1,
  }) {
    final errorColor = Theme.of(context).colorScheme.error;
    return TextFormField(
      controller: _controllers[field],
      focusNode: _focusNodes[field],
      readOnly: _submitting,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      autocorrect: autocorrect,
      enableSuggestions: autocorrect,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        label: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: errorColor),
                ),
            ],
          ),
        ),
        hintText: hint,
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) => _errorFor(field),
      onChanged: (_) => _serverErrors.remove(field),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          FormSectionCard(
            title: 'Personal Information',
            icon: Icons.person_outline,
            child: ResponsiveFieldGrid(
              children: [
                _textField(
                  RegistrationField.name,
                  'Name',
                  required: true,
                  capitalization: TextCapitalization.words,
                ),
                _textField(
                  RegistrationField.fatherName,
                  'Father Name',
                  required: true,
                  capitalization: TextCapitalization.words,
                ),
                _textField(
                  RegistrationField.motherName,
                  'Mother Name',
                  capitalization: TextCapitalization.words,
                ),
                _textField(
                  RegistrationField.nrc,
                  'NRC',
                  required: true,
                  hint: 'e.g. 12/LAMANA(N)123456',
                  autocorrect: false,
                ),
                _textField(
                  RegistrationField.rollNo,
                  'Roll No.',
                  required: true,
                  autocorrect: false,
                ),
                _textField(
                  RegistrationField.major,
                  'Major',
                  required: true,
                  capitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
          FormSectionCard(
            title: 'Contact Information',
            icon: Icons.contact_phone_outlined,
            child: ResponsiveFieldGrid(
              children: [
                _textField(
                  RegistrationField.phoneNo,
                  'Phone No.',
                  required: true,
                  hint: 'e.g. 09 123 456 789',
                  keyboardType: TextInputType.phone,
                  autocorrect: false,
                ),
                _textField(
                  RegistrationField.email,
                  'Email',
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                _textField(
                  RegistrationField.currentCity,
                  'Current City',
                  capitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
          FormSectionCard(
            title: 'Graduation Attendance',
            subtitle: 'Will the graduate attend the graduation ceremony?',
            icon: Icons.school_outlined,
            child: ChoiceFormField<AttendanceStatus>(
              key: _attendanceKey,
              label: 'Attendance Status',
              isRequired: true,
              initialValue: widget.initialRegistration?.attendanceStatus,
              options: AttendanceStatus.values,
              optionLabel: (status) => status.label,
              validator: (value) =>
                  value == null ? 'Attendance Status is required.' : null,
              onChanged: (value) => _attendance = value,
            ),
          ),
          FormSectionCard(
            title: 'Current Location',
            subtitle: 'Where does the graduate live now?',
            icon: Icons.public,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChoiceFormField<CurrentCountry>(
                  key: _countryKey,
                  label: 'Current Country',
                  isRequired: true,
                  initialValue: widget.initialRegistration?.currentCountry,
                  options: CurrentCountry.values,
                  optionLabel: (country) => country.label,
                  validator: (value) =>
                      value == null ? 'Current Country is required.' : null,
                  onChanged: (value) => setState(() => _country = value),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: _country == CurrentCountry.other
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ResponsiveFieldGrid(
                            children: [
                              _textField(
                                RegistrationField.otherCountry,
                                'Other Country',
                                required: true,
                                capitalization: TextCapitalization.words,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          FormSectionCard(
            title: 'Additional Information',
            subtitle: 'Anything else the organisers should know.',
            icon: Icons.notes_outlined,
            child: _textField(
              RegistrationField.remark,
              'Remark',
              capitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 6,
            ),
          ),
          if (_submitError != null) _ErrorBanner(message: _submitError!),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final submit = FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: Size(wide ? 240 : double.infinity, 52),
          ),
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(
            _submitting
                ? 'Saving…'
                : _isEditing
                ? 'Save Changes'
                : 'Submit Registration',
          ),
        );
        final onCancel = widget.onCancel;
        final cancel = onCancel == null
            ? null
            : OutlinedButton(
                onPressed: _submitting ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(wide ? 140 : double.infinity, 52),
                ),
                child: const Text('Cancel'),
              );

        if (wide) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 12,
            children: [?cancel, submit],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [submit, ?cancel],
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
