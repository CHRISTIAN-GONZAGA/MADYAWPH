import 'package:flutter/material.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class AppActionTile extends StatelessWidget {
  const AppActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
