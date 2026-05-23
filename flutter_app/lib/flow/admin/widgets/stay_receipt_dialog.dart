import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../dio_client.dart';

/// Shows stay receipt summary after checkout; can download PDF with auth.
Future<void> showStayReceiptDialog(
  BuildContext context, {
  required Map<String, dynamic>? receipt,
}) async {
  if (receipt == null || receipt.isEmpty) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Checkout receipt'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${receipt['booking_reference'] ?? ''}',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Guest: ${receipt['guest_name'] ?? ''}'),
            Text('Room: ${receipt['room_number'] ?? ''}'),
            Text(
              'Stay: ${receipt['check_in_date']} → ${receipt['check_out_date']}',
            ),
            const Divider(),
            ...((receipt['lines'] as List?) ?? const []).whereType<Map>().map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${line['label']}')),
                    Text(
                      '₱${(line['amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total: ₱${(receipt['subtotal'] as num?)?.toStringAsFixed(0) ?? '0'}',
              style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
          onPressed: () async {
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
              final path =
                  '${Directory.systemTemp.path}/receipt_${receipt['booking_reference']}.pdf';
              final file = File(path);
              await file.writeAsBytes(bytes, flush: true);
              final uri = Uri.file(file.path);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Receipt saved: ${file.path}')),
                );
              }
            } on DioException catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(dioErrorMessage(e))),
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open PDF'),
        ),
      ],
    ),
  );
}
