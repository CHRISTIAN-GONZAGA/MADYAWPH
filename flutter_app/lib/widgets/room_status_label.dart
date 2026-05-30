import 'package:flutter/material.dart';

import '../flow/admin/admin_dashboard_models.dart';

/// Human-readable room status labels for admin UI.
String roomStatusLabel(String status) =>
    AdminDashboardModels.roomStatusLabel(status);

Color roomStatusColor(String status) {
  switch (status.toLowerCase().trim()) {
    case 'checked_in':
      return Colors.green.shade700;
    case 'booked':
      return Colors.blue.shade700;
    case 'reserved':
      return Colors.orange.shade800;
    case 'maintenance':
      return Colors.grey.shade700;
    case 'available':
      return Colors.teal.shade700;
    default:
      return Colors.blueGrey;
  }
}
