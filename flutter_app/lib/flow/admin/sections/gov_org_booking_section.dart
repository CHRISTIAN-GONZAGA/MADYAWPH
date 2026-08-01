import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_input.dart';
import '../admin_dashboard_models.dart';
import '../widgets/hourly_billing.dart';
import '../widgets/online_payment_qr_block.dart';

/// Government / organization charge-account bookings + outstanding AR.
class GovOrgBookingSection extends StatefulWidget {
  const GovOrgBookingSection({
    super.key,
    required this.rooms,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> rooms;
  final Future<void> Function() onChanged;

  @override
  State<GovOrgBookingSection> createState() => _GovOrgBookingSectionState();
}

class _GovOrgBookingSectionState extends State<GovOrgBookingSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _selected = <String>{};
  var _busy = false;
  var _loadingBalances = false;
  List<Map<String, dynamic>> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_tabs.indexIsChanging) {
        _loadOutstanding();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _bookable {
    return widget.rooms.where(AdminDashboardModels.isWalkInBookable).toList();
  }

  Future<void> _loadOutstanding() async {
    setState(() => _loadingBalances = true);
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/org-bookings/outstanding',
      );
      final raw = res.data?['accounts'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) list.add(Map<String, dynamic>.from(item));
        }
      }
      if (mounted) setState(() => _accounts = list);
    } on DioException catch (e) {
      if (mounted) {
        showAppMessage(context, dioErrorMessage(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _loadingBalances = false);
    }
  }

  Future<void> _bookSelected() async {
    if (_busy) return;
    final selectedRooms = AdminDashboardModels.sortRoomsByNumber(
      _bookable
          .where((r) => _selected.contains(AdminDashboardModels.roomIdOf(r)))
          .toList(),
    );
    if (selectedRooms.isEmpty) {
      showAppMessage(context, 'Select at least one available room.');
      return;
    }

    setState(() => _busy = true);
    try {
      final ok = await showGovOrgBookingDialog(
        context: context,
        rooms: selectedRooms,
      );
      if (!mounted) return;
      if (ok) {
        setState(_selected.clear);
        await widget.onChanged();
        showAppMessage(
          context,
          selectedRooms.length == 1
              ? 'Organization booking created.'
              : '${selectedRooms.length} organization rooms booked.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payAccount(Map<String, dynamic> account) async {
    final paid = await showGovOrgPayDialog(context: context, account: account);
    if (!mounted) return;
    if (paid) {
      await _loadOutstanding();
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookable = _bookable;
    final floors = AdminDashboardModels.distinctFloors(bookable);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Gov / Org booking',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Charge rooms to a government or organization account. '
          'Check-in and checkout are allowed without payment; collect balances here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'New booking'),
            Tab(text: 'Outstanding'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildBookingTab(bookable, floors),
              _buildOutstandingTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookingTab(
    List<Map<String, dynamic>> bookable,
    List<int> floors,
  ) {
    return Column(
      children: [
        Expanded(
          child: bookable.isEmpty
              ? const Center(child: Text('No available rooms to book right now.'))
              : ListView(
                  children: [
                    for (final floor in floors) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          'Floor $floor',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      ...AdminDashboardModels.roomsOnFloor(bookable, floor).map((room) {
                        final id = AdminDashboardModels.roomIdOf(room);
                        final selected = _selected.contains(id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: _busy
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(id);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  });
                                },
                          title: Text('Room ${room['room_number'] ?? '—'}'),
                          subtitle: Text(
                            [
                              (room['display_name'] ?? room['room_type'] ?? '')
                                  .toString(),
                              if (HourlyBilling.isHourly(room))
                                '${HourlyBilling.blockHours(room)}h blocks',
                            ].where((s) => s.trim().isNotEmpty).join(' · '),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 8),
        AppPrimaryButton(
          label: _selected.isEmpty
              ? 'Select rooms'
              : 'Book ${_selected.length} room${_selected.length == 1 ? '' : 's'} for org',
          onPressed: _busy || _selected.isEmpty ? null : _bookSelected,
        ),
      ],
    );
  }

  Widget _buildOutstandingTab() {
    if (_loadingBalances) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No outstanding organization balances.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadOutstanding,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadOutstanding,
      child: ListView.separated(
        itemCount: _accounts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final account = _accounts[index];
          final orgName = (account['org_name'] ?? 'Organization').toString();
          final orgType = (account['org_type'] ?? 'organization').toString();
          final balance = parseJsonDouble(account['outstanding_balance']);
          final count = (account['booking_count'] as num?)?.toInt() ?? 0;
          final contact = (account['org_contact_person'] ?? '').toString();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    orgName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${orgType == 'government' ? 'Government' : 'Organization'}'
                    ' · $count room booking${count == 1 ? '' : 's'}'
                    '${contact.isEmpty ? '' : ' · $contact'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Outstanding: ${formatPeso(balance)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => _payAccount(account),
                    child: const Text('Record payment'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<bool> showGovOrgBookingDialog({
  required BuildContext context,
  required List<Map<String, dynamic>> rooms,
}) async {
  final orgNameCtrl = TextEditingController();
  final contactCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final tinCtrl = TextEditingController();
  final poCtrl = TextEditingController();
  final guestCtrl = TextEditingController();
  var orgType = 'government';
  var checkInNow = true;
  final now = DateTime.now();
  var checkIn = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  var checkOut = checkIn.add(const Duration(days: 1));

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(
          rooms.length == 1
              ? 'Org booking — Room ${rooms.first['room_number']}'
              : 'Org booking — ${rooms.length} rooms',
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: orgType,
                  decoration: const InputDecoration(
                    labelText: 'Account type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'government',
                      child: Text('Government'),
                    ),
                    DropdownMenuItem(
                      value: 'organization',
                      child: Text('Organization'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => orgType = v);
                  },
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: orgNameCtrl,
                  label: 'Company / agency name',
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: contactCtrl,
                  label: 'Authorized contact person',
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: phoneCtrl,
                  label: 'Contact phone',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: emailCtrl,
                  label: 'Contact email (optional)',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: addressCtrl,
                  label: 'Billing address (optional)',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: tinCtrl,
                  label: 'TIN (optional)',
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: poCtrl,
                  label: 'PO / reference no. (optional)',
                ),
                const SizedBox(height: 10),
                AppInput(
                  controller: guestCtrl,
                  label: 'Guest name on rooms',
                  hint: 'Defaults to contact person',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check in now'),
                  subtitle: const Text(
                    'Allowed without initial payment for org accounts',
                  ),
                  value: checkInNow,
                  onChanged: (v) => setLocal(() => checkInNow = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-in'),
                  subtitle: Text(checkIn.toIso8601String()),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: checkIn,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(checkIn),
                    );
                    if (time == null) return;
                    setLocal(() {
                      checkIn = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                      if (!checkOut.isAfter(checkIn)) {
                        checkOut = checkIn.add(const Duration(days: 1));
                      }
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-out'),
                  subtitle: Text(checkOut.toIso8601String()),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: checkOut,
                      firstDate: checkIn,
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (date == null || !ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(checkOut),
                    );
                    if (time == null) return;
                    setLocal(() {
                      checkOut = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (orgNameCtrl.text.trim().isEmpty) {
                showAppMessage(ctx, 'Enter the organization / agency name.');
                return;
              }
              if (contactCtrl.text.trim().isEmpty) {
                showAppMessage(ctx, 'Enter the authorized contact person.');
                return;
              }
              if (phoneCtrl.text.trim().length < 7) {
                showAppMessage(ctx, 'Enter a valid contact phone.');
                return;
              }
              if (!checkOut.isAfter(checkIn)) {
                showAppMessage(ctx, 'Check-out must be after check-in.');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Create booking'),
          ),
        ],
      ),
    ),
  );

  final payload = {
    'guest_name': guestCtrl.text.trim().isEmpty
        ? contactCtrl.text.trim()
        : guestCtrl.text.trim(),
    'guest_phone': phoneCtrl.text.trim(),
    'guest_email': emailCtrl.text.trim(),
    'check_in_at': checkIn.toIso8601String(),
    'check_out_at': checkOut.toIso8601String(),
    'check_in_now': checkInNow,
    'org_name': orgNameCtrl.text.trim(),
    'org_type': orgType,
    'org_contact_person': contactCtrl.text.trim(),
    'org_contact_phone': phoneCtrl.text.trim(),
    'org_contact_email': emailCtrl.text.trim(),
    'org_address': addressCtrl.text.trim(),
    'org_tin': tinCtrl.text.trim(),
    'org_po_number': poCtrl.text.trim(),
    'adults': 1,
    'children': 0,
  };

  orgNameCtrl.dispose();
  contactCtrl.dispose();
  phoneCtrl.dispose();
  emailCtrl.dispose();
  addressCtrl.dispose();
  tinCtrl.dispose();
  poCtrl.dispose();
  guestCtrl.dispose();

  if (ok != true || !context.mounted) return false;

  try {
    if (rooms.length == 1) {
      await portalDio().post<Map<String, dynamic>>(
        '/admin/org-bookings',
        data: {
          ...payload,
          'room_id': AdminDashboardModels.roomIdOf(rooms.first),
        },
      );
    } else {
      await portalDio().post<Map<String, dynamic>>(
        '/admin/org-bookings/bulk',
        data: {
          ...payload,
          'room_ids': rooms
              .map(AdminDashboardModels.roomIdOf)
              .where((id) => id.isNotEmpty)
              .toList(),
        },
      );
    }
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
    return false;
  }
}

Future<bool> showGovOrgPayDialog({
  required BuildContext context,
  required Map<String, dynamic> account,
}) async {
  final balance = parseJsonDouble(account['outstanding_balance']);
  final amountCtrl = TextEditingController(text: balance.toStringAsFixed(2));
  final refCtrl = TextEditingController();
  var method = 'Cash';

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Pay ${(account['org_name'] ?? 'organization').toString()}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Outstanding: ${formatPeso(balance)}',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'GCash',
                      child: Text('eWallet / QR Ph'),
                    ),
                    DropdownMenuItem(
                      value: 'Bank Transfer',
                      child: Text('eBank transfer'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => method = v);
                  },
                ),
                if (isOnlinePaymentMethod(method) ||
                    method == 'Bank Transfer') ...[
                  const SizedBox(height: 12),
                  if (method != 'Bank Transfer')
                    OnlinePaymentQrBlock(
                      paymentMethod: method,
                      referenceController: refCtrl,
                    )
                  else
                    AppInput(
                      controller: refCtrl,
                      label: 'Bank transfer reference',
                    ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amount <= 0) {
                showAppMessage(ctx, 'Enter a payment amount.');
                return;
              }
              if ((method == 'GCash' || method == 'Bank Transfer') &&
                  refCtrl.text.trim().length < 4) {
                showAppMessage(ctx, 'Enter the payment / transfer reference.');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Record payment'),
          ),
        ],
      ),
    ),
  );

  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
  final reference = refCtrl.text.trim();
  amountCtrl.dispose();
  refCtrl.dispose();
  if (confirmed != true || !context.mounted) return false;

  try {
    final res = await portalDio().post<Map<String, dynamic>>(
      '/admin/org-bookings/pay',
      data: {
        'org_key': (account['org_key'] ?? '').toString(),
        'amount': amount,
        'payment_method': method,
        if (reference.isNotEmpty) 'payment_reference': reference,
      },
    );
    final applied = parseJsonDouble(res.data?['amount_applied']);
    if (context.mounted) {
      showAppMessage(
        context,
        'Recorded ${formatPeso(applied)} for ${(account['org_name'] ?? 'organization').toString()}.',
      );
    }
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
    return false;
  }
}
