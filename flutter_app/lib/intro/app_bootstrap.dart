import 'package:flutter/material.dart';

import '../auth_storage.dart';
import '../dio_client.dart';
import '../flow/root_flow.dart';
import '../widgets/theme_fab.dart';
import 'madyaw_intro_screen.dart';

/// Shows the Madyaw motion intro on first launch, then the main hotel flow.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, required this.skipIntro});

  /// When true, intro was already shown — go straight to [FlowRoot].
  final bool skipIntro;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late bool _showIntro;

  @override
  void initState() {
    super.initState();
    _showIntro = !widget.skipIntro;
    warmPublicApi();
  }

  void _onIntroDone() {
    if (!mounted) return;
    AuthStorage.setIntroSeen();
    setState(() => _showIntro = false);
  }

  @override
  Widget build(BuildContext context) {
    // FlowRoot loads underneath while intro plays; intro fades out before removal.
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        const FlowRoot(),
        if (_showIntro) MadyawIntroScreen(onFinished: _onIntroDone),
        if (!_showIntro) const ThemeFab(),
      ],
    );
  }
}
