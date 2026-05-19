import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';

/// Pick a photo from gallery or camera and build multipart [FormData] for chat APIs.
class ChatAttachment {
  ChatAttachment._();

  static final _picker = ImagePicker();

  static Future<XFile?> pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
  }

  /// Resolves API attachment URLs so images load on device (not localhost /storage).
  static String resolveMediaUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final origin = _apiOrigin();
    if (trimmed.contains('/api/v1/chat/media')) {
      if (trimmed.startsWith('http')) return trimmed;
      return '$origin$trimmed';
    }

    if (trimmed.startsWith('chat/')) {
      return '$origin/api/v1/chat/media?f=${Uri.encodeComponent(trimmed)}';
    }

    const storageMarker = '/storage/';
    final storageIdx = trimmed.indexOf(storageMarker);
    if (storageIdx >= 0) {
      final path = trimmed.substring(storageIdx + storageMarker.length);
      return '$origin/api/v1/chat/media?f=${Uri.encodeComponent(path)}';
    }

    if (trimmed.startsWith('/storage/')) {
      final path = trimmed.substring('/storage/'.length);
      return '$origin/api/v1/chat/media?f=${Uri.encodeComponent(path)}';
    }

    if (!trimmed.startsWith('http')) {
      final path = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
      return '$origin/api/v1/chat/media?f=${Uri.encodeComponent(path)}';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host)) {
      if (uri.path.contains('/api/v1/chat/media')) {
        return '$origin${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      }
      final pathIdx = uri.path.indexOf(storageMarker);
      if (pathIdx >= 0) {
        final path = uri.path.substring(pathIdx + storageMarker.length);
        return '$origin/api/v1/chat/media?f=${Uri.encodeComponent(path)}';
      }
    }

    if (trimmed.startsWith('categories/') || trimmed.startsWith('rooms/')) {
      return '$origin/api/v1/chat/media?f=${Uri.encodeComponent(trimmed)}';
    }

    return trimmed;
  }

  static String _apiOrigin() {
    final base = Uri.parse(kApiBaseUrl);
    return '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  }

  static Future<FormData> formWithImage({
    required Map<String, dynamic> fields,
    required XFile file,
    String fileField = 'image_file',
  }) async {
    final map = <String, dynamic>{...fields};
    map[fileField] = await MultipartFile.fromFile(
      file.path,
      filename: file.name,
    );
    return FormData.fromMap(map);
  }
}

/// Network image that resolves API media URLs (chat, categories, rooms).
class NetworkMediaImage extends StatelessWidget {
  const NetworkMediaImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.error,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    final resolved = ChatAttachment.resolveMediaUrl(url);
    if (resolved.isEmpty) {
      return error ?? const SizedBox.shrink();
    }

    Widget image = Image.network(
      resolved,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          error ?? const Icon(Icons.broken_image_outlined),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}

/// Renders chat text plus optional image attachment from API payload.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.attachmentUrl,
  });

  final String message;
  final bool isMine;
  final String? attachmentUrl;

  factory ChatMessageBubble.fromMap(
    Map<String, dynamic> m, {
    required bool isMine,
  }) {
    final url = (m['attachment_url'] ?? '').toString();
    return ChatMessageBubble(
      message: (m['message'] ?? '').toString(),
      isMine: isMine,
      attachmentUrl:
          url.isEmpty ? null : ChatAttachment.resolveMediaUrl(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachmentUrl != null && attachmentUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  attachmentUrl!,
                  width: 260,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return SizedBox(
                      width: 260,
                      height: 140,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 260,
                    height: 80,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              if (message.isNotEmpty) const SizedBox(height: 8),
            ],
            if (message.isNotEmpty)
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
