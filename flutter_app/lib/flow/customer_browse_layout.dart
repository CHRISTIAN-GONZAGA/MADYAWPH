import 'package:flutter/material.dart';

/// Whether customer category/room screens should use the paged grid layout.
bool customerUseWideBrowseLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height;
}

/// Grid dimensions for landscape customer browse screens.
class CustomerLandscapeGridLayout {
  const CustomerLandscapeGridLayout({
    required this.crossAxisCount,
    required this.rowCount,
  });

  final int crossAxisCount;
  final int rowCount;

  int get pageSize => crossAxisCount * rowCount;

  static CustomerLandscapeGridLayout forSize(Size size) {
    final w = size.width;
    final h = size.height;
    if (w >= 1000) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 4, rowCount: 2);
    }
    if (w >= 720) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 4, rowCount: 2);
    }
    if (h < 300) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 3, rowCount: 2);
    }
    return const CustomerLandscapeGridLayout(crossAxisCount: 3, rowCount: 3);
  }
}

/// Pull-to-refresh wrapper used for both portrait lists and landscape grids.
class CustomerBrowseRefresh extends StatelessWidget {
  const CustomerBrowseRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
