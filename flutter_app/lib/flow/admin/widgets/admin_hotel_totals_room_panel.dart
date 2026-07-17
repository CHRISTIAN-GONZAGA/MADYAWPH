import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import 'admin_room_detail_navigation.dart';
import 'admin_summary_room_tile.dart';
import 'admin_floor_dropdown_list.dart';
import 'admin_room_navigation.dart';
import '../../../navigation_keys.dart';

class _RoomListPayload {
  const _RoomListPayload({
    required this.title,
    required this.rooms,
    required this.showGuest,
    this.subtitle,
    this.useFloorPicker = false,
    this.preferCheckIn = false,
    this.floorBadgeNoun,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool showGuest;
  final String? subtitle;
  final bool useFloorPicker;
  final bool preferCheckIn;
  final String? floorBadgeNoun;
}

/// Slide-up room list for Summary → Hotel totals; detail stays in-panel until back.
class HotelTotalsRoomPanelScope extends InheritedWidget {
  const HotelTotalsRoomPanelScope({
    super.key,
    required this.openRoomList,
    required this.openRoomDetail,
    required this.openRoomDetailFromList,
    required this.openRoomDetailColdStart,
    required this.closePanel,
    required this.isOpen,
    required super.child,
  });

  final void Function({
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
    bool preferCheckIn,
    String? floorBadgeNoun,
  }) openRoomList;

  final void Function(String roomId) openRoomDetail;

  final void Function({
    required String roomId,
    Map<String, dynamic>? roomSnapshot,
  }) openRoomDetailFromList;

  final void Function({
    required Map<String, dynamic> room,
    String listTitle,
    bool showGuest,
  }) openRoomDetailColdStart;

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
    this.canCreateBookings = true,
  });

