import 'package:flutter/material.dart';

import '../ui/app_visual.dart';

/// Gradient chrome + transparent scaffold. Keeps AppBar behavior; body floats on brand gradient.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.resizeToAvoidBottomInset = true,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.extendBody = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool resizeToAvoidBottomInset;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisual.of(context);

    return Scaffold(
      extendBody: extendBody,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      drawer: drawer,
      endDrawer: endDrawer,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: visual.scaffoldGradient(scheme)),
            ),
          ),
          body,
        ],
      ),
    );
  }
}
