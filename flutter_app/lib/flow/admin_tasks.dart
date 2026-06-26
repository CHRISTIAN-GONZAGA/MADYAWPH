import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_input.dart';
import '../widgets/app_state_views.dart';

/// Create and track tasks assigned to hotel staff.
class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key});

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  List<dynamic> _tasks = const [];
  List<Map<String, dynamic>> _staff = const [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

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
      final results = await Future.wait<dynamic>([
        portalDio().get<dynamic>('/tasks'),
        portalDio().get<Map<String, dynamic>>('/staff'),
      ]);
      final taskRes = results[0] as Response<dynamic>;
      final staffRes = results[1] as Response<Map<String, dynamic>>;
      final taskData = taskRes.data;
      final staffData = staffRes.data?['data'];
      final staffRows = staffData is List
          ? staffData.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];

      List<dynamic> tasks;
      if (taskData is Map && taskData['data'] is List) {
        tasks = taskData['data'] as List;
      } else if (taskData is List) {
        tasks = taskData;
      } else {
        tasks = const [];
      }

      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _staff = staffRows;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _staffLabel(String staffId) {
    for (final s in _staff) {
      if ((s['id'] ?? '').toString() == staffId) {
        return (s['name'] ?? 'Staff').toString();
      }
    }
    return 'Staff';
  }

  Future<void> _assignTask() async {
    if (_staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add staff members first (Settings → Staff management).'),
        ),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var assigneeId = (_staff.first['id'] ?? '').toString();
    var priority = 'medium';
    DateTime deadline = DateTime.now().add(const Duration(days: 1));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Assign task to staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppInput(controller: titleCtrl, label: 'Title'),
                const SizedBox(height: 8),
                AppInput(
                  controller: descCtrl,
                  label: 'Description',
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: assigneeId.isNotEmpty ? assigneeId : null,
                  decoration: const InputDecoration(
                    labelText: 'Assign to',
                    border: OutlineInputBorder(),
                  ),
                  items: _staff
                      .map(
                        (s) => DropdownMenuItem(
                          value: (s['id'] ?? '').toString(),
                          child: Text(
                            '${s['name'] ?? 'Staff'} (${s['role'] ?? ''})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => assigneeId = v ?? assigneeId),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setLocal(() => priority = v ?? priority),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Deadline'),
                  subtitle: Text(
                    '${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')} '
                    '${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: deadline,
                    );
                    if (date == null) return;
                    if (!ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(deadline),
                    );
                    setLocal(() {
                      deadline = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? 12,
                        time?.minute ?? 0,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final description = descCtrl.text.trim();
    if (title.isEmpty || description.isEmpty || assigneeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title, description, and assignee are required.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await portalDio().post('/tasks', data: {
        'title': title,
        'description': description,
        'assigned_to': assigneeId,
        'priority': priority,
        'deadline': deadline.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task assigned.')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Staff tasks'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_busy || _loading) ? null : _assignTask,
        icon: const Icon(Icons.add_task),
        label: const Text('Assign task'),
      ),
      body: _loading
          ? appScrollableLoading(onRefresh: _load)
          : _error != null
              ? appScrollableError(message: _error!, onRetry: _load, onRefresh: _load)
              : _tasks.isEmpty
                  ? appScrollableEmpty(
                      message:
                          'No tasks yet. Tap Assign task to give work to your staff team.',
                      onRefresh: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        itemCount: _tasks.length,
                        itemBuilder: (context, i) {
                          final t = _tasks[i] as Map<String, dynamic>;
                          final status = (t['status'] ?? 'pending').toString();
                          final priority = (t['priority'] ?? '').toString();
                          final assigneeId = (t['assigned_to'] ?? '').toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text((t['title'] ?? 'Task').toString()),
                              subtitle: Text(
                                '${_staffLabel(assigneeId)} · $status'
                                '${priority.isNotEmpty ? ' · $priority' : ''}',
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
