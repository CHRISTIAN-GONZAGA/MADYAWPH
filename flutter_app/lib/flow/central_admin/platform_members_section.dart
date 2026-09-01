import 'package:flutter/material.dart';

const _kPlatformNavy = Color(0xFF1A2B4A);
const _kPlatformGold = Color(0xFFD4A843);

/// Central admin directory of MADYAW members (search, points, delete).
class PlatformMembersSection extends StatefulWidget {
  const PlatformMembersSection({
    super.key,
    required this.members,
    required this.onRefresh,
    required this.onAddPoints,
    required this.onDelete,
  });

  final List<dynamic> members;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String id, String name) onAddPoints;
  final Future<void> Function(String id, String name) onDelete;

  @override
  State<PlatformMembersSection> createState() => _PlatformMembersSectionState();
}

class _PlatformMembersSectionState extends State<PlatformMembersSection> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return widget.members.whereType<Map<String, dynamic>>().where((m) {
      if (q.isEmpty) return true;
      final hay = [
        m['full_name'],
        m['email'],
        m['username'],
        m['phone'],
        m['member_shid_id'],
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pendingDelete = widget.members
        .whereType<Map<String, dynamic>>()
        .where((m) => m['deletion_requested'] == true)
        .length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F1A2E), _kPlatformNavy, Color(0xFF2D4A7A)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Members',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Search, add points, or delete a membership',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _chip(
                    'All',
                    '${widget.members.length}',
                    Icons.badge_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _chip(
                    'Deletion asked',
                    '$pendingDelete',
                    Icons.person_off_outlined,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _query,
              decoration: InputDecoration(
                hintText: 'Search name, email, username, or SHID',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No members match that search.')),
            )
          else
            ...filtered.map((m) => _MemberManageCard(
                  item: m,
                  onAddPoints: () => widget.onAddPoints(
                    (m['id'] ?? '').toString(),
                    (m['full_name'] ?? m['username'] ?? 'Member').toString(),
                  ),
                  onDelete: () => widget.onDelete(
                    (m['id'] ?? '').toString(),
                    (m['full_name'] ?? m['username'] ?? 'Member').toString(),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kPlatformGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kPlatformNavy),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _kPlatformNavy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberManageCard extends StatelessWidget {
  const _MemberManageCard({
    required this.item,
    required this.onAddPoints,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final VoidCallback onAddPoints;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = (item['full_name'] ?? 'Member').toString();
    final shid = (item['member_shid_id'] ?? '').toString();
    final email = (item['email'] ?? '').toString();
    final username = (item['username'] ?? '').toString();
    final status = (item['status'] ?? '').toString();
    final points = (item['points_balance'] as num?)?.toInt() ?? 0;
    final deletion = item['deletion_requested'] == true;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _kPlatformGold.withValues(alpha: 0.2),
                  child: const Icon(Icons.person_outline, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (username.isNotEmpty)
                        Text(
                          '@$username · $status',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Text(
                          status,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text(
                  '$points pts',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(email),
            ],
            if (shid.isNotEmpty) Text('SHID: $shid'),
            if (deletion) ...[
              const SizedBox(height: 8),
              Text(
                'Deletion requested — confirm in Approvals or delete here.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAddPoints,
                    child: const Text('Add points'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onDelete,
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
