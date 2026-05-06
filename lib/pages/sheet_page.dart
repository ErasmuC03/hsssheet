import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/sheet_config.dart';
import '../models/mhs_record.dart';
import '../services/mhs_firestore_service.dart';
import '../services/activity_service.dart';
import '../widgets/edit_record_dialog.dart';
import '../widgets/history_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const double _rowNumberWidth = 48.0;
const double _actionsWidth = 96.0;
const double _metaEmailWidth = 180.0;
const double _metaDateWidth = 140.0;
const double _rowHeight = 36.0;
const double _headerHeight = 52.0;

const _gridLine = BorderSide(color: Color(0xFFBFC5CC), width: 0.8);
const _headerBg = Color(0xFFD6DCE4);
const _evenRow = Colors.white;
const _oddRow = Color(0xFFF2F5F8);
const _selectedRow = Color(0xFFDDEAFA);
const _lockedRow = Color(0xFFFFEBEB);

// ─────────────────────────────────────────────────────────────────────────────
// SheetPage
// ─────────────────────────────────────────────────────────────────────────────
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
  final ActivityService _activity = ActivityService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecordIds = {};

  // Linked scroll controllers so header tracks body horizontally
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyHorizontalScrollController = ScrollController();
  final ScrollController _bodyVerticalScrollController = ScrollController();

  String _search = '';
  bool _moving = false;

  bool get _isCompletedTab => widget.config.id == 'completed';

  // Total fixed width for all data columns + extra meta columns
  double get _totalWidth {
    final colsWidth = widget.config.columns.fold(0.0, (sum, c) => sum + c.width);
    return _rowNumberWidth + colsWidth + _metaEmailWidth + _metaDateWidth + _actionsWidth;
  }

  @override
  void initState() {
    super.initState();
    // Keep header scroll in sync with body scroll
    _bodyHorizontalScrollController.addListener(() {
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyHorizontalScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _headerScrollController.dispose();
    _bodyHorizontalScrollController.dispose();
    _bodyVerticalScrollController.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _addRecord() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditRecordDialog(config: widget.config, record: null),
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
    // Log that user is viewing/editing
    await _activity.logRecordView(
      widget.user,
      record.id,
      record.text('clientName'),
      widget.config.id,
    );
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EditRecordDialog(config: widget.config, record: record),
      );
      if (values == null) {
        await _service.releaseLock(recordId: record.id, user: widget.user);
        return;
      }
      await _service.updateRecordAndUnlock(
        recordId: record.id,
        values: values,
        user: widget.user,
      );
      // Log the edit
      await _activity.logRecordEdit(
        widget.user,
        record.id,
        record.text('clientName'),
        widget.config.id,
        values,
      );
      _message('Record updated.');
    } catch (e) {
      await _service.releaseLock(recordId: record.id, user: widget.user);
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
      if (mounted) setState(() => _moving = false);
    }
  }

  void _openHistory(MhsRecord record) {
    showDialog(
      context: context,
      builder: (_) => HistoryDialog(record: record, service: _service),
    );
  }

  void _message(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<MhsRecord> _filterRecords(List<MhsRecord> records) {
    final search = _search.trim().toLowerCase();
    if (search.isEmpty) return records;
    return records.where((record) {
      for (final column in widget.config.columns) {
        if (record.text(column.key).toLowerCase().contains(search)) return true;
      }
      return record.updatedByEmail.toLowerCase().contains(search);
    }).toList();
  }

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    _message('$label copied.');
  }

  Future<void> _copySelectedRows(List<MhsRecord> visibleRecords) async {
    final selected = visibleRecords
        .where((r) => _selectedRecordIds.contains(r.id))
        .toList();
    if (selected.isEmpty) {
      _message('No rows selected.');
      return;
    }
    final header =
        widget.config.columns.map((c) => c.label.replaceAll('\n', ' ')).join('\t');
    final rows = selected.map((record) {
      return widget.config.columns.map((c) => record.text(c.key)).join('\t');
    }).join('\n');
    await Clipboard.setData(ClipboardData(text: '$header\n$rows'));
    _message('${selected.length} selected row(s) copied.');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
            // ── Frozen header ──────────────────────────────────────────────
            _buildFrozenHeader(allVisibleSelected, visibleIds),
            // ── Scrollable body ────────────────────────────────────────────
            Expanded(
              child: visibleRecords.isEmpty
                  ? const Center(
                      child: Text(
                        'No records found.',
                        style: TextStyle(color: Colors.black45),
                      ),
                    )
                  : _buildBody(visibleRecords),
            ),
          ],
        );
      },
    );
  }

  // ── Frozen header row ──────────────────────────────────────────────────────

  Widget _buildFrozenHeader(bool allSelected, Set<String> visibleIds) {
    return Container(
      height: _headerHeight,
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(bottom: BorderSide(color: Color(0xFF9DA7B0), width: 1.2)),
      ),
      child: SingleChildScrollView(
        controller: _headerScrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(), // driven by body scroll
        child: SizedBox(
          width: _totalWidth,
          child: Row(
            children: [
              // Row-number header cell
              _headerCell(width: _rowNumberWidth, child: const Text('#', style: _hStyle)),
              // Checkbox header
              _headerCell(
                width: 46,
                child: Checkbox(
                  value: allSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedRecordIds.addAll(visibleIds);
                      } else {
                        _selectedRecordIds.removeAll(visibleIds);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              // Data columns
              ...widget.config.columns.map((col) => _headerCell(
                    width: col.width,
                    color: col.headerColor,
                    child: Text(
                      col.label.replaceAll('\n', ' '),
                      style: _hStyle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  )),
              // Meta columns
              _headerCell(
                  width: _metaEmailWidth,
                  child: const Text('Last updated by', style: _hStyle)),
              _headerCell(
                  width: _metaDateWidth,
                  child: const Text('Last updated', style: _hStyle)),
              _headerCell(
                  width: _actionsWidth,
                  child: const Text('Actions', style: _hStyle)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell({
    required double width,
    required Widget child,
    Color? color,
  }) {
    return Container(
      width: width,
      height: _headerHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color ?? _headerBg,
        border: const Border(right: _gridLine),
      ),
      child: child,
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(List<MhsRecord> visibleRecords) {
    return Scrollbar(
      controller: _bodyVerticalScrollController,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _bodyHorizontalScrollController,
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _bodyVerticalScrollController,
          child: SingleChildScrollView(
            controller: _bodyHorizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _totalWidth,
              child: Column(
                children: [
                  for (int i = 0; i < visibleRecords.length; i++)
                    _buildRow(visibleRecords[i], i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(MhsRecord record, int index) {
    final selected = _selectedRecordIds.contains(record.id);
    final lockedByOther = record.isLockedByOther(widget.user.uid);

    Color rowBg;
    if (lockedByOther) {
      rowBg = _lockedRow;
    } else if (selected) {
      rowBg = _selectedRow;
    } else {
      rowBg = index.isEven ? _evenRow : _oddRow;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedRecordIds.remove(record.id);
          } else {
            _selectedRecordIds.add(record.id);
          }
        });
      },
      child: Container(
        height: _rowHeight,
        color: rowBg,
        child: Row(
          children: [
            // Row number
            _dataCell(
              width: _rowNumberWidth,
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontSize: 11.5, color: Colors.black38),
                textAlign: TextAlign.center,
              ),
              center: true,
            ),
            // Checkbox
            _dataCell(
              width: 46,
              child: Checkbox(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedRecordIds.add(record.id);
                    } else {
                      _selectedRecordIds.remove(record.id);
                    }
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              center: true,
            ),
            // Data columns
            ...widget.config.columns.map((col) => _buildDataCell(record, col)),
            // Meta: updated by
            _dataCell(
              width: _metaEmailWidth,
              child: Text(
                record.updatedByEmail,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Meta: updated at
            _dataCell(
              width: _metaDateWidth,
              child: Text(
                record.text('updatedAt'),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Actions
            _dataCell(
              width: _actionsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionBtn(
                    icon: lockedByOther ? Icons.lock : Icons.edit_outlined,
                    color: lockedByOther ? Colors.red : const Color(0xFF0066CC),
                    onTap: lockedByOther ? null : () => _editRecord(record),
                  ),
                  const SizedBox(width: 4),
                  _actionBtn(
                    icon: Icons.history,
                    color: Colors.black45,
                    onTap: () => _openHistory(record),
                  ),
                ],
              ),
              center: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCell(MhsRecord record, SheetColumn column) {
    final value = record.text(column.key);
    final isParcel =
        column.key.toLowerCase().contains('parcel') || column.key == 'parcel_no';

    Widget content;
    if (isParcel && value.isNotEmpty) {
      content = GestureDetector(
        onTap: () => _copyText(value, 'Parcel No'),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF0066CC),
            decoration: TextDecoration.underline,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else {
      content = Text(
        value,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight:
              column.isCompletionField ? FontWeight.w700 : FontWeight.w400,
          color: column.isCompletionField
              ? Colors.green.shade800
              : Colors.black87,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return _dataCell(
      width: column.width,
      child: Row(
        children: [
          Expanded(child: content),
          if (value.trim().isNotEmpty && !isParcel)
            InkWell(
              onTap: () => _copyText(value, column.label.replaceAll('\n', ' ')),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.copy, size: 13, color: Colors.black26),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataCell({
    required double width,
    required Widget child,
    bool center = false,
  }) {
    return Container(
      width: width,
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(
          right: _gridLine,
          bottom: _gridLine,
        ),
      ),
      child: child,
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 17, color: onTap == null ? Colors.black26 : color),
      ),
    );
  }

  // ── Top toolbar ────────────────────────────────────────────────────────────

  Widget _buildTopToolbar(List<MhsRecord> visibleRecords) {
    return Container(
      color: const Color(0xFF2F3A46),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            widget.config.shortTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          _toolbarBtn(Icons.add_circle_outline, 'Add record', _addRecord),
          _toolbarBtn(
              Icons.copy_all, 'Copy selected rows', () => _copySelectedRows(visibleRecords)),
          if (widget.config.completedField != null)
            _toolbarBtn(
              Icons.drive_file_move,
              'Move completed',
              _moving ? null : _moveCompleted,
              loading: _moving,
            ),
          _toolbarBtn(
            Icons.deselect,
            'Clear selection',
            _selectedRecordIds.isEmpty
                ? null
                : () => setState(() => _selectedRecordIds.clear()),
          ),
          const Spacer(),
          SizedBox(
            width: 300,
            height: 36,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search records…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: null,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String tip, VoidCallback? onTap,
      {bool loading = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, color: onTap == null ? Colors.white38 : Colors.white),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  // ── Info strip ─────────────────────────────────────────────────────────────

  Widget _buildInfoStrip(List<MhsRecord> visibleRecords) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.config.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _isCompletedTab ? Colors.red : Colors.black87,
              ),
            ),
          ),
          Text('Visible: ${visibleRecords.length}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(width: 16),
          Text('Selected: ${_selectedRecordIds.length}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  // ── Legend ─────────────────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: const [
          _LegendItem(color: Color(0xFF92D050), text: 'Completed / uploaded'),
          _LegendItem(color: Color(0xFFB4C7E7), text: 'WPS Questionnaire'),
          _LegendItem(color: Color(0xFFFFFF00), text: 'Due / removal date'),
          _LegendItem(color: Color(0xFFFFC000), text: 'Paper copy sent'),
          _LegendItem(color: Color(0xFFFF0000), text: 'Overdue / outcome', lightText: true),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header text style
// ─────────────────────────────────────────────────────────────────────────────
const _hStyle = TextStyle(
  fontWeight: FontWeight.w700,
  fontSize: 12,
  color: Color(0xFF1A2433),
);

// ─────────────────────────────────────────────────────────────────────────────
// Legend item
// ─────────────────────────────────────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  final bool lightText;

  const _LegendItem({required this.color, required this.text, this.lightText = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: lightText ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
