import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:image_picker/image_picker.dart';

import '../../dio_client.dart';
import '../../services/chat_notification_sound.dart';
import '../../widgets/admin_notification_badge.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/chat_attachment.dart';

const _kPlatformNavy = Color(0xFF1A2B4A);
const _kPlatformGold = Color(0xFFD4A843);

/// Central admin inbox of every hotel's MADYAW support thread.
class PlatformChatSection extends StatefulWidget {
  const PlatformChatSection({super.key});

  @override
  State<PlatformChatSection> createState() => _PlatformChatSectionState();
}

class _PlatformChatSectionState extends State<PlatformChatSection> {
  List<Map<String, dynamic>> _threads = const [];
  bool _loading = true;
  String? _error;
  Timer? _poll;
  int _unreadTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _threads.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await portalDio().get<Map<String, dynamic>>('/platform/chat/threads');
      if (!mounted) return;
      final raw = (res.data?['threads'] as List?) ?? const [];
      setState(() {
        _threads = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _unreadTotal = (res.data?['unread_total'] as num?)?.toInt() ?? 0;
        _loading = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (!silent || _threads.isEmpty) {
        setState(() {
          _error = dioErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _openHotel(Map<String, dynamic> thread) async {
    final hotelId = (thread['hotel_id'] ?? '').toString();
    if (hotelId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlatformHotelChatRoomScreen(
          hotelId: hotelId,
          hotelName: (thread['hotel_name'] ?? 'Hotel').toString(),
        ),
      ),
    );
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPlatformNavy, Color(0xFF2D4A7A)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.forum_outlined, color: _kPlatformGold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hotel chats',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      _unreadTotal > 0
                          ? '$_unreadTotal unread from hotels'
                          : 'Monitor every hotel conversation with MADYAW',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_threads.isEmpty) {
      return const Center(child: Text('No hotels registered yet.'));
    }

    final withMail = _threads.where((t) => t['has_messages'] == true).toList();
    final empty = _threads.where((t) => t['has_messages'] != true).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (withMail.isNotEmpty) ...[
          Text(
            'Active conversations',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _kPlatformNavy,
                ),
          ),
          const SizedBox(height: 8),
          ...withMail.map(_threadTile),
        ],
        if (empty.isNotEmpty) ...[
          if (withMail.isNotEmpty) const SizedBox(height: 16),
          Text(
            'Hotels with no messages yet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _kPlatformNavy,
                ),
          ),
          const SizedBox(height: 8),
          ...empty.map(_threadTile),
        ],
      ],
    );
  }

  Widget _threadTile(Map<String, dynamic> thread) {
    final unread = (thread['unread_count'] as num?)?.toInt() ?? 0;
    final latest = (thread['latest_message'] ?? '').toString().trim();
    final sender = (thread['latest_sender_name'] ?? '').toString().trim();
    final city = (thread['hotel_city'] ?? '').toString().trim();
    final subtitle = latest.isEmpty
        ? 'No messages yet — tap to start'
        : (sender.isEmpty ? latest : '$sender: $latest');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: unread > 0
                ? _kPlatformGold.withValues(alpha: 0.28)
                : _kPlatformNavy.withValues(alpha: 0.08),
            child: Icon(
              Icons.apartment_outlined,
              color: unread > 0 ? _kPlatformNavy : Colors.black54,
            ),
          ),
          title: Text(
            (thread['hotel_name'] ?? 'Hotel').toString(),
            style: TextStyle(
              fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            city.isEmpty ? subtitle : '$city · $subtitle',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: unread > 0
              ? AdminNotificationBadge(count: unread, color: _kPlatformGold)
              : const Icon(Icons.chevron_right),
          onTap: () => _openHotel(thread),
        ),
      ),
    );
  }
}

class PlatformHotelChatRoomScreen extends StatefulWidget {
  const PlatformHotelChatRoomScreen({
    super.key,
    required this.hotelId,
    required this.hotelName,
  });

  final String hotelId;
  final String hotelName;

  @override
  State<PlatformHotelChatRoomScreen> createState() =>
      _PlatformHotelChatRoomScreenState();
}

class _PlatformHotelChatRoomScreenState extends State<PlatformHotelChatRoomScreen> {
  List<dynamic> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  final _ctrl = TextEditingController();
  Timer? _poll;
  int _lastIncomingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  int _incomingCount(List<dynamic> messages) {
    return messages.where((m) {
      if (m is! Map) return false;
      final role = (m['sender_role'] ?? '').toString().toLowerCase();
      return role == 'admin' || role == 'super_admin';
    }).length;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/platform/chat/hotels/${widget.hotelId}',
      );
      if (!mounted) return;
      final next = (res.data?['messages'] as List<dynamic>?) ?? const [];
      final incoming = _incomingCount(next);
      if (silent && incoming > _lastIncomingCount && _lastIncomingCount > 0) {
        unawaited(ChatNotificationSound.playNewMessage());
      }
      setState(() {
        _messages = next;
        _lastIncomingCount = incoming;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (!silent || _messages.isEmpty) {
        setState(() {
          _error = dioErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _send({XFile? image}) async {
    final message = _ctrl.text.trim();
    if (message.isEmpty && image == null) return;
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final path = '/platform/chat/hotels/${widget.hotelId}/reply';
      if (image != null) {
        final form = await ChatAttachment.formWithImage(
          fields: {'message': message.isEmpty ? '(image)' : message},
          file: image,
        );
        await portalDio().post(path, data: form);
      } else {
        await portalDio().post(path, data: {'message': message});
      }
      _ctrl.clear();
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: Text(widget.hotelName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach photo',
                  onPressed: _sending
                      ? null
                      : () async {
                          final file = await ChatAttachment.pick(context);
                          if (file != null) await _send(image: file);
                        },
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: AppInput(
                    controller: _ctrl,
                    label: 'Reply',
                    hint: 'Message ${widget.hotelName}',
                  ),
                ),
                const SizedBox(width: 10),
                AppPrimaryButton(
                  label: 'Send',
                  onPressed: _sending ? null : () => _send(),
                  isLoading: _sending,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. You can start the conversation.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        return ChatMessageBubble.listItem(
          messages: _messages,
          index: i,
          isMineOf: (m) =>
              (m['sender_role'] ?? '').toString().toLowerCase() == 'central_admin',
        );
      },
    );
  }
}
