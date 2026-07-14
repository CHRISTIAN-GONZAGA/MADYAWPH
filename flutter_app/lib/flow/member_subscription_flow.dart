import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../dio_client.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/chat_attachment.dart';
import 'member_login_screen.dart';

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
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _password2Ctrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String _memberQrRaw = '';
  double _fee = 300;
  double _discountPercent = 10;
  int _pointsPerBooking = 1000;
  double _pointsPerPeso = 10;
  bool _loading = true;
  bool _submitting = false;

  String get _memberQrUrl => _memberQrRaw.trim().isEmpty
      ? ''
      : ChatAttachment.resolveMediaUrl(_memberQrRaw);

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
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _password2Ctrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlatform() async {
    setState(() => _loading = true);
    try {
      final res = await publicDio().get<Map<String, dynamic>>('/platform/info');
      final raw = res.data?['member_subscription_qr_url'];
      setState(() {
        _fee = (res.data?['member_monthly_fee'] as num?)?.toDouble() ?? 300;
        _discountPercent =
            (res.data?['member_booking_discount_percent'] as num?)
                    ?.toDouble() ??
                10;
        _pointsPerBooking =
            ((res.data?['member_points_per_check_in'] as num?)?.toDouble() ??
                    1000)
                .round();
        _pointsPerPeso =
            (res.data?['member_points_per_peso'] as num?)?.toDouble() ?? 10;
        _memberQrRaw = raw == null ? '' : '$raw'.trim();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _showQrPhDialog() {
    final url = _memberQrUrl;
    if (url.isEmpty) {
      showAppMessage(context, 'QR Ph image is not available yet. Ask platform support or try again later.',);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay via QR Ph'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan with your bank or e-wallet app to pay '
                '₱${_fee.toStringAsFixed(0)} for membership.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: NetworkMediaImage(
                  url: url,
                  width: 280,
                  height: 280,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'After paying, enter your transaction reference below and tap Register.',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _usernameCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty ||
        _refCtrl.text.trim().isEmpty) {
      showAppMessage(context, 'Please complete all fields.');
      return;
    }
    if (_passwordCtrl.text != _password2Ctrl.text) {
      showAppMessage(context, 'Passwords do not match.', isError: true);
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      showAppMessage(context, 'Password must be at least 6 characters.', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final username = _usernameCtrl.text.trim().toLowerCase();
      final password = _passwordCtrl.text;
      final res = await publicDio().post<Map<String, dynamic>>(
        '/member/register',
        data: {
          'full_name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'username': username,
          'password': password,
          'password_confirmation': password,
          'payment_reference': _refCtrl.text.trim(),
        },
      );
      final requestId = (res.data?['request_id'] ?? '').toString();
      if (!mounted || requestId.isEmpty) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MemberProcessingScreen(
            requestId: requestId,
            username: username,
            password: password,
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
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
          : RefreshIndicator(
              onRefresh: _loadPlatform,
              child: ListView(
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
                    '₱${_fee.toStringAsFixed(0)} / month — unlock member rates, points, and your digital membership ID.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 20),
                  _MemberBenefitsCard(
                    fee: _fee,
                    discountPercent: _discountPercent,
                    pointsPerBooking: _pointsPerBooking,
                    pointsPerPeso: _pointsPerPeso,
                  ),
                  const SizedBox(height: 20),
                  _MemberQrPhPaymentCard(
                    fee: _fee,
                    qrUrl: _memberQrUrl,
                    onShowQr: _showQrPhDialog,
                    onRefresh: _loadPlatform,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your details',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
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
                  controller: _usernameCtrl,
                  label: 'Username (for member log-in)',
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                AppPasswordField(
                  controller: _passwordCtrl,
                  labelText: 'Password',
                ),
                const SizedBox(height: 12),
                AppPasswordField(
                  controller: _password2Ctrl,
                  labelText: 'Confirm password',
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
            ),
    );
  }
}

class _MemberBenefitsCard extends StatelessWidget {
  const _MemberBenefitsCard({
    required this.fee,
    required this.discountPercent,
    required this.pointsPerBooking,
    required this.pointsPerPeso,
  });

  final double fee;
  final double discountPercent;
  final int pointsPerBooking;
  final double pointsPerPeso;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final discountLabel = discountPercent > 0
        ? '${discountPercent.toStringAsFixed(discountPercent % 1 == 0 ? 0 : 1)}% off room bookings'
        : 'Member booking rates when the platform discount is active';
    final pointsRate = pointsPerPeso % 1 == 0
        ? pointsPerPeso.toStringAsFixed(0)
        : pointsPerPeso.toStringAsFixed(1);

    final benefits = <({IconData icon, String title, String detail})>[
      (
        icon: Icons.percent_outlined,
        title: discountLabel,
        detail:
            'Sign in as a member when you book — your discount applies automatically. No membership ID typing needed.',
      ),
      (
        icon: Icons.stars_outlined,
        title: 'Earn $pointsPerBooking points per successful booking',
        detail:
            'Points go to your wallet after each successful member booking ($pointsRate pts = ₱1).',
      ),
      (
        icon: Icons.payments_outlined,
        title: 'Pay stays with points',
        detail:
            'Hotels can scan your QR and redeem points toward your bill; peso value credits the hotel wallet.',
      ),
      (
        icon: Icons.qr_code_2_outlined,
        title: 'Personal membership QR & SHID',
        detail:
            'Show your unique QR or membership ID at the front desk for member rates and points payment.',
      ),
      (
        icon: Icons.travel_explore_outlined,
        title: 'Member dashboard',
        detail:
            'Browse hotels, manage your membership, and keep your QR ready from one place.',
      ),
      (
        icon: Icons.verified_user_outlined,
        title: 'Active monthly membership',
        detail:
            '₱${fee.toStringAsFixed(0)} / month after platform approval of your registration payment.',
      ),
    ];

    return Card(
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What you get as a member',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Benefits use the current platform settings and apply while your membership is active.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 8),
            for (final b in benefits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(b.icon, color: scheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            b.detail,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberQrPhPaymentCard extends StatelessWidget {
  const _MemberQrPhPaymentCard({
    required this.fee,
    required this.qrUrl,
    required this.onShowQr,
    required this.onRefresh,
  });

  final double fee;
  final String qrUrl;
  final VoidCallback onShowQr;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQr = qrUrl.isNotEmpty;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pay with QR Ph',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '1. Scan the platform QR Ph code (₱${fee.toStringAsFixed(0)})\n'
              '2. Copy your transaction reference\n'
              '3. Complete the form below and register',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 16),
            Center(
              child: hasQr
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: onShowQr,
                          child: NetworkMediaImage(
                            url: qrUrl,
                            width: 180,
                            height: 180,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 180,
                      height: 180,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_outlined,
                            size: 48,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'QR Ph image not set yet',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasQr ? onShowQr : null,
                    icon: const Icon(Icons.fullscreen_outlined),
                    label: const Text('Show QR Ph'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Refresh QR',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MemberProcessingScreen extends StatefulWidget {
  const MemberProcessingScreen({
    super.key,
    required this.requestId,
    this.username = '',
    this.password = '',
  });

  final String requestId;
  final String username;
  final String password;

  @override
  State<MemberProcessingScreen> createState() => _MemberProcessingScreenState();
}

class _MemberProcessingScreenState extends State<MemberProcessingScreen> {
  Timer? _timer;
  String _status = 'pending';
  String? _validUntil;
  double _memberDiscountPercent = 0;
  bool _openingDashboard = false;

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
        _memberDiscountPercent =
            (res.data?['member_discount_percent'] as num?)?.toDouble() ?? 0;
      });
      if (_status == 'approved' || _status == 'rejected') {
        _timer?.cancel();
      }
    } catch (_) {}
  }

  Future<void> _openMemberDashboard() async {
    if (_openingDashboard) return;
    setState(() => _openingDashboard = true);
    try {
      if (widget.username.isNotEmpty && widget.password.isNotEmpty) {
        if (!mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => MemberLoginScreen(
              initialUsername: widget.username,
              autoPassword: widget.password,
            ),
          ),
          (route) => route.isFirst,
        );
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MemberLoginScreen(initialUsername: widget.username),
        ),
        (route) => route.isFirst,
      );
    } finally {
      if (mounted) setState(() => _openingDashboard = false);
    }
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
                const SizedBox(height: 12),
                Text(
                  'Your membership is approved. Log in to your member dashboard to browse hotels and show your unique membership QR / ID for discounts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (_memberDiscountPercent > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${_memberDiscountPercent.toStringAsFixed(0)}% off room bookings while active',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                if ((_validUntil ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Valid until ${_formatValidUntil(_validUntil!)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _openingDashboard ? null : _openMemberDashboard,
                  icon: _openingDashboard
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.dashboard_outlined),
                  label: Text(
                    _openingDashboard ? 'Opening…' : 'Open member dashboard',
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Back to home'),
                ),
              ] else ...[
                Icon(Icons.cancel_outlined, size: 64, color: scheme.error),
                const SizedBox(height: 16),
                const Text('Membership not approved'),
                const SizedBox(height: 8),
                const Text('Contact support if you believe this is an error.'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatValidUntil(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}
