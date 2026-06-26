import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../dio_client.dart';
import '../../../widgets/chat_attachment.dart';
import 'admin_opaque_scaffold.dart';
import 'admin_room_editor.dart';
import 'hourly_price_picker.dart';

/// Full-screen room setup editor (reliable on nested admin navigator / device).
class AdminRoomEditScreen extends StatefulWidget {
  const AdminRoomEditScreen({
    super.key,
    required this.room,
    this.categoryDefaults,
  });

  final Map<String, dynamic> room;
  final Map<String, dynamic>? categoryDefaults;

  @override
  State<AdminRoomEditScreen> createState() => _AdminRoomEditScreenState();
}

class _AdminRoomEditScreenState extends State<AdminRoomEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _roomNoCtrl;
  late final TextEditingController _nightlyCtrl;
  late final TextEditingController _blockPriceCtrl;

  late String _roomType;
  late String _roomBillingMode;
  late double _roomPricePerNight;
  late double _roomPricePerBlock;
  late int _roomBlockHours;
  late String _status;
  late int _selectedFloor;
  late final int _floorCount;
  late final String _existingImageUrl;

  XFile? _pickedImage;
  var _removeExistingImage = false;
  var _saving = false;

  String get _roomId =>
      (widget.room['id'] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    final cat = widget.categoryDefaults ?? const <String, dynamic>{};

    _nameCtrl = TextEditingController(
      text: (room['display_name'] ?? room['name'] ?? '').toString(),
    );
    _roomNoCtrl = TextEditingController(
      text: (room['room_number'] ?? '').toString(),
    );
    _roomType = (room['room_type'] ?? 'Single').toString();
    _roomBillingMode =
        (room['billing_mode'] ?? cat['billing_mode'] ?? 'nightly')
            .toString()
            .toLowerCase();
    _roomPricePerNight =
        (room['price_per_night'] as num?)?.toDouble() ??
        (cat['default_price'] as num?)?.toDouble() ??
        0.0;
    _roomPricePerBlock = (room['price_per_block'] as num?)?.toDouble() ??
        (cat['price_per_block'] as num?)?.toDouble() ??
        _roomPricePerNight;
    _roomBlockHours = (room['block_hours'] as num?)?.toInt() ??
        (cat['block_hours'] as num?)?.toInt() ??
        3;
    _status = (room['status'] ?? 'available').toString();
    _floorCount = (cat['floor_count'] as num?)?.toInt() ?? 1;
    _selectedFloor = (room['floor'] as num?)?.toInt() ?? 1;
    if (_selectedFloor < 1) _selectedFloor = 1;
    _nightlyCtrl = TextEditingController(text: '$_roomPricePerNight');
    _blockPriceCtrl = TextEditingController(text: '$_roomPricePerBlock');
    _existingImageUrl = (room['image_url'] ?? '').toString().trim();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomNoCtrl.dispose();
    _nightlyCtrl.dispose();
    _blockPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _roomId.isEmpty) return;
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'display_name': _nameCtrl.text.trim(),
        'room_number': _roomNoCtrl.text.trim(),
        'floor': _selectedFloor,
        'room_type': _roomType,
        'billing_mode': _roomBillingMode,
        'price_per_night': _roomPricePerNight,
        'price_per_block': _roomPricePerBlock,
        'block_hours': _roomBlockHours,
        'status': _status,
        if (_removeExistingImage) 'remove_image': true,
      };
      await putPortalMultipart('/rooms/$_roomId', payload, _pickedImage);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomNo = _roomNoCtrl.text.trim();
    final title = roomNo.isEmpty ? 'Edit room' : 'Edit room $roomNo';

    return AdminOpaqueScaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Update photo, rates, and room details shown to guests.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          AdminRoomFloorField(
            floorCount: _floorCount,
            selectedFloor: _selectedFloor,
            onChanged: (v) => setState(() => _selectedFloor = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _roomNoCtrl,
            decoration: const InputDecoration(
              labelText: 'Room number',
              prefixIcon: Icon(Icons.door_front_door_outlined),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_roomType),
            initialValue: _roomType,
            decoration: const InputDecoration(labelText: 'Room type'),
            items: const [
              DropdownMenuItem(value: 'Single', child: Text('Single')),
              DropdownMenuItem(value: 'Double', child: Text('Double')),
              DropdownMenuItem(value: 'Suite', child: Text('Suite')),
              DropdownMenuItem(value: 'Deluxe', child: Text('Deluxe')),
            ],
            onChanged: (v) => setState(() => _roomType = v ?? _roomType),
          ),
          const SizedBox(height: 14),
          RoomPricingFields(
            billingMode: _roomBillingMode,
            pricePerNight: _roomPricePerNight,
            pricePerBlock: _roomPricePerBlock,
            blockHours: _roomBlockHours,
            showExtraHourRate: false,
            nightlyController: _nightlyCtrl,
            blockPriceController: _blockPriceCtrl,
            onChanged: ({
              required String billingMode,
              required double pricePerNight,
              required double pricePerBlock,
              required int blockHours,
              required double pricePerExtraHour,
            }) {
              setState(() {
                _roomBillingMode = billingMode;
                _roomPricePerNight = pricePerNight;
                _roomPricePerBlock = pricePerBlock;
                _roomBlockHours = blockHours;
              });
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_status),
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'available', child: Text('Available')),
              DropdownMenuItem(value: 'booked', child: Text('Booked')),
              DropdownMenuItem(value: 'checked_in', child: Text('Checked in')),
              DropdownMenuItem(value: 'checked_out', child: Text('Checked out')),
              DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
              DropdownMenuItem(value: 'reserved', child: Text('Reserved')),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
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
            pickedImage: _pickedImage,
            existingImageUrl: _removeExistingImage ? null : _existingImageUrl,
            onPick: () async {
              final file =
                  await ChatAttachment.pickRoomImageFromGallery(context);
              if (file != null) {
                setState(() {
                  _pickedImage = file;
                  _removeExistingImage = false;
                });
              }
            },
            onClearPicked: () => setState(() => _pickedImage = null),
            onClearExisting: _existingImageUrl.isEmpty
                ? null
                : () => setState(() {
                      _removeExistingImage = true;
                      _pickedImage = null;
                    }),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save room'),
          ),
        ],
      ),
    );
  }
}

/// Pick one room from a list (full screen — reliable on nested admin navigator).
class AdminRoomPickerScreen extends StatelessWidget {
  const AdminRoomPickerScreen({
    super.key,
    required this.title,
    required this.rooms,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;

  @override
  Widget build(BuildContext context) {
    final sorted = List<Map<String, dynamic>>.from(rooms)
      ..sort((a, b) {
        final na = (a['room_number'] ?? '').toString();
        final nb = (b['room_number'] ?? '').toString();
        final ia = int.tryParse(na);
        final ib = int.tryParse(nb);
        if (ia != null && ib != null) return ia.compareTo(ib);
        return na.compareTo(nb);
      });

    return AdminOpaqueScaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final room = sorted[index];
          final no = (room['room_number'] ?? '—').toString();
          final name = (room['display_name'] ?? room['name'] ?? '').toString();
          final floor = (room['floor'] as num?)?.toInt();
          final subtitle = [
            if (name.isNotEmpty) name,
            if (floor != null && floor > 0) 'Floor $floor',
            adminRoomRateLabel(room),
          ].join(' · ');

          return ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: Text('Room $no'),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pop(room),
          );
        },
      ),
    );
  }
}
