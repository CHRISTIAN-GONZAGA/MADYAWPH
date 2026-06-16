import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../dio_client.dart';
import '../../../utils/money_format.dart';
import '../admin_dashboard_models.dart';

/// Shows stay receipt summary; fetches line items when missing; downloads printable PDF.
Future<void> showStayReceiptDialog(
  BuildContext context, {
  required Map<String, dynamic>? receipt,
}) async {
  if (receipt == null || receipt.isEmpty) {
    return;
  }

  var data = Map<String, dynamic>.from(receipt);
  final id = (data['booking_id'] ?? '').toString();

  if (id.isNotEmpty &&
      ((data['lines'] as List?) ?? const []).isEmpty) {
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/bookings/$id/receipt-summary',
      );
      final summary = res.data?['receipt'];
      if (summary is Map) {
        data = Map<String, dynamic>.from(summary);
      }
    } on DioException {
      // Show partial receipt from caller data.
    }
  }

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
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
                color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.35),
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
                child: Text('No line breakdown — download PDF for full receipt.'),
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
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download PDF'),
        ),
      ],
    ),
  );
}

Future<void> _downloadReceiptPdf(
  BuildContext context,
  Map<String, dynamic> receipt,
) async {
  final id = (receipt['booking_id'] ?? '').toString();
  if (id.isEmpty) return;

  try {
    final res = await portalDio().get<Uint8List>(
      '/admin/bookings/$id/receipt',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Empty receipt file');
    }
    final ref = (receipt['booking_reference'] ?? id).toString();
    final path = '${Directory.systemTemp.path}/receipt_$ref.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    final uri = Uri.file(file.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receipt saved: ${file.path}')),
      );
    }
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}
