import 'package:flutter/material.dart';

import '../config/sheet_config.dart';
import '../models/mhs_record.dart';
import '../services/dropdown_options_service.dart';

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
  final DropdownOptionsService _optionsSvc = DropdownOptionsService();

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _dropdownValues = {};

  /// Live options loaded from Firestore, keyed by field key.
  final Map<String, List<String>> _liveOptions = {};

  bool _loadingOptions = true;
  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();

    for (final column in widget.config.columns) {
      final existing = widget.record?.text(column.key) ?? '';
      _controllers[column.key] = TextEditingController(text: existing);
      if (column.options != null) {
        _dropdownValues[column.key] = null; // will be set after options load
      }
    }

    _loadAllOptions();
  }

  Future<void> _loadAllOptions() async {
    final dropdownCols =
        widget.config.columns.where((c) => c.options != null).toList();

    for (final col in dropdownCols) {
      final opts = await _optionsSvc.getOptions(col.key);
      _liveOptions[col.key] = opts;

      // Restore existing value if it's still in the list
      final existing = widget.record?.text(col.key) ?? '';
      if (opts.contains(existing)) {
        _dropdownValues[col.key] = existing;
      }
    }

    if (mounted) setState(() => _loadingOptions = false);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final values = <String, dynamic>{};

    for (final column in widget.config.columns) {
      if (column.options != null) {
        final selected = _dropdownValues[column.key];
        if (selected == null) {
          // Nothing selected — save whatever is in the text controller
          values[column.key] = _controllers[column.key]?.text.trim() ?? '';
        } else {
          values[column.key] = selected;
        }
      } else {
        values[column.key] = _controllers[column.key]?.text.trim() ?? '';
      }
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
    setState(() => _controllers[key]?.text = value);
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
        child: _loadingOptions
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                itemCount: widget.config.columns.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final column = widget.config.columns[index];
                  if (column.options != null) {
                    return _buildDropdownField(column);
                  }
                  return _buildTextField(column);
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _loadingOptions ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildDropdownField(SheetColumn column) {
    final options = _liveOptions[column.key] ?? [];
    final selected = _dropdownValues[column.key];

    // Guard: if selected value is no longer in the current options list, clear it
    final safeSelected = (selected != null && options.contains(selected))
        ? selected
        : null;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: column.label.replaceAll('\n', ' '),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: column.isCompletionField
            ? Colors.green.withOpacity(0.10)
            : Colors.grey.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeSelected,
          isExpanded: true,
          hint: const Text('Select…',
              style: TextStyle(color: Colors.black45)),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('— clear —',
                  style: TextStyle(color: Colors.black38, fontSize: 13)),
            ),
            ...options.map((opt) => DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt),
                )),
          ],
          onChanged: (v) =>
              setState(() => _dropdownValues[column.key] = v),
        ),
      ),
    );
  }

  Widget _buildTextField(SheetColumn column) {
    final controller = _controllers[column.key]!;
    final isDate = _looksLikeDateField(column);

    return TextFormField(
      controller: controller,
      maxLines: column.key.toLowerCase().contains('comment') ||
              column.key.toLowerCase().contains('info')
          ? 3
          : 1,
      decoration: InputDecoration(
        labelText: column.label.replaceAll('\n', ' '),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: column.isCompletionField
            ? Colors.green.withOpacity(0.10)
            : Colors.grey.withOpacity(0.05),
        suffixIcon: isDate
            ? IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () => _pickDate(column.key),
              )
            : null,
      ),
    );
  }
}
