import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/chat_attachment.dart';

/// Guest membership registration (₱300/month, QR Ph, platform approval).
class MemberRegistrationScreen extends StatefulWidget {
  const MemberRegistrationScreen({super.key});

  @override
  State<MemberRegistrationScreen> createState() =>
      _MemberRegistrationScreenState();
}

class _MemberRegistrationScreenState extends State<MemberRegistrationScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String? _qrUrl;
  double _fee = 300;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadPlatform();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlatform() async {
    try {
      final res = await publicDio().get<Map<String, dynamic>>('/platform/info');
      setState(() {
        _fee = (res.data?['member_monthly_fee'] as num?)?.toDouble() ?? 300;
        _qrUrl = ChatAttachment.resolveMediaUrl(
          (res.data?['member_subscription_qr_url'] ?? '').toString(),
        );
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _refCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/member/register',
        data: {
          'full_name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'payment_reference': _refCtrl.text.trim(),
        },
      );
      final requestId = (res.data?['request_id'] ?? '').toString();
      if (!mounted || requestId.isEmpty) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MemberProcessingScreen(requestId: requestId),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      appBar: AppBar(title: const Text('Become a member')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'MADYAWPH Member',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₱${_fee.toStringAsFixed(0)} / month — exclusive deals and priority support.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                if (_qrUrl != null && _qrUrl!.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'Scan to pay via QR Ph',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: NetworkMediaImage(
                              url: _qrUrl!,
                              width: 220,
                              height: 220,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                AppInput(controller: _nameCtrl, label: 'Full name'),
                const SizedBox(height: 12),
                AppInput(
                  controller: _emailCtrl,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                AppInput(
                  controller: _phoneCtrl,
                  label: 'Phone number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                AppInput(
                  controller: _refCtrl,
                  label: 'Payment reference / transaction ID',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Register'),
                ),
              ],
            ),
    );
  }
}

class MemberProcessingScreen extends StatefulWidget {
  const MemberProcessingScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<MemberProcessingScreen> createState() => _MemberProcessingScreenState();
}

class _MemberProcessingScreenState extends State<MemberProcessingScreen> {
  Timer? _timer;
  String _status = 'pending';
  String? _validUntil;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final res = await publicDio().get<Map<String, dynamic>>(
        '/member/requests/${widget.requestId}/status',
      );
      if (!mounted) return;
      setState(() {
        _status = (res.data?['status'] ?? 'pending').toString();
        _validUntil = (res.data?['member_valid_until'] ?? '').toString();
      });
      if (_status == 'approved' || _status == 'rejected') {
        _timer?.cancel();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final approved = _status == 'approved';
    final rejected = _status == 'rejected';

    return AppScaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!approved && !rejected) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Processing your membership',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We are verifying your payment. This usually takes a short while.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ] else if (approved) ...[
                Icon(Icons.verified_outlined, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Welcome, member!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if ((_validUntil ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Active until $_validUntil'),
                  ),
              ] else ...[
                Icon(Icons.cancel_outlined, size: 64, color: scheme.error),
                const SizedBox(height: 16),
                const Text('Membership not approved'),
                const SizedBox(height: 8),
                const Text('Contact support if you believe this is an error.'),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
