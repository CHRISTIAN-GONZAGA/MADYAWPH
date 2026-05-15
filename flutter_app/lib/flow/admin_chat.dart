import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../dio_client.dart';
import '../widgets/chat_attachment.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/app_state_views.dart';
class AdminChatInboxScreen extends StatefulWidget {
  const AdminChatInboxScreen({super.key});

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
      setState(() {
        _threads = (res.data?['threads'] as List?) ?? const [];
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Guest chat inbox'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoadingView();
    if (_error != null) {
      return AppErrorView(message: _error!, onRetry: _load);
    }
    if (_threads.isEmpty) {
      return const Center(child: Text('No messages yet.'));
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
          final latest = (t['latest_message'] ?? '').toString();
          final unread = (t['unread_count'] ?? 0).toString();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text('Room $roomNo'),
              subtitle:
                  Text(latest, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: unread == '0'
                  ? const Icon(Icons.chevron_right)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(unread),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => AdminChatRoomScreen(
                          roomId: roomId, roomNumber: roomNo)),
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
  const AdminChatRoomScreen(
      {super.key, required this.roomId, required this.roomNumber});

  final String roomId;
  final String roomNumber;

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
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/chat/rooms/${widget.roomId}');
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
      if (image != null) {
        final form = await ChatAttachment.formWithImage(
          fields: {
            'room_id': widget.roomId,
            'room_number': widget.roomNumber,
            'guest_name': 'In-House Guest',
            'message': text.isEmpty ? '(image)' : text,
          },
          file: image,
        );
        await portalDio().post('/admin/chat/reply', data: form);
      } else {
        await portalDio().post('/admin/chat/reply', data: {
          'room_id': widget.roomId,
          'room_number': widget.roomNumber,
          'guest_name': 'In-House Guest',
          'message': text,
        });
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
    return AppScaffold(
      appBar: AppBar(
        title: Text('Room ${widget.roomNumber}'),
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
        final isAdmin = role == 'admin' || role == 'staff';
        return ChatMessageBubble.fromMap(m, isMine: isAdmin);
      },
    );
  }
}
