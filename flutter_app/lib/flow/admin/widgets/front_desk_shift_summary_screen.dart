import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_scaffold.dart';
import '../../portal_sign_out.dart';
import 'front_desk_shift.dart';
import 'report_pdf_helper.dart';
import 'shift_report_table.dart';

/// Full-screen shift end receipt with tables and PDF export.
class FrontDeskShiftSummaryScreen extends StatefulWidget {
  const FrontDeskShiftSummaryScreen({
    super.key,
    required this.shift,
    required this.endedAt,
    this.logoutOnFinish = true,
    this.clearShiftOnFinish = true,
    this.title = 'Shift revenue summary',
  });

  final FrontDeskShift shift;
  final DateTime endedAt;
  final bool logoutOnFinish;
  /// When false, finishing only signs out / closes — never touches shift storage.
  final bool clearShiftOnFinish;
  final String title;

  @override
  State<FrontDeskShiftSummaryScreen> createState() =>
      _FrontDeskShiftSummaryScreenState();
}

class _FrontDeskShiftSummaryScreenState extends State<FrontDeskShiftSummaryScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _pdfBusy = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/shift-summary',
        queryParameters: {
          'time_in': widget.shift.startedAt.toIso8601String(),
          'time_out': widget.endedAt.toIso8601String(),
          'staff_name': widget.shift.staffName,
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
          'time_in': widget.shift.startedAt.toIso8601String(),
          'time_out': widget.endedAt.toIso8601String(),
          'staff_name': widget.shift.staffName,
          'title': widget.title,
        },
        filename:
            'shift_${widget.shift.userId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    if (widget.clearShiftOnFinish) {
      await FrontDeskShiftStorage.clear(
        hotelId: widget.shift.hotelId,
        userId: widget.shift.userId,
      );
    }
    if (!mounted) return;
    if (widget.logoutOnFinish) {
      await signOutPortalToRoleSelection(context);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final period =
        '${_fmt(widget.shift.startedAt)} → ${_fmt(widget.endedAt)}';

    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.title),
        automaticallyImplyLeading: !widget.logoutOnFinish,
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
                    Text(
                      widget.shift.staffName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      period,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    FilledButton.icon(
                      onPressed: _finishing ? null : _finish,
                      icon: _finishing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        widget.logoutOnFinish ? 'Finish & sign out' : 'Finish',
                      ),
                    ),
                  ],
                ),
    );
  }
}
