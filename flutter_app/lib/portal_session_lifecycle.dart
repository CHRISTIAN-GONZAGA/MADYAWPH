import 'package:flutter/material.dart';

import '../auth_storage.dart';

/// Records when hotel staff leave the app and clears portal auth after 60 minutes.
class PortalSessionLifecycle extends StatefulWidget {
  const PortalSessionLifecycle({super.key, required this.child});

  final Widget child;

  @override
  State<PortalSessionLifecycle> createState() => _PortalSessionLifecycleState();
}

class _PortalSessionLifecycleState extends State<PortalSessionLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AuthStorage.enforcePortalSessionTimeout();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        AuthStorage.markPortalPaused();
      case AppLifecycleState.resumed:
        AuthStorage.enforcePortalSessionTimeout();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
