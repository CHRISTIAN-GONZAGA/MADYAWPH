import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../locale_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/guest_online_payment.dart';

/// Maps instant `/customer/bookings` response + room row for the status ticket UI.
Map<String, dynamic> instantBookingStatusPayload({
  required Map<String, dynamic> booking,
  required Map<String, dynamic> room,
}) {
  return {
    'status': 'confirmed',
    'guest_name': booking['guest_name'],
    'guest_email': booking['guest_email'],
    'guest_phone': booking['guest_phone'],
    'check_in_date': booking['check_in_date'],
    'check_out_date': booking['check_out_date'],
    'room_number': room['room_number'] ?? booking['room_number'],
    'room_display_name': room['display_name'] ?? room['room_display_name'],
    'booking_reference': booking['booking_reference'],
    'external_reference': booking['booking_reference'],
    'payment_method': booking['payment_method'] ?? 'Cash',
    'estimated_total': booking['total_amount'],
  };
}

/// Polls reservation status until approved/rejected; shows room ticket when confirmed.
class CustomerBookingStatusScreen extends StatefulWidget {
  const CustomerBookingStatusScreen({
    super.key,
    required this.hotelId,
    required this.hotelName,
    required this.reference,
    this.guestEmail = '',
    this.guestPhone = '',
    this.initialReservation,
    this.instantBooking = false,
  });

  final String hotelId;
  final String hotelName;
  final String reference;
  final String guestEmail;
  final String guestPhone;
  /// Snapshot from POST /customer/reservations or instant /customer/bookings.
  final Map<String, dynamic>? initialReservation;
  /// Same-day instant booking — confirmed immediately, no reservation poll.
  final bool instantBooking;

  @override
  State<CustomerBookingStatusScreen> createState() =>
      _CustomerBookingStatusScreenState();
}

class _CustomerBookingStatusScreenState
    extends State<CustomerBookingStatusScreen> {
  Map<String, dynamic>? _reservation;
  String? _error;
  Timer? _poll;
  bool _pollUnavailable = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialReservation;
    if (initial != null && initial.isNotEmpty) {
      _reservation = Map<String, dynamic>.from(initial);
    }
    if (!widget.instantBooking) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (widget.instantBooking) return;
    try {
      final query = <String, dynamic>{'hotel_id': widget.hotelId};
      if (widget.guestEmail.trim().isNotEmpty) {
        query['guest_email'] = widget.guestEmail.trim();
      }
      if (widget.guestPhone.trim().isNotEmpty) {
        query['guest_phone'] = widget.guestPhone.trim();
      }
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/reservations/${widget.reference}',
        queryParameters: query,
      );
      if (!mounted) return;
      setState(() {
        _reservation = res.data?['reservation'] as Map<String, dynamic>?;
        _error = null;
      });
      _maybeStopPolling();
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      if (code == 404 && _reservation != null) {
        setState(() {
          _pollUnavailable = true;
          _error = null;
        });
        _poll?.cancel();
        _poll = null;
        return;
      }
      if (silent) return;
      setState(() => _error = dioErrorMessage(e));
    }
  }

  bool get _isApproved {
    if (widget.instantBooking && _reservation != null) return true;
    final s = (_reservation?['status'] ?? '').toString().toLowerCase();
    return s == 'approved' ||
        s == 'reserved' ||
        s == 'booked' ||
        s == 'confirmed';
  }

  bool get _showFullTicket {
    if (widget.instantBooking) return true;
    final s = (_reservation?['status'] ?? '').toString().toLowerCase();
    if (s == 'booked' || s == 'confirmed') return true;
    final bookingRef =
        (_reservation?['booking_reference'] ?? '').toString().trim();
    return bookingRef.isNotEmpty;
  }

  bool get _isApprovedHold {
    if (widget.instantBooking) return false;
    final s = (_reservation?['status'] ?? '').toString().toLowerCase();
    return (s == 'approved' || s == 'reserved') && !_showFullTicket;
  }

  bool get _isRejected => (_reservation?['status'] ?? '') == 'rejected';

  void _maybeStopPolling() {
    if ((_isApproved || _isRejected) && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  bool get _isOnlinePayment {
    final method = (_reservation?['payment_method'] ?? '').toString();
    return method.toLowerCase() == 'online';
  }

  bool get _needsOnlinePayment {
    if (!_isOnlinePayment || _reservation == null) return false;
    if (_reservation!['needs_online_payment'] is bool) {
      return _reservation!['needs_online_payment'] == true;
    }
    final status = (_reservation!['payment_status'] ?? '').toString().toLowerCase();
    final paid = (_reservation!['amount_paid'] as num?)?.toDouble() ?? 0;
    final due = (_reservation!['deposit_required'] as num?)?.toDouble();
    final total = (_reservation!['estimated_total'] as num?)?.toDouble() ?? 0;
    const settled = {
      'paid',
      'deposit_paid',
      'paid_pending_approval',
      'deposit_pending_approval',
    };
    final target = (due != null && due > 0) ? due : total;
    if (settled.contains(status) && paid + 0.009 >= target) {
      return false;
    }
    if (target > 0) return paid + 0.009 < target;
    return !settled.contains(status);
  }

  bool get _isProcessing => !_isApproved && !_isRejected;

  Future<bool> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('leave_booking_title')),
        content: Text(context.tr('leave_booking_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('stay_on_screen')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('leave_screen')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = (_reservation?['status'] ?? 'pending_approval').toString();

    return LocaleScope(
      builder: (context, _) => PopScope(
        canPop: !_isProcessing,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmLeave() && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: AppScaffold(
      appBar: AppBar(title: Text(context.tr('booking_status'))),
      body: _error != null && _reservation == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('retry')),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (_needsOnlinePayment && _reservation != null) ...[
                  GuestOnlinePaymentPendingCard(
                    hotelId: widget.hotelId,
                    reference: widget.reference,
                    reservation: _reservation!,
                    guestEmail: widget.guestEmail,
                    guestPhone: widget.guestPhone,
                    onPaymentStarted: () => _load(silent: true),
                  ),
                  const SizedBox(height: 20),
                ],
                if (!_isApproved && !_isRejected) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          context.tr('processing_booking'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${context.tr('reference_label', {'ref': widget.reference})}\n'
                          '${context.tr('waiting_approval', {'hotel': widget.hotelName})}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isRejected) ...[
                  Icon(Icons.cancel_outlined, size: 64, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('booking_rejected'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(context.tr('contact_front_desk')),
                ],
                if (_isApproved) ...[
                  Icon(Icons.check_circle_outline,
                      size: 72, color: Colors.green.shade600),
                  const SizedBox(height: 12),
                  Text(
                    _isApprovedHold
                        ? 'Reservation approved'
                        : context.tr('booking_confirmed'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade700,
                        ),
                  ),
                    if (_isApprovedHold) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Your room is reserved for ${_reservation?['check_in_date']}. '
                      'Check-in details will be available once your stay is activated.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_showFullTicket)
                    _TicketCard(
                      reservation: _reservation!,
                      hotelName: widget.hotelName,
                    )
                  else
                    _ReservationSummaryCard(
                      reservation: _reservation!,
                      hotelName: widget.hotelName,
                    ),
                ],
                if (_pollUnavailable && !_isApproved && !_isRejected) ...[
                  Card(
                    color: scheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: Text(context.tr('live_status_unavailable')),
                      subtitle: Text(context.tr('live_status_unavailable_sub')),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_isApproved && !_isRejected && !_needsOnlinePayment) ...[
                  const SizedBox(height: 32),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(
                        context.tr('status_colon', {'status': _label(context, status)}),
                      ),
                      subtitle: Text(context.tr('updates_automatically')),
                    ),
                  ),
                ],
              ],
            ),
          ),
    ),
      ),
    );
  }

  String _label(BuildContext context, String status) {
    return switch (status) {
      'pending_approval' => context.tr('status_pending_approval'),
      'approved' => context.tr('status_approved'),
      'reserved' => context.tr('status_reserved'),
      'booked' => context.tr('status_confirmed'),
      'confirmed' => context.tr('status_confirmed'),
      'rejected' => context.tr('status_rejected'),
      _ => status,
    };
  }
}

