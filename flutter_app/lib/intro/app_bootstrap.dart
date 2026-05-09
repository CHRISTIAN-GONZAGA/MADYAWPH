import 'package:flutter/material.dart';

import '../flow/root_flow.dart';
import '../widgets/theme_fab.dart';
import 'madyaw_intro_screen.dart';

/// Shows the Madyaw motion intro once, then the main hotel flow.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  var _showIntro = true;

  void _onIntroDone() {
    if (!mounted) return;
    setState(() => _showIntro = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (_showIntro)
          MadyawIntroScreen(onFinished: _onIntroDone)
        else
          const FlowRoot(),
        if (!_showIntro) const ThemeFab(),
      ],
    );
  }
}
