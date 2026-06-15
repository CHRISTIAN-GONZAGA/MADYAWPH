import 'dart:async';

import 'package:flutter/material.dart';

import '../admin_room_detail_screen.dart';
import 'manual_booking_dialog.dart';

/// Opens walk-in / room-detail UI as a full-screen layer over the admin dashboard.
/// Avoids Navigator.push from inside [IndexedStack] tabs (blank gray screen on device).
class AdminRoomOverlayHost {
  AdminRoomOverlayHost._();

  static final AdminRoomOverlayHost instance = AdminRoomOverlayHost._();

  void Function(AdminWalkInOverlayRequest request)? _showWalkIn;
  void Function(String roomId)? _showDetail;
  VoidCallback? _hide;

  bool get isActive => _showWalkIn != null;

  void bind({
    required void Function(AdminWalkInOverlayRequest request) showWalkIn,
    required void Function(String roomId) showDetail,
    required VoidCallback hide,
  }) {
    _showWalkIn = showWalkIn;
    _showDetail = showDetail;
    _hide = hide;
  }

  void unbind() {
    _showWalkIn = null;
    _showDetail = null;
    _hide = null;
  }

  Future<bool> openWalkIn({
    required Map<String, dynamic> room,
    required Future<void> Function() onSuccess,
  }) async {
    final show = _showWalkIn;
    if (show == null) return false;
    final completer = Completer<bool>();
    show(AdminWalkInOverlayRequest(
      room: room,
      onSuccess: onSuccess,
      onComplete: completer.complete,
    ));
    return completer.future;
  }

  Future<void> openDetail(String roomId) async {
    final show = _showDetail;
    if (show == null) return;
    show(roomId);
  }

  void close() => _hide?.call();
}

class AdminWalkInOverlayRequest {
  const AdminWalkInOverlayRequest({
    required this.room,
    required this.onSuccess,
    required this.onComplete,
  });

  final Map<String, dynamic> room;
  final Future<void> Function() onSuccess;
  final void Function(bool success) onComplete;
}

/// Full-screen overlay shown by [AdminDashboardShell].
class AdminRoomOverlayLayer extends StatelessWidget {
  const AdminRoomOverlayLayer({
    super.key,
    this.walkIn,
    this.detailRoomId,
    required this.onClose,
  });

  final AdminWalkInOverlayRequest? walkIn;
  final String? detailRoomId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final child = walkIn != null
        ? AdminWalkInBookingScreen(
            room: walkIn!.room,
            onSuccess: walkIn!.onSuccess,
            onClose: (success) {
              walkIn!.onComplete(success);
              onClose();
            },
          )
        : detailRoomId != null
            ? AdminRoomDetailScreen(
                roomId: detailRoomId!,
                onClose: onClose,
              )
            : null;

    if (child == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
