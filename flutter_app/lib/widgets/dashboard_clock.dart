import 'dart:async';

import 'package:flutter/material.dart';

/// Compact live clock for dashboard app bars (updates every 30s).
class DashboardClockAction extends StatefulWidget {
  const DashboardClockAction({super.key});

  @override
  State<DashboardClockAction> createState() => _DashboardClockActionState();
}

class _DashboardClockActionState extends State<DashboardClockAction> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour;
    final m = _now.minute.toString().padLeft(2, '0');
    final text =
        '${h.toString().padLeft(2, '0')}:$m'; // 24h — compact, locale-neutral

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}
