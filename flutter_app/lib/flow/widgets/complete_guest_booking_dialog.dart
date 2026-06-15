import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../dio_client.dart';
import '../../locale_controller.dart';
import '../admin/widgets/hourly_billing.dart';
import '../customer_search_context.dart' as customer;
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/chat_attachment.dart';

/// Result from [showCompleteGuestBookingDialog].
class CompleteGuestBookingPayload {
  const CompleteGuestBookingPayload({
    required this.guestName,
    required this.guestEmail,
    required this.guestPhone,
    required this.checkIn,
    required this.checkOut,
    required this.discountType,
    required this.paymentMethod,
    this.guestIdFile,
    this.discountIdFile,
  });

  final String guestName;
  final String guestEmail;
  final String guestPhone;
  final String checkIn;
  final String checkOut;
  final String discountType;
  final String paymentMethod;
  final XFile? guestIdFile;
  final XFile? discountIdFile;
}

class CompleteGuestBookingConfig {
  const CompleteGuestBookingConfig({
    required this.title,
    required this.summaryTitle,
    required this.rooms,
    required this.adults,
    required this.children,
    this.initialCheckIn,
    this.initialCheckOut,
    this.lockDates = false,
    this.requireGuestId = true,
    this.showAdminPaymentMethods = false,
    this.reserveMode = false,
    this.hotelId,
    this.showOnlinePayment = false,
  });

  final String title;
  final String summaryTitle;
  final int rooms;
  final int adults;
  final int children;
  final DateTime? initialCheckIn;
  final DateTime? initialCheckOut;
  final bool lockDates;
  final bool requireGuestId;
  final bool showAdminPaymentMethods;
  final bool reserveMode;
  final String? hotelId;
  final bool showOnlinePayment;

  factory CompleteGuestBookingConfig.adminWalkIn(Map<String, dynamic> room) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return CompleteGuestBookingConfig(
      title: 'Complete your booking',
      summaryTitle: 'Walk-in · Room ${room['room_number'] ?? '—'}',
      rooms: 1,
      adults: 2,
      children: 0,
      initialCheckIn: today,
      initialCheckOut: today.add(const Duration(days: 1)),
      requireGuestId: true,
      showAdminPaymentMethods: true,
    );
  }

  factory CompleteGuestBookingConfig.fromSearch({
    required customer.CustomerSearchContext search,
    String? hotelId,
  }) {
    return CompleteGuestBookingConfig(
      title: 'Complete your booking',
      summaryTitle: 'From your search',
      rooms: search.rooms,
      adults: search.adults,
      children: search.children,
      initialCheckIn: search.checkIn,
      initialCheckOut: search.checkOut,
      lockDates: true,
      requireGuestId: true,
      showOnlinePayment: true,
      hotelId: hotelId,
    );
  }

  factory CompleteGuestBookingConfig.customerWalkIn() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return CompleteGuestBookingConfig(
      title: 'Book room',
      summaryTitle: 'Walk-in booking',
      rooms: 1,
      adults: 2,
      children: 0,
      initialCheckIn: today,
      initialCheckOut: today.add(const Duration(days: 1)),
      requireGuestId: false,
    );
  }

  factory CompleteGuestBookingConfig.customerReserve() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return CompleteGuestBookingConfig(
      title: 'Request reservation',
      summaryTitle: 'Reservation request',
      rooms: 1,
      adults: 2,
      children: 0,
      initialCheckIn: today.add(const Duration(days: 1)),
      initialCheckOut: today.add(const Duration(days: 2)),
      requireGuestId: false,
      reserveMode: true,
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<CompleteGuestBookingPayload?> showCompleteGuestBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> room,
  required CompleteGuestBookingConfig config,
}) {
  final theme = Theme.of(context);
  return showDialog<CompleteGuestBookingPayload>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (dialogContext) => Theme(
      data: theme,
      child: _CompleteGuestBookingDialog(
        room: room,
        config: config,
      ),
    ),
  );
}

class _CompleteGuestBookingDialog extends StatefulWidget {
  const _CompleteGuestBookingDialog({
    required this.room,
    required this.config,
  });

  final Map<String, dynamic> room;
  final CompleteGuestBookingConfig config;

  @override
  State<_CompleteGuestBookingDialog> createState() =>
      _CompleteGuestBookingDialogState();
}

