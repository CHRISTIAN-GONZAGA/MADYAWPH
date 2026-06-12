import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/philippine_city_index.dart';

/// Destination input with scrollable Philippine city suggestions.
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
  PhilippineCityIndex? _index;
  List<PhilippineCityEntry> _suggestions = const [];
  bool _loadingIndex = true;
  bool _showList = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller.addListener(_refreshSuggestions);
    PhilippineCityIndex.load().then((idx) {
      if (!mounted) return;
      setState(() {
        _index = idx;
        _loadingIndex = false;
      });
      _refreshSuggestions();
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    widget.controller.removeListener(_refreshSuggestions);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    setState(() => _showList = _focus.hasFocus);
    if (_focus.hasFocus) _refreshSuggestions();
  }

  void _refreshSuggestions() {
    final idx = _index;
    if (idx == null) return;
    setState(() {
      _suggestions = idx.search(widget.controller.text);
    });
  }

  void _pick(PhilippineCityEntry entry) {
    HapticFeedback.selectionClick();
    widget.controller.text = entry.searchQuery;
    widget.onSelected?.call(entry);
    setState(() => _showList = false);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      widget.controller.clear();
                      _refreshSuggestions();
                    },
                    icon: const Icon(Icons.close, size: 20),
                  )
                : Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
          ),
          onTap: () => setState(() => _showList = true),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _showList && (_suggestions.isNotEmpty || _loadingIndex)
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              elevation: 2,
              shadowColor: Colors.black12,
              borderRadius: BorderRadius.circular(14),
              color: scheme.surfaceContainerHigh,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: _loadingIndex
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
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
}
