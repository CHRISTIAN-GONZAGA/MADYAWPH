import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../dio_client.dart';
import '../../../widgets/chat_attachment.dart';
import '../admin_dashboard_models.dart';
import 'admin_dev_error_panel.dart';
import 'admin_opaque_scaffold.dart';
import 'admin_room_editor.dart';
import 'admin_room_form_constants.dart';
import 'hourly_price_picker.dart';

/// Full-screen room setup editor (reliable on nested admin navigator / device).
class AdminRoomEditScreen extends StatefulWidget {
  const AdminRoomEditScreen({
    super.key,
    required this.room,
    this.categoryDefaults,
    this.categoryLabel,
  });

  final Map<String, dynamic> room;
  final Map<String, dynamic>? categoryDefaults;
  final String? categoryLabel;

  @override
  State<AdminRoomEditScreen> createState() => _AdminRoomEditScreenState();
}

class _AdminRoomEditScreenState extends State<AdminRoomEditScreen> {
  late final Map<String, dynamic> _room;
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
  String? _renderError;

  String get _roomId => AdminDashboardModels.roomIdOf(_room);

  @override
  void initState() {
    super.initState();
    try {
      _room = normalizeAdminRoomForEdit(
        Map<String, dynamic>.from(widget.room),
      );
      final cat = widget.categoryDefaults ?? const <String, dynamic>{};

      _nameCtrl = TextEditingController(
        text: (_room['display_name'] ?? _room['name'] ?? '').toString(),
      );
      _roomNoCtrl = TextEditingController(
        text: (_room['room_number'] ?? '').toString(),
      );
      _roomType = normalizeAdminRoomChoice(
        _room['room_type'],
        'Single',
        adminRoomTypeOptions,
      );
      _roomBillingMode =
          (_room['billing_mode'] ?? cat['billing_mode'] ?? 'nightly')
              .toString()
              .toLowerCase();
      if (_roomBillingMode != 'hourly') {
        _roomBillingMode = 'nightly';
      }
      _roomPricePerNight = parseAdminDouble(
        _room['price_per_night'],
        parseAdminDouble(cat['default_price']),
      );
      _roomPricePerBlock = parseAdminDouble(
        _room['price_per_block'],
        parseAdminDouble(
          cat['price_per_block'],
          _roomPricePerNight,
        ),
      );
      _roomBlockHours = parseAdminInt(
        _room['block_hours'],
        parseAdminInt(cat['block_hours'], 3),
      );
      _status = normalizeAdminRoomChoice(
        _room['status'],
        'available',
        adminRoomStatusOptions,
      );
      _floorCount = parseAdminInt(cat['floor_count'], 1);
      _selectedFloor = parseAdminInt(_room['floor'], 1);
      if (_selectedFloor < 1) _selectedFloor = 1;
      if (_selectedFloor > _floorCount) {
        _selectedFloor = _floorCount.clamp(1, 99);
      }
      _nightlyCtrl = TextEditingController(text: '$_roomPricePerNight');
      _blockPriceCtrl = TextEditingController(text: '$_roomPricePerBlock');
      _existingImageUrl = (_room['image_url'] ?? '').toString().trim();

      if (_roomId.isEmpty) {
        _renderError = 'Room id is missing after normalization.\n'
            'Raw keys: ${_room.keys.join(', ')}';
      }
    } catch (e, stack) {
      _renderError = AdminDevErrorPanel.formatError(e, stack);
      _room = Map<String, dynamic>.from(widget.room);
      _nameCtrl = TextEditingController();
      _roomNoCtrl = TextEditingController();
      _nightlyCtrl = TextEditingController(text: '0');
      _blockPriceCtrl = TextEditingController(text: '0');
      _roomType = 'Single';
      _roomBillingMode = 'nightly';
      _roomPricePerNight = 0;
      _roomPricePerBlock = 0;
      _roomBlockHours = 3;
      _status = 'available';
      _selectedFloor = 1;
      _floorCount = 1;
      _existingImageUrl = '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomNoCtrl.dispose();
    _nightlyCtrl.dispose();
    _blockPriceCtrl.dispose();
    super.dispose();
  }

  String _debugDump() {
    return const JsonEncoder.withIndent('  ').convert({
      'room_id': _roomId,
      'room_type': _roomType,
      'status': _status,
      'billing_mode': _roomBillingMode,
      'floor': _selectedFloor,
      'category_label': widget.categoryLabel,
      'raw_room': _room,
      'category_defaults': widget.categoryDefaults,
    });
  }

  Future<void> _save() async {
    if (_saving || _roomId.isEmpty || _renderError != null) return;
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
      setState(() {
        _renderError = dioErrorMessage(e);
      });
    } catch (e, stack) {
      if (!mounted) return;
      setState(() {
        _renderError = AdminDevErrorPanel.formatError(e, stack);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _title() {
    final roomNo = _roomNoCtrl.text.trim();
    final category = (widget.categoryLabel ?? '').trim();
    if (roomNo.isEmpty && category.isEmpty) return 'Edit room';
    if (roomNo.isEmpty) return 'Edit room · $category';
    if (category.isEmpty) return 'Edit room $roomNo';
    return 'Edit room $roomNo · $category';
  }

  @override
  Widget build(BuildContext context) {
    return AdminOpaqueScaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (_renderError == null)
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
      body: _renderError != null
          ? AdminDevErrorPanel(
              title: 'Room editor failed to load',
              message: _renderError!,
              details: kDebugMode ? _debugDump() : null,
              hint: 'Pull back and try again, or copy this error for support.',
            )
          : _EditForm(
              nameCtrl: _nameCtrl,
              roomNoCtrl: _roomNoCtrl,
              nightlyCtrl: _nightlyCtrl,
              blockPriceCtrl: _blockPriceCtrl,
              roomType: _roomType,
              roomBillingMode: _roomBillingMode,
              roomPricePerNight: _roomPricePerNight,
              roomPricePerBlock: _roomPricePerBlock,
              roomBlockHours: _roomBlockHours,
              status: _status,
              floorCount: _floorCount,
              selectedFloor: _selectedFloor,
              existingImageUrl: _existingImageUrl,
              pickedImage: _pickedImage,
              removeExistingImage: _removeExistingImage,
              saving: _saving,
              onRoomTypeChanged: (v) => setState(() => _roomType = v),
              onStatusChanged: (v) => setState(() => _status = v),
              onFloorChanged: (v) => setState(() => _selectedFloor = v),
              onPricingChanged: ({
                required String billingMode,
                required double pricePerNight,
                required double pricePerBlock,
                required int blockHours,
              }) {
                setState(() {
                  _roomBillingMode = billingMode;
                  _roomPricePerNight = pricePerNight;
                  _roomPricePerBlock = pricePerBlock;
                  _roomBlockHours = blockHours;
                });
              },
              onPickImage: (file) => setState(() {
                _pickedImage = file;
                _removeExistingImage = false;
              }),
              onClearPicked: () => setState(() => _pickedImage = null),
              onClearExisting: () => setState(() {
                _removeExistingImage = true;
                _pickedImage = null;
              }),
              onSave: _save,
            ),
    );
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({
    required this.nameCtrl,
    required this.roomNoCtrl,
    required this.nightlyCtrl,
    required this.blockPriceCtrl,
    required this.roomType,
    required this.roomBillingMode,
    required this.roomPricePerNight,
    required this.roomPricePerBlock,
    required this.roomBlockHours,
    required this.status,
    required this.floorCount,
    required this.selectedFloor,
    required this.existingImageUrl,
    required this.pickedImage,
    required this.removeExistingImage,
    required this.saving,
    required this.onRoomTypeChanged,
    required this.onStatusChanged,
    required this.onFloorChanged,
    required this.onPricingChanged,
    required this.onPickImage,
    required this.onClearPicked,
    required this.onClearExisting,
    required this.onSave,
  });

  final TextEditingController nameCtrl;
  final TextEditingController roomNoCtrl;
  final TextEditingController nightlyCtrl;
  final TextEditingController blockPriceCtrl;
  final String roomType;
  final String roomBillingMode;
  final double roomPricePerNight;
  final double roomPricePerBlock;
  final int roomBlockHours;
  final String status;
  final int floorCount;
  final int selectedFloor;
  final String existingImageUrl;
  final XFile? pickedImage;
  final bool removeExistingImage;
  final bool saving;
  final ValueChanged<String> onRoomTypeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<int> onFloorChanged;
  final void Function({
    required String billingMode,
    required double pricePerNight,
    required double pricePerBlock,
    required int blockHours,
  }) onPricingChanged;
  final ValueChanged<XFile> onPickImage;
  final VoidCallback onClearPicked;
  final VoidCallback onClearExisting;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
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
          floorCount: floorCount,
          selectedFloor: selectedFloor,
          onChanged: onFloorChanged,
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
          value: roomType,
          decoration: const InputDecoration(labelText: 'Room type'),
          items: const [
            DropdownMenuItem(value: 'Single', child: Text('Single')),
            DropdownMenuItem(value: 'Double', child: Text('Double')),
            DropdownMenuItem(value: 'Suite', child: Text('Suite')),
            DropdownMenuItem(value: 'Deluxe', child: Text('Deluxe')),
          ],
          onChanged: (v) {
            if (v != null) onRoomTypeChanged(v);
          },
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
            onPricingChanged(
              billingMode: billingMode,
              pricePerNight: pricePerNight,
              pricePerBlock: pricePerBlock,
              blockHours: blockHours,
            );
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const [
            DropdownMenuItem(value: 'available', child: Text('Available')),
            DropdownMenuItem(value: 'booked', child: Text('Booked')),
            DropdownMenuItem(value: 'checked_in', child: Text('Checked in')),
            DropdownMenuItem(value: 'checked_out', child: Text('Checked out')),
            DropdownMenuItem(value: 'cleaning', child: Text('Cleaning')),
            DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
            DropdownMenuItem(value: 'reserved', child: Text('Reserved')),
          ],
          onChanged: (v) {
            if (v != null) onStatusChanged(v);
          },
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
          existingImageUrl: removeExistingImage ? null : existingImageUrl,
          onPick: () async {
            final file =
                await ChatAttachment.pickRoomImageFromGallery(context);
            if (file != null) onPickImage(file);
          },
          onClearPicked: onClearPicked,
          onClearExisting:
              existingImageUrl.isEmpty ? null : onClearExisting,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: const Text('Save room'),
        ),
      ],
    );
  }
}

