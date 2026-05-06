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
// Fixed layout constants (these are the *minimum* / natural widths)
// ─────────────────────────────────────────────────────────────────────────────
const double _rowNumberWidth = 42.0;
const double _checkboxWidth = 40.0;
const double _actionsWidth = 80.0;
const double _metaEmailWidth = 160.0;
const double _metaDateWidth = 130.0;
const double _rowHeight = 36.0;
const double _headerHeight = 48.0;

const _gridLine = BorderSide(color: Color(0xFFBFC5CC), width: 0.8);
const _headerBg = Color(0xFFD6DCE4);
const _evenRow = Colors.white;
const _oddRow = Color(0xFFF2F5F8);
const _selectedRow = Color(0xFFDDEAFA);
const _lockedRow = Color(0xFFFFEBEB);

const _hStyle = TextStyle(
  fontWeight: FontWeight.w700,
  fontSize: 12,
  color: Color(0xFF1A2433),
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

class _SheetPageState extends State<SheetPage> {
  final MhsFirestoreService _service = MhsFirestoreService();
  final ActivityService _activity = ActivityService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecordIds = {};

  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyHScrollController = ScrollController();
  final ScrollController _bodyVScrollController = ScrollController();

  String _search = '';
  bool _moving = false;

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

    _bodyHScrollController.addListener(() {
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyHScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  void _message(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

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
    return StreamBuilder<List<MhsRecord>>(
      stream: _service.watchRecords(widget.config.id),
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
                const SelectableText(
                  '#',
                  style: _hStyle,
                ),
              ),
              _hCell(
                _checkboxWidth * scale,
                FittedBox(
                  fit: BoxFit.scaleDown,
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
              ...widget.config.columns.map(
                    (col) => _hCell(
                  col.width * scale,
                  SelectableText(
                    col.label.replaceAll('\n', ' '),
                    style: _hStyle,
                    maxLines: 2,
                  ),
                  color: col.headerColor,
                ),
              ),
              _hCell(
                _metaEmailWidth * scale,
                const SelectableText(
                  'Last updated by',
                  style: _hStyle,
                ),
              ),
              _hCell(
                _metaDateWidth * scale,
                const SelectableText(
                  'Last updated',
                  style: _hStyle,
                ),
              ),
              _hCell(
                _actionsWidth * scale,
                const SelectableText(
                  'Actions',
                  style: _hStyle,
                ),
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
    return Scrollbar(
      controller: _bodyVScrollController,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _bodyHScrollController,
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _bodyVScrollController,
          child: SingleChildScrollView(
            controller: _bodyHScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalW,
              child: Column(
                children: [
                  for (int i = 0; i < records.length; i++)
                    _buildRow(
                      records[i],
                      i,
                      scale,
                    ),
                ],
              ),
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

    final rowBg = lockedByOther
        ? _lockedRow
        : selected
        ? _selectedRow
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
    final value = record.text(column.key);
    final isParcel =
        column.key.toLowerCase().contains('parcel') || column.key == 'parcel_no';

    final content = isParcel && value.isNotEmpty
        ? GestureDetector(
      onTap: () => _copyText(value, 'Parcel No'),
      child: Text(
        value,
        style: TextStyle(
          fontSize: fs,
          color: const Color(0xFF0066CC),
          decoration: TextDecoration.underline,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    )
        : Text(
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
    );

    return _dCell(
      column.width * scale,
      rowH,
      Row(
        children: [
          Expanded(child: content),
          if (value.trim().isNotEmpty && !isParcel)
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
      color: const Color(0xFF2F3A46),
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            widget.config.shortTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          _tbBtn(
            Icons.add_circle_outline,
            'Add record',
            _addRecord,
          ),
          _tbBtn(
            Icons.copy_all,
            'Copy selected',
                () => _copySelectedRows(visibleRecords),
          ),
          if (widget.config.completedField != null)
            _tbBtn(
              Icons.drive_file_move,
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
          const Spacer(),

          // Search box grows/shrinks with available space.
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 160,
              maxWidth: 340,
            ),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 17,
                  ),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                    tooltip: null,
                    icon: const Icon(
                      Icons.close,
                      size: 15,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _search = '');
                    },
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 5,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.config.title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: _isCompletedTab ? Colors.red : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Visible: ${visibleRecords.length}',
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.black54,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Selected: ${_selectedRecordIds.length}',
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.black54,
            ),
          ),
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