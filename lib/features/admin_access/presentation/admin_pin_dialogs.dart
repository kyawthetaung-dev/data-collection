import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../graduation_registration/presentation/widgets/app_snack_bar.dart';
import '../domain/admin_pin_hasher.dart';
import '../domain/admin_session.dart';
import 'admin_scope.dart';

/// Turns Admin Mode on, asking for the PIN. On a browser with no PIN yet it
/// asks the user to set one instead. Resolves to whether Admin Mode is on.
Future<bool> requestAdminAccess(BuildContext context) async {
  final session = AdminScope.read(context);
  if (session.isAdmin) return true;

  final bool hasPin;
  try {
    hasPin = await session.hasPinSet();
  } catch (error, stackTrace) {
    debugPrint('Reading the Admin settings failed: $error\n$stackTrace');
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Could not open the Admin settings. Please try again.',
        kind: AppSnackBarKind.error,
      );
    }
    return false;
  }
  if (!context.mounted) return false;

  final granted =
      await showDialog<bool>(
        context: context,
        // A stray tap outside must not throw away a half-typed PIN.
        barrierDismissible: false,
        builder: (_) =>
            hasPin ? const AdminLoginDialog() : const AdminSetupDialog(),
      ) ??
      false;
  if (granted && context.mounted) {
    showAppSnackBar(context, 'Admin mode is on.');
  }
  return granted;
}

/// Asks for the current PIN and a new one. Only meant for Admin Mode.
Future<void> showChangePinDialog(BuildContext context) async {
  final changed =
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AdminChangePinDialog(),
      ) ??
      false;
  if (changed && context.mounted) {
    showAppSnackBar(context, 'Admin PIN changed.');
  }
}

/// Turns Admin Mode off. Protected screens close at once.
void exitAdminMode(BuildContext context) {
  AdminScope.read(context).logout();
  showAppSnackBar(context, 'Admin mode is off.', kind: AppSnackBarKind.info);
}

/// A masked, digits-only PIN field.
///
/// The PIN is never shown: there is no "show" toggle, so it cannot be read
/// over a shoulder or in a screenshot.
class AdminPinField extends StatelessWidget {
  const AdminPinField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.errorText,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final String? errorText;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(AdminPinRules.maxLength),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        errorText: errorText,
      ),
    );
  }
}

/// The frame every PIN dialog shares: a fixed comfortable width on tablets and
/// desktops, the full width minus a margin on phones, and scrolling so the
/// on-screen keyboard never hides the buttons.
class _PinDialogFrame extends StatelessWidget {
  const _PinDialogFrame({
    required this.title,
    required this.children,
    required this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  static const contentWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      icon: const Icon(Icons.admin_panel_settings_outlined),
      title: Text(title),
      content: SizedBox(
        width: contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.md,
          children: children,
        ),
      ),
      actions: actions,
    );
  }
}

class _BusyLabel extends StatelessWidget {
  const _BusyLabel({required this.busy, required this.label});

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    return busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
  }
}

String _seconds(Duration wait) {
  final seconds = (wait.inMilliseconds / 1000).ceil();
  return '$seconds second${seconds == 1 ? '' : 's'}';
}

