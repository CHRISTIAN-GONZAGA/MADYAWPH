import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:image_picker/image_picker.dart';

import '../../dio_client.dart';
import '../../services/chat_notification_sound.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_input.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/chat_attachment.dart';

/// Hotel admin / super admin thread with MADYAW platform support.
class HotelMadyawChatScreen extends StatefulWidget {
  const HotelMadyawChatScreen({super.key});

  @override
  State<HotelMadyawChatScreen> createState() => _HotelMadyawChatScreenState();
}

class _HotelMadyawChatScreenState extends State<HotelMadyawChatScreen> {
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
      return role == 'central_admin';
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
        '/admin/platform-chat/messages',
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
    } catch (e) {
      if (!mounted) return;
      if (!silent || _messages.isEmpty) {
        setState(() {
          _error = '$e';
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
      if (image != null) {
        final form = await ChatAttachment.formWithImage(
          fields: {'message': message.isEmpty ? '(image)' : message},
          file: image,
        );
        await portalDio().post('/admin/platform-chat/messages', data: form);
      } else {
        await portalDio().post(
          '/admin/platform-chat/messages',
          data: {'message': message},
        );
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
        title: const Text('Chat with MADYAW'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
            child: const ListTile(
              leading: Icon(Icons.support_agent_outlined),
              title: Text('MADYAW platform support'),
              subtitle: Text('Messages go to central admin. They will reply here.'),
            ),
          ),
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
                    label: 'Message',
                    hint: 'Write to MADYAW',
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
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No messages yet. Ask MADYAW about credits, billing, or account support.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        return ChatMessageBubble.listItem(
          messages: _messages,
          index: i,
          isMineOf: (m) {
            final role = (m['sender_role'] ?? '').toString().toLowerCase();
            return role == 'admin' || role == 'super_admin';
          },
        );
      },
    );
  }
}
