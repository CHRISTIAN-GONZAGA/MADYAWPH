import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
class CustomerToolsScreen extends StatelessWidget {
  const CustomerToolsScreen({super.key, required this.hotelId});

  final String hotelId;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Customer tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_search_outlined),
              title: const Text('Track booking by reference'),
              subtitle: const Text(
                  'Find booking details using reference + email/phone'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TrackBookingScreen(hotelId: hotelId),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('OTP verification'),
              subtitle: const Text('Send OTP via SMS and verify'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const OtpScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrackBookingScreen extends StatefulWidget {
  const TrackBookingScreen({super.key, required this.hotelId});

  final String hotelId;

  @override
  State<TrackBookingScreen> createState() => _TrackBookingScreenState();
}

class _TrackBookingScreenState extends State<TrackBookingScreen> {
  final _ref = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
  Map<String, dynamic>? _booking;
  bool _busy = false;

  @override
  void dispose() {
    _ref.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final ref = _ref.text.trim();
    if (ref.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _booking = null;
    });
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/bookings/$ref',
        queryParameters: {
          'hotel_id': widget.hotelId,
          if (_email.text.trim().isNotEmpty) 'guest_email': _email.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'guest_phone': _phone.text.trim(),
        },
      );
      setState(() {
        _booking = res.data;
        _busy = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _downloadPdf() async {
    final ref = _ref.text.trim();
    if (ref.isEmpty) return;
    // This triggers a download in browser contexts. On mobile, you’d typically
    // open in an external browser or use a PDF viewer plugin.
    // For now, we just hit the endpoint to verify it exists.
    try {
      await publicDio().get<List<int>>(
        '/bookings/$ref/pdf',
        queryParameters: {
          'hotel_id': widget.hotelId,
          if (_email.text.trim().isNotEmpty) 'guest_email': _email.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'guest_phone': _phone.text.trim(),
        },
        options: Options(responseType: ResponseType.bytes),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'PDF endpoint reachable. (Integrate viewer/download next)')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Track booking')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppInput(
            controller: _ref,
            label: 'Booking reference',
            hint: 'e.g. BK2026...',
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _email,
            label: 'Guest email (optional)',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _phone,
            label: 'Guest phone (optional)',
            keyboardType: TextInputType.phone,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  label: 'Lookup',
                  onPressed: _busy ? null : _lookup,
                  isLoading: _busy,
                ),
              ),
              const SizedBox(width: 10),
              AppSecondaryButton(
                label: 'PDF',
                onPressed: _downloadPdf,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_booking != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_booking?['booking_reference'] ?? '').toString(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Guest: ${(_booking?['guest_name'] ?? '').toString()}'),
                    Text(
                        'Phone: ${(_booking?['guest_phone'] ?? '').toString()}'),
                    Text(
                        'Email: ${(_booking?['guest_email'] ?? '').toString()}'),
                    Text('Room ID: ${(_booking?['room_id'] ?? '').toString()}'),
                    Text(
                        'Check-in: ${(_booking?['check_in_date'] ?? '').toString()}'),
                    Text(
                        'Check-out: ${(_booking?['check_out_date'] ?? '').toString()}'),
                    Text('Status: ${(_booking?['status'] ?? '').toString()}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await publicDio().post('/otp/send', data: {'phone': phone});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('OTP sent.')));
    } on DioException catch (e) {
      setState(() => _error = dioErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final phone = _phone.text.trim();
    final otp = _otp.text.trim();
    if (phone.isEmpty || otp.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await publicDio().post<Map<String, dynamic>>('/otp/verify',
          data: {'phone': phone, 'otp': otp});
      final ok = res.data?['ok'] == true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'OTP verified.' : 'OTP invalid.')),
      );
    } on DioException catch (e) {
      setState(() => _error = dioErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('OTP verification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppInput(
            controller: _phone,
            label: 'Phone',
            hint: 'E.164 e.g. +63917xxxxxxx',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          AppInput(
            controller: _otp,
            label: 'OTP (6 digits)',
            keyboardType: TextInputType.number,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  label: 'Send OTP',
                  onPressed: _busy ? null : _send,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppSecondaryButton(
                  label: 'Verify',
                  onPressed: _busy ? null : _verify,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
