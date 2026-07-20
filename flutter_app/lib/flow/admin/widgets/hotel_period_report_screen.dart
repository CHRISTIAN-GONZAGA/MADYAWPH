import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../../../widgets/app_scaffold.dart';
import 'admin_reports_ui.dart';
import 'report_pdf_helper.dart';

/// Hotel-wide period report (Setup → Analytics). Independent of front-desk shift state.
class HotelPeriodReportScreen extends StatefulWidget {
  const HotelPeriodReportScreen({
    super.key,
    required this.timeIn,
    required this.timeOut,
    required this.title,
    this.subtitle,
  });

  final DateTime timeIn;
  final DateTime timeOut;
  final String title;
  final String? subtitle;

  @override
  State<HotelPeriodReportScreen> createState() =>
      _HotelPeriodReportScreenState();
}

class _HotelPeriodReportScreenState extends State<HotelPeriodReportScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _pdfBusy = false;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/shift-summary',
        queryParameters: {
          'time_in': widget.timeIn.toIso8601String(),
          'time_out': widget.timeOut.toIso8601String(),
        },
      );
      if (!mounted) return;
      setState(() {
        _data = res.data;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _downloadPdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      await downloadReportPdf(
        context: context,
        path: '/reports/shift-summary/pdf',
        queryParameters: {
          'time_in': widget.timeIn.toIso8601String(),
          'time_out': widget.timeOut.toIso8601String(),
          'title': widget.title,
        },
        filename: 'hotel_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Map<String, dynamic> get _summary =>
      (_data?['summary'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> _list(String key) {
    final raw = _data?[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final period = '${_fmt(widget.timeIn)} → ${_fmt(widget.timeOut)}';
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    final bookings = _list('booking_transactions');
    final amenities = _list('amenity_transactions');
    final gross = parseJsonDouble(summary['gross_revenue']);
    final net = parseJsonDouble(summary['net_revenue'] ?? summary['profit']);

    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _loading || _pdfBusy ? null : _downloadPdf,
            icon: _pdfBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Download PDF',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: scheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    ReportsHeroHeader(
                      title: widget.title,
                      selectedDateLabel: period,
                      caption: widget.subtitle?.isNotEmpty == true
                          ? widget.subtitle!
                          : 'Hotel-wide revenue for this period',
                      onRefresh: _load,
                      isRefreshing: _loading,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _TotalCard(
                            label: 'Gross revenue',
                            value: formatPeso(gross),
                            color: Colors.teal.shade700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TotalCard(
                            label: 'Net revenue',
                            value: formatPeso(net),
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TotalCard(
                            label: 'Bookings',
                            value: '${summary['bookings'] ?? bookings.length}',
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TotalCard(
                            label: 'Amenity sales',
                            value: '${amenities.length}',
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ExpandCard(
                      title: 'Revenue breakdown',
                      subtitle: 'Rooms, amenities, refunds, net',
                      icon: Icons.account_balance_wallet_outlined,
                      initiallyExpanded: true,
                      child: Column(
                        children: [
                          _MetricRow(
                            'Room revenue',
                            formatPeso(summary['room_revenue'] ?? 0),
                          ),
                          _MetricRow(
                            'Amenity revenue',
                            formatPeso(summary['amenity_revenue'] ?? 0),
                          ),
                          _MetricRow(
                            'Refunds',
                            formatPeso(summary['refunds'] ?? 0),
                          ),
                          _MetricRow(
                            'Transfer adjustments',
                            formatPeso(summary['transfer_adjustments'] ?? 0),
                          ),
                          _MetricRow(
                            'Reseller payouts',
                            formatPeso(
                              summary['reseller_commissions_paid'] ?? 0,
                            ),
                          ),
                          const Divider(height: 18),
                          _MetricRow(
                            'Gross revenue',
                            formatPeso(summary['gross_revenue'] ?? 0),
                            bold: true,
                          ),
                          _MetricRow(
                            'Net revenue',
                            formatPeso(
                              summary['net_revenue'] ?? summary['profit'] ?? 0,
                            ),
                            bold: true,
                          ),
                          _MetricRow(
                            'Net profit',
                            formatPeso(summary['profit'] ?? 0),
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                    _ExpandCard(
                      title: 'Operations summary',
                      subtitle: 'Occupancy activity in this period',
                      icon: Icons.hotel_outlined,
                      child: Column(
                        children: [
                          _MetricRow(
                            'Paid bookings',
                            '${summary['bookings'] ?? 0}',
                          ),
                          _MetricRow(
                            'Rooms checked in',
                            '${summary['rooms_checked_in'] ?? 0}',
                          ),
                          _MetricRow(
                            'Rooms checked out',
                            '${summary['rooms_checked_out'] ?? 0}',
                          ),
                        ],
                      ),
                    ),
                    _ExpandCard(
                      title: 'Booking transactions',
                      subtitle:
                          '${bookings.length} paid stay(s) · tap rows for details',
                      icon: Icons.receipt_long_outlined,
                      initiallyExpanded: true,
                      child: bookings.isEmpty
                          ? const Text('No booking payments in this period.')
                          : Column(
                              children: bookings.map((r) {
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    (r['guest_name'] ?? 'Guest').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if ((r['reference'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        r['reference'].toString(),
                                      if ((r['room_number'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        'Room ${r['room_number']}',
                                      if ((r['payment_method'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        r['payment_method'].toString(),
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                  ),
                                  trailing: Text(
                                    formatPeso(parseJsonDouble(r['amount'])),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    _ExpandCard(
                      title: 'Amenity transactions',
                      subtitle: '${amenities.length} amenity sale(s)',
                      icon: Icons.room_service_outlined,
                      child: amenities.isEmpty
                          ? const Text('No amenity sales in this period.')
                          : Column(
                              children: amenities.map((r) {
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    (r['description'] ?? r['label'] ?? 'Amenity')
                                        .toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if ((r['room_number'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        'Room ${r['room_number']}',
                                      _shortDate(r['paid_at']),
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                  ),
                                  trailing: Text(
                                    formatPeso(parseJsonDouble(r['amount'])),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _pdfBusy ? null : _downloadPdf,
                      icon: _pdfBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _pdfBusy ? 'Preparing PDF…' : 'Download printable PDF',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
    );
  }

  static String _shortDate(dynamic value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ExpandCard extends StatelessWidget {
  const _ExpandCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: scheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(subtitle),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [child],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: bold
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openHotelPeriodReport({
  required BuildContext context,
  required DateTime timeIn,
  required DateTime timeOut,
  required String title,
  String? subtitle,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => HotelPeriodReportScreen(
        timeIn: timeIn,
        timeOut: timeOut,
        title: title,
        subtitle: subtitle,
      ),
    ),
  );
}
