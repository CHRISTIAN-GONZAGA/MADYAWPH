import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../admin_dashboard_models.dart';

class GuestPortfolioSection extends StatefulWidget {
  const GuestPortfolioSection({
    super.key,
    required this.rooms,
  });

  final List<Map<String, dynamic>> rooms;

  @override
  State<GuestPortfolioSection> createState() => _GuestPortfolioSectionState();
}

class _GuestPortfolioSectionState extends State<GuestPortfolioSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<dynamic> _history = const [];
  String _query = '';
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/guest-history');
      setState(() {
        _history = (res.data?['data'] as List?) ?? const [];
        _loadingHistory = false;
      });
    } on DioException {
      setState(() => _loadingHistory = false);
    }
  }

  List<Map<String, dynamic>> get _currentGuests {
    return widget.rooms
        .where((r) => AdminDashboardModels.statusOf(r) == 'checked_in')
        .map((r) {
          final b = r['latest_booking'] as Map<String, dynamic>?;
          return {
            'guest_name': (r['current_guest_name'] ?? b?['guest_name'] ?? '')
                .toString(),
            'guest_phone': (b?['guest_phone'] ?? '').toString(),
            'guest_email': (b?['guest_email'] ?? '').toString(),
            'room_number': (r['room_number'] ?? '').toString(),
            'category': AdminDashboardModels.categoryLabel(r),
            'check_in': (r['current_check_in'] ?? b?['check_in_date'] ?? '')
                .toString(),
            'check_out':
                (r['current_check_out'] ?? b?['check_out_date'] ?? '').toString(),
            'payment_status': (b?['payment_status'] ?? 'unpaid').toString(),
            'booking_reference': (b?['booking_reference'] ?? '').toString(),
          };
        })
        .toList();
  }

  bool _matches(Map<String, dynamic> g) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return '${g['guest_name']} ${g['guest_email']} ${g['guest_phone']} ${g['room_number']}'
        .toLowerCase()
        .contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentGuests.where(_matches).toList();
    final history = _history
        .whereType<Map<String, dynamic>>()
        .where((h) {
          if (_query.isEmpty) return true;
          final q = _query.toLowerCase();
          return '${h['guest_name']} ${h['guest_email']} ${h['guest_phone']} ${h['booking_reference']}'
              .toLowerCase()
              .contains(q);
        })
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name, email, phone, room…',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Current guests'),
            Tab(text: 'Guest history'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: current.length,
                itemBuilder: (context, i) => _GuestCard(data: current[i]),
              ),
              _loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: history.length,
                      itemBuilder: (context, i) {
                        final h = history[i];
                        return _GuestCard(
                          data: {
                            'guest_name': (h['guest_name'] ?? '').toString(),
                            'guest_email': (h['guest_email'] ?? '').toString(),
                            'guest_phone': (h['guest_phone'] ?? '').toString(),
                            'room_number': (h['room_number'] ?? '').toString(),
                            'check_in': (h['check_in_date'] ?? '').toString(),
                            'check_out': (h['check_out_date'] ?? '').toString(),
                            'payment_status':
                                (h['payment_status'] ?? '').toString(),
                            'booking_reference':
                                (h['booking_reference'] ?? '').toString(),
                            'category': '',
                          },
                          isHistory: true,
                        );
                      },
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.data, this.isHistory = false});
  final Map<String, dynamic> data;
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(isHistory ? Icons.history_edu_outlined : Icons.person),
        title: Text((data['guest_name'] ?? 'Guest').toString()),
        subtitle: Text(
          [
            'Room ${data['room_number']}',
            if ((data['category'] ?? '').toString().isNotEmpty)
              data['category'],
            'Phone: ${data['guest_phone']}',
            'Email: ${data['guest_email']}',
            'Check-in: ${data['check_in']}',
            'Check-out: ${data['check_out']}',
            'Payment: ${data['payment_status']}',
            if ((data['booking_reference'] ?? '').toString().isNotEmpty)
              'Ref: ${data['booking_reference']}',
          ].join('\n'),
        ),
        isThreeLine: true,
      ),
    );
  }
}
