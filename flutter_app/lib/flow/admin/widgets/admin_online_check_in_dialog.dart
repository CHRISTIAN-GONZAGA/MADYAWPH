import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../widgets/admin_time_slot_field.dart';
import '../admin_dashboard_models.dart';
import 'walk_in_complimentary_picker.dart';

String formatAdminCheckInDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Check-in dialog for booked rooms. Public online guests must select amenity
/// inquiries before check-in (complimentary options saved on the booking).
Future<bool> showAdminOnlineAwareCheckInDialog(
  BuildContext context, {
  required Map<String, dynamic> room,
}) async {
  final roomId = AdminDashboardModels.roomIdOf(room);
  if (roomId.isEmpty) {
    showAppMessage(context, 'Room ID missing. Refresh and try again.');
    return false;
  }

  final requiresAmenities = AdminDashboardModels.isPublicOnlineBooking(room);
  final inDate = AdminDashboardModels.stayStartDate(room) ?? DateTime.now();
  final outDate =
      AdminDashboardModels.stayEndDate(room) ?? inDate.add(const Duration(days: 1));
  var checkInDate = inDate;
  var checkOutDate = outDate;
  var checkInTime = AdminDashboardModels.bookingTimeOfDay(room, 'check_in_time') ??
      const TimeOfDay(hour: 15, minute: 0);
  var checkOutTime = AdminDashboardModels.bookingTimeOfDay(room, 'check_out_time') ??
      const TimeOfDay(hour: 11, minute: 0);

  var amenityMenuItems = const <Map<String, dynamic>>[];
  if (requiresAmenities) {
    try {
      final menuRes =
          await portalDio().get<Map<String, dynamic>>('/admin/amenity-menu');
      amenityMenuItems = ((menuRes.data?['data'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((item) => item['is_active'] != false)
          .toList();
    } catch (_) {
      amenityMenuItems = const [];
    }
    if (!context.mounted) return false;
  }

  final complimentaryQty = <String, int>{};

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Check in — Room ${room['room_number']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AdminDashboardModels.guestName(room),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              if (requiresAmenities) ...[
                const SizedBox(height: 8),
                Text(
                  'Online booking — record amenity inquiries before check-in.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Check-in date'),
                subtitle: Text(formatAdminCheckInDate(checkInDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: checkInDate,
                  );
                  if (picked != null) setLocal(() => checkInDate = picked);
                },
              ),
              AdminTimeSlotField(
                label: 'Check-in time',
                value: checkInTime,
                onChanged: (t) {
                  if (t != null) setLocal(() => checkInTime = t);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Check-out date'),
                subtitle: Text(formatAdminCheckInDate(checkOutDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: checkInDate,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: checkOutDate,
                  );
                  if (picked != null) setLocal(() => checkOutDate = picked);
                },
              ),
              AdminTimeSlotField(
                label: 'Check-out time',
                value: checkOutTime,
                onChanged: (t) {
                  if (t != null) setLocal(() => checkOutTime = t);
                },
              ),
              if (requiresAmenities) ...[
                const SizedBox(height: 12),
                Text(
                  'Guest amenity inquiries',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                if (amenityMenuItems.isEmpty)
                  Text(
                    'No amenity menu items yet. Add products in Amenities, then check in.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  )
                else
                  WalkInComplimentaryPicker(
                    menuItems: amenityMenuItems,
                    quantitiesById: complimentaryQty,
                    onChanged: () => setLocal(() {}),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (requiresAmenities && amenityMenuItems.isNotEmpty) {
                final selected = complimentaryQty.values.any((q) => q > 0);
                if (!selected) {
                  showAppMessage(
                    ctx,
                    'Select at least one amenity the guest is inquiring about.',
                    isError: true,
                  );
                  return;
                }
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Check in guest'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;

  final inTime = checkInTime ?? const TimeOfDay(hour: 15, minute: 0);
  final outTime = checkOutTime ?? const TimeOfDay(hour: 11, minute: 0);
  final checkInAt = DateTime(
    checkInDate.year,
    checkInDate.month,
    checkInDate.day,
    inTime.hour,
    inTime.minute,
  );
  final checkOutAt = DateTime(
    checkOutDate.year,
    checkOutDate.month,
    checkOutDate.day,
    outTime.hour,
    outTime.minute,
  );

  final data = <String, dynamic>{
    'status': 'checked_in',
    'check_in_at': checkInAt.toIso8601String(),
    'check_out_at': checkOutAt.toIso8601String(),
  };

  if (requiresAmenities && complimentaryQty.isNotEmpty) {
    data['free_breakfast_options'] = amenityMenuItems
        .map((item) {
          final id = (item['id'] ?? item['_id'] ?? '').toString();
          final qty = complimentaryQty[id] ?? 0;
          if (qty <= 0) return null;
          return {
            'menu_item_id': id,
            'name': (item['name'] ?? '').toString(),
            'quantity': qty,
            'amenity_type':
                (item['amenity_type'] ?? item['type'] ?? '').toString(),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  try {
    await portalDio().patch('/admin/rooms/$roomId/status', data: data);
    if (!context.mounted) return false;
    showAppMessage(context, 'Guest checked in.');
    return true;
  } on DioException catch (e) {
    if (!context.mounted) return false;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return false;
  }
}
