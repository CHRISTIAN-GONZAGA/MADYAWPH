import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../dio_client.dart';
import '../../../widgets/chat_attachment.dart';
import 'hourly_billing.dart';
import 'hourly_price_picker.dart';

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
}) async {
  final roomId = (room['id'] ?? '').toString();
  if (roomId.isEmpty) return false;

  final cat = categoryDefaults ?? const <String, dynamic>{};
  final nameCtrl = TextEditingController(
    text: (room['display_name'] ?? room['name'] ?? '').toString(),
  );
  final roomNoCtrl = TextEditingController(
    text: (room['room_number'] ?? '').toString(),
  );
  var roomType = (room['room_type'] ?? 'Single').toString();
  var roomBillingMode =
      (room['billing_mode'] ?? cat['billing_mode'] ?? 'nightly').toString();
  var roomPricePerNight =
      (room['price_per_night'] as num?)?.toDouble() ??
      (cat['default_price'] as num?)?.toDouble() ??
      0.0;
  var roomPricePerBlock = (room['price_per_block'] as num?)?.toDouble() ??
      (cat['price_per_block'] as num?)?.toDouble() ??
      roomPricePerNight;
  var roomBlockHours = (room['block_hours'] as num?)?.toInt() ??
      (cat['block_hours'] as num?)?.toInt() ??
      3;
  var status = (room['status'] ?? 'available').toString();
  final floorCount = (cat['floor_count'] as num?)?.toInt() ?? 1;
  var selectedFloor = (room['floor'] as num?)?.toInt() ?? 1;
  if (selectedFloor < 1) selectedFloor = 1;
  final nightlyCtrl = TextEditingController(text: '$roomPricePerNight');
  final blockPriceCtrl = TextEditingController(text: '$roomPricePerBlock');
  final existingImageUrl = (room['image_url'] ?? '').toString().trim();
  XFile? pickedImage;
  var removeExistingImage = false;

  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Edit room ${roomNoCtrl.text.trim().isEmpty ? '' : roomNoCtrl.text.trim()}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Update photo, rates, and room details shown to guests.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 18),
                  if (floorCount > 1) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey<int>(selectedFloor),
                      initialValue: selectedFloor.clamp(1, floorCount),
                      decoration: const InputDecoration(
                        labelText: 'Floor',
                        prefixIcon: Icon(Icons.layers_outlined),
                      ),
                      items: List.generate(
                        floorCount,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('Floor ${i + 1}'),
                        ),
                      ),
                      onChanged: (v) =>
                          setLocal(() => selectedFloor = v ?? selectedFloor),
                    ),
                    const SizedBox(height: 14),
                  ],
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
                          value: 'checked_in', child: Text('Checked in')),
                      DropdownMenuItem(
                          value: 'checked_out', child: Text('Checked out')),
                      DropdownMenuItem(
                          value: 'maintenance', child: Text('Maintenance')),
                      DropdownMenuItem(
                          value: 'reserved', child: Text('Reserved')),
                    ],
                    onChanged: (v) => setLocal(() => status = v ?? status),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Room photo',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  AdminRoomGalleryPicker(
                    pickedImage: pickedImage,
                    existingImageUrl:
                        removeExistingImage ? null : existingImageUrl,
                    onPick: () async {
                      final file =
                          await ChatAttachment.pickRoomImageFromGallery(context);
                      if (file != null) {
                        setLocal(() {
                          pickedImage = file;
                          removeExistingImage = false;
                        });
                      }
                    },
                    onClearPicked: () => setLocal(() => pickedImage = null),
                    onClearExisting: existingImageUrl.isEmpty
                        ? null
                        : () => setLocal(() {
                              removeExistingImage = true;
                              pickedImage = null;
                            }),
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
                          'display_name': nameCtrl.text.trim(),
                          'room_number': roomNoCtrl.text.trim(),
                          'floor': selectedFloor,
                          'room_type': roomType,
                          'billing_mode': roomBillingMode,
                          'price_per_night': roomPricePerNight,
                          'price_per_block': roomPricePerBlock,
                          'block_hours': roomBlockHours,
                          'status': status,
                          if (removeExistingImage) 'remove_image': true,
                          '__image': pickedImage,
                        }),
                        child: const Text('Save'),
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

  final image = payload.remove('__image') as XFile?;
  try {
    await putPortalMultipart('/rooms/$roomId', payload, image);
    return true;
  } on DioException {
    rethrow;
  }
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
    text: '${(category['default_price'] as num?)?.toDouble() ?? 0}',
  );
  final blockPriceCtrl = TextEditingController(
    text:
        '${(category['price_per_block'] as num?)?.toDouble() ?? (category['default_price'] as num?)?.toDouble() ?? 1000}',
  );
  var roomBillingMode =
      (category['billing_mode'] ?? 'nightly').toString().toLowerCase();
  var roomPricePerNight =
      (category['default_price'] as num?)?.toDouble() ?? 0;
  var roomPricePerBlock =
      (category['price_per_block'] as num?)?.toDouble() ?? roomPricePerNight;
  var roomBlockHours = (category['block_hours'] as num?)?.toInt() ?? 3;
  var roomType = 'Single';
  var status = 'available';
  final floorCount = (category['floor_count'] as num?)?.toInt() ?? 1;
  var selectedFloor = 1;
  XFile? pickedImage;

  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
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
                  if (floorCount > 1) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey<int>(selectedFloor),
                      initialValue: selectedFloor,
                      decoration: const InputDecoration(
                        labelText: 'Floor',
                        prefixIcon: Icon(Icons.layers_outlined),
                        helperText: 'Select which floor this room is on',
                      ),
                      items: List.generate(
                        floorCount,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('Floor ${i + 1}'),
                        ),
                      ),
                      onChanged: (v) =>
                          setLocal(() => selectedFloor = v ?? selectedFloor),
                    ),
                    const SizedBox(height: 14),
                  ],
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
  await postPortalMultipart('/rooms', payload, image);
  return true;
}

String adminRoomRateLabel(Map<String, dynamic> room) {
  return HourlyBilling.priceLabel(room);
}
