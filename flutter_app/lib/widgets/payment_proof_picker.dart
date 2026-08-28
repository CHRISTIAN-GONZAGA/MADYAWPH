import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_attachment.dart';

/// Gallery / camera picker plus a thumbnail of the selected payment screenshot.
class PaymentProofPicker extends StatelessWidget {
  const PaymentProofPicker({
    super.key,
    required this.file,
    required this.onChanged,
  });

  final XFile? file;
  final ValueChanged<XFile?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await ChatAttachment.pick(context);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(file == null ? 'Upload payment screenshot' : 'Change screenshot'),
        ),
        if (file != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: FutureBuilder(
                future: file!.readAsBytes(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Remove'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Thumbnail of a submitted payment screenshot on the central admin request cards.
class PaymentProofThumb extends StatelessWidget {
  const PaymentProofThumb({
    super.key,
    required this.url,
    this.label = 'Payment screenshot',
    this.emptyMessage = 'No payment screenshot attached.',
  });

  final String url;
  final String label;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return Text(
        emptyMessage,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
    }
    final resolved = ChatAttachment.resolveMediaUrl(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => Dialog(
                child: InteractiveViewer(
                  child: NetworkMediaImage(
                    url: resolved,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: NetworkMediaImage(
              url: resolved,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}

/// Valid ID + payment screenshot (and optional discount ID) from an online stay.
class GuestStayDocuments extends StatelessWidget {
  const GuestStayDocuments({
    super.key,
    this.guestIdUrl = '',
    this.paymentScreenshotUrl = '',
    this.discountIdUrl = '',
    this.requireIdAndReceipt = false,
  });

  final String guestIdUrl;
  final String paymentScreenshotUrl;
  final String discountIdUrl;
  final bool requireIdAndReceipt;

  static String urlFrom(Map<String, dynamic>? data, String key) {
    if (data == null) return '';
    final top = (data[key] ?? '').toString().trim();
    if (top.isNotEmpty) return top;
    final meta = data['metadata'];
    if (meta is Map) {
      return (meta[key] ?? '').toString().trim();
    }
    return '';
  }

  bool get hasAny =>
      guestIdUrl.trim().isNotEmpty ||
      paymentScreenshotUrl.trim().isNotEmpty ||
      discountIdUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!requireIdAndReceipt && !hasAny) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Guest documents',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap an image to enlarge before you approve or check in.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        PaymentProofThumb(
          url: guestIdUrl,
          label: 'Valid ID',
          emptyMessage: 'No valid ID attached.',
        ),
        const SizedBox(height: 12),
        PaymentProofThumb(
          url: paymentScreenshotUrl,
          label: 'Payment screenshot',
          emptyMessage: 'No payment screenshot attached.',
        ),
        if (discountIdUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          PaymentProofThumb(
            url: discountIdUrl,
            label: 'Discount / senior / PWD ID',
            emptyMessage: '',
          ),
        ],
      ],
    );
  }
}
