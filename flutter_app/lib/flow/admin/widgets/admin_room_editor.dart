import 'dart:io';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_overlay.dart';
import '../../../widgets/chat_attachment.dart';
import '../admin_dashboard_models.dart';
import 'admin_room_edit_screen.dart';
import 'admin_room_form_constants.dart';
import 'hourly_billing.dart';
import 'hourly_price_picker.dart';

const _roomTypeOptions = adminRoomTypeOptions;
const _roomStatusOptions = adminRoomStatusOptions;

String _normalizeRoomChoice(
  dynamic raw,
  String fallback,
  List<String> allowed,
) =>
    normalizeAdminRoomChoice(raw, fallback, allowed);

/// Flattens API/Mongo room maps so edit dialogs always receive usable fields.
Map<String, dynamic> normalizeAdminRoomForEdit(Map<String, dynamic> raw) {
  final room = Map<String, dynamic>.from(raw);
  final id = AdminDashboardModels.roomIdOf(room);
  if (id.isNotEmpty) {
    room['id'] = id;
  }
  room['status'] = _normalizeRoomChoice(
    room['status'],
    'available',
    _roomStatusOptions,
  );
  room['room_type'] = _normalizeRoomChoice(
    room['room_type'],
    'Single',
    _roomTypeOptions,
  );
  room['billing_mode'] =
      (room['billing_mode'] ?? 'nightly').toString().toLowerCase();
  room['price_per_night'] = parseAdminDouble(room['price_per_night']);
  room['price_per_block'] = parseAdminDouble(
    room['price_per_block'],
    parseAdminDouble(room['price_per_night']),
  );
  room['block_hours'] = parseAdminInt(room['block_hours'], 3);
  final floor = parseAdminInt(room['floor'], 0);
  if (floor > 0) {
    room['floor'] = floor;
  }
  return room;
}

Future<void> putPortalMultipart(
  String path,
  Map<String, dynamic> fields,
  XFile? image,
) async {
  if (image != null) {
    final form = await ChatAttachment.formWithImage(
      fields: fields,
      file: image,
    );
    await portalDio().put(
      path,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        headers: {Headers.acceptHeader: 'application/json'},
      ),
    );
  } else {
    final body = <String, dynamic>{};
    for (final entry in fields.entries) {
      final v = entry.value;
      if (v == null) continue;
      body[entry.key] = v is num || v is bool ? v.toString() : v;
    }
    await portalDio().put(path, data: body);
  }
}

Future<void> postPortalMultipart(
  String path,
  Map<String, dynamic> fields,
  XFile? image,
) async {
  if (image != null) {
    final form = await ChatAttachment.formWithImage(
      fields: fields,
      file: image,
    );
    await portalDio().post(
      path,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        headers: {Headers.acceptHeader: 'application/json'},
      ),
    );
  } else {
    final body = <String, dynamic>{};
    for (final entry in fields.entries) {
      final v = entry.value;
      if (v == null) continue;
      body[entry.key] = v is num || v is bool ? v.toString() : v;
    }
    await portalDio().post(path, data: body);
  }
}

class AdminRoomGalleryPicker extends StatelessWidget {
  const AdminRoomGalleryPicker({
    super.key,
    this.pickedImage,
    this.existingImageUrl,
    required this.onPick,
    required this.onClearPicked,
    this.onClearExisting,
  });

  final XFile? pickedImage;
  final String? existingImageUrl;
  final Future<void> Function() onPick;
  final VoidCallback onClearPicked;
  final VoidCallback? onClearExisting;

