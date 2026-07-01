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

    final size = MediaQuery.sizeOf(context);
    final layout = widget.layout ??
        CustomerLandscapeGridLayout.forItemCount(size, widget.itemCount);
    final pageSize = layout.pageSize;
    final pages = (widget.itemCount / pageSize).ceil();
    final startIndices = List.generate(pages, (p) => p * pageSize);
    final singlePage = pages == 1;

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        return PageView.builder(
          controller: _pageCtrl,
          itemCount: pages,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, pageIndex) {
            final start = startIndices[pageIndex];
            final countOnPage = (pageIndex == pages - 1)
                ? widget.itemCount - start
                : pageSize;

            const spacing = 10.0;
            final columns = layout.crossAxisCount;
            final rowsOnPage =
                ((countOnPage - 1) ~/ columns) + 1;
            final cellW =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cellH = singlePage
                ? (constraints.maxHeight - spacing * (rowsOnPage - 1)) /
                    rowsOnPage
                : (constraints.maxHeight - spacing * (layout.rowCount - 1)) /
                    layout.rowCount;

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
    );

    if (singlePage) {
      return grid;
    }

    return Column(
      children: [
        Expanded(child: grid),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 130;
        final imageFlex = tight ? 2 : 3;
        final textFlex = tight ? 3 : 2;

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
                  flex: imageFlex,
                  child: imageUrl.isEmpty
                      ? ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.category_outlined,
                              color: scheme.outline, size: tight ? 22 : 28),
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
                  flex: textFlex,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      tight ? 4 : 6,
                      8,
                      tight ? 5 : 7,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: tight ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                fontSize: tight ? 11 : null,
                              ),
                        ),
                        if (!tight &&
                            description != null &&
                            description!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                          ),
                        ],
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              available
                                  ? Icons.check_circle_outline
                                  : Icons.block,
                              size: 11,
                              color:
                                  available ? scheme.primary : scheme.error,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                availLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: available
                                          ? scheme.primary
                                          : scheme.error,
                                      fontWeight: FontWeight.w700,
                                      fontSize: tight ? 9 : 10,
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
      },
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 130;
        final imageFlex = tight ? 2 : 3;
        final textFlex = tight ? 3 : 2;

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
                flex: imageFlex,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkMediaImage(
                      url: imageUrl,
                      fit: BoxFit.cover,
                      error: ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.bed_outlined,
                            color: scheme.outline, size: tight ? 22 : 28),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      left: 4,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              child: Text(
                                priceLabel,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: textFlex,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    tight ? 4 : 5,
                    8,
                    tight ? 5 : 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: tight ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              fontSize: tight ? 11 : null,
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
                                  padding: EdgeInsets.symmetric(
                                    vertical: tight ? 3 : 5,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  'Reserve',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: tight ? 9 : 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: FilledButton(
                                onPressed: busy ? null : onBook,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    vertical: tight ? 3 : 5,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  'Book',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: tight ? 9 : 10),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        FilledButton(
                          onPressed: busy ? null : onBook,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: tight ? 4 : 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            busy ? '…' : 'Book',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: tight ? 10 : 11),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
