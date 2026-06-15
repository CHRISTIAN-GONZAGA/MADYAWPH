import 'package:flutter/material.dart';

/// Solid-background scaffold for admin routes pushed over the dashboard.
class AdminOpaqueScaffold extends StatelessWidget {
  const AdminOpaqueScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Scaffold(
        backgroundColor: scheme.surface,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
