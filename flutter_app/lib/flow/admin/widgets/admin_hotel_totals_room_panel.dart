import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'admin_room_detail_navigation.dart';
import 'admin_summary_room_tile.dart';

class _RoomListPayload {
  const _RoomListPayload({
    required this.title,
    required this.rooms,
    required this.showGuest,
    this.subtitle,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool showGuest;
  final String? subtitle;
}

/// Slide-up room list + details for Summary → Hotel totals (no Navigator/modals).
class HotelTotalsRoomPanelScope extends InheritedWidget {
  const HotelTotalsRoomPanelScope({
    super.key,
    required this.openRoomList,
    required this.openRoomDetail,
    required this.closePanel,
    required this.backToRoomList,
    required this.isOpen,
    required super.child,
  });

  final void Function({
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) openRoomList;

  final void Function(String roomId) openRoomDetail;

  final VoidCallback closePanel;

  final VoidCallback backToRoomList;

  final bool isOpen;

  static HotelTotalsRoomPanelScope? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<HotelTotalsRoomPanelScope>();
  }

  @override
  bool updateShouldNotify(HotelTotalsRoomPanelScope oldWidget) {
    return isOpen != oldWidget.isOpen;
  }
}

class HotelTotalsRoomPanelHost extends StatefulWidget {
  const HotelTotalsRoomPanelHost({
    super.key,
    required this.child,
    this.onRefresh,
    this.onBindBackHandler,
  });

  final Widget child;
  final Future<void> Function()? onRefresh;
  final ValueChanged<bool Function()>? onBindBackHandler;

  @override
  State<HotelTotalsRoomPanelHost> createState() =>
      _HotelTotalsRoomPanelHostState();
}

class _HotelTotalsRoomPanelHostState extends State<HotelTotalsRoomPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  bool _visible = false;
  bool _showDetail = false;
  _RoomListPayload? _list;
  String? _detailRoomId;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBindBackHandler?.call(_handleBack);
    });
  }

  @override
  void dispose() {
    AdminRoomDetailNavigation.notifyPanelOpen(false);
    widget.onBindBackHandler?.call(() => false);
    _slideCtrl.dispose();
    super.dispose();
  }

  void _syncOpenFlag() {
    AdminRoomDetailNavigation.notifyPanelOpen(_visible);
    widget.onBindBackHandler?.call(_handleBack);
  }

  void _openRoomList({
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) {
    HapticFeedback.selectionClick();
    setState(() {
      _visible = true;
      _showDetail = false;
      _detailRoomId = null;
      _list = _RoomListPayload(
        title: title,
        rooms: rooms,
        showGuest: showGuest,
        subtitle: subtitle,
      );
    });
    _syncOpenFlag();
    _slideCtrl.forward(from: 0);
  }

  void _openRoomDetail(String roomId) {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _showDetail = true;
      _detailRoomId = id;
    });
  }

  Future<void> _closePanel() async {
    if (!_visible) return;
    await _slideCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _visible = false;
      _showDetail = false;
      _detailRoomId = null;
      _list = null;
    });
    _syncOpenFlag();
    final refresh = widget.onRefresh;
    if (refresh != null) {
      await refresh();
    }
  }

  void _backToRoomList() {
    if (!_showDetail) {
      _closePanel();
      return;
    }
    setState(() {
      _showDetail = false;
      _detailRoomId = null;
    });
  }

  bool _handleBack() {
    if (!_visible) return false;
    if (_showDetail) {
      _backToRoomList();
      return true;
    }
    _closePanel();
    return true;
  }

  Widget _buildPanelBody(BuildContext context) {
    if (_showDetail && _detailRoomId != null) {
      return AdminRoomDetailScreen(
        key: ValueKey(_detailRoomId),
        roomId: _detailRoomId!,
        embedded: true,
        onClose: _backToRoomList,
      );
    }

    final list = _list;
    if (list == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No rooms loaded. Close and try again.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return _HotelTotalsRoomGrid(
      rooms: list.rooms,
      showGuest: list.showGuest,
      subtitle: list.subtitle,
      onRoomTap: _openRoomDetail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelHeight = MediaQuery.sizeOf(context).height * 0.92;
    final bg = _showDetail
        ? const Color(0xFFF5F3EF)
        : Theme.of(context).colorScheme.surface;

    return HotelTotalsRoomPanelScope(
      isOpen: _visible,
      openRoomList: _openRoomList,
      openRoomDetail: _openRoomDetail,
      closePanel: _closePanel,
      backToRoomList: _backToRoomList,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closePanel,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelHeight,
              child: SlideTransition(
                position: _slideAnim,
                child: Material(
                  color: bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Expanded(
                          child: _showDetail && _detailRoomId != null
                              ? _buildPanelBody(context)
                              : Scaffold(
                                  backgroundColor: bg,
                                  appBar: AppBar(
                                    title: Text(
                                      _list?.title ?? 'Rooms',
                                    ),
                                    leading: BackButton(
                                      onPressed: _closePanel,
                                    ),
                                  ),
                                  body: _buildPanelBody(context),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HotelTotalsRoomGrid extends StatelessWidget {
  const _HotelTotalsRoomGrid({
    required this.rooms,
    required this.showGuest,
    required this.onRoomTap,
    this.subtitle,
  });

  final List<Map<String, dynamic>> rooms;
  final bool showGuest;
  final String? subtitle;
  final void Function(String roomId) onRoomTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columns = adminSummaryRoomGridColumns(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            subtitle ?? '${rooms.length} room(s) · tap a tile for details',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.28,
            ),
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              return AdminSummaryRoomGridTile(
                room: room,
                showGuest: showGuest,
                onTap: () => onRoomTap(AdminDashboardModels.roomIdOf(room)),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Opens room list/detail inside [HotelTotalsRoomPanelHost] when available.
void openHotelTotalsRoomList(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> rooms,
  required bool showGuest,
  String? subtitle,
}) {
  if (rooms.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No rooms in "$title".')),
    );
    return;
  }
  final panel = HotelTotalsRoomPanelScope.maybeOf(context);
  if (panel == null) {
    AdminRoomDetailNavigation.showRoomListSheet(
      context: context,
      title: title,
      rooms: rooms,
      showGuest: showGuest,
      subtitle: subtitle,
    );
    return;
  }
  panel.openRoomList(
    title: title,
    rooms: rooms,
    showGuest: showGuest,
    subtitle: subtitle,
  );
}

void openHotelTotalsRoomDetail(
  BuildContext context, {
  required Map<String, dynamic> room,
}) {
  final id = AdminDashboardModels.roomIdOf(room);
  if (id.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Room ID missing. Pull to refresh the dashboard and try again.',
        ),
      ),
    );
    return;
  }
  final panel = HotelTotalsRoomPanelScope.maybeOf(context);
  if (panel == null) {
    AdminRoomDetailNavigation.showRoomDetailSheet(roomId: id, context: context);
    return;
  }
  if (!panel.isOpen) {
    panel.openRoomList(
      title: 'Room details',
      rooms: [room],
      showGuest: true,
    );
  }
  panel.openRoomDetail(id);
}
