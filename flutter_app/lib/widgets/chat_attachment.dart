import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../locale_controller.dart';
import '../l10n/app_strings.dart';

/// Pick a photo from gallery or camera and build multipart [FormData] for chat APIs.
class ChatAttachment {
  ChatAttachment._();

  static final _picker = ImagePicker();

  static const _allowedRoomExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

  /// Gallery-only picker for room/category images (JPG, PNG, WEBP).
  static Future<XFile?> pickRoomImageFromGallery(BuildContext context) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1920,
    );
    if (file == null) return null;
    final ext = _extensionOf(file.path);
    if (!_allowedRoomExtensions.contains(ext)) {
      if (context.mounted) {
        showAppMessage(context, 'Only JPG, JPEG, PNG, or WEBP images are allowed.');
      }
      return null;
    }
    return file;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }

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

    if (trimmed.startsWith('categories/') ||
        trimmed.startsWith('rooms/') ||
        trimmed.startsWith('hotel-banners/') ||
        trimmed.startsWith('platform-qr/') ||
        trimmed.startsWith('payment-qr/') ||
        trimmed.startsWith('bookings/') ||
        trimmed.startsWith('reseller-ids/')) {
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
    final map = <String, dynamic>{};
    for (final entry in fields.entries) {
      final v = entry.value;
      if (v == null) {
        continue;
      }
      map[entry.key] = v is num || v is bool ? v.toString() : v;
    }
    map[fileField] = await MultipartFile.fromFile(
      file.path,
      filename: file.name.isNotEmpty ? file.name : 'upload.jpg',
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
///
/// Messenger-style: my messages are primary-colored on the right, others are
/// grey on the left. Consecutive messages from the same side are visually
/// grouped, and tapping a bubble reveals its exact send time.
class ChatMessageBubble extends StatefulWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.attachmentUrl,
    this.originalMessage,
    this.showTranslation = false,
    this.detectedLang,
    this.sentAt,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  final String message;
  final bool isMine;
  final String? attachmentUrl;
  final String? originalMessage;
  final bool showTranslation;
  final String? detectedLang;
  final DateTime? sentAt;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  factory ChatMessageBubble.fromMap(
    Map<String, dynamic> m, {
    required bool isMine,
    bool isFirstInGroup = true,
    bool isLastInGroup = true,
  }) {
    final url = (m['attachment_url'] ?? '').toString();
    final display = (m['display_message'] ?? m['message'] ?? '').toString();
    final original = (m['original_message'] ?? m['message'] ?? '').toString();
    final show = m['show_translation'] == true;
    return ChatMessageBubble(
      message: display,
      isMine: isMine,
      attachmentUrl:
          url.isEmpty ? null : ChatAttachment.resolveMediaUrl(url),
      originalMessage: show ? original : null,
      showTranslation: show,
      detectedLang: (m['detected_lang'] ?? '').toString(),
      sentAt: sentAtOf(m),
      isFirstInGroup: isFirstInGroup,
      isLastInGroup: isLastInGroup,
    );
  }

  static DateTime? sentAtOf(Map<String, dynamic> m) {
    for (final key in ['sent_at', 'created_at', 'latest_sent_at']) {
      final raw = m[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  static String _time12(DateTime local) {
    final h24 = local.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = h24 < 12 ? 'AM' : 'PM';
    return '$h:$mm $ampm';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Short label used in thread lists (e.g. "9:41 PM", "Yesterday 9:41 PM").
  static String formatTimestamp(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = _time12(local);
    if (day == today) return time;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return 'Yesterday $time';
    if (local.year == now.year) {
      return '${_months[local.month - 1]} ${local.day} $time';
    }
    return '${_months[local.month - 1]} ${local.day}, ${local.year} $time';
  }

  /// Messenger-style centered divider label (e.g. "Wed at 9:41 AM").
  static String formatDividerLabel(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = _time12(local);
    if (day == today) return time;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return 'Yesterday at $time';
    if (today.difference(day).inDays < 7) {
      return '${_weekdays[local.weekday - 1]} at $time';
    }
    if (local.year == now.year) {
      return '${_months[local.month - 1]} ${local.day} at $time';
    }
    return '${_months[local.month - 1]} ${local.day}, ${local.year} at $time';
  }

  /// A centered time divider is shown before the first message and whenever
  /// there is a gap of 20+ minutes between messages (like Messenger).
  static bool shouldShowDivider(DateTime? previous, DateTime? current) {
    if (current == null) return false;
    if (previous == null) return true;
    return current.difference(previous).abs() >= const Duration(minutes: 20);
  }

  /// Builds one thread item (divider + bubble) for a chat ListView.
  ///
  /// Handles Messenger-style grouping: consecutive messages from the same
  /// side sent close together share tight spacing and flattened corners.
  static Widget listItem({
    required List<dynamic> messages,
    required int index,
    required bool Function(Map<String, dynamic> message) isMineOf,
  }) {
    Map<String, dynamic> mapAt(int i) {
      final raw = messages[i];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return const <String, dynamic>{};
    }

    bool sameGroup(int a, int b) {
      final ma = mapAt(a);
      final mb = mapAt(b);
      if (isMineOf(ma) != isMineOf(mb)) return false;
      final ta = sentAtOf(ma);
      final tb = sentAtOf(mb);
      if (ta == null || tb == null) return true;
      return tb.difference(ta).abs() <= const Duration(minutes: 3);
    }

    final m = mapAt(index);
    final at = sentAtOf(m);
    final prevAt = index > 0 ? sentAtOf(mapAt(index - 1)) : null;
    final showDivider =
        index == 0 ? at != null : shouldShowDivider(prevAt, at);

    final isFirst = index == 0 || showDivider || !sameGroup(index - 1, index);
    var isLast = index == messages.length - 1;
    if (!isLast) {
      final nextAt = sentAtOf(mapAt(index + 1));
      isLast = shouldShowDivider(at, nextAt) || !sameGroup(index, index + 1);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider && at != null) ChatTimestampDivider(at: at),
        Padding(
          padding: EdgeInsets.only(
            top: isFirst && !showDivider && index != 0 ? 10 : 0,
          ),
          child: ChatMessageBubble.fromMap(
            m,
            isMine: isMineOf(m),
            isFirstInGroup: isFirst,
            isLastInGroup: isLast,
          ),
        ),
      ],
    );
  }

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  bool _showTime = false;

  BorderRadius _bubbleRadius() {
    const full = Radius.circular(18);
    const flat = Radius.circular(4);
    if (widget.isMine) {
      return BorderRadius.only(
        topLeft: full,
        bottomLeft: full,
        topRight: widget.isFirstInGroup ? full : flat,
        bottomRight: widget.isLastInGroup ? full : flat,
      );
    }
    return BorderRadius.only(
      topRight: full,
      bottomRight: full,
      topLeft: widget.isFirstInGroup ? full : flat,
      bottomLeft: widget.isLastInGroup ? full : flat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = widget.isMine;
    final bubbleColor = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    final fgMuted = mine
        ? scheme.onPrimary.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final maxWidth =
        (MediaQuery.sizeOf(context).width * 0.78).clamp(200.0, 340.0);
    final hasAttachment =
        widget.attachmentUrl != null && widget.attachmentUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onTap: widget.sentAt == null
                ? null
                : () => setState(() => _showTime = !_showTime),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: EdgeInsets.symmetric(
                horizontal: hasAttachment ? 6 : 14,
                vertical: hasAttachment ? 6 : 9,
              ),
              constraints: BoxConstraints(maxWidth: maxWidth),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: _bubbleRadius(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasAttachment) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(
                        widget.attachmentUrl!,
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
                          child:
                              Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    ),
                    if (widget.message.isNotEmpty) const SizedBox(height: 6),
                  ],
                  if (widget.message.isNotEmpty)
                    Padding(
                      padding: hasAttachment
                          ? const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3)
                          : EdgeInsets.zero,
                      child: Text(
                        widget.message,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: fg, height: 1.25),
                      ),
                    ),
                  if (widget.showTranslation &&
                      widget.originalMessage != null &&
                      widget.originalMessage!.isNotEmpty &&
                      widget.originalMessage != widget.message) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: hasAttachment
                          ? const EdgeInsets.symmetric(horizontal: 8)
                          : EdgeInsets.zero,
                      child: Text(
                        '${AppStrings.t(appLocaleNotifier.value, 'translated_from')}: ${widget.originalMessage}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: fgMuted,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Tap-to-reveal exact send time, like Messenger.
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: (_showTime && widget.sentAt != null)
              ? Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(
                    ChatMessageBubble.formatTimestamp(widget.sentAt!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Centered grey timestamp shown between message groups, like Messenger.
class ChatTimestampDivider extends StatelessWidget {
  const ChatTimestampDivider({super.key, required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          ChatMessageBubble.formatDividerLabel(at),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
        ),
      ),
    );
  }
}
