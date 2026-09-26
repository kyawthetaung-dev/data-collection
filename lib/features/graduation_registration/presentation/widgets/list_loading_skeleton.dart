import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app_theme.dart';

/// Grey placeholder shapes shown while the registration list loads, in the
/// layout the list will take, so the page does not jump when the data arrives.
///
/// Reading from IndexedDB is usually near-instant, so nothing is drawn for the
/// first [showDelay]: a quick load never flashes a skeleton.
class ListLoadingSkeleton extends StatefulWidget {
  const ListLoadingSkeleton({
    super.key,
    this.asTable = false,
    this.columns = 1,
  });

  /// How long to wait before showing anything.
  static const showDelay = Duration(milliseconds: 250);

  /// Shape the placeholder as table rows instead of cards.
  final bool asTable;

  /// How many columns of placeholder cards, when not [asTable].
  final int columns;

  @override
  State<ListLoadingSkeleton> createState() => _ListLoadingSkeletonState();
}

class _ListLoadingSkeletonState extends State<ListLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  // Created up front, not lazily: a quick load removes this widget before the
  // delay is over, and a controller must not first be created while disposing.
  late final AnimationController _pulse;
  Timer? _delay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _delay = Timer(ListLoadingSkeleton.showDelay, () {
      if (!mounted) return;
      setState(() => _visible = true);
      _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading registrations',
      liveRegion: true,
      child: ExcludeSemantics(
        child: _visible
            ? FadeTransition(
                opacity: Tween<double>(begin: 0.45, end: 1).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _Bar(width: 200, height: 20),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _Bar(height: 56, radius: AppRadius.control),
                      const SizedBox(height: AppSpacing.lg),
                      if (widget.asTable)
                        const _TableSkeleton()
                      else
                        _CardsSkeleton(columns: widget.columns),
                    ],
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

/// A grey rounded bar.
class _Bar extends StatelessWidget {
  const _Bar({this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class _TableSkeleton extends StatelessWidget {
  const _TableSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  _Bar(width: 24),
                  SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 3, child: _Bar()),
                  SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 2, child: _Bar()),
                  SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 3, child: _Bar()),
                  SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 3, child: _Bar()),
                  SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 2, child: _Bar()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    Widget card() => const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bar(width: 160, height: 18),
            SizedBox(height: AppSpacing.sm),
            _Bar(width: 220),
            SizedBox(height: AppSpacing.lg),
            _Bar(width: 120),
            SizedBox(height: AppSpacing.lg),
            _Bar(width: 90, height: 24),
          ],
        ),
      ),
    );

    return Column(
      spacing: AppSpacing.md,
      children: [
        for (var row = 0; row < 3; row++)
          Row(
            spacing: AppSpacing.md,
            children: [
              for (var column = 0; column < columns; column++)
                Expanded(child: card()),
            ],
          ),
      ],
    );
  }
}