class _CompleteGuestBookingDialogState extends State<_CompleteGuestBookingDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _checkInCtrl;
  late final TextEditingController _checkOutCtrl;

  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  var _discountType = 'none';
  var _paymentMethod = 'Cash';
  XFile? _guestIdFile;
  XFile? _discountIdFile;
  String _paymentQrUrl = '';
  var _qrLoading = false;

  CompleteGuestBookingConfig get config => widget.config;
  Map<String, dynamic> get room => widget.room;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _checkInCtrl = TextEditingController();
    _checkOutCtrl = TextEditingController();
    _checkInDate = config.initialCheckIn;
    _checkOutDate = config.initialCheckOut;
    if (_checkInDate != null) {
      _checkInCtrl.text = _fmtDate(_checkInDate!);
    }
    if (_checkOutDate != null) {
      _checkOutCtrl.text = _fmtDate(_checkOutDate!);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentQr() async {
    final hotelId = config.hotelId;
    if (hotelId == null || hotelId.isEmpty) return;
    setState(() => _qrLoading = true);
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/payment-qr',
        queryParameters: {'hotel_id': hotelId},
      );
      _paymentQrUrl = (res.data?['qr_url'] ?? '').toString();
    } catch (_) {
      _paymentQrUrl = '';
    } finally {
      if (mounted) setState(() => _qrLoading = false);
    }
  }

  Future<void> _pickCheckIn() async {
    if (config.lockDates) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = config.reserveMode ? today.add(const Duration(days: 1)) : today;
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: config.reserveMode
          ? today.add(const Duration(days: 365))
          : today.add(const Duration(days: 365)),
      initialDate: _checkInDate ?? first,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkInDate = picked;
      if (_checkOutDate != null && !_checkOutDate!.isAfter(picked)) {
        _checkOutDate = null;
        _checkOutCtrl.clear();
      }
      _checkInCtrl.text = _fmtDate(picked);
    });
  }

  Future<void> _pickCheckOut() async {
    if (config.lockDates) return;
    if (_checkInDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('select_checkin_first'))),
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      firstDate: HourlyBilling.isHourly(room) && !config.reserveMode
          ? _checkInDate!
          : _checkInDate!.add(const Duration(days: 1)),
      lastDate: _checkInDate!.add(const Duration(days: 365)),
      initialDate: _checkOutDate ??
          (HourlyBilling.isHourly(room) && !config.reserveMode
              ? _checkInDate!
              : _checkInDate!.add(const Duration(days: 1))),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkOutDate = picked;
      _checkOutCtrl.text = _fmtDate(picked);
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Enter your full name.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter a valid email address.');
      return;
    }
    if (phone.length < 7) {
      _snack('Enter a valid phone number.');
      return;
    }
    if (config.requireGuestId && _guestIdFile == null) {
      _snack('Upload your government ID.');
      return;
    }
    if (_discountType != 'none' && _discountIdFile == null) {
      _snack('Upload a photo of your discount ID.');
      return;
    }
    if (_checkInCtrl.text.trim().isEmpty || _checkOutCtrl.text.trim().isEmpty) {
      _snack('Select check-in and check-out.');
      return;
    }

    Navigator.of(context).pop(
      CompleteGuestBookingPayload(
        guestName: name,
        guestEmail: email,
        guestPhone: phone,
        checkIn: _checkInCtrl.text.trim(),
        checkOut: _checkOutCtrl.text.trim(),
        discountType: _discountType,
        paymentMethod: _paymentMethod,
        guestIdFile: _guestIdFile,
        discountIdFile: _discountIdFile,
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nights = (_checkInDate != null && _checkOutDate != null)
        ? _checkOutDate!.difference(_checkInDate!).inDays
        : 0;
    final safeNights = nights > 0 ? nights : 0;
    final estTotal = (_checkInDate != null && _checkOutDate != null)
        ? HourlyBilling.customerDateStayCharge(room, _checkInDate!, _checkOutDate!)
        : 0.0;
    final discountPct = switch (_discountType) {
      'pwd' => 20.0,
      'senior' => 20.0,
      _ => 0.0,
    };
    final estAfterDiscount =
        HourlyBilling.round50(estTotal * (1 - (discountPct / 100)));
    final durationLabel = (_checkInDate != null && _checkOutDate != null)
        ? (HourlyBilling.isHourly(room)
            ? () {
                final inAt = HourlyBilling.customerStayCheckIn(_checkInDate!);
                final outAt = HourlyBilling.customerStayCheckOut(
                  room,
                  _checkInDate!,
                  _checkOutDate!,
                );
                final hours = HourlyBilling.stayHours(inAt, outAt);
                final blocks = HourlyBilling.blocksForStay(
                  hours,
                  HourlyBilling.blockHours(room),
                );
                return '$hours hr(s) · $blocks block(s) of ${HourlyBilling.blockHours(room)}h';
              }()
            : '$safeNights night${safeNights == 1 ? '' : 's'}')
        : '';

    final checkInLabel = config.lockDates
        ? 'Check-in'
        : (config.reserveMode
            ? 'Check-in (from tomorrow)'
            : 'Check-in (today for walk-in)');

    final paymentItems = config.showAdminPaymentMethods
        ? const [
            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
            DropdownMenuItem(value: 'GCash', child: Text('GCash')),
            DropdownMenuItem(value: 'PayMaya', child: Text('PayMaya')),
            DropdownMenuItem(value: 'Credit Card', child: Text('Credit Card')),
          ]
        : const [
            DropdownMenuItem(value: 'Cash', child: Text('Cash at hotel')),
            DropdownMenuItem(value: 'Online', child: Text('Online (QR Ph)')),
          ];

    return AlertDialog(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      title: Text(config.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.summaryTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('guest_party_line', {
                        'rooms': '${config.rooms}',
                        'adults': '${config.adults}',
                        'children': '${config.children}',
                      }),
                    ),
                    if (_checkInDate != null && _checkOutDate != null)
                      Text(
                        '${_fmtDate(_checkInDate!)} → ${_fmtDate(_checkOutDate!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      HourlyBilling.priceLabel(room),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppInput(
              controller: _nameCtrl,
              label: context.tr('full_name'),
            ),
            const SizedBox(height: 8),
            AppInput(
              controller: _emailCtrl,
              label: context.tr('email_gmail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            AppInput(
              controller: _phoneCtrl,
              label: context.tr('phone_number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final file = await ChatAttachment.pick(context);
                if (file != null) setState(() => _guestIdFile = file);
              },
              icon: const Icon(Icons.credit_card_outlined),
              label: Text(
                _guestIdFile == null
                    ? 'Upload government ID *'
                    : 'ID attached — tap to replace',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _discountType,
              decoration: const InputDecoration(
                labelText: 'Discount (optional)',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('No discount')),
                DropdownMenuItem(value: 'pwd', child: Text('PWD (20% off)')),
                DropdownMenuItem(
                  value: 'senior',
                  child: Text('Senior citizen (20% off)'),
                ),
              ],
              onChanged: (v) => setState(() {
                _discountType = v ?? 'none';
                if (_discountType == 'none') _discountIdFile = null;
              }),
            ),
            if (_discountType != 'none') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final file = await ChatAttachment.pick(context);
                  if (file != null) setState(() => _discountIdFile = file);
                },
                icon: const Icon(Icons.badge_outlined),
                label: Text(
                  _discountIdFile == null
                      ? 'Upload discount ID photo'
                      : 'Discount ID attached — tap to replace',
                ),
              ),
            ],
            const SizedBox(height: 8),
            AppInput(
              controller: _checkInCtrl,
              label: checkInLabel,
              hint: config.lockDates ? null : 'Tap to open calendar',
              readOnly: true,
              onTap: config.lockDates ? null : _pickCheckIn,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
            const SizedBox(height: 8),
            AppInput(
              controller: _checkOutCtrl,
              label: 'Check-out date',
              hint: config.lockDates ? null : 'Tap to open calendar',
              readOnly: true,
              onTap: config.lockDates ? null : _pickCheckOut,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
            if (config.showOnlinePayment || config.showAdminPaymentMethods) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder(),
                ),
                items: paymentItems,
                onChanged: (v) async {
                  final next = v ?? 'Cash';
                  setState(() => _paymentMethod = next);
                  if (next == 'Online' &&
                      config.showOnlinePayment &&
                      _paymentQrUrl.isEmpty) {
                    await _loadPaymentQr();
                  }
                },
              ),
              if (_paymentMethod == 'Online' && config.showOnlinePayment) ...[
                const SizedBox(height: 12),
                if (_qrLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_paymentQrUrl.isEmpty)
                  const Text(
                    'Hotel has not uploaded a payment QR yet. You may still submit — pay at the desk if needed.',
                    style: TextStyle(fontSize: 12),
                  )
                else
                  Center(
                    child: Column(
                      children: [
                        const Text(
                          'Scan to pay via GCash / Maya / QR Ph',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        NetworkMediaImage(
                          url: _paymentQrUrl,
                          width: 200,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                config.reserveMode
                    ? 'The hotel will approve your dates. You will be notified when the stay is activated on check-in day.'
                    : 'Duration: $durationLabel\n'
                        'Estimated: ₱${estTotal.toStringAsFixed(2)}'
                        '${discountPct > 0 ? ' → ₱${estAfterDiscount.toStringAsFixed(2)} after discount' : ''}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppPrimaryButton(
          label: config.reserveMode ? 'Submit request' : 'Submit booking',
          onPressed: _submit,
        ),
      ],
    );
  }
}
