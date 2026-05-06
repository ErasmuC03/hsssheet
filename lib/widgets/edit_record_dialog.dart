import 'package:flutter/material.dart';

import '../config/sheet_config.dart';
import '../models/mhs_record.dart';

class EditRecordDialog extends StatefulWidget {
  final SheetConfig config;
  final MhsRecord? record;

  const EditRecordDialog({
    super.key,
    required this.config,
    required this.record,
  });

  @override
  State<EditRecordDialog> createState() => _EditRecordDialogState();
}

class _EditRecordDialogState extends State<EditRecordDialog> {
  final Map<String, TextEditingController> _controllers = {};

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();

    for (final column in widget.config.columns) {
      _controllers[column.key] = TextEditingController(
        text: widget.record?.text(column.key) ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _save() {
    final values = <String, dynamic>{};

    for (final column in widget.config.columns) {
      values[column.key] = _controllers[column.key]?.text.trim() ?? '';
    }

    Navigator.of(context).pop(values);
  }

  Future<void> _pickDate(String key) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: DateTime.now(),
    );

    if (picked == null) return;

    final value =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';

    _controllers[key]?.text = value;
  }

  bool _looksLikeDateField(SheetColumn column) {
    final key = column.key.toLowerCase();
    final label = column.label.toLowerCase();

    return key.contains('date') ||
        key.contains('dob') ||
        label.contains('date') ||
        label.contains('due');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit record' : 'Add record'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: ListView.separated(
          itemCount: widget.config.columns.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final column = widget.config.columns[index];
            final controller = _controllers[column.key]!;

            return TextFormField(
              controller: controller,
              maxLines: column.key.toLowerCase().contains('comment') ? 4 : 1,
              decoration: InputDecoration(
                labelText: column.label.replaceAll('\n', ' '),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: column.isCompletionField
                    ? Colors.green.withOpacity(0.10)
                    : Colors.grey.withOpacity(0.05),
                suffixIcon: _looksLikeDateField(column)
                    ? IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () => _pickDate(column.key),
                )
                    : null,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }
}