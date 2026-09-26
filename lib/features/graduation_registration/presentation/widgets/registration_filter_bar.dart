import 'package:flutter/material.dart';

import '../../domain/entities/registration_enums.dart';

/// The search box and the Major, Attendance and Country filters.
///
/// On a wide layout everything sits in one row. On a narrow one the search box
/// keeps the row to itself and the three filters fold behind a button, so the
/// list is not pushed off the screen.
class RegistrationFilterBar extends StatelessWidget {
  const RegistrationFilterBar({
    super.key,
    required this.wide,
    required this.searchController,
    required this.majorOptions,
    required this.major,
    required this.attendance,
    required this.country,
    required this.filtersExpanded,
    required this.hasActiveFilters,
    required this.onQueryChanged,
    required this.onMajorChanged,
    required this.onAttendanceChanged,
    required this.onCountryChanged,
    required this.onFiltersExpandedChanged,
    required this.onClear,
  });

  static const majorFilterKey = ValueKey('major-filter');
  static const attendanceFilterKey = ValueKey('attendance-filter');
  static const countryFilterKey = ValueKey('country-filter');
  static const filtersButtonKey = ValueKey('filters-button');

  final bool wide;
  final TextEditingController searchController;
  final List<String> majorOptions;
  final String? major;
  final AttendanceStatus? attendance;
  final CurrentCountry? country;

  /// Whether the folded filters are open. Only used when not [wide].
  final bool filtersExpanded;

  /// Whether a search or any filter is set, which enables "Clear".
  final bool hasActiveFilters;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onMajorChanged;
  final ValueChanged<AttendanceStatus?> onAttendanceChanged;
  final ValueChanged<CurrentCountry?> onCountryChanged;
  final ValueChanged<bool> onFiltersExpandedChanged;
  final VoidCallback onClear;

  int get _dropdownFilterCount =>
      (major == null ? 0 : 1) +
      (attendance == null ? 0 : 1) +
      (country == null ? 0 : 1);

  @override
  Widget build(BuildContext context) => wide ? _buildWide() : _buildNarrow();

  Widget _search() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: searchController,
      builder: (context, value, _) => TextField(
        controller: searchController,
        onChanged: onQueryChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search name, NRC, roll no. or phone',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    searchController.clear();
                    onQueryChanged('');
                  },
                ),
        ),
      ),
    );
  }

  Widget _majorDropdown() => _FilterDropdown<String>(
    key: majorFilterKey,
    label: 'Major',
    allLabel: 'All majors',
    value: major,
    options: [for (final option in majorOptions) (option, option)],
    onChanged: onMajorChanged,
  );

  Widget _attendanceDropdown() => _FilterDropdown<AttendanceStatus>(
    key: attendanceFilterKey,
    label: 'Attendance',
    allLabel: 'All statuses',
    value: attendance,
    options: [for (final s in AttendanceStatus.values) (s, s.label)],
    onChanged: onAttendanceChanged,
  );

  Widget _countryDropdown() => _FilterDropdown<CurrentCountry>(
    key: countryFilterKey,
    label: 'Country',
    allLabel: 'All countries',
    value: country,
    options: [for (final c in CurrentCountry.values) (c, c.label)],
    onChanged: onCountryChanged,
  );

  Widget _clearButton() => TextButton.icon(
    onPressed: hasActiveFilters ? onClear : null,
    icon: const Icon(Icons.filter_alt_off_outlined),
    label: const Text('Clear'),
  );

  Widget _buildWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Expanded(flex: 4, child: _search()),
        Expanded(flex: 2, child: _majorDropdown()),
        Expanded(flex: 2, child: _attendanceDropdown()),
        Expanded(flex: 2, child: _countryDropdown()),
        SizedBox(height: 56, child: _clearButton()),
      ],
    );
  }

  Widget _buildNarrow() {
    final count = _dropdownFilterCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(child: _search()),
            Badge.count(
              count: count,
              isLabelVisible: count > 0,
              child: IconButton.filledTonal(
                key: filtersButtonKey,
                tooltip: filtersExpanded ? 'Hide filters' : 'Show filters',
                isSelected: filtersExpanded,
                icon: const Icon(Icons.tune),
                selectedIcon: const Icon(Icons.expand_less),
                onPressed: () => onFiltersExpandedChanged(!filtersExpanded),
                style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: filtersExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      _majorDropdown(),
                      _attendanceDropdown(),
                      _countryDropdown(),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (hasActiveFilters)
          Align(alignment: Alignment.centerLeft, child: _clearButton()),
      ],
    );
  }
}

/// A labelled dropdown with an "All …" entry that means "no filter".
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    super.key,
    required this.label,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String allLabel;
  final T? value;

  /// Each option's value and the text shown for it.
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text(allLabel, overflow: TextOverflow.ellipsis),
            ),
            for (final (optionValue, optionLabel) in options)
              DropdownMenuItem<T?>(
                value: optionValue,
                child: Text(optionLabel, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
