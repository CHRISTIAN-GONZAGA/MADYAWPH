import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import '../../dio_client.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';
import '../../widgets/payment_redirect.dart';
import '../../utils/money_format.dart';

/// Upload a payment QR per method (QR Ph, GCash, PayMaya, Maribank, bank
/// transfer), verify references, and connect the hotel PayMongo account.
class AdminOnlinePaymentScreen extends StatefulWidget {
  const AdminOnlinePaymentScreen({super.key});

  @override
  State<AdminOnlinePaymentScreen> createState() =>
      _AdminOnlinePaymentScreenState();
}

class _AdminOnlinePaymentScreenState extends State<AdminOnlinePaymentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _methods = const [];
  final Map<String, TextEditingController> _nameCtrls = {};
  final Map<String, TextEditingController> _numberCtrls = {};
  final Map<String, TextEditingController> _notesCtrls = {};
  bool _loadingQr = true;
  String? _busyMethod;
  final _refCtrl = TextEditingController();
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
    _loadMethods();
    _loadPaymongo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refCtrl.dispose();
    for (final ctrl in [
      ..._nameCtrls.values,
      ..._numberCtrls.values,
      ..._notesCtrls.values,
    ]) {
      ctrl.dispose();
    }
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
    setState(() => _connectingPaymongo = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/payments/paymongo/refresh-child',
      );
      if (!mounted) return;
      await _loadPaymongo();
      final data = Map<String, dynamic>.from(res.data ?? const {});
      if (data['open_onboarding_url'] == true) {
        await _openPaymongoOnboardingUrl(data);
        if (!mounted) return;
        showAppMessage(
          context,
          'Opening PayMongo to finish ID verification. When done, tap Refresh status here.',
        );
      } else {
        showAppMessage(
          context,
          (data['message'] ??
                  'Status updated. If ID is already submitted, wait for PayMongo review — no need to resubmit.')
              .toString(),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
      await _loadPaymongo();
    } finally {
      if (mounted) setState(() => _connectingPaymongo = false);
    }
  }

  Future<bool> _openPaymongoOnboardingUrl(Map<String, dynamic>? data) async {
    if (data == null) return false;
    if (data['open_onboarding_url'] == false) return false;
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
        return 'Status: ID submitted — PayMongo review / activation';
      case 'VERIFICATION_PENDING':
        return 'Status: Complete ID verification in PayMongo';
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

  Widget _onboardingSteps(
    ColorScheme scheme, {
    required bool identityDone,
    required bool reviewDone,
    bool businessPending = false,
  }) {
    Widget step(String label, bool done, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              done ? Icons.check_circle : (active ? Icons.radio_button_checked : Icons.radio_button_off),
              size: 18,
              color: done
                  ? scheme.primary
                  : active
                      ? scheme.tertiary
                      : scheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: done || active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        step('1. Selfie + valid ID (PayMongo hosted page)', identityDone, active: !identityDone),
        step(
          businessPending
              ? '2. Business / merchant details (PayMongo hosted page)'
              : '2. PayMongo review & account activation',
          reviewDone,
          active: identityDone && !reviewDone,
        ),
        step('3. Payment ready — guests can pay with QR Ph', reviewDone),
      ],
    );
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
    final onboardingPhase =
        (_paymongo?['onboarding_phase'] as Map?)?.cast<String, dynamic>() ??
            const {};
    final phase = (onboardingPhase['phase'] ?? '').toString();
    final phaseLabel = (onboardingPhase['label'] ?? '').toString();
    final phaseDetail = (onboardingPhase['detail'] ?? '').toString();
    final canOpenSetup = onboardingPhase['can_open_setup'] == true;
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
              connected
                  ? 'Status: Payment Ready'
                  : (phaseLabel.isNotEmpty ? phaseLabel : _onboardingStatusLabel(onboarding, ready: connected)),
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
            if (!connected && phaseDetail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                phaseDetail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
            if (!connected && phase == 'paymongo_review') ...[
              const SizedBox(height: 10),
              _onboardingSteps(scheme, identityDone: true, reviewDone: false),
            ] else if (!connected && phase == 'verify_identity') ...[
              const SizedBox(height: 10),
              _onboardingSteps(scheme, identityDone: false, reviewDone: false),
            ] else if (!connected && phase == 'complete_business') ...[
              const SizedBox(height: 10),
              _onboardingSteps(scheme, identityDone: true, reviewDone: false, businessPending: true),
            ],
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
                if (canOpenSetup || phase == 'complete_business') ...[
                  FilledButton(
                    onPressed: _connectingPaymongo
                        ? null
                        : _continueOrOpenOnboarding,
                    child: Text(
                      phase == 'complete_business'
                          ? 'Continue business setup'
                          : onboarding == 'REJECTED'
                              ? 'Retry ID verification'
                              : 'Open ID verification',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (phase == 'paymongo_review') ...[
                  Text(
                    'This is normal after ID submission. PayMongo reviews on their side — '
                    'the app cannot open another setup page until they approve or send a business-details link.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 12),
                ],
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

  Future<void> _loadMethods() async {
    setState(() {
      _loadingQr = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/payment-methods',
      );
      if (!mounted) return;
      setState(() {
        _applyMethods(res.data?['methods']);
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

  void _applyMethods(dynamic raw) {
    final list = (raw as List?) ?? const [];
    _methods = list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    for (final method in _methods) {
      final key = (method['key'] ?? '').toString();
      if (key.isEmpty) continue;
      _controllerFor(_nameCtrls, key).text =
          (method['account_name'] ?? '').toString();
      _controllerFor(_numberCtrls, key).text =
          (method['account_number'] ?? '').toString();
      _controllerFor(_notesCtrls, key).text =
          (method['instructions'] ?? '').toString();
    }
  }

  TextEditingController _controllerFor(
    Map<String, TextEditingController> store,
    String key,
  ) =>
      store.putIfAbsent(key, TextEditingController.new);

  Future<void> _uploadMethodQr(String key, String label) async {
    final file = await ChatAttachment.pick(context);
    if (file == null) return;
    setState(() => _busyMethod = key);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const {},
        file: file,
        fileField: 'image_file',
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/payment-methods/$key/qr',
        data: form,
      );
      if (!mounted) return;
      setState(() => _applyMethods(res.data?['methods']));
      showAppMessage(context, '$label QR updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyMethod = null);
    }
  }

  Future<void> _removeMethodQr(String key, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $label QR?'),
        content: Text('Guests will no longer see $label as a payment option.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyMethod = key);
    try {
      final res = await portalDio().delete<Map<String, dynamic>>(
        '/admin/hotel/payment-methods/$key/qr',
      );
      if (!mounted) return;
      setState(() => _applyMethods(res.data?['methods']));
      showAppMessage(context, '$label QR removed.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyMethod = null);
    }
  }

  Future<void> _saveMethodDetails(String key, String label) async {
    setState(() => _busyMethod = key);
    try {
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/hotel/payment-methods/$key',
        data: {
          'account_name': _controllerFor(_nameCtrls, key).text.trim(),
          'account_number': _controllerFor(_numberCtrls, key).text.trim(),
          'instructions': _controllerFor(_notesCtrls, key).text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _applyMethods(res.data?['methods']));
      showAppMessage(context, '$label details saved.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyMethod = null);
    }
  }

  Widget _methodCard(ColorScheme scheme, Map<String, dynamic> method) {
    final key = (method['key'] ?? '').toString();
    final label = (method['label'] ?? key).toString();
    final hint = (method['hint'] ?? '').toString();
    final qrUrl = (method['qr_url'] ?? '').toString();
    final hasQr = qrUrl.isNotEmpty;
    final busy = _busyMethod == key;
    final isBank = key == 'bank_transfer';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (hint.isNotEmpty)
                        Text(
                          hint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: method['configured'] == true
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    method['configured'] == true ? 'Live' : 'Not set',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: method['configured'] == true
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasQr)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: NetworkMediaImage(
                    url: qrUrl,
                    width: 190,
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(Icons.qr_code_2, size: 46, color: scheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      'No $label QR yet',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _uploadMethodQr(key, label),
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(hasQr ? 'Replace QR' : 'Upload QR'),
                  ),
                ),
                if (hasQr) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remove QR',
                    onPressed: busy ? null : () => _removeMethodQr(key, label),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controllerFor(_nameCtrls, key),
              decoration: InputDecoration(
                labelText: isBank ? 'Account name' : 'Account name (optional)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controllerFor(_numberCtrls, key),
              keyboardType:
                  isBank ? TextInputType.text : TextInputType.phone,
              decoration: InputDecoration(
                labelText: isBank ? 'Account number' : 'Mobile number',
                hintText: isBank ? '1234-5678-9012' : '09171234567',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controllerFor(_notesCtrls, key),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note shown to guests (optional)',
                hintText: 'e.g. Use InstaPay, send the receipt to the front desk',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            AppPrimaryButton(
              label: busy ? 'Saving…' : 'Save $label details',
              onPressed: busy ? null : () => _saveMethodDetails(key, label),
            ),
          ],
        ),
      ),
    );
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
            Tab(text: 'Payment QRs'),
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
                'Upload one QR per payment method. Guests booking a room see a button '
                'for every method you set up here and scan the matching code — nothing '
                'opens their wallet app automatically.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              _paymongoCard(scheme),
              const SizedBox(height: 20),
              Text(
                'Payment methods',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (_loadingQr)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(_error!, style: TextStyle(color: scheme.error))
              else
                for (final method in _methods) _methodCard(scheme, method),
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
                      '${total > 0 ? ' · ${formatMoney(total, decimals: 0)}' : ''}',
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
