import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/activity_service.dart';

class AdminPage extends StatefulWidget {
  final User user;

  const AdminPage({super.key, required this.user});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final ActivityService _activityService = ActivityService();
  String _filterAction = 'all';
  String _filterUser = '';

  static const _actionColors = {
    'login': Color(0xFF2196F3),
    'logout': Color(0xFF9E9E9E),
    'record_view': Color(0xFF4CAF50),
    'record_edit': Color(0xFFFF9800),
    'created': Color(0xFF9C27B0),
    'moved_to_completed': Color(0xFF00BCD4),
  };

  static const _actionLabels = {
    'login': 'Login',
    'logout': 'Logout',
    'record_view': 'Record Viewed',
    'record_edit': 'Record Edited',
    'created': 'Record Created',
    'moved_to_completed': 'Moved to Completed',
  };

  Color _colorForAction(String action) =>
      _actionColors[action] ?? const Color(0xFF607D8B);

  String _labelForAction(String action) =>
      _actionLabels[action] ?? action;

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('dd MMM yyyy  HH:mm:ss').format(ts.toDate().toLocal());
    }
    return ts.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2F3A46),
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Text(
          'Activity Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
        actions: [
          // Filter by action type
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterAction,
                dropdownColor: const Color(0xFF2F3A46),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                iconEnabledColor: Colors.white,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All actions')),
                  ..._actionLabels.entries.map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) => setState(() => _filterAction = v ?? 'all'),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // User filter bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.person_search, size: 18, color: Colors.black54),
                const SizedBox(width: 8),
                SizedBox(
                  width: 280,
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Filter by email…',
                      hintStyle: const TextStyle(fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() => _filterUser = v.trim().toLowerCase()),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Showing latest 200 events · Live',
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Header row
          Container(
            color: const Color(0xFFE9EEF3),
            child: _buildHeaderRow(),
          ),
          const Divider(height: 1, color: Color(0xFFCCCCCC)),
          // Activity list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _activityService.watchActivity(limit: 200),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var events = snapshot.data!;

                // Apply filters
                if (_filterAction != 'all') {
                  events = events.where((e) => e['action'] == _filterAction).toList();
                }
                if (_filterUser.isNotEmpty) {
                  events = events
                      .where((e) =>
                      (e['userEmail']?.toString() ?? '').toLowerCase().contains(_filterUser))
                      .toList();
                }

                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'No activity found.',
                      style: TextStyle(color: Colors.black45),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  itemBuilder: (context, index) {
                    final e = events[index];
                    return _buildEventRow(e, index);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: const [
          SizedBox(width: 40, child: Text('#', style: _headerStyle)),
          SizedBox(width: 170, child: Text('Timestamp', style: _headerStyle)),
          SizedBox(width: 220, child: Text('User', style: _headerStyle)),
          SizedBox(width: 150, child: Text('Action', style: _headerStyle)),
          Expanded(child: Text('Details', style: _headerStyle)),
        ],
      ),
    );
  }

  Widget _buildEventRow(Map<String, dynamic> e, int index) {
    final action = e['action']?.toString() ?? '';
    final color = _colorForAction(action);
    final label = _labelForAction(action);
    final email = e['userEmail']?.toString() ?? '—';
    final ts = _formatTimestamp(e['timestamp']);
    final isEven = index % 2 == 0;

    String details = '';
    if (e['clientName'] != null) {
      details = e['clientName'].toString();
      if (e['sheetId'] != null) {
        details += '  (${_sheetLabel(e['sheetId'].toString())})';
      }
    }
    if (e['changedFields'] is List) {
      final fields = (e['changedFields'] as List).join(', ');
      details += details.isNotEmpty ? ' · Fields: $fields' : 'Fields: $fields';
    }

    return Container(
      color: isEven ? Colors.white : const Color(0xFFF7F9FC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(ts, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          SizedBox(
            width: 220,
            child: Text(
              email,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1A1A1A)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 150,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.35), width: 0.8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              details,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _sheetLabel(String sheetId) {
    switch (sheetId) {
      case 'paed_cns':
        return 'Paed & CNS';
      case 'clinpsych_sw_asd':
        return 'Clin Psych / SW / ASD';
      case 'completed':
        return 'Completed';
      default:
        return sheetId;
    }
  }
}

const _headerStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Color(0xFF2B2B2B),
);