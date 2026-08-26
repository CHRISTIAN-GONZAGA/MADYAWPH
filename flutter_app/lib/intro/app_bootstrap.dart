import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../services/guest_room_deep_link.dart';
import '../flow/root_flow.dart';
import '../widgets/theme_fab.dart';
import 'madyaw_intro_screen.dart';

/// Plays the Madyaw intro on cold start, then mounts the main flow.
/// Front desk with a saved session skips the intro and goes to the dashboard.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool? _showIntro;

  @override
  void initState() {
    super.initState();
    warmPublicApi();
    _decideIntro();
  }

  Future<void> _decideIntro() async {
    final skip = await AuthStorage.isFrontDeskSession() &&
        ((await AuthStorage.portalToken()) ?? '').isNotEmpty;
    if (!mounted) return;
    setState(() => _showIntro = !skip);
    if (skip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GuestRoomDeepLink.consumePendingIfAny();
      });
    }
  }

  void _onIntroDone() {
    if (!mounted) return;
    setState(() => _showIntro = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuestRoomDeepLink.consumePendingIfAny();
      // Navigator may not be ready on the first frame after intro.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        GuestRoomDeepLink.consumePendingIfAny();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro == null) {
      return const ColoredBox(color: Color(0xFF1A2B4A));
    }
    if (_showIntro!) {
      return MadyawIntroScreen(onFinished: _onIntroDone);
    }

    return const Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        FlowRoot(),
        ThemeFab(),
      ],
    );
  }
}
