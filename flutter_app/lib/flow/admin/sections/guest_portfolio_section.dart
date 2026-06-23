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
            'check_in': AdminDashboardModels.formatDisplayDate(
              r['current_check_in'] ?? b?['check_in_date'],
            ),
            'check_out': AdminDashboardModels.formatDisplayDate(
              r['current_check_out'] ?? b?['check_out_date'],
            ),
            'payment_status': (b?['payment_status'] ?? 'unpaid').toString(),
            'booking_reference': (b?['booking_reference'] ?? '').toString(),
            'adults': (b?['adults'] as num?)?.toInt() ?? 1,
            'children': (b?['children'] as num?)?.toInt() ?? 0,
            'guests_male': (b?['guests_male'] as num?)?.toInt() ?? 0,
            'guests_female': (b?['guests_female'] as num?)?.toInt() ?? 0,
            'guest_nationality': (b?['guest_nationality'] ?? '').toString(),
            'free_breakfast': AdminDashboardModels.formatFreeBreakfast(
              b?['free_breakfast_options'] as List?,
            ),
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
                            'check_in': AdminDashboardModels.formatDisplayDate(
                              h['check_in_date'],
                            ),
                            'check_out': AdminDashboardModels.formatDisplayDate(
                              h['check_out_date'],
                            ),
                            'payment_status':
                                (h['payment_status'] ?? '').toString(),
                            'booking_reference':
                                (h['booking_reference'] ?? '').toString(),
                            'category': '',
                            'adults': (h['adults'] as num?)?.toInt() ?? 1,
                            'children': (h['children'] as num?)?.toInt() ?? 0,
                            'guests_male': (h['guests_male'] as num?)?.toInt() ?? 0,
                            'guests_female':
                                (h['guests_female'] as num?)?.toInt() ?? 0,
                            'guest_nationality':
                                (h['guest_nationality'] ?? '').toString(),
                            'free_breakfast':
                                AdminDashboardModels.formatFreeBreakfast(
                              h['free_breakfast_options'] as List?,
                            ),
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
    final guest = (data['guest_name'] ?? 'Guest').toString();
    final roomNo = (data['room_number'] ?? '').toString();
    final summary = [
      if (roomNo.isNotEmpty) 'Room $roomNo',
      if (isHistory && (data['check_out'] ?? '').toString().isNotEmpty)
        'Out: ${data['check_out']}',
      if (!isHistory && (data['payment_status'] ?? '').toString().isNotEmpty)
        data['payment_status'],
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(isHistory ? Icons.history_edu_outlined : Icons.person),
        title: Text(guest, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          summary.isEmpty ? 'Tap for details' : summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((data['category'] ?? '').toString().isNotEmpty)
                  _row('Category', data['category'].toString()),
                if ((data['guest_phone'] ?? '').toString().isNotEmpty)
                  _row('Phone', data['guest_phone'].toString()),
                if ((data['guest_email'] ?? '').toString().isNotEmpty)
                  _row('Email', data['guest_email'].toString()),
                if ((data['check_in'] ?? '').toString().isNotEmpty &&
                    data['check_in'] != '—')
                  _row('Check-in', data['check_in'].toString()),
                if ((data['check_out'] ?? '').toString().isNotEmpty &&
                    data['check_out'] != '—')
                  _row('Check-out', data['check_out'].toString()),
                if (((data['adults'] as num?)?.toInt() ?? 0) > 0 ||
                    ((data['children'] as num?)?.toInt() ?? 0) > 0)
                  _row(
                    'Party',
                    'Adults ${(data['adults'] as num?)?.toInt() ?? 1} · '
                        'Children ${(data['children'] as num?)?.toInt() ?? 0}',
                  ),
                if (((data['guests_male'] as num?)?.toInt() ?? 0) > 0 ||
                    ((data['guests_female'] as num?)?.toInt() ?? 0) > 0)
                  _row(
                    'Demographics',
                    'Male ${(data['guests_male'] as num?)?.toInt() ?? 0} · '
                        'Female ${(data['guests_female'] as num?)?.toInt() ?? 0}',
                  ),
                if ((data['guest_nationality'] ?? '').toString().isNotEmpty)
                  _row('Nationality', data['guest_nationality'].toString()),
                if ((data['free_breakfast'] ?? '').toString().isNotEmpty)
                  _row('Complimentary items', data['free_breakfast'].toString()),
                if ((data['payment_status'] ?? '').toString().isNotEmpty)
                  _row('Payment', data['payment_status'].toString()),
                if ((data['booking_reference'] ?? '').toString().isNotEmpty)
                  _row('Reference', data['booking_reference'].toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
