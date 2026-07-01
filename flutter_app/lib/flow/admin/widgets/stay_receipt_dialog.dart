import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:open_filex/open_filex.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../admin_dashboard_models.dart';

bool _looksLikePdf(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

String? _pdfErrorFromBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    return 'PDF download returned no data.';
  }
  if (_looksLikePdf(bytes)) return null;
  try {
    final text = String.fromCharCodes(bytes.take(512));
    if (text.trimLeft().startsWith('{') || text.contains('"message"')) {
      return 'Server did not return a PDF. Pull to refresh and try again.';
    }
  } catch (_) {}
  return 'Downloaded file is not a valid PDF.';
}

/// Shows stay receipt summary; fetches line items when missing; downloads printable PDF.
Future<void> showStayReceiptDialog(
  BuildContext context, {
  required Map<String, dynamic>? receipt,
}) async {
  final dialogCtx = resolveNoticeContext(context);
  if (dialogCtx == null) return;

  if (receipt == null || receipt.isEmpty) {
    await showAppMessage(
      dialogCtx,
      'No receipt data was passed to the dialog.',
      isError: true,
      title: 'Receipt error',
    );
    return;
  }

  var data = Map<String, dynamic>.from(receipt);
  final id = AdminDashboardModels.documentIdOf(data);

  if (id.isEmpty) {
    await showAppMessage(
      dialogCtx,
      'Guest log row is missing a booking ID (raw id: ${receipt['id']}, _id: ${receipt['_id']}).',
      isError: true,
      title: 'Receipt error',
    );
    return;
  }
  data['booking_id'] = id;

  if (((data['lines'] as List?) ?? const []).isEmpty) {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/bookings/$id/receipt-summary',
      );
      final summary = res.data?['receipt'];
      if (summary is Map) {
        data = Map<String, dynamic>.from(summary);
        data['booking_id'] = AdminDashboardModels.documentIdOf(data).isEmpty
            ? id
            : AdminDashboardModels.documentIdOf(data);
      }
    } on DioException catch (e) {
      if (!dialogCtx.mounted) return;
      await showAppMessage(
        dialogCtx,
        'Could not load receipt summary: ${dioErrorMessage(e)}',
        isError: true,
        title: 'Receipt error',
      );
    }
  }

  if (!dialogCtx.mounted) return;

  await showDialog<void>(
    context: dialogCtx,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.receipt_long, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Checkout receipt')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data['booking_reference'] ?? ''}',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text('Guest: ${data['guest_name'] ?? ''}'),
                  Text('Room: ${data['room_number'] ?? ''}'),
                  Text(
                    'Stay: ${AdminDashboardModels.formatDateRange(data['check_in_date'], data['check_out_date'])}',
                  ),
                  if ((data['payment_status'] ?? '').toString().isNotEmpty)
                    Text('Payment: ${data['payment_status']}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Line items',
              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            ...((data['lines'] as List?) ?? const []).whereType<Map>().map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${line['label']}')),
                    Text(
                      formatBillLineAmount(line),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            if (((data['lines'] as List?) ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No line breakdown — open PDF for full receipt.'),
              ),
            const Divider(height: 20),
            if (((data['refunds'] as num?) ?? 0) > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Refunds',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Text(
                    '−${formatPeso((data['refunds'] as num?) ?? 0)}',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  formatPeso(
                    (data['total_due'] as num?) ??
                        (data['subtotal'] as num?) ??
                        0,
                  ),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => _downloadReceiptPdf(ctx, data),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open PDF'),
        ),
      ],
    ),
  );
}

Future<void> _downloadReceiptPdf(
  BuildContext context,
  Map<String, dynamic> receipt,
) async {
  final id = AdminDashboardModels.documentIdOf(receipt).isEmpty
      ? (receipt['booking_id'] ?? '').toString()
      : AdminDashboardModels.documentIdOf(receipt);
  if (id.isEmpty) {
    if (context.mounted) {
      await showAppMessage(
        context,
        'Missing booking ID for PDF download.',
        isError: true,
        title: 'Receipt error',
      );
    }
    return;
  }

  try {
    final res = await portalDio().get<List<int>>(
      '/admin/bookings/$id/receipt',
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': 'application/pdf'},
      ),
    );
    final bytes = Uint8List.fromList(res.data ?? const []);
    final pdfError = _pdfErrorFromBytes(bytes);
    if (pdfError != null) {
      if (context.mounted) {
        await showAppMessage(context, pdfError, isError: true, title: 'Receipt error');
      }
      return;
    }

    final ref = (receipt['booking_reference'] ?? id).toString();
    final safeRef = ref.replaceAll(RegExp(r'[^\w\-.]+'), '_');
    final file = File('${Directory.systemTemp.path}/receipt_$safeRef.pdf');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path, type: 'application/pdf');
    if (!context.mounted) return;

    if (result.type != ResultType.done) {
      final detail = result.message.isNotEmpty
          ? result.message
          : 'Could not open PDF viewer.';
      await showAppMessage(
        context,
        '$detail\n\nSaved to:\n${file.path}',
        isError: true,
        title: 'Open PDF failed',
      );
    }
  } on DioException catch (e) {
    if (context.mounted) {
      await showAppMessage(
        context,
        dioErrorMessage(e),
        isError: true,
        title: 'Receipt download failed',
      );
    }
  } on PlatformException catch (e) {
    if (context.mounted) {
      await showAppMessage(
        context,
        '${e.code}: ${e.message ?? e.details ?? e.toString()}',
        isError: true,
        title: 'PlatformException',
      );
    }
  } catch (e) {
    if (context.mounted) {
      await showAppMessage(
        context,
        '$e',
        isError: true,
        title: 'Receipt error',
      );
    }
  }
}
