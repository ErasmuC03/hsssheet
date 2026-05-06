import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/sheet_config.dart';
import '../models/mhs_record.dart';
import '../services/mhs_firestore_service.dart';
import '../widgets/edit_record_dialog.dart';
import '../widgets/history_dialog.dart';

class SheetPage extends StatefulWidget {
  final SheetConfig config;
  final User user;

  const SheetPage({
    super.key,
    required this.config,
    required this.user,
  });

  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  final MhsFirestoreService _service = MhsFirestoreService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecordIds = {};
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  String _search = '';
  bool _moving = false;

  bool get _isCompletedTab => widget.config.id == 'completed';

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _addRecord() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditRecordDialog(
        config: widget.config,
        record: null,
      ),
    );
    if (values == null) return;
    await _service.createRecord(
      config: widget.config,
      values: values,
      user: widget.user,
    );
    _message('Record added.');
  }

  Future<void> _editRecord(MhsRecord record) async {
    final lock = await _service.tryLockRecord(
      recordId: record.id,
      user: widget.user,
    );
    if (!lock.acquired) {
      final who = lock.lockedByEmail ?? 'another user';
      _message('This record is currently locked by $who.');
      return;
    }
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EditRecordDialog(
          config: widget.config,
          record: record,
        ),
      );
      if (values == null) {
        await _service.releaseLock(
          recordId: record.id,
          user: widget.user,
        );
        return;
      }
      await _service.updateRecordAndUnlock(
        recordId: record.id,
        values: values,
        user: widget.user,
      );
      _message('Record updated.');
    } catch (e) {
      await _service.releaseLock(
        recordId: record.id,
        user: widget.user,
      );
      _message('Update failed: $e');
    }
  }

  Future<void> _moveCompleted() async {
    setState(() => _moving = true);
    try {
      final result = await _service.moveCompletedRecords(
        config: widget.config,
        user: widget.user,
      );
      _message(
        'Moved ${result.moved}. '
            'Skipped locked: ${result.skippedLocked}. '
            'Incomplete: ${result.skippedIncomplete}.',
      );
    } catch (e) {
      _message('Move failed: $e');
    } finally {
      if (mounted) {
        setState(() => _moving = false);
      }
    }
  }

  void _openHistory(MhsRecord record) {
    showDialog(
      context: context,
      builder: (_) => HistoryDialog(
        record: record,
        service: _service,
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<MhsRecord> _filterRecords(List<MhsRecord> records) {
    final search = _search.trim().toLowerCase();
    if (search.isEmpty) return records;
    return records.where((record) {
      for (final column in widget.config.columns) {
        if (record.text(column.key).toLowerCase().contains(search)) {
          return true;
        }
      }
      if (record.updatedByEmail.toLowerCase().contains(search)) {
        return true;
      }
      return false;
    }).toList();
  }

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    _message('$label copied.');
  }

  Future<void> _copyRecord(MhsRecord record) async {
    final header = widget.config.columns
        .map((column) => column.label.replaceAll('\n', ' '))
        .join('\t');
    final values = widget.config.columns.map((column) {
      return record.text(column.key);
    }).join('\t');
    await Clipboard.setData(ClipboardData(text: '$header\n$values'));
    _message('Row copied. You can paste it into Excel.');
  }

  Future<void> _copySelectedRows(List<MhsRecord> visibleRecords) async {
    final selectedRecords = visibleRecords
        .where((record) => _selectedRecordIds.contains(record.id))
        .toList();
    if (selectedRecords.isEmpty) {
      _message('No rows selected.');
      return;
    }
    final header = widget.config.columns
        .map((c) => c.label.replaceAll('\n', ' '))
        .join('\t');
    final rows = selectedRecords.map((record) {
      return widget.config.columns.map((column) {
        return record.text(column.key);
      }).join('\t');
    }).join('\n');
    await Clipboard.setData(
      ClipboardData(text: '$header\n$rows'),
    );
    _message('${selectedRecords.length} selected row(s) copied.');
  }

  // ==================== STYLING THAT MATCHES YOUR SCREENSHOT ====================

  DataColumn _buildColumn(SheetColumn column) {
    final isNumeric = ['Qty', 'Weight', 'Cost %', 'PC', 'Total', 'DPTH', 'TBL', 'FLR']
        .contains(column.label);

    return DataColumn(
      tooltip: '',
      label: Container(
        width: column.width,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
        color: const Color(0xFFE9EEF3),
        child: Text(
          column.label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: Color(0xFF2B2B2B),
          ),
          textAlign: isNumeric ? TextAlign.right : TextAlign.left,
        ),
      ),
    );
  }

  DataCell _buildCell(MhsRecord record, SheetColumn column) {
    final value = record.text(column.key);
    final isNumeric = ['Qty', 'Weight', 'Cost %', 'PC', 'Total', 'DPTH', 'TBL', 'FLR']
        .contains(column.label);
    final isParcel = column.key.toLowerCase().contains('parcel') || column.key == 'parcel_no';

    return DataCell(
      Container(
        width: column.width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: isParcel
                  ? GestureDetector(
                onTap: () => _copyText(value, 'Parcel No'),
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF0066CC),
                    decoration: TextDecoration.underline,
                  ),
                ),
              )
                  : SelectableText(
                value,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: column.isCompletionField ? FontWeight.w700 : FontWeight.w400,
                  color: column.isCompletionField ? Colors.green.shade800 : Colors.black87,
                ),
              ),
            ),
            if (value.trim().isNotEmpty && !isParcel)
              InkWell(
                onTap: () => _copyText(value, column.label.replaceAll('\n', ' ')),
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.copy, size: 14, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  DataCell _buildActionsCell(MhsRecord record) {
    final lockedByOther = record.isLockedByOther(widget.user.uid);

    return DataCell(
      SizedBox(
        width: 110,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: null,
              icon: Icon(
                lockedByOther ? Icons.lock : Icons.edit,
                color: lockedByOther ? Colors.red : const Color(0xFF0066CC),
                size: 19,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: lockedByOther ? null : () => _editRecord(record),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: null,
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 19),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                // TODO: Implement delete if you need it
                _message('Delete functionality coming soon');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar(List<MhsRecord> visibleRecords) {
    return Container(
      color: const Color(0xFF2F3A46),
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            widget.config.shortTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 20),
          IconButton(
            tooltip: null,
            onPressed: _addRecord,
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          ),
          IconButton(
            tooltip: null,
            onPressed: () => _copySelectedRows(visibleRecords),
            icon: const Icon(Icons.copy_all, color: Colors.white),
          ),
          if (widget.config.completedField != null)
            IconButton(
              tooltip: null,
              onPressed: _moving ? null : _moveCompleted,
              icon: _moving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.drive_file_move, color: Colors.white),
            ),
          IconButton(
            tooltip: null,
            onPressed: _selectedRecordIds.isEmpty
                ? null
                : () => setState(() => _selectedRecordIds.clear()),
            icon: const Icon(Icons.deselect, color: Colors.white),
          ),
          const Spacer(),
          SizedBox(
            width: 340,
            height: 40,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search records...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                  tooltip: null,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStrip(List<MhsRecord> visibleRecords) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.config.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _isCompletedTab ? Colors.red : Colors.black87,
              ),
            ),
          ),
          Text(
            'Visible: ${visibleRecords.length}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(width: 16),
          Text(
            'Selected: ${_selectedRecordIds.length}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: const [
          _LegendItem(color: Color(0xFF00C853), text: 'Completed / uploaded'),
          _LegendItem(color: Color(0xFFB4A7D6), text: 'WPS Questionnaire'),
          _LegendItem(color: Color(0xFFFFEB3B), text: 'Due / removal date'),
          _LegendItem(color: Color(0xFFFFC000), text: 'Paper copy sent'),
          _LegendItem(color: Color(0xFFF44336), text: 'Overdue / outcome'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MhsRecord>>(
      stream: _service.watchRecords(widget.config.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data!;
        final visibleRecords = _filterRecords(records);
        final visibleIds = visibleRecords.map((r) => r.id).toSet();
        final allVisibleSelected = visibleRecords.isNotEmpty &&
            visibleIds.every(_selectedRecordIds.contains);

        return Column(
          children: [
            _buildTopToolbar(visibleRecords),
            _buildInfoStrip(visibleRecords),
            _buildLegend(),
            Expanded(
              child: visibleRecords.isEmpty
                  ? const Center(child: Text('No records found.'))
                  : Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                interactive: true,
                notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: Scrollbar(
                    controller: _verticalScrollController,
                    thumbVisibility: true,
                    interactive: true,
                    notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.vertical,
                    child: SingleChildScrollView(
                      controller: _verticalScrollController,
                      primary: false,
                      child: DataTable(
                        headingRowHeight: 50,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 56,
                        columnSpacing: 0,
                        horizontalMargin: 0,
                        dividerThickness: 0.8,
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFE9EEF3)),
                        dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                              (states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.blue.withOpacity(0.06);
                            }
                            return Colors.white;
                          },
                        ),
                        border: const TableBorder(
                          horizontalInside: BorderSide(color: Color(0xFFD4D7DD), width: 0.8),
                          bottom: BorderSide(color: Color(0xFFD4D7DD), width: 0.8),
                        ),
                        columns: [
                          DataColumn(
                            tooltip: '',
                            label: SizedBox(
                              width: 50,
                              child: Center(
                                child: Checkbox(
                                  value: allVisibleSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedRecordIds.addAll(visibleIds);
                                      } else {
                                        _selectedRecordIds.removeAll(visibleIds);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                          ...widget.config.columns.map(_buildColumn),
                          const DataColumn(
                            tooltip: '',
                            label: SizedBox(
                              width: 160,
                              child: Text(
                                'Last updated by',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                              ),
                            ),
                          ),
                          const DataColumn(
                            tooltip: '',
                            label: SizedBox(
                              width: 140,
                              child: Text(
                                'Last updated',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                              ),
                            ),
                          ),
                          const DataColumn(
                            tooltip: '',
                            label: SizedBox(
                              width: 110,
                              child: Center(
                                child: Text(
                                  'Acts',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                        rows: visibleRecords.map((record) {
                          final selected = _selectedRecordIds.contains(record.id);
                          return DataRow(
                            selected: selected,
                            color: WidgetStateProperty.resolveWith<Color?>(
                                  (_) {
                                if (record.isLockedByOther(widget.user.uid)) {
                                  return Colors.red.withOpacity(0.06);
                                }
                                if (selected) {
                                  return Colors.blue.withOpacity(0.06);
                                }
                                return null;
                              },
                            ),
                            cells: [
                              DataCell(
                                Center(
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedRecordIds.add(record.id);
                                        } else {
                                          _selectedRecordIds.remove(record.id);
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ),
                              ...widget.config.columns.map((col) => _buildCell(record, col)),
                              DataCell(
                                SelectableText(
                                  record.updatedByEmail,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              DataCell(
                                SelectableText(
                                  record.text('updatedAt'),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              _buildActionsCell(record),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendItem({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final isRed = color == const Color(0xFFF44336);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: isRed ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

