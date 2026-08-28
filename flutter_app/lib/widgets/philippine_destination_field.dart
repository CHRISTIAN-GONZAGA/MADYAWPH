import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_logo_paths.dart';
import '../data/philippine_city_index.dart';

/// Destination input with overlay city suggestions that scroll independently
/// of the parent search page.
class PhilippineDestinationField extends StatefulWidget {
  const PhilippineDestinationField({
    super.key,
    required this.controller,
    this.onSelected,
    this.hintText = 'City, region, or hotel name',
  });

  final TextEditingController controller;
  final ValueChanged<PhilippineCityEntry>? onSelected;
  final String hintText;

  @override
  State<PhilippineDestinationField> createState() =>
      _PhilippineDestinationFieldState();
}

class _PhilippineDestinationFieldState extends State<PhilippineDestinationField> {
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  PhilippineCityIndex? _index;
  List<PhilippineCityEntry> _suggestions = const [];
  bool _loadingIndex = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller.addListener(_onQueryChanged);
    PhilippineCityIndex.load().then((idx) {
      if (!mounted) return;
      setState(() {
        _index = idx;
        _loadingIndex = false;
      });
      _refreshSuggestions();
      _rebuildOverlay();
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    _focus.removeListener(_onFocus);
    widget.controller.removeListener(_onQueryChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _refreshSuggestions();
      _showOverlay();
    }
  }

  void _onQueryChanged() {
    _refreshSuggestions();
    if (mounted) setState(() {});
    _rebuildOverlay();
  }

  void _refreshSuggestions() {
    final idx = _index;
    if (idx == null) return;
    _suggestions = idx.search(widget.controller.text);
  }

  bool get _shouldShowOverlay =>
      _focus.hasFocus && (_loadingIndex || _suggestions.isNotEmpty);

  void _showOverlay() {
    if (_overlay != null) {
      _rebuildOverlay();
      return;
    }
    if (!_shouldShowOverlay) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_overlay!);
  }

  void _rebuildOverlay() {
    if (_overlay == null) {
      if (_shouldShowOverlay) _showOverlay();
      return;
    }
    if (!_shouldShowOverlay) {
      _removeOverlay();
      return;
    }
    _overlay!.markNeedsBuild();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _closeSuggestions() {
    _removeOverlay();
    _focus.unfocus();
  }

  void _pick(PhilippineCityEntry entry) {
    HapticFeedback.selectionClick();
    widget.controller.text = entry.searchQuery;
    widget.onSelected?.call(entry);
    _closeSuggestions();
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? MediaQuery.sizeOf(overlayContext).width - 32;
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeSuggestions,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 10,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: 260,
              child: _loadingIndex
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: const ScrollBehavior().copyWith(
                        overscroll: false,
                        physics: const ClampingScrollPhysics(),
                      ),
                      child: ListView.separated(
                        primary: false,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.manual,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                        itemBuilder: (context, i) {
                          final entry = _suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              size: 20,
                              color: scheme.primary,
                            ),
                            title: Text(
                              entry.city,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${entry.province} · ${entry.region}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _pick(entry),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        onTap: _showOverlay,
        onTapOutside: (_) {},
        decoration: InputDecoration(
          hintText: widget.hintText,
          filled: true,
          fillColor: scheme.brightness == Brightness.dark
              ? scheme.surfaceContainerLowest
              : Colors.white,
          prefixIcon: const Icon(
            Icons.location_on_outlined,
            color: MadyawBrand.navy,
          ),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    widget.controller.clear();
                    _refreshSuggestions();
                    _rebuildOverlay();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close, size: 20),
                )
              : Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: scheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
