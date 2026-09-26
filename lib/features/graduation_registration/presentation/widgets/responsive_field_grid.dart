import 'package:flutter/widgets.dart';

/// Marks a child of [ResponsiveFieldGrid] that spans every column.
class FullWidth extends StatelessWidget {
  const FullWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Lays out form fields in two columns when there is room for them and in a
/// single full-width column otherwise. Wrap a child in [FullWidth] to make it
/// span both columns.
class ResponsiveFieldGrid extends StatelessWidget {
  const ResponsiveFieldGrid({
    super.key,
    required this.children,
    this.spacing = 16,
    this.twoColumnMinWidth = 600,
  });

  final List<Widget> children;
  final double spacing;

  /// The narrowest available width that still gets two columns.
  final double twoColumnMinWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columnWidth = width >= twoColumnMinWidth
            ? ((width - spacing) / 2).floorToDouble()
            : width;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: child is FullWidth ? width : columnWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}
