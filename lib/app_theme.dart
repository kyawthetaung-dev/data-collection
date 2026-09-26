import 'package:flutter/material.dart';

/// The spacing scale. Use these instead of one-off numbers so gaps line up
/// across every screen.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// The corner radii: one for controls (buttons, inputs, menus), one for cards
/// and one for dialogs.
abstract final class AppRadius {
  static const control = 12.0;
  static const card = 16.0;
  static const dialog = 20.0;
}

/// Colours the Material colour scheme has no slot for.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  static const light = AppColors(
    success: Color(0xFF2E7D32),
    successContainer: Color(0xFFE3F4E8),
    onSuccessContainer: Color(0xFF1B5E20),
  );

  /// Something went well: a saved registration, an allowed attendance.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  @override
  AppColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return AppColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
    );
  }
}

extension AppThemeContext on BuildContext {
  /// The app's extra colours.
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

/// The look of the whole app, defined once so every screen is consistent.
abstract final class AppTheme {
  static const seed = Color(0xFF3949AB);

  /// The minimum height of a button or input, and so of a finger target.
  static const controlHeight = 48.0;

  static ThemeData light() {
    final colors = ColorScheme.fromSeed(seedColor: seed);
    // Standard density on every platform. Left to itself Flutter tightens
    // controls on desktop browsers, which would make the same screen look and
    // feel different on a laptop and a tablet.
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final buttonText = text.labelLarge?.copyWith(fontWeight: FontWeight.w600);

    return base.copyWith(
      scaffoldBackgroundColor: colors.surfaceContainerLow,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surface,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        hintStyle: TextStyle(color: colors.outline),
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, controlHeight),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, controlHeight),
          shape: controlShape,
          side: BorderSide(color: colors.outline),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, controlHeight),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: controlShape,
        side: BorderSide(color: colors.outlineVariant),
        selectedColor: colors.primaryContainer,
        labelStyle: text.labelLarge,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.dialog),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
      extensions: const [AppColors.light],
    );
  }
}
