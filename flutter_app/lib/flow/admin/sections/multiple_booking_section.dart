import 'package:flutter/material.dart';

import '../admin_dashboard_models.dart';
import '../widgets/admin_multi_room_booking.dart';

/// Select multiple walk-in bookable rooms and book under one guest profile.
class MultipleBookingSection extends StatefulWidget {
  const MultipleBookingSection({
    super.key,
    required this.rooms,
    required this.onBooked,
  });

  final List<Map<String, dynamic>> rooms;
  final Future<void> Function() onBooked;

  @override
  State<MultipleBookingSection> createState() => _MultipleBookingSectionState();
}

class _MultipleBookingSectionState extends State<MultipleBookingSection> {
  final _selected = <String>{};
  var _busy = false;

  List<Map<String, dynamic>> get _bookable {
    return widget.rooms.where(AdminDashboardModels.isWalkInBookable).toList();
  }

  Future<void> _bookSelected() async {
    if (_busy) return;

    final selectedRooms = AdminDashboardModels.sortRoomsByNumber(
      _bookable
          .where((r) => _selected.contains(AdminDashboardModels.roomIdOf(r)))
          .toList(),
    );
    if (selectedRooms.length < 2) return;

    setState(() => _busy = true);
    try {
      final ok = await showAdminMultiRoomWalkInBooking(
        context: context,
        rooms: selectedRooms,
      );
      if (!mounted) return;
      if (ok) {
        setState(_selected.clear);
        await widget.onBooked();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleRoom(String id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  int _selectedCountOnFloor(List<Map<String, dynamic>> floorRooms) {
    var count = 0;
    for (final room in floorRooms) {
      final id = AdminDashboardModels.roomIdOf(room);
      if (id.isNotEmpty && _selected.contains(id)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final bookable = _bookable;
    final floors = AdminDashboardModels.distinctFloors(bookable);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Group booking',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Expand a floor, then select two or more rooms (across any floors). '
            'You will pick dates on a shared calendar and complete the guest form.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('${_selected.length} room(s) selected'),
              ),
            ),
          ),
        if (bookable.isEmpty)
          const Expanded(
            child: Center(child: Text('No walk-in bookable rooms right now.')),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
              itemCount: floors.length,
              itemBuilder: (context, floorIndex) {
                final floor = floors[floorIndex];
                final floorRooms =
                    AdminDashboardModels.roomsOnFloor(bookable, floor);
                final selectedOnFloor = _selectedCountOnFloor(floorRooms);
                final allOnFloorSelected = floorRooms.isNotEmpty &&
                    selectedOnFloor == floorRooms.length;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: floorIndex == 0 || selectedOnFloor > 0,
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        '$floor',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      AdminDashboardModels.floorLabel(floor),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${floorRooms.length} available'
                      '${selectedOnFloor > 0 ? ' · $selectedOnFloor selected' : ''}',
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    children: [
                      if (floorRooms.length > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        if (allOnFloorSelected) {
                                          for (final room in floorRooms) {
                                            _selected.remove(
                                              AdminDashboardModels.roomIdOf(room),
                                            );
                                          }
                                        } else {
                                          for (final room in floorRooms) {
                                            final id =
                                                AdminDashboardModels.roomIdOf(room);
                                            if (id.isNotEmpty) {
                                              _selected.add(id);
                                            }
                                          }
                                        }
                                      });
                                    },
                              child: Text(
                                allOnFloorSelected
                                    ? 'Clear floor'
                                    : 'Select all on floor',
                              ),
                            ),
                          ),
                        ),
                      ...floorRooms.map((room) {
                        final id = AdminDashboardModels.roomIdOf(room);
                        final roomNo =
                            (room['room_number'] ?? '—').toString();
                        final category =
                            AdminDashboardModels.categoryLabel(room);
                        return CheckboxListTile(
                          value: id.isNotEmpty && _selected.contains(id),
                          tristate: false,
                          onChanged: _busy || id.isEmpty
                              ? null
                              : (v) => _toggleRoom(id, v),
                          title: Text('Room $roomNo'),
                          subtitle: Text(category),
                          secondary: CircleAvatar(
                            radius: 18,
                            child: Text(
                              roomNo,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          dense: true,
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _busy || _selected.length < 2 ? null : _bookSelected,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _selected.isEmpty
                          ? 'Select rooms'
                          : 'Continue · ${_selected.length} rooms',
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
