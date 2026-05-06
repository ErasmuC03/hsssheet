import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/mhs_record.dart';
import '../services/mhs_firestore_service.dart';

class HistoryDialog extends StatelessWidget {
  final MhsRecord record;
  final MhsFirestoreService service;

  const HistoryDialog({
    super.key,
    required this.record,
    required this.service,
  });

  String _formatTimestamp(dynamic value) {
    return MhsRecord.formatDateTime(value);
  }

  String _formatChanges(dynamic changes) {
    if (changes == null) return '';

    if (changes is Map) {
      final buffer = StringBuffer();

      changes.forEach((key, value) {
        if (value is Map && value.containsKey('old') && value.containsKey('new')) {
          buffer.writeln('$key: "${value['old']}" → "${value['new']}"');
        } else {
          buffer.writeln('$key: $value');
        }
      });

      return buffer.toString().trim();
    }

    return changes.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('History: ${record.text('clientName')}'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: service.watchHistory(record.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final history = snapshot.data!;

            if (history.isEmpty) {
              return const Center(child: Text('No history found.'));
            }

            return ListView.separated(
              itemCount: history.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = history[index];

                final action = item['action']?.toString() ?? '';
                final userEmail = item['userEmail']?.toString() ?? '';
                final timestamp = item['timestamp'];
                final changes = item['changes'];

                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    action,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'By: $userEmail\n'
                        'At: ${_formatTimestamp(timestamp)}\n\n'
                        '${_formatChanges(changes)}',
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}