import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../auth_storage.dart';
import '../../dio_client.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';
import '../public_hotel_search_screen.dart';

/// Developer-only platform control panel (not hotel admin).
class CentralAdminDashboardScreen extends StatefulWidget {
  const CentralAdminDashboardScreen({super.key});

  @override
  State<CentralAdminDashboardScreen> createState() =>
      _CentralAdminDashboardScreenState();
}

class _CentralAdminDashboardScreenState extends State<CentralAdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _settings;
  List<dynamic> _creditRequests = const [];
  List<dynamic> _memberRequests = const [];
  List<dynamic> _hotels = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        portalDio().get<Map<String, dynamic>>('/platform/settings'),
        portalDio().get<Map<String, dynamic>>('/platform/credit-requests'),
        portalDio().get<Map<String, dynamic>>('/platform/member-requests'),
        portalDio().get<Map<String, dynamic>>('/platform/hotels'),
      ]);
      setState(() {
        _settings = results[0].data;
        _creditRequests = (results[1].data?['data'] as List?) ?? const [];
        _memberRequests = (results[2].data?['data'] as List?) ?? const [];
        _hotels = (results[3].data?['data'] as List?) ?? const [];
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _uploadQr({required bool creditWallet}) async {
    final image = await ChatAttachment.pickRoomImageFromGallery(context);
    if (image == null || !mounted) return;
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const <String, dynamic>{},
        file: image,
      );
      final path = creditWallet
          ? '/platform/settings/credit-wallet-qr'
          : '/platform/settings/member-qr';
      await portalDio().post(
        path,
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR image updated.')),
      );
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _approveCredit(String id) async {
    try {
      await portalDio().post('/platform/credit-requests/$id/approve');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _rejectCredit(String id) async {
    try {
      await portalDio().post('/platform/credit-requests/$id/reject');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _approveMember(String id) async {
    try {
      await portalDio().post('/platform/member-requests/$id/approve');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _rejectMember(String id) async {
    try {
      await portalDio().post('/platform/member-requests/$id/reject');
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _deleteHotel(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete hotel?'),
        content: Text(
          'Permanently delete "$name" and all its rooms, bookings, and staff accounts?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await portalDio().delete('/platform/hotels/$id');
      await AuthStorage.clearHotelsDirectoryCache();
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  }

  Future<void> _signOut() async {
    await AuthStorage.clearPortalAuth();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PublicHotelSearchScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Platform control'),
        backgroundColor: const Color(0xFF1A2B4A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: const Color(0xFFD4A843),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Credit approvals'),
            Tab(text: 'Member approvals'),
            Tab(text: 'QR payments'),
            Tab(text: 'Hotels'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _ApprovalList(
                      emptyMessage: 'No pending credit top-ups.',
                      items: _creditRequests,
                      pendingOnly: true,
                      builder: (item) => _CreditRequestCard(
                        item: item,
                        onApprove: () => _approveCredit((item['id'] ?? '').toString()),
                        onReject: () => _rejectCredit((item['id'] ?? '').toString()),
                      ),
                    ),
                    _ApprovalList(
                      emptyMessage: 'No pending member requests.',
                      items: _memberRequests,
                      pendingOnly: true,
                      builder: (item) => _MemberRequestCard(
                        item: item,
                        onApprove: () => _approveMember((item['id'] ?? '').toString()),
                        onReject: () => _rejectMember((item['id'] ?? '').toString()),
                      ),
                    ),
                    _QrSettingsTab(
                      settings: _settings ?? const {},
                      onUploadCredit: () => _uploadQr(creditWallet: true),
                      onUploadMember: () => _uploadQr(creditWallet: false),
                    ),
                    _HotelsTab(
                      hotels: _hotels,
                      onDelete: _deleteHotel,
                    ),
                  ],
                ),
    );
  }
}

class _ApprovalList extends StatelessWidget {
  const _ApprovalList({
    required this.emptyMessage,
    required this.items,
    required this.pendingOnly,
    required this.builder,
  });

  final String emptyMessage;
  final List<dynamic> items;
  final bool pendingOnly;
  final Widget Function(Map<String, dynamic> item) builder;

  @override
  Widget build(BuildContext context) {
    final list = items
        .whereType<Map<String, dynamic>>()
        .where((e) => !pendingOnly || (e['status'] ?? '') == 'pending')
        .toList();

    if (list.isEmpty) {
      return Center(child: Text(emptyMessage));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => builder(list[i]),
    );
  }
}

class _CreditRequestCard extends StatelessWidget {
  const _CreditRequestCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (item['hotel_name'] ?? 'Hotel').toString(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text('Amount: ₱${item['amount']}'),
            Text('Reference: ${item['payment_reference']}'),
            Text('By: ${item['requested_by_name'] ?? '—'}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRequestCard extends StatelessWidget {
  const _MemberRequestCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (item['full_name'] ?? 'Member').toString(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text('Email: ${item['email']}'),
            Text('Phone: ${item['phone']}'),
            Text('Amount: ₱${item['amount']} / month'),
            Text('Reference: ${item['payment_reference']}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QrSettingsTab extends StatelessWidget {
  const _QrSettingsTab({
    required this.settings,
    required this.onUploadCredit,
    required this.onUploadMember,
  });

  final Map<String, dynamic> settings;
  final VoidCallback onUploadCredit;
  final VoidCallback onUploadMember;

  @override
  Widget build(BuildContext context) {
    final creditQr = ChatAttachment.resolveMediaUrl(
      (settings['credit_wallet_qr_url'] ?? '').toString(),
    );
    final memberQr = ChatAttachment.resolveMediaUrl(
      (settings['member_subscription_qr_url'] ?? '').toString(),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _QrCard(
          title: 'Hotel credit wallet top-up (QR Ph)',
          subtitle: 'All hotels scan this when requesting credit top-ups.',
          imageUrl: creditQr,
          onUpload: onUploadCredit,
        ),
        const SizedBox(height: 16),
        _QrCard(
          title: 'Become a member (QR Ph)',
          subtitle: 'Guests pay ₱${settings['member_monthly_fee'] ?? 300}/month via this QR.',
          imageUrl: memberQr,
          onUpload: onUploadMember,
        ),
      ],
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onUpload,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.qr_code_2, size: 64),
                      )
                    : NetworkMediaImage(url: imageUrl, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Upload QR Ph image'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotelsTab extends StatelessWidget {
  const _HotelsTab({required this.hotels, required this.onDelete});

  final List<dynamic> hotels;
  final Future<void> Function(String id, String name) onDelete;

  @override
  Widget build(BuildContext context) {
    if (hotels.isEmpty) {
      return const Center(child: Text('No hotels registered.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: hotels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final h = hotels[i] as Map<String, dynamic>;
        final id = (h['id'] ?? '').toString();
        final name = (h['name'] ?? 'Hotel').toString();
        return Card(
          child: ListTile(
            title: Text(name),
            subtitle: Text((h['city'] ?? h['location'] ?? '').toString()),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => onDelete(id, name),
            ),
          ),
        );
      },
    );
  }
}
