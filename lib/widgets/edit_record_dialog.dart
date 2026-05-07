import 'package:flutter/material.dart';

import '../config/sheet_config.dart';
import '../models/mhs_record.dart';
import '../services/dropdown_options_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF1E293B);
const _kBorder = Color(0xFFE2E8F0);

// Map header colour value → section label
const _sectionLabels = <int, String>{
  0xFFD9D9D9: 'Client Information',
  0xFFB4C7E7: 'Clinic & Site',
  0xFFFFF2CC: 'Questionnaire Details',
  0xFFFFFFFF: 'Questionnaire Details',
  0xFFFFFF00: 'Dates',
  0xFFFFC000: 'Dates',
  0xFF92D050: 'Completion',
  0xFFFF0000: 'Follow-up & Outcome',
};

// ─────────────────────────────────────────────────────────────────────────────
// EditRecordDialog
// ─────────────────────────────────────────────────────────────────────────────
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
        _dropdownValues[column.key] = null;
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
      final existing = widget.record?.text(col.key) ?? '';
      if (opts.contains(existing)) {
        _dropdownValues[col.key] = existing;
      }
    }
    if (mounted) setState(() => _loadingOptions = false);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  void _save() {
    final values = <String, dynamic>{};
    for (final column in widget.config.columns) {
      if (column.options != null) {
        final selected = _dropdownValues[column.key];
        values[column.key] =
            selected ?? _controllers[column.key]?.text.trim() ?? '';
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
      initialDate:
          DateTime.tryParse(_controllers[key]?.text ?? '') ?? DateTime.now(),
    );
    if (picked == null) return;
    final value = '${picked.year.toString().padLeft(4, '0')}-'
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

  // ── Section grouping ───────────────────────────────────────────────────────

  List<_Section> _buildSections() {
    final sections = <_Section>[];
    String? currentLabel;
    List<SheetColumn> currentCols = [];

    for (final col in widget.config.columns) {
      final label =
          _sectionLabels[col.headerColor.value] ?? 'Other';
      if (label != currentLabel) {
        if (currentCols.isNotEmpty && currentLabel != null) {
          sections.add(_Section(currentLabel, List.from(currentCols)));
        }
        currentLabel = label;
        currentCols = [col];
      } else {
        currentCols.add(col);
      }
    }
    if (currentCols.isNotEmpty && currentLabel != null) {
      sections.add(_Section(currentLabel, List.from(currentCols)));
    }
    return sections;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 780,
        height: 680,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: _kPrimary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    _isEdit
                        ? Icons.edit_outlined
                        : Icons.add_circle_outline,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isEdit ? 'Edit Record' : 'Add Record',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon:
                        const Icon(Icons.close, color: Colors.white70),
                    splashRadius: 20,
                    tooltip: 'Cancel',
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: _loadingOptions
                  ? const Center(child: CircularProgressIndicator())
                  : _buildForm(),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black54,
                      side: const BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _loadingOptions ? null : _save,
                    icon:
                        const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final sections = _buildSections();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      itemCount: sections.length,
      itemBuilder: (context, sIdx) {
        final section = sections[sIdx];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section divider + label
            Padding(
              padding:
                  EdgeInsets.only(top: sIdx == 0 ? 0 : 16, bottom: 8),
              child: Row(
                children: [
                  Text(
                    section.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Divider(height: 1, color: _kBorder)),
                ],
              ),
            ),
            // Fields
            ...section.columns.map((col) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: col.options != null
                      ? _buildDropdownField(col)
                      : _buildTextField(col),
                )),
          ],
        );
      },
    );
  }

  // ── Dropdown field ─────────────────────────────────────────────────────────

  Widget _buildDropdownField(SheetColumn column) {
    final options = _liveOptions[column.key] ?? [];
    final selected = _dropdownValues[column.key];
    final safeSelected =
        (selected != null && options.contains(selected)) ? selected : null;

    final accent = column.isCompletionField
        ? const Color(0xFF16A34A)
        : const Color(0xFF2563EB);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: column.label.replaceAll('\n', ' '),
        labelStyle:
            const TextStyle(fontSize: 13, color: Colors.black54),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        filled: true,
        fillColor: column.isCompletionField
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFFAFAFA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeSelected,
          isExpanded: true,
          hint: const Text('Select…',
              style: TextStyle(color: Colors.black38, fontSize: 13)),
          style: const TextStyle(
              color: Colors.black87, fontSize: 13.5),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('— clear —',
                  style: TextStyle(color: Colors.black38, fontSize: 13)),
            ),
            ...options.map((opt) =>
                DropdownMenuItem<String>(value: opt, child: Text(opt))),
          ],
          onChanged: (v) =>
              setState(() => _dropdownValues[column.key] = v),
        ),
      ),
    );
  }

  // ── Text / date field ──────────────────────────────────────────────────────

  Widget _buildTextField(SheetColumn column) {
    final controller = _controllers[column.key]!;
    final isDate = _looksLikeDateField(column);
    final accent = column.isCompletionField
        ? const Color(0xFF16A34A)
        : const Color(0xFF2563EB);

    return TextFormField(
      controller: controller,
      maxLines: column.key.toLowerCase().contains('comment') ||
              column.key.toLowerCase().contains('info')
          ? 3
          : 1,
      style: const TextStyle(fontSize: 13.5, color: Colors.black87),
      decoration: InputDecoration(
        labelText: column.label.replaceAll('\n', ' '),
        labelStyle:
            const TextStyle(fontSize: 13, color: Colors.black54),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        filled: true,
        fillColor: column.isCompletionField
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFFAFAFA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: isDate
            ? IconButton(
                icon: Icon(Icons.calendar_today_outlined,
                    size: 17, color: accent),
                onPressed: () => _pickDate(column.key),
              )
            : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section data class
// ─────────────────────────────────────────────────────────────────────────────
class _Section {
  final String label;
  final List<SheetColumn> columns;
  const _Section(this.label, this.columns);
}
