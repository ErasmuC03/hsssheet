import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/sheet_config.dart';
import '../models/mhs_record.dart';
import '../services/mhs_firestore_service.dart';
import '../services/activity_service.dart';
import '../main.dart' show showAppSnackBar;
import '../services/dropdown_options_service.dart';
import '../services/presence_service.dart';
import '../widgets/edit_record_dialog.dart';
import '../widgets/history_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants
// ─────────────────────────────────────────────────────────────────────────────
const double _rowNumberWidth = 42.0;
const double _checkboxWidth = 40.0;
const double _actionsWidth = 80.0;
const double _metaEmailWidth = 160.0;
const double _metaDateWidth = 130.0;
const double _rowHeight = 38.0;
const double _headerHeight = 46.0;

// ─────────────────────────────────────────────────────────────────────────────
// Refined colour palette
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary     = Color(0xFF1E293B);
const _gridLine     = BorderSide(color: Color(0xFFD0D7E0), width: 0.7);
const _headerBg     = Color(0xFFEFF2F7);
const _evenRow      = Colors.white;
const _oddRow       = Color(0xFFF8FAFC);
const _selectedRow  = Color(0xFFEFF6FF);
const _lockedRow    = Color(0xFFFEF2F2);
const _overdueRow   = Color(0xFFFFFBEB);   // warm amber for past-due

const _hStyle = TextStyle(
  fontWeight: FontWeight.w700,
  fontSize: 11.5,
  color: Color(0xFF374151),
  letterSpacing: 0.2,
);

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

