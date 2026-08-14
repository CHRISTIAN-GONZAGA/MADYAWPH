import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import '../../dio_client.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';
import '../../widgets/payment_redirect.dart';

/// Upload QR Ph for online guest payments, set wallet numbers, verify refs,
/// and connect the hotel PayMongo merchant account.
class AdminOnlinePaymentScreen extends StatefulWidget {
  const AdminOnlinePaymentScreen({super.key});

  @override
  State<AdminOnlinePaymentScreen> createState() =>
      _AdminOnlinePaymentScreenState();
}

class _AdminOnlinePaymentScreenState extends State<AdminOnlinePaymentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _qrUrl;
  bool _loadingQr = true;
  bool _uploading = false;
  bool _savingNumbers = false;
  final _refCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _mayaCtrl = TextEditingController();
  final _pmSecretCtrl = TextEditingController();
  final _pmPublicCtrl = TextEditingController();
  final _pmInviteEmailCtrl = TextEditingController();
  List<Map<String, dynamic>> _refResults = const [];
  bool _searching = false;
  String? _error;
  bool _loadingPaymongo = true;
  bool _connectingPaymongo = false;
  Map<String, dynamic>? _paymongo;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadQr();
    _loadPaymongo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refCtrl.dispose();
    _gcashCtrl.dispose();
    _mayaCtrl.dispose();
    _pmSecretCtrl.dispose();
    _pmPublicCtrl.dispose();
    _pmInviteEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPaymongo() async {
    setState(() => _loadingPaymongo = true);
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/payments/paymongo/status',
      );
      if (!mounted) return;
      setState(() {
        _paymongo = res.data;
        _loadingPaymongo = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPaymongo = false;
        _error ??= dioErrorMessage(e);
      });
    }
  }

  Future<void> _connectPaymongoKeys() async {
    final secret = _pmSecretCtrl.text.trim();
    final public = _pmPublicCtrl.text.trim();
    if (secret.isEmpty || public.isEmpty) {
      showAppMessage(context, 'Enter both PayMongo secret and public keys.', isError: true);
      return;
    }
    setState(() => _connectingPaymongo = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/payments/paymongo/connect',
        data: {
          'connection_type': 'api_keys',
          'secret_key': secret,
          'public_key': public,
        },
      );
      if (!mounted) return;
      _pmSecretCtrl.clear();
      _pmPublicCtrl.clear();
      showAppMessage(context, (res.data?['message'] ?? 'PayMongo connected.').toString());
      await _loadPaymongo();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  Future<void> _connectPaymongoInvite() async {
    final email = _pmInviteEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showAppMessage(context, 'Enter a valid invite email.', isError: true);
      return;
    }
    setState(() => _connectingPaymongo = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/payments/paymongo/connect',
        data: {
          'connection_type': 'linked_account',
          'invite_email': email,
        },
      );
      if (!mounted) return;
      showAppMessage(context, (res.data?['message'] ?? 'Invite created.').toString());
      await _loadPaymongo();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  Future<void> _refreshPaymongoLink() async {
    setState(() => _connectingPaymongo = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/payments/paymongo/refresh-link',
      );
      if (!mounted) return;
      showAppMessage(context, (res.data?['message'] ?? 'Status updated.').toString());
      await _loadPaymongo();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  Future<void> _disconnectPaymongo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect PayMongo?'),
        content: const Text(
          'Guests will no longer be redirected to PayMongo checkout until you connect again. Manual QR / wallet numbers can still be used as fallback.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _connectingPaymongo = true);
    try {
      await portalDio().post('/admin/payments/paymongo/disconnect');
      if (!mounted) return;
      showAppMessage(context, 'PayMongo disconnected.');
      await _loadPaymongo();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  Future<void> _startChildOnboarding() async {
    setState(() => _connectingPaymongo = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/payments/paymongo/start-child-onboarding',
      );
      if (!mounted) return;
      await _loadPaymongo();
      final opened = await _openPaymongoOnboardingUrl(res.data);
      if (!mounted) return;
      if (opened) {
        showAppMessage(
          context,
          'Opening PayMongo setup. Complete verification there, then tap Refresh status.',
        );
      } else {
        showAppMessage(
          context,
          (res.data?['message'] ??
                  'PayMongo setup started, but no setup link was returned. Tap Continue PayMongo Setup.')
              .toString(),
          isError: true,
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
      await _loadPaymongo();
      // Even on 422, try opening a URL if the account payload includes one.
      await _openPaymongoOnboardingUrl(e.response?.data is Map
          ? Map<String, dynamic>.from(e.response!.data as Map)
          : null);
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  Future<void> _continueOrOpenOnboarding() async {
    // Always mint/refresh via API — never reopen a cached example.com link.
    await _startChildOnboarding();
  }

  Future<bool> _openPaymongoOnboardingUrl(Map<String, dynamic>? data) async {
    if (data == null) return false;
    final fromTop = (data['redirect_url'] ?? data['onboarding_url'] ?? '')
        .toString()
        .trim();
    if (fromTop.isNotEmpty) {
      return PaymentRedirect.openCheckout(context, fromTop);
    }
    final account = data['account'];
    if (account is Map) {
      final url = (account['onboarding_url'] ?? account['invite_signup_url'] ?? '')
          .toString()
          .trim();
      if (url.isNotEmpty) {
        return PaymentRedirect.openCheckout(context, url);
      }
    }
    return false;
  }

  Future<void> _refreshChildOnboarding() async {
    setState(() => _connectingPaymongo = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/payments/paymongo/refresh-child',
      );
      if (!mounted) return;
      showAppMessage(
        context,
        (res.data?['message'] ?? 'Status updated.').toString(),
      );
      await _loadPaymongo();
      // If still pending and a link was minted, offer to open it.
      final url = (res.data?['redirect_url'] ??
              res.data?['onboarding_url'] ??
              ((_paymongo?['account'] as Map?)?['onboarding_url']) ??
              '')
          .toString()
          .trim();
      if (url.isNotEmpty &&
          !(_paymongo?['payment_ready'] == true ||
              _paymongo?['connected'] == true)) {
        await PaymentRedirect.openCheckout(context, url);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  String _onboardingStatusLabel(String status, {required bool ready}) {
    if (ready || status == 'ACTIVE') return 'Status: Payment Ready';
    switch (status) {
      case 'NOT_STARTED':
        return 'Status: Not Started';
      case 'ONBOARDING':
      case 'REQUIREMENTS_PENDING':
        return 'Status: Setup Required';
      case 'VERIFICATION_PENDING':
        return 'Status: Verification In Progress';
      case 'REJECTED':
        return 'Status: Action Required';
      case 'ONBOARDING_FAILED':
        return 'Status: Setup Failed — Retry';
      case 'DISCONNECTED':
        return 'Status: Disconnected';
      default:
        return 'Status: $status';
    }
  }

  Widget _paymongoCard(ColorScheme scheme) {
    final connected = _paymongo?['connected'] == true ||
        _paymongo?['payment_ready'] == true;
    final account =
        (_paymongo?['account'] as Map?)?.cast<String, dynamic>() ?? const {};
    final envLabel = (_paymongo?['environment_label'] ?? 'TEST').toString();
    final platformSecretMode =
        (_paymongo?['platform_secret_mode'] ?? account['platform_secret_mode'] ?? '')
            .toString();
    final linkedEnabled = _paymongo?['linked_accounts_enabled'] == true;
    final childEnabled = _paymongo?['child_onboarding_enabled'] != false;
    final onboarding =
        (account['onboarding_status'] ?? _paymongo?['onboarding_status'] ?? 'NOT_STARTED')
            .toString();
    final connectedAt = (account['connected_at'] ?? '').toString();
    final activatedAt = (account['activated_at'] ?? '').toString();
    final merchantHint =
        (account['child_merchant_id'] ?? account['merchant_account_id'] ?? '')
            .toString();
    final onboardingUrl = (account['onboarding_url'] ?? '').toString();
    final signupUrl = (account['invite_signup_url'] ?? '').toString();
    final lastError = (account['last_error'] ?? '').toString();
    final needsSetup = !connected &&
        (onboarding == 'NOT_STARTED' ||
            onboarding == 'ONBOARDING_FAILED' ||
            onboarding == 'DISCONNECTED');
    final inProgress = !connected &&
        (onboarding == 'ONBOARDING' ||
            onboarding == 'REQUIREMENTS_PENDING' ||
            onboarding == 'VERIFICATION_PENDING' ||
            onboarding == 'REJECTED');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PAYMENT SETUP · PayMongo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Payment Environment: $envLabel',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _onboardingStatusLabel(onboarding, ready: connected),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: connected
                        ? scheme.primary
                        : onboarding == 'REJECTED' ||
                                onboarding == 'ONBOARDING_FAILED'
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                  ),
            ),
            if (platformSecretMode == 'test' || platformSecretMode == 'missing') ...[
              const SizedBox(height: 8),
              Text(
                platformSecretMode == 'missing'
                    ? 'Server PayMongo secret is missing. Set PAYMONGO_SECRET_KEY (sk_live_…) on Render — keys typed under Advanced do not drive Set Up PayMongo.'
                    : 'Server is still using a TEST PayMongo secret (sk_test_). That often returns example.com mock links. Put sk_live_/pk_live_ in Render env, set PAYMONGO_MODE=production, redeploy.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      height: 1.35,
                    ),
              ),
            ],
            if (merchantHint.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('PayMongo Account: $merchantHint'),
            ],
            if (activatedAt.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Activated: $activatedAt'),
            ] else if (connectedAt.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Started: $connectedAt'),
            ],
            if (lastError.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                lastError,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              connected
                  ? 'Guests pay via PayMongo Hosted Checkout using QR Ph (currently the only active method on this PayMongo account).'
                  : 'Complete PayMongo verification so guests can pay bookings securely with QR Ph. KYC/KYB is handled by PayMongo — we never bypass it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 12),
            if (_loadingPaymongo)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (childEnabled && needsSetup)
                FilledButton(
                  onPressed:
                      _connectingPaymongo ? null : _startChildOnboarding,
                  child: Text(
                    _connectingPaymongo
                        ? 'Starting…'
                        : onboarding == 'ONBOARDING_FAILED'
                            ? 'Retry PayMongo Setup'
                            : 'Set Up PayMongo',
                  ),
                ),
              if (childEnabled && inProgress) ...[
                FilledButton(
                  onPressed: _connectingPaymongo
                      ? null
                      : _continueOrOpenOnboarding,
                  child: Text(
                    onboarding == 'REJECTED'
                        ? 'Continue Setup'
                        : 'Continue PayMongo Setup',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed:
                      _connectingPaymongo ? null : _refreshChildOnboarding,
                  child: const Text('Refresh status'),
                ),
              ],
              if (connected) ...[
                Text(
                  'PayMongo Connected ✓',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                ),
                TextButton(
                  onPressed:
                      _connectingPaymongo ? null : _disconnectPaymongo,
                  child: const Text('Disconnect'),
                ),
              ],
              if (!connected) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Advanced: connect with your own PayMongo API keys',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pmPublicCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Public key (pk_test_… / pk_live_…)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pmSecretCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Secret key (sk_test_… / sk_live_…)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed:
                      _connectingPaymongo ? null : _connectPaymongoKeys,
                  child: Text(
                    _connectingPaymongo
                        ? 'Connecting…'
                        : 'Connect with API keys',
                  ),
                ),
                if (linkedEnabled) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pmInviteEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Linked Accounts invite email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed:
                        _connectingPaymongo ? null : _connectPaymongoInvite,
                    child: const Text('Send Linked Accounts invite'),
                  ),
                  if (signupUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      signupUrl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    OutlinedButton(
                      onPressed:
                          _connectingPaymongo ? null : _refreshPaymongoLink,
                      child: const Text('Refresh invite status'),
                    ),
                  ],
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadQr() async {
    setState(() {
      _loadingQr = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/payment-qr',
      );
      if (!mounted) return;
      setState(() {
        _qrUrl = (res.data?['qr_url'] ?? '').toString();
        _gcashCtrl.text =
            (res.data?['payment_gcash_mobile'] ?? '').toString();
        _mayaCtrl.text = (res.data?['payment_maya_mobile'] ?? '').toString();
        _loadingQr = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loadingQr = false;
      });
    }
  }

  Future<void> _uploadQr() async {
    final file = await ChatAttachment.pick(context);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const {},
        file: file,
        fileField: 'image_file',
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/payment-qr',
        data: form,
      );
      if (!mounted) return;
      setState(() {
        _qrUrl = (res.data?['qr_url'] ?? '').toString();
      });
      showAppMessage(context, 'Payment QR updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveWalletNumbers() async {
    setState(() => _savingNumbers = true);
    try {
      await portalDio().patch(
        '/admin/hotel/payment-wallet-numbers',
        data: {
          'payment_gcash_mobile': _gcashCtrl.text.trim(),
          'payment_maya_mobile': _mayaCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      showAppMessage(
        context,
        'Wallet numbers saved. Guests can use Pay Now in the booking app.',
      );
      await _loadQr();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _savingNumbers = false);
    }
  }

  Future<void> _searchRefs() async {
    final q = _refCtrl.text.trim();
    if (q.length < 3) {
      showAppMessage(context, 'Enter at least 3 characters.');
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/payment-references/search',
        queryParameters: {'q': q},
      );
      if (!mounted) return;
      final raw = res.data?['results'] as List<dynamic>? ?? const [];
      setState(() {
        _refResults = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Online payments'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'QR Ph code'),
            Tab(text: 'Verify payment'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Connect PayMongo so guests pay via Hosted Checkout with QR Ph '
                '(currently the only active method on this PayMongo account). '
                'QR and wallet numbers below remain available as a manual fallback only — they are not the PayMongo payment destination.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              _paymongoCard(scheme),
              const SizedBox(height: 20),
              Text(
                'Manual fallback (QR / wallet numbers)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (_loadingQr)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(_error!, style: TextStyle(color: scheme.error))
              else if ((_qrUrl ?? '').isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: NetworkMediaImage(
                      url: _qrUrl!,
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.qr_code_2, size: 64, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'No payment QR uploaded yet.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              AppPrimaryButton(
                label: _uploading ? 'Uploading…' : 'Upload / replace QR image',
                onPressed: _uploading ? null : _uploadQr,
              ),
              const SizedBox(height: 28),
              Text(
                'Wallet numbers (manual fallback only)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Optional contact / manual Send Money fallback when PayMongo is not connected. '
                'Do not treat these numbers as the PayMongo merchant destination.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gcashCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'GCash mobile number',
                  hintText: '09171234567',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mayaCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Maya mobile number',
                  hintText: '09181234567',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _savingNumbers || _loadingQr ? null : _saveWalletNumbers,
                child: Text(
                  _savingNumbers ? 'Saving…' : 'Save wallet numbers',
                ),
              ),
            ],
          ),
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Search by payment reference (e.g. PAY20260530…) to confirm a guest completed an online transfer.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _refCtrl,
                decoration: InputDecoration(
                  labelText: 'Payment reference',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    onPressed: _searching ? null : _searchRefs,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchRefs(),
              ),
              const SizedBox(height: 16),
              ..._refResults.map((r) {
                final ref = (r['reference'] ?? '').toString();
                final guest = (r['guest_name'] ?? '').toString();
                final method = (r['payment_method'] ?? '').toString();
                final status = (r['payment_status'] ?? '').toString();
                final total = (r['total_amount'] as num?)?.toDouble() ?? 0;
                final type = (r['type'] ?? '').toString();

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(
                      type == 'booking'
                          ? Icons.receipt_long
                          : Icons.pending_actions_outlined,
                    ),
                    title: Text(
                      ref,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '$guest · $method · $status'
                      '${total > 0 ? ' · ₱${total.toStringAsFixed(0)}' : ''}',
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
              if (_refResults.isEmpty &&
                  _refCtrl.text.length >= 3 &&
                  !_searching)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: Text('No matching references found.')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
