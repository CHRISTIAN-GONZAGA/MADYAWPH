import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_models.dart';
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

/// Slide-up room list for Summary → Hotel totals; room detail opens in a sheet.
class HotelTotalsRoomPanelScope extends InheritedWidget {
  const HotelTotalsRoomPanelScope({
    super.key,
    required this.openRoomList,
    required this.openRoomDetail,
    required this.closePanel,
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
    this.resolveLiveRooms,
  });

  final Widget child;
  final Future<void> Function()? onRefresh;
  final ValueChanged<bool Function()>? onBindBackHandler;
  final List<Map<String, dynamic>> Function()? resolveLiveRooms;

  @override
  State<HotelTotalsRoomPanelHost> createState() =>
      _HotelTotalsRoomPanelHostState();
}

class _HotelTotalsRoomPanelHostState extends State<HotelTotalsRoomPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<double> _slideOffset;

  bool _visible = false;
  _RoomListPayload? _list;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideOffset = CurvedAnimation(
      parent: _slideCtrl,
      curve: Curves.easeOutCubic,
    );
    _slideCtrl.addListener(_onSlideTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBindBackHandler?.call(_handleBack);
    });
  }

  void _onSlideTick() {
    if (_visible && _slideCtrl.isAnimating) setState(() {});
  }

  @override
  void dispose() {
    _slideCtrl.removeListener(_onSlideTick);
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

  Future<void> _openRoomDetail(String roomId) async {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty || !mounted) return;
    HapticFeedback.selectionClick();
    await AdminRoomDetailNavigation.showHotelTotalsRoomDetailSheet(
      context: context,
      roomId: id,
      initialRoomSnapshot: _roomSnapshotForDetail(id),
    );
  }

  Future<void> _closePanel() async {
    if (!_visible) return;
    await _slideCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _visible = false;
      _list = null;
    });
    _syncOpenFlag();
    final refresh = widget.onRefresh;
    if (refresh != null) {
      await refresh();
    }
  }

  bool _handleBack() {
    if (!_visible) return false;
    _closePanel();
    return true;
  }

  Map<String, dynamic>? _roomSnapshotForDetail(String roomId) {
    final live = widget.resolveLiveRooms?.call() ?? const [];
    for (final room in live) {
      if (AdminDashboardModels.roomIdOf(room) == roomId) {
        return room;
      }
    }
    final rooms = _list?.rooms;
    if (rooms == null) return null;
    for (final room in rooms) {
      if (AdminDashboardModels.roomIdOf(room) == roomId) {
        return room;
      }
    }
    return null;
  }

  Widget _buildPanel(
    BuildContext context, {
    required double panelHeight,
    required Color bg,
    required String title,
  }) {
    final hidden = _slideCtrl.isAnimating
        ? (1 - _slideOffset.value) * panelHeight
        : 0.0;
    return Transform.translate(
      offset: Offset(0, hidden),
      child: Material(
        color: bg,
        elevation: 12,
        shadowColor: Colors.black45,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: SizedBox(
          height: panelHeight,
          width: double.infinity,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HotelTotalsPanelHeader(
                  title: title,
                  backgroundColor: bg,
                  onBack: _closePanel,
                ),
                Expanded(child: _buildListBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListBody(BuildContext context) {
    final list = _list;
    if (list == null) {
      return const Center(
        child: Text('No rooms loaded. Close and try again.'),
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
    final bg = Theme.of(context).colorScheme.surface;
    final list = _list;
    final title = list?.title ?? 'Rooms';

    return HotelTotalsRoomPanelScope(
      isOpen: _visible,
      openRoomList: _openRoomList,
      openRoomDetail: _openRoomDetail,
      closePanel: _closePanel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
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
              child: _buildPanel(
                context,
                panelHeight: panelHeight,
                bg: bg,
                title: title,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HotelTotalsPanelHeader extends StatelessWidget {
  const _HotelTotalsPanelHeader({
    required this.title,
    required this.backgroundColor,
    required this.onBack,
  });

  final String title;
  final Color backgroundColor;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          SizedBox(
            height: kToolbarHeight,
            child: Row(
              children: [
                BackButton(onPressed: onBack),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open room list. Pull to refresh and retry.'),
      ),
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
    AdminRoomDetailNavigation.showRoomDetailSheet(
      roomId: id,
      context: context,
      initialRoomSnapshot: room,
    );
    return;
  }

  if (!panel.isOpen) {
    panel.openRoomList(
      title: 'Occupied rooms',
      rooms: [room],
      showGuest: true,
    );
  }
  panel.openRoomDetail(id);
}
