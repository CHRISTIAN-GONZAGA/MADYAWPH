import 'package:flutter/material.dart';

import '../../../widgets/app_scaffold.dart';
import 'admin_sales_panel.dart';

/// Dedicated amenities sales / profit report.
class AmenitiesReportScreen extends StatelessWidget {
  const AmenitiesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Amenities reports')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: AdminSalesPanel(),
      ),
    );
  }
}
