import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mhs_record.dart';
import '../services/mhs_firestore_service.dart';
import '../utils/field_labels.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF1E293B);
const _kBorder = Color(0xFFE2E8F0);
const _kSurface = Color(0xFFF8FAFC);

const _kActionMeta = <String, _ActionMeta>{
  'created': _ActionMeta(
    label: 'Created',
    color: Color(0xFF7C3AED),
    icon: Icons.add_circle_outline,
  ),
  'edited': _ActionMeta(
    label: 'Edited',
    color: Color(0xFF2563EB),
    icon: Icons.edit_outlined,
  ),
  'inline_edit': _ActionMeta(
    label: 'Quick Edit',
    color: Color(0xFF0891B2),
    icon: Icons.bolt_outlined,
  ),
  'record_view': _ActionMeta(
    label: 'Viewed',
    color: Color(0xFF16A34A),
    icon: Icons.visibility_outlined,
  ),
  'moved_to_completed': _ActionMeta(
    label: 'Completed',
    color: Color(0xFF0D9488),
    icon: Icons.check_circle_outline,
  ),
  'demo_data_created': _ActionMeta(
    label: 'Demo Data',
    color: Color(0xFF9CA3AF),
    icon: Icons.science_outlined,
  ),
};

class _ActionMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _ActionMeta({
    required this.label,
    required this.color,
    required this.icon,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HistoryDialog
// ─────────────────────────────────────────────────────────────────────────────
class HistoryDialog extends StatelessWidget {
  final MhsRecord record;
  final MhsFirestoreService service;

  const HistoryDialog({
    super.key,
    required this.record,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final clientName = record.text('clientName');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 780,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Container(
              color: _kPrimary,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Change History',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (clientName.isNotEmpty)
                          Text(
                            clientName,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    splashRadius: 20,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: service.watchHistory(record.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final history = snapshot.data!;

                  if (history.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.history_toggle_off,
                              size: 40, color: Colors.black26),
                          SizedBox(height: 10),
                          Text(
                            'No history yet.',
                            style: TextStyle(color: Colors.black45),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 20),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final isLast = index == history.length - 1;
                      return _HistoryEntry(item: item, isLast: isLast);
                    },
                  );
                },
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────────
            Container(
              color: _kSurface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Colors.black38),
                  const SizedBox(width: 6),
                  const Text(
                    'All times are local.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black38),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Close'),
                  ),
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
// Single timeline entry
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryEntry extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isLast;

  const _HistoryEntry({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final action = item['action']?.toString() ?? '';
    final meta = _kActionMeta[action] ??
        const _ActionMeta(
          label: 'Event',
          color: Color(0xFF64748B),
          icon: Icons.circle_outlined,
        );
    final email = item['userEmail']?.toString() ?? '—';
    final ts = item['timestamp'];
    final changes = item['changes'];
    final hasChanges =
        changes is Map && changes.isNotEmpty && action != 'created';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline track ────────────────────────────────────────────────
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: meta.color.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: meta.color.withOpacity(0.35), width: 1.5),
                  ),
                  child:
                      Icon(meta.icon, color: meta.color, size: 15),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: _kBorder,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action badge + timestamp row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: meta.color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: meta.color.withOpacity(0.30), width: 0.8),
                        ),
                        child: Text(
                          meta.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: meta.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTs(ts),
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black45),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // User
                  Row(
                    children: [
                      _Avatar(email: email),
                      const SizedBox(width: 6),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF1E293B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  // Changes diff table
                  if (hasChanges) ...[
                    const SizedBox(height: 8),
                    _DiffTable(changes: changes as Map),
                  ],

                  // Created: show key initial values
                  if (action == 'created' && changes is Map) ...[
                    const SizedBox(height: 8),
                    _CreatedSummary(data: changes as Map),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate().toLocal();
    } else {
      return ts.toString();
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    String relative;
    if (diff.inSeconds < 60) {
      relative = 'just now';
    } else if (diff.inMinutes < 60) {
      relative = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      relative = '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      relative = '${diff.inDays}d ago';
    } else {
      relative = DateFormat('d MMM yyyy').format(dt);
    }
    final absolute = DateFormat('d MMM yyyy, HH:mm').format(dt);
    return '$relative  ·  $absolute';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diff table — shows old → new for each changed field
// ─────────────────────────────────────────────────────────────────────────────
class _DiffTable extends StatelessWidget {
  final Map changes;

  const _DiffTable({required this.changes});

  @override
  Widget build(BuildContext context) {
    final entries = changes.entries
        .where((e) => e.key != 'updatedAt' && e.key != 'updatedBy')
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Table(
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(1),
          2: IntrinsicColumnWidth(),
          3: FlexColumnWidth(1),
        },
        children: [
          // Header
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
            children: [
              _th('Field'),
              _th('Before'),
              _th(''),
              _th('After'),
            ],
          ),
          ...entries.map((e) {
            final key = e.key.toString();
            final val = e.value;
            final label = humanizeFieldKey(key);
            String oldVal = '';
            String newVal = '';
            if (val is Map && val.containsKey('old') && val.containsKey('new')) {
              oldVal = val['old']?.toString() ?? '';
              newVal = val['new']?.toString() ?? '';
            } else {
              newVal = val?.toString() ?? '';
            }
            return TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _kBorder, width: 0.6)),
              ),
              children: [
                _td(label, bold: true),
                _td(oldVal.isEmpty ? '—' : oldVal, muted: true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_forward,
                      size: 13, color: Colors.black38),
                ),
                _td(newVal.isEmpty ? '—' : newVal, highlight: newVal != oldVal),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.black45,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _td(String text, {bool bold = false, bool muted = false, bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: muted
                ? Colors.black38
                : highlight
                    ? const Color(0xFF1D4ED8)
                    : Colors.black87,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Created summary — key fields from the initial data
// ─────────────────────────────────────────────────────────────────────────────
class _CreatedSummary extends StatelessWidget {
  final Map data;

  const _CreatedSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final show = ['clientName', 'clientDob', 'umrn', 'sheet']
        .where((k) => data[k]?.toString().isNotEmpty == true)
        .toList();

    if (show.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        border: Border.all(color: const Color(0xFFDDD6FE)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: show.map((k) {
          return RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              children: [
                TextSpan(
                  text: '${humanizeFieldKey(k)}: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                TextSpan(text: data[k].toString()),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User avatar initials badge
// ─────────────────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String email;

  const _Avatar({required this.email});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(email);
    final color = _colorFromEmail(email);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
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

  Color _colorFromEmail(String email) {
    const palette = [
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF0891B2),
      Color(0xFF16A34A),
      Color(0xFFD97706),
      Color(0xFFDC2626),
      Color(0xFFDB2777),
    ];
    final hash = email.codeUnits.fold(0, (a, b) => a + b);
    return palette[hash % palette.length];
  }
}
