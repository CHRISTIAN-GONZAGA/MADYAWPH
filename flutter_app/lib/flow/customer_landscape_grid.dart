import 'package:flutter/material.dart';

import '../widgets/chat_attachment.dart';

const kCustomerLandscapePageSize = 9;
const kCustomerLandscapeColumns = 3;

List<List<T>> chunkList<T>(List<T> items, int size) {
  if (items.isEmpty) return const [];
  final pages = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    final end = i + size > items.length ? items.length : i + size;
    pages.add(items.sublist(i, end));
  }
  return pages;
}

/// Landscape layout: up to 9 tappable cells per page (3×3), swipe between pages.
class CustomerLandscapePagedGrid extends StatefulWidget {
  const CustomerLandscapePagedGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.pageSize = kCustomerLandscapePageSize,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int pageSize;

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

    final pages = (widget.itemCount / widget.pageSize).ceil();
    final startIndices = List.generate(
      pages,
      (p) => p * widget.pageSize,
    );

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
                  : widget.pageSize;

              return LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  const rows = kCustomerLandscapeColumns;
                  final cellW =
                      (constraints.maxWidth - spacing * (rows - 1)) / rows;
                  final cellH =
                      (constraints.maxHeight - spacing * (rows - 1)) / rows;

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: rows,
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
          const SizedBox(height: 6),
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
          const SizedBox(height: 4),
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
  });

  final String name;
  final String imageUrl;
  final String availLabel;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
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
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
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
                    const Spacer(),
                    Text(
                      availLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: available
                                ? scheme.primary
                                : scheme.error,
                            fontWeight: FontWeight.w700,
                          ),
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
    required this.onTap,
    this.busy = false,
  });

  final String title;
  final String priceLabel;
  final String imageUrl;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
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
                    top: 4,
                    right: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
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
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
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
                    FilledButton(
                      onPressed: busy ? null : onTap,
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
      ),
    );
  }
}
