import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../main.dart' show showAppSnackBar;
import '../services/dropdown_options_service.dart';

/// Maps each dropdown field key → human-readable label shown in settings.
const _dropdownFields = {
  'localCdsCatchmentSite': 'Local CDS Catchment Site',
  'paediatricianClinic': 'Paediatrician / Clinic',
  'questionnairePlatform': 'Questionnaire Platform',
  'questionnaireType': 'Questionnaire Type',
  'completedBy': 'Completed By',
  'cpAsd': 'CP / ASD',
};

class DropdownSettingsPage extends StatefulWidget {
  final User user;
  const DropdownSettingsPage({super.key, required this.user});

  @override
  State<DropdownSettingsPage> createState() => _DropdownSettingsPageState();
}

class _DropdownSettingsPageState extends State<DropdownSettingsPage> {
  final DropdownOptionsService _svc = DropdownOptionsService();
  String _selectedField = _dropdownFields.keys.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2F3A46),
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Text(
          'Dropdown Options Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
      ),
      body: Row(
        children: [
          // ── Left panel: field selector ────────────────────────────────────
          Container(
            width: 260,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'FIELDS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: _dropdownFields.entries.map((entry) {
                      final isSelected = _selectedField == entry.key;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: const Color(0xFFE8F0FE),
                        selectedColor: const Color(0xFF1A73E8),
                        leading: Icon(
                          Icons.list_alt,
                          size: 18,
                          color: isSelected
                              ? const Color(0xFF1A73E8)
                              : Colors.black38,
                        ),
                        title: Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        onTap: () =>
                            setState(() => _selectedField = entry.key),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // ── Right panel: option editor ────────────────────────────────────
          Expanded(
            child: _FieldEditor(
              fieldKey: _selectedField,
              fieldLabel: _dropdownFields[_selectedField]!,
              service: _svc,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field editor panel
// ─────────────────────────────────────────────────────────────────────────────

class _FieldEditor extends StatefulWidget {
  final String fieldKey;
  final String fieldLabel;
  final DropdownOptionsService service;

  const _FieldEditor({
    required this.fieldKey,
    required this.fieldLabel,
    required this.service,
  });

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  final TextEditingController _addController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _addOption(List<String> current) async {
    final value = _addController.text.trim();
    if (value.isEmpty) return;
    if (current.contains(value)) {
      _showSnack('That option already exists.');
      return;
    }
    setState(() => _saving = true);
    await widget.service.setOptions(widget.fieldKey, [...current, value]);
    _addController.clear();
    setState(() => _saving = false);
  }

  Future<void> _deleteOption(List<String> current, String value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove option?'),
        content: Text(
            '"$value" will no longer appear in the dropdown. Existing records that already use it are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.setOptions(
        widget.fieldKey, current.where((e) => e != value).toList());
  }

  Future<void> _reorder(
      List<String> current, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final updated = List<String>.from(current);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    await widget.service.setOptions(widget.fieldKey, updated);
  }

  void _showSnack(String msg) => showAppSnackBar(msg);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: widget.service.watchOptions(widget.fieldKey),
      builder: (context, snapshot) {
        final options = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fieldLabel,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${options.length} option${options.length == 1 ? '' : 's'} · drag to reorder',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Add new option bar
            Container(
              color: const Color(0xFFF8F9FA),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      decoration: InputDecoration(
                        hintText: 'Type a new option and press Add…',
                        hintStyle:
                            const TextStyle(fontSize: 13, color: Colors.black38),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFCCCCCC)),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _addOption(options),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _addOption(options),
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F3A46),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Reorderable list
            Expanded(
              child: options.isEmpty
                  ? const Center(
                      child: Text(
                        'No options yet. Add one above.',
                        style: TextStyle(color: Colors.black38),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: options.length,
                      onReorder: (oldIndex, newIndex) =>
                          _reorder(options, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final opt = options[index];
                        return _OptionTile(
                          key: ValueKey(opt),
                          value: opt,
                          index: index,
                          onDelete: () => _deleteOption(options, opt),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single option row
// ─────────────────────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String value;
  final int index;
  final VoidCallback onDelete;

  const _OptionTile({
    super.key,
    required this.value,
    required this.index,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}',
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black38,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.drag_handle, size: 18, color: Colors.black26),
          ],
        ),
        title: Text(value, style: const TextStyle(fontSize: 13.5)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          tooltip: 'Remove',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