class _SheetPageState extends State<SheetPage>
    with AutomaticKeepAliveClientMixin {
  /// Keep this tab's state alive when the user switches to another tab so that
  /// the Firestore stream stays connected and the grid shows instantly on return.
  @override
  bool get wantKeepAlive => true;
  final MhsFirestoreService _service = MhsFirestoreService();
  final ActivityService _activity = ActivityService();
  final PresenceService _presence = PresenceService();

  /// Cached stream — created once in initState so StreamBuilder never
  /// resubscribes on setState, which would flash a spinner and re-fetch data.
  late final Stream<List<MhsRecord>> _recordsStream;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecordIds = {};

  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyHScrollController = ScrollController();
  final ScrollController _bodyVScrollController = ScrollController();

  String _search = '';
  bool _moving = false;

  // ── Inline editing ──────────────────────────────────────────────────────────
  String? _inlineTextRecordId;
  String? _inlineTextColumnKey;
  final TextEditingController _inlineTEC = TextEditingController();
  final FocusNode _inlineFocusNode = FocusNode();
  final Map<String, List<String>> _cachedDropdownOptions = {};
  Offset _pendingDropdownPosition = Offset.zero;

  bool get _isCompletedTab => widget.config.id == 'completed';

  /// Sum of all natural column widths.
  double get _naturalDataWidth =>
      widget.config.columns.fold(0.0, (s, c) => s + c.width);

  double _naturalTotalWidth() =>
      _rowNumberWidth +
          _checkboxWidth +
          _naturalDataWidth +
          _metaEmailWidth +
          _metaDateWidth +
          _actionsWidth;

  @override
  void initState() {
    super.initState();

    // Subscribe once — reuse across all rebuilds.
    _recordsStream = _service.watchRecords(widget.config.id);

    _bodyHScrollController.addListener(() {
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyHScrollController.offset);
      }
    });

    // Commit any pending inline text edit when the TextField loses focus
    // (e.g. user clicks a non-interactive area of the screen).
    _inlineFocusNode.addListener(() {
      if (!_inlineFocusNode.hasFocus) {
        _commitCurrentTextEdit();
      }
    });

    _preloadDropdownOptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inlineTEC.dispose();
    _inlineFocusNode.dispose();
    _headerScrollController.dispose();
    _bodyHScrollController.dispose();
    _bodyVScrollController.dispose();
    super.dispose();
  }

  // ── Scale factor ────────────────────────────────────────────────────────────

  /// Returns a scale factor so that all columns together fit [availableWidth].
  /// Minimum scale of 0.4 keeps text/icons readable.
  double _scale(double availableWidth) {
    final natural = _naturalTotalWidth();
    if (natural <= 0) return 1.0;

    final s = availableWidth / natural;
    return s.clamp(0.4, 3.0);
  }

  // ── Overdue detection ───────────────────────────────────────────────────────

  /// Returns true when the record's due date has passed and it is not yet
  /// marked as completed (only meaningful on active tabs, not the completed tab).
  bool _isOverdue(MhsRecord record) {
    final completedField = widget.config.completedField;
    if (completedField == null) return false;
    if (record.text(completedField).trim().isNotEmpty) return false;

    final dueDateStr = record.text('questionnaireDueDate');
    if (dueDateStr.isEmpty) return false;

    final dueDate = DateTime.tryParse(dueDateStr);
    if (dueDate == null) return false;

    return dueDate.isBefore(DateTime.now());
  }

  // ── Inline editing helpers ───────────────────────────────────────────────────

  /// Pre-loads all dropdown options for columns in this config so the first tap
  /// on any dropdown cell is instant.
  Future<void> _preloadDropdownOptions() async {
    for (final col in widget.config.columns) {
      if (col.options != null) {
        final opts = await DropdownOptionsService().getOptions(col.key);
        if (mounted) {
          setState(() => _cachedDropdownOptions[col.key] = opts);
        }
      }
    }
  }

  bool _looksLikeDateField(SheetColumn column) {
    final key = column.key.toLowerCase();
    final label = column.label.toLowerCase();
    return key.contains('date') ||
        key.contains('dob') ||
        label.contains('date') ||
        label.contains('due');
  }

  /// Commits the currently active inline text edit to Firestore.
  /// Safe to call even when no edit is in progress.
  Future<void> _commitCurrentTextEdit() async {
    if (_inlineTextRecordId == null || _inlineTextColumnKey == null) return;

    final recordId = _inlineTextRecordId!;
    final fieldKey = _inlineTextColumnKey!;
    final value = _inlineTEC.text.trim();

    // Clear state first so re-entrant calls are no-ops
    if (mounted) {
      setState(() {
        _inlineTextRecordId = null;
        _inlineTextColumnKey = null;
      });
    }

    try {
      await _service.quickUpdateField(
        recordId: recordId,
        fieldKey: fieldKey,
        value: value,
        user: widget.user,
      );
    } catch (e) {
      if (mounted) _message('Save failed: $e');
    }
  }

  /// Starts inline text editing for the given cell.
  Future<void> _startTextEdit(MhsRecord record, SheetColumn column) async {
    // Clicking the already-active cell is a no-op
    if (_inlineTextRecordId == record.id && _inlineTextColumnKey == column.key) {
      return;
    }

    // Commit any previous text edit before switching cells
    await _commitCurrentTextEdit();

    if (record.isLockedByOther(widget.user.uid)) {
      _message('Record is locked by ${record.lockedByEmail}');
      return;
    }

    if (!mounted) return;
    setState(() {
      _inlineTextRecordId = record.id;
      _inlineTextColumnKey = column.key;
      _inlineTEC.text = record.text(column.key);
    });
  }

  /// Shows a popup-menu dropdown for a dropdown column cell.
  Future<void> _showCellDropdownAtPosition(
    MhsRecord record,
    SheetColumn column,
    Offset globalPos,
  ) async {
    // Commit any pending text edit first
    await _commitCurrentTextEdit();

    if (record.isLockedByOther(widget.user.uid)) {
      _message('Record is locked by ${record.lockedByEmail}');
      return;
    }

    // Ensure options are cached
    if (!_cachedDropdownOptions.containsKey(column.key)) {
      final opts = await DropdownOptionsService().getOptions(column.key);
      if (!mounted) return;
      setState(() => _cachedDropdownOptions[column.key] = opts);
    }

    final options = _cachedDropdownOptions[column.key] ?? [];
    final currentValue = record.text(column.key);

    if (!mounted) return;

    final selected = await showMenu<String?>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 240,
        globalPos.dy + 300,
      ),
      initialValue: currentValue.isEmpty ? null : currentValue,
      items: [
        const PopupMenuItem<String?>(
          value: '__clear__',
          child: Text(
            '— clear —',
            style: TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ),
        ...options.map(
          (opt) => PopupMenuItem<String?>(
            value: opt,
            child: Text(opt, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );

    if (selected == null) return; // Dismissed without selection

    final newValue = selected == '__clear__' ? '' : selected;
    if (newValue == currentValue) return; // No change

    try {
      await _service.quickUpdateField(
        recordId: record.id,
        fieldKey: column.key,
        value: newValue,
        user: widget.user,
      );
    } catch (e) {
      if (mounted) _message('Save failed: $e');
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

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
      _message(
        'This record is currently locked by ${lock.lockedByEmail ?? 'another user'}.',
      );
      return;
    }

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

      await _activity.logRecordEdit(
        widget.user,
        record.id,
        record.text('clientName'),
        widget.config.id,
        values,
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
        'Moved ${result.moved}. Locked: ${result.skippedLocked}. Incomplete: ${result.skippedIncomplete}.',
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

  void _message(String msg) => showAppSnackBar(msg);

  List<MhsRecord> _filterRecords(List<MhsRecord> records) {
    final q = _search.trim().toLowerCase();

    if (q.isEmpty) return records;

    return records.where((r) {
      for (final col in widget.config.columns) {
        if (r.text(col.key).toLowerCase().contains(q)) {
          return true;
        }
      }

      return r.updatedByEmail.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(
      ClipboardData(text: value),
    );

    _message('$label copied.');
  }

  Future<void> _copySelectedRows(List<MhsRecord> visible) async {
    final selected = visible
        .where((r) => _selectedRecordIds.contains(r.id))
        .toList();

    if (selected.isEmpty) {
      _message('No rows selected.');
      return;
    }

    final header = widget.config.columns
        .map((c) => c.label.replaceAll('\n', ' '))
        .join('\t');

    final rows = selected
        .map(
          (r) => widget.config.columns
          .map((c) => r.text(c.key))
          .join('\t'),
    )
        .join('\n');

    await Clipboard.setData(
      ClipboardData(text: '$header\n$rows'),
    );

    _message('${selected.length} row(s) copied.');
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    return StreamBuilder<List<MhsRecord>>(
      stream: _recordsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final records = snapshot.data!;
        final visibleRecords = _filterRecords(records);
        final visibleIds = visibleRecords.map((r) => r.id).toSet();

        final allSelected = visibleRecords.isNotEmpty &&
            visibleIds.every(_selectedRecordIds.contains);

        return Column(
          children: [
            _buildTopToolbar(visibleRecords),
            _buildInfoStrip(visibleRecords),
            _buildLegend(),

            // Use LayoutBuilder so the table knows its available width.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availW = constraints.maxWidth;
                  final scale = _scale(availW);
                  final totalW = _naturalTotalWidth() * scale;

                  return Column(
                    children: [
                      _buildFrozenHeader(
                        allSelected,
                        visibleIds,
                        scale,
                        totalW,
                      ),
                      Expanded(
                        child: visibleRecords.isEmpty
                            ? const Center(
                          child: Text(
                            'No records found.',
                            style: TextStyle(color: Colors.black45),
                          ),
                        )
                            : _buildBody(
                          visibleRecords,
                          scale,
                          totalW,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Frozen header ────────────────────────────────────────────────────────────

  Widget _buildFrozenHeader(
      bool allSelected,
      Set<String> visibleIds,
      double scale,
      double totalW,
      ) {
    return Container(
      height: _headerHeight,
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF9DA7B0),
            width: 1.2,
          ),
        ),
      ),
      child: SingleChildScrollView(
        controller: _headerScrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: totalW,
          child: Row(
            children: [
              _hCell(
                _rowNumberWidth * scale,
                const Text('#', style: _hStyle),
              ),
              _hCell(
                _checkboxWidth * scale,
                Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: allSelected,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedRecordIds.addAll(visibleIds);
                        } else {
                          _selectedRecordIds.removeAll(visibleIds);
                        }
                      }),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
              ...widget.config.columns.map(
                (col) => _hCell(
                  col.width * scale,
                  Text(
                    col.label.replaceAll('\n', ' '),
                    style: _hStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  color: col.headerColor,
                ),
              ),
              _hCell(
                _metaEmailWidth * scale,
                const Text('Last updated by', style: _hStyle),
              ),
              _hCell(
                _metaDateWidth * scale,
                const Text('Last updated', style: _hStyle),
              ),
              _hCell(
                _actionsWidth * scale,
                const Text('Actions', style: _hStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hCell(
      double width,
      Widget child, {
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

  // ── Body ─────────────────────────────────────────────────────────────────────

  Widget _buildBody(
      List<MhsRecord> records,
      double scale,
      double totalW,
      ) {
    // Fixed row height so ListView can skip layout for off-screen rows.
    final rowH = (_rowHeight * scale).clamp(28.0, 52.0);

    // Horizontal scroll is the outer layer (synced with the frozen header).
    // Vertical scroll is handled by ListView.builder, which only renders
    // visible rows — critical for performance with 100+ records.
    return Scrollbar(
      controller: _bodyHScrollController,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _bodyHScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalW,
          child: Scrollbar(
            controller: _bodyVScrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _bodyVScrollController,
              itemCount: records.length,
              itemExtent: rowH, // fixed height → O(1) layout per scroll event
              itemBuilder: (context, i) => _buildRow(records[i], i, scale),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
      MhsRecord record,
      int index,
      double scale,
      ) {
    final selected = _selectedRecordIds.contains(record.id);
    final lockedByOther = record.isLockedByOther(widget.user.uid);
    final overdue = _isOverdue(record);

    final rowBg = lockedByOther
        ? _lockedRow
        : selected
            ? _selectedRow
            : overdue
                ? _overdueRow
                : index.isEven
                    ? _evenRow
                    : _oddRow;

    // Scale font sizes — clamp so they stay readable.
    final fs = (12.0 * scale).clamp(8.0, 14.0);
    final fsSmall = (11.0 * scale).clamp(7.5, 13.0);
    final rowH = (_rowHeight * scale).clamp(28.0, 52.0);

    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedRecordIds.remove(record.id);
        } else {
          _selectedRecordIds.add(record.id);
        }
      }),
      child: Container(
        height: rowH,
        color: rowBg,
        child: Row(
          children: [
            // Row number
            _dCell(
              _rowNumberWidth * scale,
              rowH,
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: fsSmall,
                  color: Colors.black38,
                ),
                textAlign: TextAlign.center,
              ),
              center: true,
            ),

            // Checkbox
            _dCell(
              _checkboxWidth * scale,
              rowH,
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Transform.scale(
                  scale: scale.clamp(0.6, 1.0),
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedRecordIds.add(record.id);
                      } else {
                        _selectedRecordIds.remove(record.id);
                      }
                    }),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              center: true,
              padding: EdgeInsets.zero,
            ),

            // Data columns
            ...widget.config.columns.map(
                  (col) => _buildDataCell(
                record,
                col,
                scale,
                fs,
                rowH,
              ),
            ),

            // Meta
            _dCell(
              _metaEmailWidth * scale,
              rowH,
              Text(
                record.updatedByEmail,
                style: TextStyle(
                  fontSize: fsSmall,
                  color: Colors.black54,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _dCell(
              _metaDateWidth * scale,
              rowH,
              Text(
                record.text('updatedAt'),
                style: TextStyle(
                  fontSize: fsSmall,
                  color: Colors.black54,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Actions
            // Fixed: FittedBox prevents RenderFlex overflow when the table scales down.
            _dCell(
              _actionsWidth * scale,
              rowH,
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _actionBtn(
                      icon: lockedByOther
                          ? Icons.lock
                          : Icons.edit_outlined,
                      color: lockedByOther
                          ? Colors.red
                          : const Color(0xFF0066CC),
                      onTap: lockedByOther
                          ? null
                          : () => _editRecord(record),
                    ),
                    SizedBox(width: (2 * scale).clamp(1, 4)),
                    _actionBtn(
                      icon: Icons.history,
                      color: Colors.black45,
                      onTap: () => _openHistory(record),
                    ),
                  ],
                ),
              ),
              center: true,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCell(
      MhsRecord record,
      SheetColumn column,
      double scale,
      double fs,
      double rowH,
      ) {
    final cellWidth = column.width * scale;
    final value = record.text(column.key);
    final lockedByOther = record.isLockedByOther(widget.user.uid);
    final isInlineEditing =
        _inlineTextRecordId == record.id && _inlineTextColumnKey == column.key;

    // ── Inline text edit mode ──────────────────────────────────────────────
    if (isInlineEditing) {
      return _buildInlineTextCell(column, cellWidth, rowH, fs, scale);
    }

    // ── Display mode ──────────────────────────────────────────────────────
    final isDropdown = column.options != null;

    Widget displayContent;

    if (isDropdown) {
      // Dropdown cell: show value + small arrow indicator
      displayContent = Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: fs,
                fontWeight: column.isCompletionField
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: column.isCompletionField
                    ? Colors.green.shade800
                    : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!lockedByOther)
            Icon(
              Icons.arrow_drop_down,
              size: (14.0 * scale).clamp(10.0, 16.0),
              color: Colors.black38,
            ),
        ],
      );
    } else {
      // Text cell: show value + copy icon
      displayContent = Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: fs,
                fontWeight: column.isCompletionField
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: column.isCompletionField
                    ? Colors.green.shade800
                    : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (value.trim().isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: InkWell(
                onTap: () => _copyText(
                  value,
                  column.label.replaceAll('\n', ' '),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.copy,
                    size: (12.0 * scale).clamp(9.0, 14.0),
                    color: Colors.black26,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: isDropdown && !lockedByOther
          ? (d) => _pendingDropdownPosition = d.globalPosition
          : null,
      onTap: lockedByOther
          ? null
          : () {
              if (isDropdown) {
                _showCellDropdownAtPosition(
                    record, column, _pendingDropdownPosition);
              } else {
                _startTextEdit(record, column);
              }
            },
      child: _dCell(cellWidth, rowH, displayContent),
    );
  }

  /// Inline text-editing cell (shown instead of the read-only cell).
  Widget _buildInlineTextCell(
      SheetColumn column,
      double cellWidth,
      double rowH,
      double fs,
      double scale,
      ) {
    final isDate = _looksLikeDateField(column);

    return Container(
      width: cellWidth,
      height: rowH,
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border.all(color: const Color(0xFF1976D2), width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inlineTEC,
              focusNode: _inlineFocusNode,
              autofocus: true,
              style: TextStyle(fontSize: fs, color: Colors.black87),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commitCurrentTextEdit(),
            ),
          ),
          if (isDate)
            GestureDetector(
              onTap: () async {
                final parsed = DateTime.tryParse(_inlineTEC.text);
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  initialDate: parsed ?? DateTime.now(),
                );
                if (picked != null && mounted) {
                  _inlineTEC.text =
                      '${picked.year.toString().padLeft(4, '0')}-'
                      '${picked.month.toString().padLeft(2, '0')}-'
                      '${picked.day.toString().padLeft(2, '0')}';
                  _commitCurrentTextEdit();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.calendar_today,
                  size: (12.0 * scale).clamp(10.0, 14.0),
                  color: const Color(0xFF1976D2),
                ),
              ),
            ),
          const SizedBox(width: 2),
          // ✓ commit
          GestureDetector(
            onTap: _commitCurrentTextEdit,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 1),
              child: Icon(Icons.check_circle, size: 15, color: Colors.green),
            ),
          ),
          // ✕ cancel
          GestureDetector(
            onTap: () => setState(() {
              _inlineTextRecordId = null;
              _inlineTextColumnKey = null;
            }),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 1),
              child: Icon(Icons.cancel, size: 15, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dCell(
      double width,
      double height,
      Widget child, {
        bool center = false,
        EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 5),
      }) {
    return Container(
      width: width,
      height: height,
      padding: padding,
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
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? Colors.black26 : color,
        ),
      ),
    );
  }

  // ── Toolbar ──────────────────────────────────────────────────────────────────

  Widget _buildTopToolbar(List<MhsRecord> visibleRecords) {
    return Container(
      color: _kPrimary,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Action buttons
          _tbBtn(Icons.add_circle_outline, 'Add record', _addRecord),
          _tbBtn(
            Icons.copy_all,
            'Copy selected',
            () => _copySelectedRows(visibleRecords),
          ),
          if (widget.config.completedField != null)
            _tbBtn(
              Icons.drive_file_move_outlined,
              'Move completed',
              _moving ? null : _moveCompleted,
              loading: _moving,
            ),
          _tbBtn(
            Icons.deselect,
            'Clear selection',
            _selectedRecordIds.isEmpty
                ? null
                : () => setState(() => _selectedRecordIds.clear()),
          ),

          const SizedBox(width: 8),

          // Overdue badge
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _presence.watchSheetPresence(widget.config.id),
            builder: (ctx, snap) {
              final users = (snap.data ?? [])
                  .where((p) =>
                      p['userId']?.toString() != widget.user.uid)
                  .toList();
              if (users.isEmpty) return const SizedBox.shrink();
              return Row(
                children: [
                  const SizedBox(width: 4),
                  const Text(
                    'Also viewing:',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 11.5),
                  ),
                  const SizedBox(width: 6),
                  ...users.take(5).map((p) {
                    final email =
                        p['userEmail']?.toString() ?? '?';
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: email,
                        child: _PresenceAvatar(email: email),
                      ),
                    );
                  }),
                  if (users.length > 5)
                    Text(
                      '+${users.length - 5}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                ],
              );
            },
          ),

          const Spacer(),

          // Search box
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 160,
              maxWidth: 320,
            ),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle:
                      const TextStyle(color: Colors.black45, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 17),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tbBtn(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
        bool loading = false,
      }) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 34,
        minHeight: 34,
      ),
      icon: loading
          ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      )
          : Icon(
        icon,
        size: 20,
        color: onTap == null ? Colors.white38 : Colors.white,
      ),
    );
  }

  // ── Info strip ───────────────────────────────────────────────────────────────

  Widget _buildInfoStrip(List<MhsRecord> visibleRecords) {
    final overdueCount =
        visibleRecords.where(_isOverdue).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.config.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isCompletedTab
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF374151),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (overdueCount > 0) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFFC107), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 12, color: Color(0xFFB45309)),
                  const SizedBox(width: 4),
                  Text(
                    '$overdueCount overdue',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '${visibleRecords.length} record${visibleRecords.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
          if (_selectedRecordIds.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              '${_selectedRecordIds.length} selected',
              style: const TextStyle(
                  fontSize: 11.5, color: Color(0xFF2563EB)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Legend ───────────────────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 5),
      child: Wrap(
        spacing: 5,
        runSpacing: 3,
        children: const [
          _LegendItem(
            color: Color(0xFF92D050),
            text: 'Completed / uploaded',
          ),
          _LegendItem(
            color: Color(0xFFB4C7E7),
            text: 'WPS Questionnaire',
          ),
          _LegendItem(
            color: Color(0xFFFFFF00),
            text: 'Due / removal date',
          ),
          _LegendItem(
            color: Color(0xFFFFC000),
            text: 'Paper copy sent',
          ),
          _LegendItem(
            color: Color(0xFFFF0000),
            text: 'Overdue / outcome',
            lightText: true,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence avatar (shown in toolbar)
// ─────────────────────────────────────────────────────────────────────────────
class _PresenceAvatar extends StatelessWidget {
  final String email;

  const _PresenceAvatar({required this.email});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(email);
    final color = _colorFor(email);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _initials(String email) {
    if (email.isEmpty) return '?';
    final parts = email.split('@').first.split('.');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return email[0].toUpperCase();
  }

  Color _colorFor(String email) {
    const palette = [
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF0891B2),
      Color(0xFF16A34A),
      Color(0xFFD97706),
      Color(0xFFDC2626),
    ];
    final h = email.codeUnits.fold(0, (a, b) => a + b);
    return palette[h % palette.length];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legend item
// ─────────────────────────────────────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  final bool lightText;

  const _LegendItem({
    required this.color,
    required this.text,
    this.lightText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: lightText ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}