/// Asks for the PIN. Pops `true` once Admin Mode is on.
class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  final _pin = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;
  bool _locked = false;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _locked) return;
    if (_pin.text.isEmpty) {
      setState(() => _error = 'Enter the PIN.');
      return;
    }
    final session = AdminScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await session.login(_pin.text);
      if (!mounted) return;
      switch (result.outcome) {
        case LoginOutcome.success:
          Navigator.of(context).pop(true);
          return;
        case LoginOutcome.incorrect:
          final left = result.attemptsLeft ?? 0;
          _fail(
            left <= 2
                ? 'Incorrect PIN. $left attempt${left == 1 ? '' : 's'} left.'
                : 'Incorrect PIN.',
          );
        case LoginOutcome.lockedOut:
          _startCountdown(session, result.retryAfter ?? Duration.zero);
        case LoginOutcome.noPinSet:
          _fail(
            'No Admin PIN is set on this browser. Close this and try again.',
          );
      }
    } catch (error, stackTrace) {
      debugPrint('Checking the Admin PIN failed: $error\n$stackTrace');
      if (mounted) _fail('Could not check the PIN. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows [message] and clears the field, so a wrong PIN is not left lying in
  /// it and the next try starts fresh.
  void _fail(String message) {
    setState(() => _error = message);
    _pin.clear();
    _focus.requestFocus();
  }

  void _startCountdown(AdminSession session, Duration wait) {
    _pin.clear();
    _countdown?.cancel();
    setState(() {
      _locked = true;
      _error = 'Too many wrong attempts. Try again in ${_seconds(wait)}.';
    });
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = session.lockRemaining;
      if (!mounted) return;
      if (remaining == null) {
        timer.cancel();
        setState(() {
          _locked = false;
          _error = null;
        });
        _focus.requestFocus();
      } else {
        setState(
          () => _error =
              'Too many wrong attempts. Try again in ${_seconds(remaining)}.',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PinDialogFrame(
      title: 'Admin PIN',
      actions: [
        TextButton(
          // Not while the PIN is being checked: a cancelled login must not
          // still switch Admin Mode on a moment later.
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _locked ? null : _submit,
          child: _BusyLabel(busy: _busy, label: 'Login'),
        ),
      ],
      children: [
        const Text('Enter the Admin PIN to manage registrations.'),
        AdminPinField(
          controller: _pin,
          focusNode: _focus,
          label: 'PIN',
          autofocus: true,
          enabled: !_busy,
          errorText: _error,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null && !_locked) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// Sets the first Admin PIN on a browser that has none. Pops `true` once it is
/// set and Admin Mode is on.
class AdminSetupDialog extends StatefulWidget {
  const AdminSetupDialog({super.key});

  @override
  State<AdminSetupDialog> createState() => _AdminSetupDialogState();
}

class _AdminSetupDialogState extends State<AdminSetupDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  String? _pinError;
  String? _confirmError;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = AdminPinRules.validate(_pin.text);
    final mismatch = _pin.text != _confirm.text
        ? 'The PINs do not match.'
        : null;
    if (problem != null || mismatch != null) {
      setState(() {
        _pinError = problem;
        _confirmError = problem == null ? mismatch : null;
      });
      return;
    }
    final session = AdminScope.read(context);
    setState(() {
      _busy = true;
      _pinError = null;
      _confirmError = null;
    });
    try {
      await session.setUpPin(_pin.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AdminPinAlreadySetException {
      // Another tab of this browser set a PIN in the meantime.
      if (mounted) {
        setState(
          () => _pinError =
              'An Admin PIN was already set in another tab. Close this and '
              'log in with it.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Setting the Admin PIN failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _pinError = 'Could not save the PIN. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PinDialogFrame(
      title: 'Set an Admin PIN',
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _BusyLabel(busy: _busy, label: 'Set PIN'),
        ),
      ],
      children: [
        const Text(
          'The Admin PIN protects the registration list, exports and imports '
          'on this browser. Choose 4 to 12 digits.',
        ),
        AdminPinField(
          controller: _pin,
          label: 'New PIN',
          autofocus: true,
          enabled: !_busy,
          errorText: _pinError,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _pinError = null),
          onSubmitted: (_) => _confirmFocus.requestFocus(),
        ),
        AdminPinField(
          controller: _confirm,
          focusNode: _confirmFocus,
          label: 'Confirm PIN',
          enabled: !_busy,
          errorText: _confirmError,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _confirmError = null),
          onSubmitted: (_) => _submit(),
        ),
        Text(
          'If you forget it, the only way to reset it is to clear this site\'s '
          'data in your browser, which also deletes the registrations stored '
          'here. Export a JSON backup regularly.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Replaces the Admin PIN. Pops `true` once it is changed.
class AdminChangePinDialog extends StatefulWidget {
  const AdminChangePinDialog({super.key});

  @override
  State<AdminChangePinDialog> createState() => _AdminChangePinDialogState();
}

class _AdminChangePinDialogState extends State<AdminChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _nextFocus = FocusNode();
  final _confirmFocus = FocusNode();
  String? _currentError;
  String? _nextError;
  String? _confirmError;
  bool _busy = false;
  bool _locked = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    _nextFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final currentProblem = _current.text.isEmpty
        ? 'Enter the current PIN.'
        : null;
    final nextProblem = AdminPinRules.validate(_next.text);
    final mismatch = _next.text != _confirm.text
        ? 'The PINs do not match.'
        : null;
    if (currentProblem != null || nextProblem != null || mismatch != null) {
      setState(() {
        _currentError = currentProblem;
        _nextError = nextProblem;
        _confirmError = nextProblem == null ? mismatch : null;
      });
      return;
    }
    final session = AdminScope.read(context);
    setState(() {
      _busy = true;
      _currentError = _nextError = _confirmError = null;
    });
    try {
      final result = await session.changePin(
        currentPin: _current.text,
        newPin: _next.text,
      );
      if (!mounted) return;
      switch (result.outcome) {
        case LoginOutcome.success:
          Navigator.of(context).pop(true);
          return;
        case LoginOutcome.incorrect:
          setState(() => _currentError = 'Incorrect PIN.');
          _current.clear();
        case LoginOutcome.lockedOut:
          _locked = true;
          setState(
            () => _currentError =
                'Too many wrong attempts. Try again in '
                '${_seconds(result.retryAfter ?? Duration.zero)}.',
          );
        case LoginOutcome.noPinSet:
          setState(() => _currentError = 'No Admin PIN is set.');
      }
    } on AdminModeRequiredException {
      // Admin Mode ended while the dialog was open.
      if (mounted) Navigator.of(context).pop(false);
    } catch (error, stackTrace) {
      debugPrint('Changing the Admin PIN failed: $error\n$stackTrace');
      if (mounted) {
        setState(
          () => _currentError = 'Could not change the PIN. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PinDialogFrame(
      title: 'Change Admin PIN',
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _BusyLabel(busy: _busy, label: 'Change PIN'),
        ),
      ],
      children: [
        AdminPinField(
          controller: _current,
          label: 'Current PIN',
          autofocus: true,
          enabled: !_busy,
          errorText: _currentError,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (!_locked) setState(() => _currentError = null);
          },
          onSubmitted: (_) => _nextFocus.requestFocus(),
        ),
        AdminPinField(
          controller: _next,
          focusNode: _nextFocus,
          label: 'New PIN',
          enabled: !_busy,
          errorText: _nextError,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _nextError = null),
          onSubmitted: (_) => _confirmFocus.requestFocus(),
        ),
        AdminPinField(
          controller: _confirm,
          focusNode: _confirmFocus,
          label: 'Confirm new PIN',
          enabled: !_busy,
          errorText: _confirmError,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _confirmError = null),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}
