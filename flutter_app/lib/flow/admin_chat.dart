import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../dio_client.dart';
import '../widgets/admin_notification_badge.dart';
import 'admin/admin_dashboard_header.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/app_state_views.dart';

/// Hub with separate guest and staff chat inboxes.
class AdminChatHubScreen extends StatefulWidget {
  const AdminChatHubScreen({super.key});

  @override
  State<AdminChatHubScreen> createState() => _AdminChatHubScreenState();
}

class _AdminChatHubScreenState extends State<AdminChatHubScreen> {
  AdminChatBadgeInfo _badge = const AdminChatBadgeInfo(
    totalUnread: 0,
    guestUnread: 0,
    staffUnread: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadBadge();
  }

  Future<void> _loadBadge() async {
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/chat/inbox');
      if (!mounted) return;
      setState(() {
        _badge = adminChatBadgeFromData(inbox: res.data, guestMessages: const []);
      });
    } on DioException {
      // Keep previous counts.
    }
  }

  Widget _tabLabel(String text, int count, Color color) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 6),
            AdminNotificationBadge(count: count, color: color, size: 16),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        appBar: AppBar(
          title: const Text('Chat'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadBadge,
              tooltip: 'Refresh unread counts',
            ),
          ],
          bottom: TabBar(
            tabs: [
              _tabLabel('Guests', _badge.guestUnread, AdminChatColors.guest),
              _tabLabel('Staff', _badge.staffUnread, AdminChatColors.staff),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AdminChatInboxScreen(
              staffOnly: false,
              onThreadsLoaded: _loadBadge,
            ),
            AdminChatInboxScreen(
              staffOnly: true,
              onThreadsLoaded: _loadBadge,
            ),
          ],
        ),
      ),
    );
  }
}

class AdminChatInboxScreen extends StatefulWidget {
  const AdminChatInboxScreen({
    super.key,
    required this.staffOnly,
    this.onThreadsLoaded,
  });

  final bool staffOnly;
  final VoidCallback? onThreadsLoaded;

  @override
  State<AdminChatInboxScreen> createState() => _AdminChatInboxScreenState();
}

class _AdminChatInboxScreenState extends State<AdminChatInboxScreen> {
  List<dynamic> _threads = const [];
  String? _error;
  bool _loading = true;

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
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/chat/inbox');
      final key = widget.staffOnly ? 'staff_threads' : 'guest_threads';
      final threads = (res.data?[key] as List?) ??
          (widget.staffOnly
              ? _filterStaffThreads(res.data?['threads'] as List?)
              : (res.data?['threads'] as List?) ?? const []);
      setState(() {
        _threads = threads;
        _loading = false;
      });
      widget.onThreadsLoaded?.call();
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<dynamic> _filterStaffThreads(List<dynamic>? threads) {
    if (threads == null) return const [];
    return threads
        .where((t) =>
            ((t as Map)['room_id'] ?? '').toString().startsWith('STAFF-ADMIN:'))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }
    if (_threads.isEmpty) {
      return Center(
        child: Text(
          widget.staffOnly
              ? 'No staff messages yet.'
              : 'No guest messages yet.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _threads.length,
        itemBuilder: (context, i) {
          final t = _threads[i] as Map<String, dynamic>;
          final roomId = (t['room_id'] ?? '').toString();
          final roomNo = (t['room_number'] ?? '').toString();
          final staffName = (t['staff_name'] ?? '').toString();
          final latest = (t['latest_message'] ?? '').toString();
          final unreadCount = (t['unread_count'] as num?)?.toInt() ?? 0;
          final isStaff = widget.staffOnly ||
              roomId.startsWith('STAFF-ADMIN:') ||
              (t['is_staff_thread'] == true);
          final badgeColor =
              isStaff ? AdminChatColors.staff : AdminChatColors.guest;
          final title =
              isStaff ? (staffName.isNotEmpty ? staffName : 'Staff') : 'Room $roomNo';
          final subtitlePrefix =
              isStaff ? 'Staff chat · ' : '';
          return Card(
            child: ListTile(
              leading: Icon(
                isStaff ? Icons.badge_outlined : Icons.forum_outlined,
              ),
              title: Text(title),
              subtitle: Text(
                '$subtitlePrefix$latest',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: unreadCount == 0
                  ? const Icon(Icons.chevron_right)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AdminNotificationBadge(
                          count: unreadCount,
                          color: badgeColor,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
              onTap: () async {
                final replyName = isStaff
                    ? (staffName.isNotEmpty ? staffName : 'Staff')
                    : 'In-House Guest';
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminChatRoomScreen(
                      roomId: roomId,
                      roomNumber: roomNo,
                      displayTitle: title,
                      replyGuestName: replyName,
                      isStaffThread: isStaff,
                    ),
                  ),
                );
                await _load();
              },
            ),
          );
        },
      ),
    );
  }
}

class AdminChatRoomScreen extends StatefulWidget {
  const AdminChatRoomScreen({
    super.key,
    required this.roomId,
    required this.roomNumber,
    this.displayTitle,
    this.replyGuestName = 'In-House Guest',
    this.isStaffThread = false,
  });

  final String roomId;
  final String roomNumber;
  final String? displayTitle;
  final String replyGuestName;
  final bool isStaffThread;

  @override
  State<AdminChatRoomScreen> createState() => _AdminChatRoomScreenState();
}

class _AdminChatRoomScreenState extends State<AdminChatRoomScreen> {
  List<dynamic> _messages = const [];
  String? _error;
  bool _loading = true;
  bool _sending = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final encodedRoomId = Uri.encodeComponent(widget.roomId);
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/chat/rooms/$encodedRoomId',
      );
      setState(() {
        _messages = (res.data?['messages'] as List?) ?? const [];
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _send({XFile? image}) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && image == null) return;
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final fields = {
        'room_id': widget.roomId,
        'room_number': widget.roomNumber,
        'guest_name': widget.replyGuestName,
        'message': text.isEmpty ? '(image)' : text,
      };
      if (image != null) {
        final form = await ChatAttachment.formWithImage(
          fields: fields,
          file: image,
        );
        await portalDio().post('/admin/chat/reply', data: form);
      } else {
        await portalDio().post('/admin/chat/reply', data: fields);
      }
      _ctrl.clear();
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(dioErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.displayTitle ??
        (widget.isStaffThread
            ? widget.replyGuestName
            : 'Room ${widget.roomNumber}');
    return AppScaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
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
                    label: 'Reply message',
                    hint: 'Type a reply',
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('No messages in this thread yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i] as Map<String, dynamic>;
        final role = (m['sender_role'] ?? '').toString();
        final isAdmin = role == 'admin';
        return ChatMessageBubble.fromMap(m, isMine: isAdmin);
      },
    );
  }
}
