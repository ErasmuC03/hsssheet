import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/activity_service.dart';
import '../utils/field_labels.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF1E293B);
const _kBorder = Color(0xFFE2E8F0);
const _kSurface = Color(0xFFF8FAFC);

const _kActionMeta = <String, _Meta>{
  'login': _Meta('Login', Color(0xFF2563EB), Icons.login_rounded),
  'logout': _Meta('Logout', Color(0xFF64748B), Icons.logout_rounded),
  'record_view': _Meta('Viewed', Color(0xFF16A34A), Icons.visibility_outlined),
  'record_edit': _Meta('Edited', Color(0xFF2563EB), Icons.edit_outlined),
  'inline_edit': _Meta('Quick Edit', Color(0xFF0891B2), Icons.bolt_outlined),
  'created': _Meta('Created', Color(0xFF7C3AED), Icons.add_circle_outline),
  'moved_to_completed':
      _Meta('Completed', Color(0xFF0D9488), Icons.check_circle_outline),
  'demo_data_created':
      _Meta('Demo Data', Color(0xFF9CA3AF), Icons.science_outlined),
};

class _Meta {
  final String label;
  final Color color;
  final IconData icon;
  const _Meta(this.label, this.color, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminPage
// ─────────────────────────────────────────────────────────────────────────────
class AdminPage extends StatefulWidget {
  final User user;
  const AdminPage({super.key, required this.user});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final ActivityService _activitySvc = ActivityService();
  String _filterAction = 'all';
  String _filterUser = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Activity Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          // Action-type filter
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterAction,
                dropdownColor: _kPrimary,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                iconEnabledColor: Colors.white70,
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All actions')),
                  ..._kActionMeta.entries.map(
                    (e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value.label)),
                  ),
                ],
                onChanged: (v) => setState(() => _filterAction = v ?? 'all'),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _activitySvc.watchActivity(limit: 300),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;

