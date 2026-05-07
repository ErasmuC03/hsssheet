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
  const HomePage({super.key, required this.user});

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
      final result = await _service.generateDemoDataOnce(user: widget.user);
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
        SnackBar(content: Text('Failed to generate demo data: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingDemoData = false);
    }
  }

  void _openAdminDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminPage(user: widget.user)),
    );
  }

  void _openDropdownSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DropdownSettingsPage(user: widget.user)),
    );
  }

  void _showRefreshMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live data refreshes automatically.')),
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
    // === ULTRA-PREMIUM PALETTE ===
    const headerColor = Color(0xFF0F172A); // Deep premium slate (2026 SaaS standard)
    const pageBackground = Color(0xFFF8FAFC);
    const accentBlue = Color(0xFF3B82F6);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: pageBackground,
        body: Column(
          children: [
            // === MASTER-LEVEL APP BAR (truly expert) ===
            Container(
              height: 76,
              decoration: BoxDecoration(
                color: headerColor,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2C000000),
                    blurRadius: 24,
                    offset: Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  // Premium branding
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.11),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.health_and_safety_outlined,
                          color: Colors.white,
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MHS Tracker',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.7,
                              height: 1.05,
                            ),
                          ),
                          Text(
                            'Questionnaire Tracking Workbook',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.64),
                              fontSize: 12.2,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Responsive navigation – ultra-clean
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useCompactMenu = MediaQuery.of(context).size.width < 980;

                      if (useCompactMenu) {
                        return Row(
                          children: [
                            _UserChip(email: widget.user.email ?? ''),
                            const SizedBox(width: 14),
                            PopupMenuButton<String>(
                              elevation: 12,
                              color: Colors.white,
                              splashRadius: 24,
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white,
                                size: 27,
                              ),
                              onSelected: _handleCompactMenu,
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'activity',
                                  child: _MenuItem(icon: Icons.analytics_rounded, text: 'Activity dashboard'),
                                ),
                                const PopupMenuItem(
                                  value: 'dropdowns',
                                  child: _MenuItem(icon: Icons.tune_rounded, text: 'Dropdown settings'),
                                ),
                                PopupMenuItem(
                                  value: 'demo',
                                  enabled: !_generatingDemoData,
                                  child: _MenuItem(
                                    icon: Icons.dataset_rounded,
                                    text: _generatingDemoData ? 'Generating…' : 'Generate demo data',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'refresh',
                                  child: _MenuItem(icon: Icons.refresh_rounded, text: 'Refresh info'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'logout',
                                  child: _MenuItem(icon: Icons.logout_rounded, text: 'Logout'),
                                ),
                              ],
                            ),
                          ],
                        );
                      }

                      // Desktop navigation – premium filled buttons
                      return Row(
                        children: [
                          _HeaderButton(
                            icon: Icons.analytics_rounded,
                            label: 'Activity',
                            onTap: _openAdminDashboard,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.tune_rounded,
                            label: 'Dropdowns',
                            onTap: _openDropdownSettings,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.dataset_rounded,
                            label: _generatingDemoData ? 'Generating…' : 'Demo Data',
                            loading: _generatingDemoData,
                            onTap: _generatingDemoData ? null : _generateDemoData,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.refresh_rounded,
                            label: 'Refresh',
                            onTap: _showRefreshMessage,
                          ),
                          const SizedBox(width: 28),
                          _UserChip(email: widget.user.email ?? ''),
                          const SizedBox(width: 12),
                          _LogoutButton(onTap: _logout),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // === REFINED SECONDARY TAB BAR ===
            Container(
              height: 52,
              color: const Color(0xFFF1F5F9),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicatorColor: headerColor,
                      indicatorWeight: 4,
                      indicatorPadding: const EdgeInsets.symmetric(horizontal: 18),
                      labelColor: headerColor,
                      unselectedLabelColor: Colors.black87,
                      labelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 26),
                      tabs: const [
                        Tab(height: 50, text: 'Paed & CNS'),
                        Tab(height: 50, text: 'Clin Psych / SW / ASD'),
                        Tab(height: 50, text: 'Completed / Deleted'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: TabBarView(
                children: [
                  SheetPage(config: paedCnsConfig, user: widget.user),
                  SheetPage(config: clinPsychSwAsdConfig, user: widget.user),
                  SheetPage(config: completedConfig, user: widget.user),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === PREMIUM HEADER BUTTON (Material 3 – glassmorphic elegance) ===
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
    return FilledButton.icon(
      onPressed: onTap,
      icon: loading
          ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Colors.white,
        ),
      )
          : Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.095),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        textStyle: const TextStyle(
          fontSize: 13.4,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        minimumSize: const Size(0, 42),
      ),
    );
  }
}

// === ULTRA-PREMIUM USER CHIP (with initials avatar) ===
class _UserChip extends StatelessWidget {
  final String email;
  const _UserChip({required this.email});

  String _getInitials(String email) {
    if (email.trim().isEmpty) return 'U';
    final name = email.split('@')[0];
    final parts = name.split(RegExp(r'[._-]'));
    return parts.length > 1
        ? (parts[0][0] + parts[1][0]).toUpperCase()
        : name.isNotEmpty
        ? name[0].toUpperCase()
        : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final displayEmail = email.trim().isEmpty ? 'Signed in' : email;
    final initials = _getInitials(email);

    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 6, right: 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.11),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              displayEmail.length > 26 ? '${displayEmail.substring(0, 23)}…' : displayEmail,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// === CLEAN LOGOUT BUTTON ===
class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sign out',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.13),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.22)),
          ),
          child: const Icon(
            Icons.logout_rounded,
            size: 21,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// === MENU ITEM FOR COMPACT MENU ===
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MenuItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: Colors.black87),
        const SizedBox(width: 14),
        Text(text, style: const TextStyle(fontSize: 14.8)),
      ],
    );
  }
}