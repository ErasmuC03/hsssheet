import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/sheet_config.dart';
import '../services/mhs_firestore_service.dart';
import '../services/activity_service.dart';
import '../services/dropdown_options_service.dart';
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

class _HomePageState extends State<HomePage> {
  final MhsFirestoreService _service = MhsFirestoreService();
  final ActivityService _activity = ActivityService();

  bool _generatingDemoData = false;

  @override
  void initState() {
    super.initState();

    _activity.logLogin(widget.user);

    // Seed dropdown defaults into Firestore if this is the first run.
    DropdownOptionsService().seedDefaultsIfEmpty();
  }

  Future<void> _logout() async {
    await _activity.logLogout(widget.user);
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _generateDemoData() async {
    if (_generatingDemoData) return;

    setState(() => _generatingDemoData = true);

    try {
      final result = await _service.generateDemoDataOnce(
        user: widget.user,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyGenerated
                ? 'Demo data has already been generated.'
                : 'Generated ${result.created} demo records.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate demo data: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _generatingDemoData = false);
      }
    }
  }

  void _openAdminDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPage(user: widget.user),
      ),
    );
  }

  void _openDropdownSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DropdownSettingsPage(user: widget.user),
      ),
    );
  }

  void _showRefreshMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live data refreshes automatically.'),
      ),
    );
  }

  Future<void> _handleCompactMenu(String value) async {
    switch (value) {
      case 'activity':
        _openAdminDashboard();
        break;
      case 'dropdowns':
        _openDropdownSettings();
        break;
      case 'demo':
        await _generateDemoData();
        break;
      case 'refresh':
        _showRefreshMessage();
        break;
      case 'logout':
        await _logout();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const darkHeader = Color(0xFF26313D);
    const pageBackground = Color(0xFFF4F6F9);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: pageBackground,
        body: Column(
          children: [
            Container(
              height: 58,
              decoration: const BoxDecoration(
                color: darkHeader,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.health_and_safety,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MHS Tracker',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Questionnaire Tracking Workbook',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final useCompactMenu = screenWidth < 980;

                      if (useCompactMenu) {
                        return Row(
                          children: [
                            _UserChip(email: widget.user.email ?? ''),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              color: Colors.white,
                              onSelected: _handleCompactMenu,
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'activity',
                                  child: _MenuItem(
                                    icon: Icons.bar_chart,
                                    text: 'Activity dashboard',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'dropdowns',
                                  child: _MenuItem(
                                    icon: Icons.tune,
                                    text: 'Dropdown settings',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'demo',
                                  enabled: !_generatingDemoData,
                                  child: const _MenuItem(
                                    icon: Icons.dataset,
                                    text: 'Generate demo data',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'refresh',
                                  child: _MenuItem(
                                    icon: Icons.refresh,
                                    text: 'Refresh info',
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'logout',
                                  child: _MenuItem(
                                    icon: Icons.logout,
                                    text: 'Logout',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          _HeaderButton(
                            icon: Icons.bar_chart,
                            label: 'Activity',
                            onTap: _openAdminDashboard,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.tune,
                            label: 'Dropdowns',
                            onTap: _openDropdownSettings,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.dataset,
                            label: _generatingDemoData ? 'Generating...' : 'Demo Data',
                            loading: _generatingDemoData,
                            onTap: _generatingDemoData ? null : _generateDemoData,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.refresh,
                            label: 'Refresh',
                            onTap: _showRefreshMessage,
                          ),
                          const SizedBox(width: 12),
                          _UserChip(email: widget.user.email ?? ''),
                          const SizedBox(width: 8),
                          _LogoutButton(onTap: _logout),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            Container(
              height: 42,
              color: const Color(0xFFF1F3F5),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicatorColor: const Color(0xFF26313D),
                      indicatorWeight: 3,
                      labelColor: const Color(0xFF26313D),
                      unselectedLabelColor: Colors.black54,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 18),
                      tabs: const [
                        Tab(height: 40, text: 'Paed & CNS'),
                        Tab(height: 40, text: 'Clin Psych / SW / ASD'),
                        Tab(height: 40, text: 'Completed / Deleted'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFD8DEE6)),

            Expanded(
              child: TabBarView(
                children: [
                  SheetPage(
                    config: paedCnsConfig,
                    user: widget.user,
                  ),
                  SheetPage(
                    config: clinPsychSwAsdConfig,
                    user: widget.user,
                  ),
                  SheetPage(
                    config: completedConfig,
                    user: widget.user,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  icon,
                  size: 17,
                  color: Colors.white,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final String email;

  const _UserChip({
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final displayEmail = email.trim().isEmpty ? 'Signed in' : email;

    return Container(
      height: 34,
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_circle,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              displayEmail,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LogoutButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        width: 38,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.red.withOpacity(0.25),
          ),
        ),
        child: const Icon(
          Icons.logout,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MenuItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.black87,
        ),
        const SizedBox(width: 10),
        Text(text),
      ],
    );
  }
}