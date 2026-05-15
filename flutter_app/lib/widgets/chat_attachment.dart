import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
      attachmentUrl: url.isEmpty ? null : url,
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
