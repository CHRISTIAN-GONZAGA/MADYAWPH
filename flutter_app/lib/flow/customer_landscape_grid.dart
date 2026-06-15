import 'package:flutter/material.dart';

import '../widgets/chat_attachment.dart';
import 'customer_browse_layout.dart';

/// Landscape layout: paged grid with adaptive columns/rows, swipe between pages.
class CustomerLandscapePagedGrid extends StatefulWidget {
  const CustomerLandscapePagedGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.layout,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final CustomerLandscapeGridLayout? layout;

  @override
  State<CustomerLandscapePagedGrid> createState() =>
      _CustomerLandscapePagedGridState();
}

class _CustomerLandscapePagedGridState extends State<CustomerLandscapePagedGrid> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return const SizedBox.shrink();
    }

    final layout =
        widget.layout ?? CustomerLandscapeGridLayout.forSize(MediaQuery.sizeOf(context));
    final pageSize = layout.pageSize;
    final pages = (widget.itemCount / pageSize).ceil();
    final startIndices = List.generate(pages, (p) => p * pageSize);

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: pages,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, pageIndex) {
              final start = startIndices[pageIndex];
              final countOnPage = (pageIndex == pages - 1)
                  ? widget.itemCount - start
                  : pageSize;

              return LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final columns = layout.crossAxisCount;
                  final rows = layout.rowCount;
                  final cellW =
                      (constraints.maxWidth - spacing * (columns - 1)) / columns;
                  final cellH =
                      (constraints.maxHeight - spacing * (rows - 1)) / rows;

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: cellW / cellH,
                    ),
                    itemCount: countOnPage,
                    itemBuilder: (context, i) =>
                        widget.itemBuilder(context, start + i),
                  );
                },
              );
            },
          ),
        ),
        if (pages > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class CustomerLandscapeCategoryTile extends StatelessWidget {
  const CustomerLandscapeCategoryTile({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.availLabel,
    required this.available,
    required this.onTap,
    this.description,
  });

  final String name;
  final String imageUrl;
  final String availLabel;
  final bool available;
  final VoidCallback onTap;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: imageUrl.isEmpty
                  ? ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.category_outlined,
                          color: scheme.outline, size: 28),
                    )
                  : NetworkMediaImage(
                      url: imageUrl,
                      fit: BoxFit.cover,
                      error: ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined,
                            color: scheme.outline),
                      ),
                    ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          available ? Icons.check_circle_outline : Icons.block,
                          size: 12,
                          color: available ? scheme.primary : scheme.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            availLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: available
                                          ? scheme.primary
                                          : scheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerLandscapeRoomTile extends StatelessWidget {
  const CustomerLandscapeRoomTile({
    super.key,
    required this.title,
    required this.priceLabel,
    required this.imageUrl,
    required this.onBook,
    this.onReserve,
    this.busy = false,
  });

  final String title;
  final String priceLabel;
  final String imageUrl;
  final VoidCallback onBook;
  final VoidCallback? onReserve;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showReserve = onReserve != null;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetworkMediaImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  error: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.bed_outlined,
                        color: scheme.outline, size: 28),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      child: Text(
                        priceLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  if (showReserve)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy ? null : onReserve,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Reserve', style: TextStyle(fontSize: 10)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy ? null : onBook,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Book', style: TextStyle(fontSize: 10)),
                          ),
                        ),
                      ],
                    )
                  else
                    FilledButton(
                      onPressed: busy ? null : onBook,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        busy ? '…' : 'Book',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
