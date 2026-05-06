import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/sheet_config.dart';
import '../services/mhs_firestore_service.dart';
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

  bool _generatingDemoData = false;

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _generateDemoData() async {
    setState(() => _generatingDemoData = true);

    try {
      final result = await _service.generateDemoDataOnce(
        user: widget.user,
      );

      if (!mounted) return;

      if (result.alreadyGenerated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo data has already been generated.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${result.created} demo records.'),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    const darkHeader = Color(0xFF2F3A46);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        appBar: AppBar(
          backgroundColor: darkHeader,
          foregroundColor: Colors.white,
          elevation: 2,
          centerTitle: true,
          title: const Text(
            'MHS Questionnaire Tracking Workbook',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 21,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Generate demo data',
              onPressed: _generatingDemoData ? null : _generateDemoData,
              icon: _generatingDemoData
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.dataset),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Live data refreshes automatically.')),
                );
              },
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Paed & CNS'),
              Tab(text: 'Clin Psych / SW / ASD'),
              Tab(text: 'Completed / Deleted'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SheetPage(config: paedCnsConfig, user: widget.user),
            SheetPage(config: clinPsychSwAsdConfig, user: widget.user),
            SheetPage(config: completedConfig, user: widget.user),
          ],
        ),
      ),
    );
  }
}