import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/sheet_config.dart';
import '../main.dart' show showAppSnackBar;
import '../services/activity_service.dart';
import '../services/dropdown_options_service.dart';
import '../services/mhs_firestore_service.dart';
import '../services/presence_service.dart';
import 'admin_page.dart';
import 'dropdown_settings_page.dart';
import 'sheet_page.dart';

class HomePage extends StatefulWidget {
  final User user;

  const HomePage({
    super.key,
    required this.user,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final MhsFirestoreService _service = MhsFirestoreService();
  final ActivityService _activity = ActivityService();
  final PresenceService _presence = PresenceService();

  late final TabController _tabController;

  /// Pre-built tab pages — created once so TabBarView always receives the same
  /// widget instances and never tears down keep-alive state on presence updates.
  late final List<Widget> _tabChildren;

  /// Cached presence stream — avoids creating a new subscription every build.
  late final Stream<List<Map<String, dynamic>>> _presenceStream;

  bool _generatingDemoData = false;

  /// Sheet configs in tab order — must match TabBarView children.
  static final _tabs = [paedCnsConfig, clinPsychSwAsdConfig, completedConfig];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    // Build pages once — identity is stable for the lifetime of HomePage.
    _tabChildren = _tabs
        .map((cfg) => SheetPage(config: cfg, user: widget.user))
        .toList();

    _presenceStream = _presence.watchAllPresence();

    _activity.logLogin(widget.user);
    DropdownOptionsService().seedDefaultsIfEmpty();

    // Register presence on the initial tab.
    _presence.setPresence(widget.user, _tabs[0].id);

    // Update presence whenever the user switches tabs.
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _presence.setPresence(widget.user, _tabs[_tabController.index].id);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _activity.logLogout(widget.user);
    await _presence.clearPresence(widget.user.uid);
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _generateDemoData() async {
    setState(() => _generatingDemoData = true);
    try {
      final result = await _service.generateDemoDataOnce(user: widget.user);
      showAppSnackBar(result.alreadyGenerated
          ? 'Demo data has already been generated.'
          : 'Generated ${result.created} demo records.');
    } catch (e) {
      showAppSnackBar('Failed: $e');
    } finally {
      if (mounted) setState(() => _generatingDemoData = false);
    }
  }

  void _openAdminDashboard() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AdminPage(user: widget.user)),
      );

  void _openDropdownSettings() => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => DropdownSettingsPage(user: widget.user)),
      );

  @override
  Widget build(BuildContext context) {
    // The Scaffold and TabBarView are built once and never rebuilt on presence
    // changes. Only the TabBar labels (tiny widgets) rebuild via StreamBuilder.
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: const Text(
          'MHS Questionnaire Tracking',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          _AppBarBtn(
            icon: Icons.bar_chart_rounded,
            tooltip: 'Activity Dashboard',
            onTap: _openAdminDashboard,
          ),
          _AppBarBtn(
            icon: Icons.tune_rounded,
            tooltip: 'Dropdown Settings',
            onTap: _openDropdownSettings,
          ),
          _AppBarBtn(
            icon: Icons.dataset_outlined,
            tooltip: 'Generate demo data',
            onTap: _generatingDemoData ? null : _generateDemoData,
            loading: _generatingDemoData,
          ),
          _AppBarBtn(
            icon: Icons.logout_rounded,
            tooltip: 'Logout',
            onTap: _logout,
          ),
          const SizedBox(width: 6),
        ],
        // Only the tab labels need presence data — wrap just the TabBar so
        // presence heartbeats never trigger a Scaffold / TabBarView rebuild.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _presenceStream,
            builder: (context, presSnap) {
              final presence = presSnap.data ?? [];
              final Map<String, int> othersPerSheet = {};
              for (final doc in presence) {
                if (doc['userId']?.toString() == widget.user.uid) continue;
                final sid = doc['sheetId']?.toString() ?? '';
                if (sid.isNotEmpty) {
                  othersPerSheet[sid] = (othersPerSheet[sid] ?? 0) + 1;
                }
              }
              return TabBar(
                controller: _tabController,
                isScrollable: false,
                indicatorColor: const Color(0xFF3B82F6),
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: _tabs.map((cfg) {
                  final others = othersPerSheet[cfg.id] ?? 0;
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cfg.shortTitle),
                        if (others > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$others',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ),
      // Stable children list — same widget instances every build, so
      // AutomaticKeepAliveClientMixin actually keeps the pages alive.
      body: TabBarView(
        controller: _tabController,
        children: _tabChildren,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small app-bar button with consistent sizing
// ─────────────────────────────────────────────────────────────────────────────
class _AppBarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool loading;

  const _AppBarBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon, size: 22,
              color: onTap == null ? Colors.white38 : Colors.white),
    );
  }
}