class _ReservationSummaryCard extends StatelessWidget {
  const _ReservationSummaryCard({
    required this.reservation,
    required this.hotelName,
  });

  final Map<String, dynamic> reservation;
  final String hotelName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resRef = (reservation['external_reference'] ?? '').toString();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reservation summary',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Divider(height: 24),
            _row(context.tr('lbl_hotel'), hotelName),
            _row(context.tr('lbl_guest'), '${reservation['guest_name']}'),
            _row(context.tr('lbl_room'), 'Room ${reservation['room_number']}'),
            _row(context.tr('lbl_checkin'), '${reservation['check_in_date']}'),
            _row(context.tr('lbl_checkout'), '${reservation['check_out_date']}'),
            _row(context.tr('lbl_reservation'), resRef),
            if ((reservation['payment_status_label'] ?? '').toString().isNotEmpty)
              _row(
                'Payment status',
                (reservation['payment_status_label'] ?? '').toString(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.reservation, required this.hotelName});

  final Map<String, dynamic> reservation;
  final String hotelName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paymentMethod =
        (reservation['payment_method'] ?? 'Cash').toString();
    final paymentRef = (reservation['payment_reference'] ?? '').toString();
    final bookingRef = (reservation['booking_reference'] ?? '').toString();
    final resRef = (reservation['external_reference'] ?? '').toString();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('room_ticket'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.4,
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Divider(height: 24),
            _row(context.tr('lbl_hotel'), hotelName),
            _row(context.tr('lbl_guest'), '${reservation['guest_name']}'),
            _row(context.tr('lbl_room'), 'Room ${reservation['room_number']}'),
            if ((reservation['stay_summary'] ?? '').toString().isNotEmpty)
              _row('Stay', (reservation['stay_summary'] ?? '').toString()),
            _row(context.tr('lbl_checkin'), '${reservation['check_in_date']}'),
            _row(context.tr('lbl_checkout'), '${reservation['check_out_date']}'),
            _row(context.tr('lbl_reservation'), resRef),
            if (bookingRef.isNotEmpty)
              _row(context.tr('lbl_booking_ref'), bookingRef),
            _row(context.tr('lbl_payment'), paymentMethod),
            if (paymentMethod.toLowerCase() == 'online' && paymentRef.isNotEmpty)
              _row(context.tr('lbl_payment_ref'), paymentRef, highlight: true),
            if ((reservation['payment_status_label'] ?? '').toString().isNotEmpty)
              _row(
                'Payment status',
                (reservation['payment_status_label'] ?? '').toString(),
                highlight: true,
              ),
            if ((reservation['estimated_total'] as num?) != null &&
                (reservation['estimated_total'] as num) > 0)
              _row(
                context.tr('lbl_total'),
                '₱${(reservation['estimated_total'] as num).toStringAsFixed(0)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                color: highlight ? Colors.green.shade800 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