          // Apply filters
          var events = all.where((e) {
            if (_filterAction != 'all' && e['action'] != _filterAction) {
              return false;
            }
            if (_filterUser.isNotEmpty &&
                !(e['userEmail']?.toString() ?? '')
                    .toLowerCase()
                    .contains(_filterUser)) {
              return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              // ── Stats strip ──────────────────────────────────────────────
              _StatsStrip(allEvents: all),

              // ── Filter bar ───────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.person_search,
                        size: 17, color: Colors.black45),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 260,
                      height: 34,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Filter by email…',
                          hintStyle: const TextStyle(
                              fontSize: 12.5, color: Colors.black38),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: Color(0xFFCCCCCC)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: Color(0xFFDDDDDD)),
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) =>
                            setState(() => _filterUser = v.trim().toLowerCase()),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${events.length} event${events.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black45),
                    ),
                    const SizedBox(width: 10),
                    // Live indicator
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Live',
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF22C55E)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _kBorder),

              // ── Column headers ───────────────────────────────────────────
              Container(
                color: const Color(0xFFF1F5F9),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Row(
                  children: [
                    SizedBox(
                        width: 36,
                        child: Text('#', style: _hStyle)),
                    SizedBox(
                        width: 160,
                        child: Text('Timestamp', style: _hStyle)),
                    SizedBox(
                        width: 240,
                        child: Text('User', style: _hStyle)),
                    SizedBox(
                        width: 120,
                        child: Text('Action', style: _hStyle)),
                    Expanded(child: Text('Details', style: _hStyle)),
                  ],
                ),
              ),
              const Divider(height: 1, color: _kBorder),

              // ── Event list ───────────────────────────────────────────────
              Expanded(
                child: events.isEmpty
                    ? const Center(
                        child: Text(
                          'No activity found.',
                          style: TextStyle(color: Colors.black45),
                        ),
                      )
                    : ListView.separated(
                        itemCount: events.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: _kBorder),
                        itemBuilder: (context, i) =>
                            _EventRow(event: events[i], index: i),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats strip
// ─────────────────────────────────────────────────────────────────────────────
class _StatsStrip extends StatelessWidget {
  final List<Map<String, dynamic>> allEvents;

  const _StatsStrip({required this.allEvents});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final todayEvents = allEvents.where((e) {
      final ts = e['timestamp'];
      if (ts is! Timestamp) return false;
      return ts.toDate().isAfter(todayStart);
    }).toList();

    final todayEdits = todayEvents
        .where((e) =>
            e['action'] == 'record_edit' || e['action'] == 'inline_edit')
        .length;

    final activeUsers = allEvents
        .map((e) => e['userEmail']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;

    // Most active user (most edit events)
    final editCounts = <String, int>{};
    for (final e in allEvents) {
      if (e['action'] == 'record_edit' || e['action'] == 'inline_edit') {
        final u = e['userEmail']?.toString() ?? '';
        if (u.isNotEmpty) editCounts[u] = (editCounts[u] ?? 0) + 1;
      }
    }
    final topUser = editCounts.entries.isEmpty
        ? null
        : editCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);

    return Container(
      color: _kPrimary,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          _StatCard(
            icon: Icons.today_outlined,
            label: "Today's edits",
            value: '$todayEdits',
          ),
          const SizedBox(width: 12),
          _StatCard(
            icon: Icons.people_outline,
            label: 'Active users',
            value: '$activeUsers',
          ),
          const SizedBox(width: 12),
          _StatCard(
            icon: Icons.star_outline,
            label: 'Most active',
            value: topUser == null
                ? '—'
                : topUser.key.split('@').first,
            subtitle: topUser == null
                ? null
                : '${topUser.value} edit${topUser.value == 1 ? '' : 's'}',
          ),
          const SizedBox(width: 12),
          _StatCard(
            icon: Icons.receipt_long_outlined,
            label: 'Total events',
            value: '${allEvents.length}',
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white60, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 10.5, color: Colors.white54),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white38)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event row
// ─────────────────────────────────────────────────────────────────────────────
class _EventRow extends StatefulWidget {
  final Map<String, dynamic> event;
  final int index;

  const _EventRow({required this.event, required this.index});

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final action = e['action']?.toString() ?? '';
    final meta = _kActionMeta[action] ??
        const _Meta('Event', Color(0xFF64748B), Icons.circle_outlined);
    final email = e['userEmail']?.toString() ?? '—';
    final ts = _fmtTs(e['timestamp']);
    final isEven = widget.index % 2 == 0;

    // Build detail text
    String detail = '';
    if (e['clientName'] != null) {
      detail = e['clientName'].toString();
      if (e['sheetId'] != null) {
        detail += '  (${_sheetLabel(e['sheetId'].toString())})';
      }
    }

    // For edits: list changed field names
    final changedFields = e['changedFields'];
    if (changedFields is List && changedFields.isNotEmpty) {
      final labels = changedFields
          .map((k) => humanizeFieldKey(k.toString()))
          .join(', ');
      if (detail.isNotEmpty) detail += '\n';
      detail += 'Fields: $labels';
    }

    // Does this row have expandable change detail?
    final changes = e['changes'];
    final hasChanges = changes is Map && changes.isNotEmpty &&
        action != 'demo_data_created';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasChanges ? () => setState(() => _expanded = !_expanded) : null,
          child: Container(
            color: isEven ? Colors.white : _kSurface,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${widget.index + 1}',
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black38),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Text(ts,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54)),
                ),
                SizedBox(
                  width: 240,
                  child: Row(
                    children: [
                      _SmallAvatar(email: email),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          email,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF1E293B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: _ActionBadge(meta: meta),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          detail,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      if (hasChanges)
                        Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: Colors.black38,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded && hasChanges)
          Container(
            color: const Color(0xFFF0F7FF),
            padding: const EdgeInsets.fromLTRB(76, 8, 16, 10),
            child: _MiniDiffTable(changes: changes as Map),
          ),
      ],
    );
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('dd MMM yy  HH:mm:ss').format(ts.toDate().toLocal());
    }
    return ts.toString();
  }

  String _sheetLabel(String id) {
    switch (id) {
      case 'paed_cns':
        return 'Paed & CNS';
      case 'clinpsych_sw_asd':
        return 'Clin Psych';
      case 'completed':
        return 'Completed';
      default:
        return id;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini diff table (expandable in admin row)
// ─────────────────────────────────────────────────────────────────────────────
class _MiniDiffTable extends StatelessWidget {
  final Map changes;

  const _MiniDiffTable({required this.changes});

  @override
  Widget build(BuildContext context) {
    final entries = changes.entries
        .where((e) =>
            e.key != 'updatedAt' &&
            e.key != 'updatedBy' &&
            e.key != 'updatedByEmail')
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final key = e.key.toString();
        final val = e.value;
        String oldVal = '';
        String newVal = '';

        if (val is Map &&
            val.containsKey('old') &&
            val.containsKey('new')) {
          oldVal = val['old']?.toString() ?? '';
          newVal = val['new']?.toString() ?? '';
        } else {
          newVal = val?.toString() ?? '';
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFFCFE2FF)),
                ),
                child: Text(
                  humanizeFieldKey(key),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (oldVal.isNotEmpty) ...[
                Text(
                  oldVal,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.black45,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(Icons.arrow_forward,
                      size: 11, color: Colors.black26),
                ),
              ],
              Text(
                newVal.isEmpty ? '(cleared)' : newVal,
                style: TextStyle(
                  fontSize: 11.5,
                  color: newVal.isEmpty
                      ? Colors.black38
                      : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────
class _ActionBadge extends StatelessWidget {
  final _Meta meta;

  const _ActionBadge({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: meta.color.withOpacity(0.30), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 11, color: meta.color),
          const SizedBox(width: 4),
          Text(
            meta.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: meta.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  final String email;

  const _SmallAvatar({required this.email});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(email);
    final color = _colorFor(email);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _initials(String email) {
    if (email.isEmpty || email == '—') return '?';
    final parts = email.split('@').first.split('.');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return email[0].toUpperCase();
  }

  Color _colorFor(String email) {
    const pal = [
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF0891B2),
      Color(0xFF16A34A),
      Color(0xFFD97706),
      Color(0xFFDC2626),
      Color(0xFFDB2777),
    ];
    final h = email.codeUnits.fold(0, (a, b) => a + b);
    return pal[h % pal.length];
  }
}

const _hStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: Colors.black45,
  letterSpacing: 0.3,
);