  final Widget child;
  final Future<void> Function()? onRefresh;
  final ValueChanged<bool Function()>? onBindBackHandler;
  final List<Map<String, dynamic>> Function()? resolveLiveRooms;
  final bool canCreateBookings;

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
  String? _detailRoomId;
  Map<String, dynamic>? _detailSnapshot;

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
    if (_visible && _slideCtrl.isAnimating && _detailRoomId == null) {
      setState(() {});
    }
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
    bool preferCheckIn = false,
    String? floorBadgeNoun,
  }) {
    HapticFeedback.selectionClick();
    final useFloorPicker = AdminDashboardModels.needsFloorDrilldown(rooms);
    setState(() {
      _visible = true;
      _detailRoomId = null;
      _detailSnapshot = null;
      _list = _RoomListPayload(
        title: title,
        rooms: rooms,
        showGuest: showGuest,
        subtitle: subtitle,
        useFloorPicker: useFloorPicker,
        preferCheckIn: preferCheckIn,
        floorBadgeNoun: floorBadgeNoun,
      );
    });
    _syncOpenFlag();
    _slideCtrl.forward(from: 0);
  }

  void openRoomDetailFromList({
    required String roomId,
    Map<String, dynamic>? roomSnapshot,
  }) {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _detailRoomId = id;
      _detailSnapshot = roomSnapshot ?? _roomSnapshotForDetail(id);
    });
  }

  void openRoomDetailColdStart({
    required Map<String, dynamic> room,
    String listTitle = 'Room details',
    bool showGuest = true,
  }) {
    final id = AdminDashboardModels.roomIdOf(room);
    if (id.isEmpty || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _visible = true;
      _list = _RoomListPayload(
        title: listTitle,
        rooms: [room],
        showGuest: showGuest,
      );
      _detailRoomId = id;
      _detailSnapshot = room;
    });
    _syncOpenFlag();
    _slideCtrl.forward(from: 0);
  }

  void _openRoomDetail(String roomId) {
    final room = _roomSnapshotForDetail(roomId);
    if (room != null) {
      _onRoomTileTap(room);
      return;
    }
    openRoomDetailFromList(roomId: roomId);
  }

  Future<void> _onRoomTileTap(Map<String, dynamic> room) async {
    final navContext = adminDashboardNavigatorKey.currentContext ?? context;
    if (!navContext.mounted) return;
    await AdminRoomNavigation.handleRoomTap(
      navContext,
      room: room,
      preferCheckIn: _list?.preferCheckIn ?? false,
      canCreateBookings: widget.canCreateBookings,
      onSuccess: () async {
        await widget.onRefresh?.call();
      },
      onManageRoom: (ctx, selected) async {
        openRoomDetailFromList(
          roomId: AdminDashboardModels.roomIdOf(selected),
          roomSnapshot: selected,
        );
      },
    );
  }

  void _backFromDetail() {
    if (_detailRoomId == null) return;
    setState(() {
      _detailRoomId = null;
      _detailSnapshot = null;
    });
  }

  Future<void> _closePanel() async {
    if (!_visible) return;
    setState(() {
      _detailRoomId = null;
      _detailSnapshot = null;
    });
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
    if (_detailRoomId != null) {
      _backFromDetail();
      return true;
    }
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

  Widget _buildPanelBody(BuildContext context) {
    final detailId = _detailRoomId;
    if (detailId != null) {
      return AdminRoomDetailScreen(
        key: ValueKey('panel-detail-$detailId'),
        roomId: detailId,
        embedded: true,
        initialRoomSnapshot: _detailSnapshot,
        onClose: _backFromDetail,
      );
    }

    final list = _list;
    final bg = Theme.of(context).colorScheme.surface;
    if (list == null) {
      return ColoredBox(
        color: bg,
        child: const Center(
          child: Text('No rooms loaded. Close and try again.'),
        ),
      );
    }

    if (list.useFloorPicker) {
      return ColoredBox(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HotelTotalsPanelHeader(
              title: list.title,
              backgroundColor: bg,
              onBack: _closePanel,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                list.subtitle ??
                    '${list.rooms.length} room(s) — tap a floor to expand',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: AdminFloorDropdownList(
                rooms: list.rooms,
                badgeNoun: list.floorBadgeNoun,
                onRoomTap: (room) => _onRoomTileTap(room),
              ),
            ),
          ],
        ),
      );
    }

    final displayRooms = AdminDashboardModels.sortRoomsByNumber(list.rooms);

    return _HotelTotalsListPage(
      title: list.title,
      rooms: displayRooms,
      showGuest: list.showGuest,
      subtitle: list.subtitle,
      onBack: _handleBack,
      onClosePanel: _closePanel,
      onRoomTap: (room) => _onRoomTileTap(room),
    );
  }

  Widget _buildPanel(
    BuildContext context, {
    required double panelHeight,
    required Color bg,
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
            child: _buildPanelBody(context),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelHeight = MediaQuery.sizeOf(context).height * 0.92;
    final bg = Theme.of(context).colorScheme.surface;

    return HotelTotalsRoomPanelScope(
      isOpen: _visible,
      openRoomList: _openRoomList,
      openRoomDetail: _openRoomDetail,
      openRoomDetailFromList: openRoomDetailFromList,
      openRoomDetailColdStart: openRoomDetailColdStart,
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
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HotelTotalsListPage extends StatelessWidget {
  const _HotelTotalsListPage({
    required this.title,
    required this.rooms,
    required this.showGuest,
    required this.onClosePanel,
    required this.onRoomTap,
    required this.onBack,
    this.subtitle,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool showGuest;
  final String? subtitle;
  final VoidCallback onClosePanel;
  final VoidCallback onBack;
  final void Function(Map<String, dynamic> room) onRoomTap;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;

    return ColoredBox(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HotelTotalsPanelHeader(
            title: title,
            backgroundColor: bg,
            onBack: onBack,
          ),
          Expanded(
            child: _HotelTotalsRoomGrid(
              rooms: rooms,
              showGuest: showGuest,
              subtitle: subtitle,
              onRoomTap: onRoomTap,
            ),
          ),
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
  final void Function(Map<String, dynamic> room) onRoomTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columns = adminSummaryRoomGridColumns(context);
    final sorted = AdminDashboardModels.sortRoomsByNumber(rooms);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            subtitle ?? '${sorted.length} room(s) · tap to book or manage',
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
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final room = sorted[i];
              return AdminSummaryRoomGridTile(
                room: room,
                showGuest: showGuest,
                onTap: () => onRoomTap(room),
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
  bool preferCheckIn = false,
  String? floorBadgeNoun,
}) {
  if (rooms.isEmpty) {
    showAppMessage(context, 'No rooms in "$title".');
    return;
  }

  final panel = HotelTotalsRoomPanelScope.maybeOf(context);
  if (panel == null) {
    showAppMessage(context, 'Could not open room list. Pull to refresh and retry.');
    return;
  }

  panel.openRoomList(
    title: title,
    rooms: rooms,
    showGuest: showGuest,
    subtitle: subtitle,
    preferCheckIn: preferCheckIn,
    floorBadgeNoun: floorBadgeNoun,
  );
}

void openHotelTotalsRoomDetail(
  BuildContext context, {
  required Map<String, dynamic> room,
}) {
  final id = AdminDashboardModels.roomIdOf(room);
  if (id.isEmpty) {
    showAppMessage(context, 'Room ID missing. Pull to refresh the dashboard and try again.',);
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
    panel.openRoomDetailColdStart(
      room: room,
      listTitle: 'Room details',
      showGuest: true,
    );
    return;
  }

  panel.openRoomDetailFromList(
    roomId: id,
    roomSnapshot: room,
  );
}
