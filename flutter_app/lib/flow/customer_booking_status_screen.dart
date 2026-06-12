import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/chat_attachment.dart';

/// Polls reservation status until approved/rejected; shows room ticket when confirmed.
class CustomerBookingStatusScreen extends StatefulWidget {
  const CustomerBookingStatusScreen({
    super.key,
    required this.hotelId,
    required this.hotelName,
    required this.reference,
    required this.guestEmail,
    this.initialReservation,
  });

  final String hotelId;
  final String hotelName;
  final String reference;
  final String guestEmail;
  /// Snapshot from POST /customer/reservations — used when poll API is unavailable.
  final Map<String, dynamic>? initialReservation;

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
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/reservations/${widget.reference}',
        queryParameters: {
          'hotel_id': widget.hotelId,
          'guest_email': widget.guestEmail,
        },
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
    final s = (_reservation?['status'] ?? '').toString();
    return s == 'approved' || s == 'reserved' || s == 'booked';
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = (_reservation?['status'] ?? 'pending_approval').toString();

    return AppScaffold(
      appBar: AppBar(title: const Text('Booking status')),
      body: _error != null && _reservation == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
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
                          'Processing your booking',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Reference ${widget.reference}\n'
                          'Waiting for ${widget.hotelName} to approve your stay.',
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
                    'Booking not approved',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please contact the hotel front desk for assistance.',
                  ),
                ],
                if (_isApproved) ...[
                  Icon(Icons.check_circle_outline,
                      size: 72, color: Colors.green.shade600),
                  const SizedBox(height: 12),
                  Text(
                    'Booking confirmed!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade700,
                        ),
                  ),
                  const SizedBox(height: 20),
                  _TicketCard(
                    reservation: _reservation!,
                    hotelName: widget.hotelName,
                  ),
                ],
                if (_pollUnavailable && !_isApproved && !_isRejected) ...[
                  Card(
                    color: scheme.surfaceContainerHighest,
                    child: const ListTile(
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('Live status updates unavailable'),
                      subtitle: Text(
                        'Your request was submitted. Save your reference and '
                        'contact the hotel — they will confirm by email or phone.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_isApproved && !_isRejected) ...[
                  if (_isOnlinePayment) ...[
                    const SizedBox(height: 16),
                    _OnlinePaymentPendingCard(
                      hotelId: widget.hotelId,
                      reservation: _reservation!,
                    ),
                  ],
                  const SizedBox(height: 32),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text('Status: ${_label(status)}'),
                      subtitle: const Text(
                        'You can leave this screen open — it updates automatically.',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
  }

  String _label(String status) {
    return switch (status) {
      'pending_approval' => 'Pending approval',
      'approved' => 'Approved',
      'reserved' => 'Reserved',
      'booked' => 'Confirmed',
      'rejected' => 'Rejected',
      _ => status,
    };
  }
}

class _OnlinePaymentPendingCard extends StatefulWidget {
  const _OnlinePaymentPendingCard({
    required this.hotelId,
    required this.reservation,
  });

  final String hotelId;
  final Map<String, dynamic> reservation;

  @override
  State<_OnlinePaymentPendingCard> createState() =>
      _OnlinePaymentPendingCardState();
}

class _OnlinePaymentPendingCardState extends State<_OnlinePaymentPendingCard> {
  String _qrUrl = '';
  bool _loadingQr = true;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    if (widget.hotelId.isEmpty) {
      setState(() => _loadingQr = false);
      return;
    }
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/customer/payment-qr',
        queryParameters: {'hotel_id': widget.hotelId},
      );
      if (!mounted) return;
      setState(() {
        _qrUrl = (res.data?['qr_url'] ?? '').toString();
        _loadingQr = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingQr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paymentRef = (widget.reservation['payment_reference'] ?? '').toString();
    final total = (widget.reservation['estimated_total'] as num?)?.toDouble() ?? 0;

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Complete online payment',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (paymentRef.isNotEmpty)
              SelectableText(
                'Reference: $paymentRef',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (total > 0) ...[
              const SizedBox(height: 4),
              Text('Amount: ₱${total.toStringAsFixed(0)}'),
            ],
            const SizedBox(height: 8),
            const Text(
              'Pay via GCash, Maya, or QR Ph using the hotel QR below. '
              'The hotel will verify your payment reference when approving.',
            ),
            if (_loadingQr)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_qrUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: NetworkMediaImage(
                  url: _qrUrl,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ],
        ),
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
              'ROOM TICKET',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.4,
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Divider(height: 24),
            _row('Hotel', hotelName),
            _row('Guest', '${reservation['guest_name']}'),
            _row('Room', 'Room ${reservation['room_number']}'),
            _row('Check-in', '${reservation['check_in_date']}'),
            _row('Check-out', '${reservation['check_out_date']}'),
            _row('Reservation', resRef),
            if (bookingRef.isNotEmpty) _row('Booking ref', bookingRef),
            _row('Payment', paymentMethod),
            if (paymentMethod.toLowerCase() == 'online' && paymentRef.isNotEmpty)
              _row('Payment reference', paymentRef, highlight: true),
            if ((reservation['estimated_total'] as num?) != null &&
                (reservation['estimated_total'] as num) > 0)
              _row(
                'Total',
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
