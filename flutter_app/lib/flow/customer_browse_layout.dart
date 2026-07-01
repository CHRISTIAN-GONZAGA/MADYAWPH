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

  /// Tighter grid when only a few categories or rooms are available.
  static CustomerLandscapeGridLayout forItemCount(Size size, int itemCount) {
    if (itemCount <= 0) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 1, rowCount: 1);
    }
    final base = forSize(size);
    if (itemCount == 1) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 1, rowCount: 1);
    }
    if (itemCount <= 2) {
      return CustomerLandscapeGridLayout(
        crossAxisCount: itemCount.clamp(1, base.crossAxisCount),
        rowCount: 1,
      );
    }
    if (itemCount < base.crossAxisCount) {
      return CustomerLandscapeGridLayout(
        crossAxisCount: itemCount,
        rowCount: 1,
      );
    }
    if (itemCount < base.pageSize) {
      final rows = ((itemCount - 1) ~/ base.crossAxisCount) + 1;
      return CustomerLandscapeGridLayout(
        crossAxisCount: base.crossAxisCount,
        rowCount: rows.clamp(1, base.rowCount),
      );
    }
    return base;
  }

  static CustomerLandscapeGridLayout forSize(Size size) {
    final w = size.width;
    final h = size.height;
    if (h < 260) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 4, rowCount: 1);
    }
    if (h < 360) {
      if (w >= 900) {
        return const CustomerLandscapeGridLayout(crossAxisCount: 5, rowCount: 2);
      }
      return const CustomerLandscapeGridLayout(crossAxisCount: 4, rowCount: 2);
    }
    if (w >= 1000) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 4, rowCount: 2);
    }
    if (w >= 720) {
      return const CustomerLandscapeGridLayout(crossAxisCount: 4, rowCount: 2);
    }
    return const CustomerLandscapeGridLayout(crossAxisCount: 3, rowCount: 2);
  }
}

/// Pull-to-refresh wrapper used for both portrait lists and landscape grids.
class CustomerBrowseRefresh extends StatelessWidget {
  const CustomerBrowseRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.landscape = false,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    if (landscape) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: constraints.maxHeight,
                width: constraints.maxWidth,
                child: child,
              ),
            );
          },
        ),
      );
    }

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
