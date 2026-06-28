import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_scaffold.dart';
import 'report_pdf_helper.dart';
import 'shift_report_table.dart';

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
        filename:
            'hotel_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = '${_fmt(widget.timeIn)} → ${_fmt(widget.timeOut)}';

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
                    if (widget.subtitle != null &&
                        widget.subtitle!.isNotEmpty) ...[
                      Text(
                        widget.subtitle!,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      period,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    ShiftReportTable(
                      summary: (_data?['summary'] as Map<String, dynamic>?) ??
                          const {},
                      bookingRows: ((_data?['booking_transactions'] as List?)
                              ?.whereType<Map<String, dynamic>>()
                              .map(Map<String, dynamic>.from)
                              .toList()) ??
                          const [],
                      amenityRows: ((_data?['amenity_transactions'] as List?)
                              ?.whereType<Map<String, dynamic>>()
                              .map(Map<String, dynamic>.from)
                              .toList()) ??
                          const [],
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _pdfBusy ? null : _downloadPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Download printable PDF'),
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