/// Bottom-sheet friendly room list (used before opening [AdminRoomEditScreen]).
Future<Map<String, dynamic>?> showAdminRoomPickerSheet(
  BuildContext context, {
  required String categoryLabel,
  required List<Map<String, dynamic>> rooms,
}) {
  final sorted = List<Map<String, dynamic>>.from(rooms)
    ..sort((a, b) {
      final na = (a['room_number'] ?? '').toString();
      final nb = (b['room_number'] ?? '').toString();
      final ia = int.tryParse(na);
      final ib = int.tryParse(nb);
      if (ia != null && ib != null) return ia.compareTo(ib);
      return na.compareTo(nb);
    });

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      if (sorted.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: AdminDevErrorPanel(
            title: 'No rooms to show',
            message: 'The API returned ${rooms.length} room(s) for '
                '"$categoryLabel", but none could be listed.',
            details: rooms
                .map((r) => AdminDashboardModels.roomIdOf(r))
                .join(', '),
            hint: 'Pull to refresh on Room categories, then try again.',
          ),
        );
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Select room · $categoryLabel',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '${sorted.length} room(s) — tap one to edit',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final room = sorted[index];
                    final no = (room['room_number'] ?? '—').toString();
                    final name =
                        (room['display_name'] ?? room['name'] ?? '').toString();
                    final floor = parseAdminInt(room['floor'], 0);
                    final subtitle = [
                      if (name.isNotEmpty) name,
                      if (floor != null && floor > 0) 'Floor $floor',
                      safeAdminRoomRateLabel(room),
                    ].join(' · ');

                    return ListTile(
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text('Room $no'),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(ctx).pop(room),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
