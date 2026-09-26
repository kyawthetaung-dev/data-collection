import 'package:flutter/material.dart';

/// A single-choice field shown as a row of large, tappable chips.
///
/// It takes part in [Form] validation like any other [FormField], so a
/// `validator` can require a choice.
class ChoiceFormField<T> extends FormField<T> {
  ChoiceFormField({
    super.key,
    required String label,
    bool isRequired = false,
    required List<T> options,
    required String Function(T option) optionLabel,
    super.initialValue,
    super.validator,
    super.autovalidateMode = AutovalidateMode.onUserInteraction,
    ValueChanged<T>? onChanged,
  }) : super(
         builder: (state) {
           final theme = Theme.of(state.context);
           final colors = theme.colorScheme;
           final labelColor = state.hasError
               ? colors.error
               : colors.onSurfaceVariant;
           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               // The plain text reads "Label *"; the asterisk is drawn in red.
               Text.rich(
                 TextSpan(
                   text: label,
                   children: [
                     if (isRequired)
                       TextSpan(
                         text: ' *',
                         style: TextStyle(color: colors.error),
                       ),
                   ],
                 ),
                 style: theme.textTheme.labelLarge?.copyWith(color: labelColor),
               ),
               const SizedBox(height: 8),
               Wrap(
                 spacing: 8,
                 runSpacing: 8,
                 children: [
                   for (final option in options)
                     ChoiceChip(
                       label: Text(optionLabel(option)),
                       selected: state.value == option,
                       padding: const EdgeInsets.symmetric(
                         horizontal: 8,
                         vertical: 12,
                       ),
                       onSelected: (_) {
                         state.didChange(option);
                         onChanged?.call(option);
                       },
                     ),
                 ],
               ),
               if (state.hasError)
                 Padding(
                   padding: const EdgeInsets.only(top: 6, left: 4),
                   child: Text(
                     state.errorText!,
                     style: theme.textTheme.bodySmall?.copyWith(
                       color: colors.error,
                     ),
                   ),
                 ),
             ],
           );
         },
       );
}
