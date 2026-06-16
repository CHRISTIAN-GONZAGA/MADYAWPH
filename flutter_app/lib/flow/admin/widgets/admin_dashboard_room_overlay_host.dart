import 'package:flutter/material.dart';

import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';
import '../admin_room_summary_detail_screen.dart';
import 'admin_dashboard_routes.dart';
import 'admin_room_detail_navigation.dart';

class _RoomListOverlay {
  const _RoomListOverlay({
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

/// Holds room list + detail overlays above the admin dashboard (survives data refresh).
class AdminDashboardRoomOverlayHost extends StatefulWidget {
  const AdminDashboardRoomOverlayHost({
    super.key,
    required this.child,
    this.onBindBackHandler,
    this.onRefresh,
  });

  final Widget child;
  final ValueChanged<bool Function()>? onBindBackHandler;
  final Future<void> Function()? onRefresh;

  @override
  State<AdminDashboardRoomOverlayHost> createState() =>
      _AdminDashboardRoomOverlayHostState();
}

class _AdminDashboardRoomOverlayHostState
    extends State<AdminDashboardRoomOverlayHost> {
  _RoomListOverlay? _roomList;
  String? _detailRoomId;

  bool get _isOpen => _roomList != null || _detailRoomId != null;

  @override
  void initState() {
    super.initState();
    AdminRoomDetailNavigation.bindShellOpenDetail(_openRoomDetail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBindBackHandler?.call(_handleBack);
    });
  }

  @override
  void dispose() {
    AdminRoomDetailNavigation.bindShellOpenDetail(null);
    AdminRoomDetailNavigation.notifyShellOverlayOpen(false);
    widget.onBindBackHandler?.call(() => false);
    super.dispose();
  }

  void _syncOverlayFlag() {
    AdminRoomDetailNavigation.notifyShellOverlayOpen(_isOpen);
    widget.onBindBackHandler?.call(_handleBack);
  }

  void _openRoomList({
    required String title,
    required List<Map<String, dynamic>> rooms,
    required bool showGuest,
    String? subtitle,
  }) {
    setState(() {
      _roomList = _RoomListOverlay(
        title: title,
        rooms: rooms,
        showGuest: showGuest,
        subtitle: subtitle,
      );
      _detailRoomId = null;
    });
    _syncOverlayFlag();
  }

  void _openRoomDetail(String roomId) {
    final id = AdminDashboardModels.normalizeRoomIdString(roomId);
    if (id.isEmpty) return;
    setState(() => _detailRoomId = id);
    _syncOverlayFlag();
  }

  Future<void> _closeRoomDetail() async {
    if (_detailRoomId == null) return;
    setState(() => _detailRoomId = null);
    _syncOverlayFlag();
    final refresh = widget.onRefresh;
    if (refresh != null) {
      await refresh();
    }
  }

  void _closeRoomList() {
    if (_roomList == null) return;
    setState(() {
      _roomList = null;
      _detailRoomId = null;
    });
    _syncOverlayFlag();
  }

  void _closeTopOverlay() {
    if (_detailRoomId != null) {
      _closeRoomDetail();
      return;
    }
    _closeRoomList();
  }

  bool _handleBack() {
    if (_detailRoomId != null) {
      _closeRoomDetail();
      return true;
    }
    if (_roomList != null) {
      _closeRoomList();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AdminDashboardRoutes(
      openRoomList: _openRoomList,
      openRoomDetail: _openRoomDetail,
      closeRoomList: _closeRoomList,
      closeTopOverlay: _closeTopOverlay,
      isOverlayOpen: _isOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_roomList != null)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  child: AdminRoomSummaryDetailScreen(
                    title: _roomList!.title,
                    rooms: _roomList!.rooms,
                    showGuest: _roomList!.showGuest,
                    subtitle: _roomList!.subtitle,
                  ),
                ),
              ),
            ),
          if (_detailRoomId != null)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFFF5F3EF),
                child: SafeArea(
                  child: AdminRoomDetailScreen(
                    key: ValueKey('room-detail-$_detailRoomId'),
                    roomId: _detailRoomId!,
                    onClose: () => _closeRoomDetail(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
