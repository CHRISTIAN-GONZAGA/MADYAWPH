import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../dio_client.dart';

/// FO check-in / check-out drill-down from Summary → Hotel totals.
Future<void> showFrontDeskActivityDialog(
  BuildContext context, {
  required String action,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) {
          return _FrontDeskActivitySheet(
            action: action,
            title: title,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class _FrontDeskActivitySheet extends StatefulWidget {
  const _FrontDeskActivitySheet({
    required this.action,
    required this.title,
    required this.scrollController,
  });

  final String action;
  final String title;
  final ScrollController scrollController;

  @override
  State<_FrontDeskActivitySheet> createState() => _FrontDeskActivitySheetState();
}

class _FrontDeskActivitySheetState extends State<_FrontDeskActivitySheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-activity',
        queryParameters: {'action': widget.action},
      );
      if (!mounted) return;
      final data = res.data ?? const {};
      final accounts = (data['accounts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [];
      setState(() {
        _accounts = accounts;
        _total = (data['total'] as num?)?.toInt() ?? 0;
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

  Future<void> _openAccountRooms(Map<String, dynamic> account) async {
    HapticFeedback.selectionClick();
    final userId = (account['user_id'] ?? '').toString();
    final username = (account['username'] ?? 'Front desk').toString();
    if (userId.isEmpty) return;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return _FrontDeskAccountRoomsSheet(
              action: widget.action,
              userId: userId,
              username: username,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  'Today · $_total room(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loadAccounts,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _accounts.isEmpty
                        ? Center(
                            child: Text(
                              'No registered front desk accounts yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            controller: widget.scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _accounts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final account = _accounts[index];
                              final count =
                                  (account['count'] as num?)?.toInt() ?? 0;
                              final username =
                                  (account['username'] ?? 'Front desk')
                                      .toString();
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => _openAccountRooms(account),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: scheme
                                              .primaryContainer
                                              .withValues(alpha: 0.7),
                                          child: Icon(
                                            Icons.badge_outlined,
                                            color: scheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                username,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '$count room(s) today',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '$count',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: scheme.primary,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _FrontDeskAccountRoomsSheet extends StatefulWidget {
  const _FrontDeskAccountRoomsSheet({
    required this.action,
    required this.userId,
    required this.username,
    required this.scrollController,
  });

  final String action;
  final String userId;
  final String username;
  final ScrollController scrollController;

  @override
  State<_FrontDeskAccountRoomsSheet> createState() =>
      _FrontDeskAccountRoomsSheetState();
}

class _FrontDeskAccountRoomsSheetState
    extends State<_FrontDeskAccountRoomsSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rooms = const [];

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/reports/frontdesk-activity/rooms',
        queryParameters: {
          'action': widget.action,
          'user_id': widget.userId,
        },
      );
      if (!mounted) return;
      final data = res.data ?? const {};
      final rooms = (data['rooms'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [];
      setState(() {
        _rooms = rooms;
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

  String _formatWhen(dynamic value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verb = widget.action == 'check_out' ? 'checked out' : 'checked in';

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.username,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  'Rooms $verb today · ${_rooms.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loadRooms,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _rooms.isEmpty
                        ? Center(
                            child: Text(
                              'No rooms $verb by this account today.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            controller: widget.scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _rooms.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final room = _rooms[index];
                              final roomNo =
                                  (room['room_number'] ?? '—').toString();
                              final guest =
                                  (room['guest_name'] ?? '').toString();
                              final reference =
                                  (room['booking_reference'] ?? '').toString();
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Room $roomNo',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (guest.isNotEmpty)
                                        Text(
                                          guest,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      if (reference.isNotEmpty)
                                        Text(
                                          reference,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatWhen(room['occurred_at']),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// Loads today's FO check-in/out totals for Summary cards.
class FoActivityStatCards extends StatefulWidget {
  const FoActivityStatCards({super.key});

  @override
  State<FoActivityStatCards> createState() => _FoActivityStatCardsState();
}

class _FoActivityStatCardsState extends State<FoActivityStatCards> {
  int _checkIns = 0;
  int _checkOuts = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTotals();
  }

  Future<void> _loadTotals() async {
    try {
      final dio = portalDio();
      final results = await Future.wait([
        dio.get<Map<String, dynamic>>(
          '/reports/frontdesk-activity',
          queryParameters: {'action': 'check_in'},
        ),
        dio.get<Map<String, dynamic>>(
          '/reports/frontdesk-activity',
          queryParameters: {'action': 'check_out'},
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _checkIns = (results[0].data?['total'] as num?)?.toInt() ?? 0;
        _checkOuts = (results[1].data?['total'] as num?)?.toInt() ?? 0;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FoStatCard(
            label: 'FO CHECK-IN',
            value: _loaded ? '$_checkIns' : '…',
            icon: Icons.login_rounded,
            color: Colors.indigo.shade700,
            onTap: () {
              HapticFeedback.selectionClick();
              showFrontDeskActivityDialog(
                context,
                action: 'check_in',
                title: 'FO check-in',
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _FoStatCard(
            label: 'FO CHECK-OUT',
            value: _loaded ? '$_checkOuts' : '…',
            icon: Icons.logout_rounded,
            color: Colors.deepPurple.shade700,
            onTap: () {
              HapticFeedback.selectionClick();
              showFrontDeskActivityDialog(
                context,
                action: 'check_out',
                title: 'FO check-out',
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FoStatCard extends StatelessWidget {
  const _FoStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.07),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