  @override
  Widget build(BuildContext context) {
    final existing = (existingImageUrl ?? '').trim();
    final hasExisting = existing.isNotEmpty && pickedImage == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pickedImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(pickedImage!.path),
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else if (hasExisting)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: NetworkMediaImage(
              url: existing,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              error: Container(
                height: 140,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          )
        else
          Container(
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onPick(),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
              ),
            ),
            if (pickedImage != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove new photo',
                onPressed: onClearPicked,
                icon: const Icon(Icons.close),
              ),
            ] else if (hasExisting && onClearExisting != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: onClearExisting,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Edit room setup: photo, rates, display name, status, etc.
Future<bool> showAdminEditRoomDialog(
  BuildContext context, {
  required Map<String, dynamic> room,
  Map<String, dynamic>? categoryDefaults,
  String? categoryLabel,
}) async {
  room = normalizeAdminRoomForEdit(room);
  final roomId = AdminDashboardModels.roomIdOf(room);
  if (roomId.isEmpty) {
    if (context.mounted) {
      showAppMessage(context, 'Cannot edit this room — id is missing. Refresh and try again.',);
    }
    return false;
  }

  if (!context.mounted) return false;

  final saved = await pushAdminFullScreen<bool>(
    context,
    builder: (_) => AdminRoomEditScreen(
      room: room,
      categoryDefaults: categoryDefaults,
      categoryLabel: categoryLabel,
    ),
  );
  return saved == true;
}

/// Create a new room under [category].
Future<bool> showAdminCreateRoomDialog(
  BuildContext context, {
  required Map<String, dynamic> category,
}) async {
  final categoryId =
      (category['id'] ?? category['_id'] ?? '').toString().trim();
  if (categoryId.isEmpty) return false;

  final nameCtrl = TextEditingController();
  final roomNoCtrl = TextEditingController();
  final nightlyCtrl = TextEditingController(
    text: '${parseAdminDouble(category['default_price'])}',
  );
  final blockPriceCtrl = TextEditingController(
    text:
        '${parseAdminDouble(category['price_per_block'], parseAdminDouble(category['default_price'], 1000))}',
  );
  var roomBillingMode =
      (category['billing_mode'] ?? 'nightly').toString().toLowerCase();
  var roomPricePerNight = parseAdminDouble(category['default_price']);
  var roomPricePerBlock = parseAdminDouble(
    category['price_per_block'],
    roomPricePerNight,
  );
  var roomBlockHours = parseAdminInt(category['block_hours'], 3);
  var roomType = 'Single';
  var status = 'available';
  final floorCount = parseAdminInt(category['floor_count'], 1);
  var selectedFloor = 1;
  XFile? pickedImage;

  if (!context.mounted) return false;

  final payload = await showAppOverlayDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New room · ${(category['name'] ?? 'category')}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  AdminRoomFloorField(
                    floorCount: floorCount,
                    selectedFloor: selectedFloor,
                    onChanged: (v) => setLocal(() => selectedFloor = v),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: roomNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Room number',
                      prefixIcon: Icon(Icons.door_front_door_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(roomType),
                    initialValue: roomType,
                    decoration: const InputDecoration(labelText: 'Room type'),
                    items: const [
                      DropdownMenuItem(value: 'Single', child: Text('Single')),
                      DropdownMenuItem(value: 'Double', child: Text('Double')),
                      DropdownMenuItem(value: 'Suite', child: Text('Suite')),
                      DropdownMenuItem(value: 'Deluxe', child: Text('Deluxe')),
                    ],
                    onChanged: (v) => setLocal(() => roomType = v ?? roomType),
                  ),
                  const SizedBox(height: 14),
                  RoomPricingFields(
                    billingMode: roomBillingMode,
                    pricePerNight: roomPricePerNight,
                    pricePerBlock: roomPricePerBlock,
                    blockHours: roomBlockHours,
                    showExtraHourRate: false,
                    nightlyController: nightlyCtrl,
                    blockPriceController: blockPriceCtrl,
                    onChanged: ({
                      required String billingMode,
                      required double pricePerNight,
                      required double pricePerBlock,
                      required int blockHours,
                      required double pricePerExtraHour,
                    }) {
                      setLocal(() {
                        roomBillingMode = billingMode;
                        roomPricePerNight = pricePerNight;
                        roomPricePerBlock = pricePerBlock;
                        roomBlockHours = blockHours;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(status),
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                          value: 'available', child: Text('Available')),
                      DropdownMenuItem(value: 'booked', child: Text('Booked')),
                      DropdownMenuItem(
                          value: 'cleaning', child: Text('Cleaning')),
                      DropdownMenuItem(
                          value: 'maintenance', child: Text('Maintenance')),
                    ],
                    onChanged: (v) => setLocal(() => status = v ?? status),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Room photo',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  AdminRoomGalleryPicker(
                    pickedImage: pickedImage,
                    onPick: () async {
                      final file =
                          await ChatAttachment.pickRoomImageFromGallery(context);
                      if (file != null) setLocal(() => pickedImage = file);
                    },
                    onClearPicked: () => setLocal(() => pickedImage = null),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, {
                          'category_id': categoryId,
                          'display_name': nameCtrl.text.trim(),
                          'room_number': roomNoCtrl.text.trim(),
                          'floor': selectedFloor,
                          'room_type': roomType,
                          'billing_mode': roomBillingMode,
                          'price_per_night': roomPricePerNight,
                          'price_per_block': roomPricePerBlock,
                          'block_hours': roomBlockHours,
                          'status': status,
                          '__image': pickedImage,
                        }),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  nameCtrl.dispose();
  roomNoCtrl.dispose();
  nightlyCtrl.dispose();
  blockPriceCtrl.dispose();
  if (payload == null) return false;
  if ((payload['display_name'] ?? '').toString().isEmpty ||
      (payload['room_number'] ?? '').toString().isEmpty) {
    return false;
  }

  final image = payload.remove('__image') as XFile?;
  if (image == null) {
    if (context.mounted) {
      showAppMessage(context, 'Room photo is required. Pick an image from the gallery.');
    }
    return false;
  }

  try {
    await postPortalMultipart('/rooms', payload, image);
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
    return false;
  }
}

String adminRoomRateLabel(Map<String, dynamic> room) {
  return HourlyBilling.priceLabel(room);
}

/// Floor picker shown when creating or editing a room.
class AdminRoomFloorField extends StatelessWidget {
  const AdminRoomFloorField({
    super.key,
    required this.floorCount,
    required this.selectedFloor,
    required this.onChanged,
  });

  final int floorCount;
  final int selectedFloor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxFloor = floorCount.clamp(1, 99);
    final safeSelected = selectedFloor.clamp(1, maxFloor);

    if (maxFloor <= 6) {
      return DropdownButtonFormField<int>(
        key: ValueKey<int>(safeSelected),
        initialValue: safeSelected,
        decoration: InputDecoration(
          labelText: 'Floor',
          prefixIcon: const Icon(Icons.layers_outlined),
          helperText: maxFloor > 1
              ? 'Select floor 1–$maxFloor for this category'
              : 'This category has one floor (set more in category settings)',
        ),
        items: List.generate(
          maxFloor,
          (i) => DropdownMenuItem(
            value: i + 1,
            child: Text('Floor ${i + 1}'),
          ),
        ),
        onChanged: (v) => onChanged(v ?? safeSelected),
      );
    }

    return TextFormField(
      key: ValueKey<int>(safeSelected),
      initialValue: '$safeSelected',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Floor',
        prefixIcon: const Icon(Icons.layers_outlined),
        helperText: 'Enter floor 1–$maxFloor',
      ),
      onChanged: (v) {
        final parsed = int.tryParse(v.trim());
        if (parsed == null) return;
        onChanged(parsed.clamp(1, maxFloor));
      },
    );
  }
}
