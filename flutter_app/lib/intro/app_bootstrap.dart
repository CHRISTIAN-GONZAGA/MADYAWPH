import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../flow/root_flow.dart';
import '../widgets/theme_fab.dart';
import 'madyaw_intro_screen.dart';

/// Plays the Madyaw intro on every cold start, then mounts the main flow.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    warmPublicApi();
  }

  void _onIntroDone() {
    if (!mounted) return;
    setState(() => _showIntro = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro) {
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
