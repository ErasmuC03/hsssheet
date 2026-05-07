import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';

// ── App-wide snack bar key ────────────────────────────────────────────────────
// Using a GlobalKey bypasses widget-tree ancestor lookups entirely, so
// showSnackBar is safe to call from async callbacks even after a hot reload
// or widget disposal.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Show a snack bar from anywhere — including async callbacks that outlive
/// their originating widget.
void showAppSnackBar(String message) {
  appMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MhsQuestionnaireTrackerApp());
}

class MhsQuestionnaireTrackerApp extends StatelessWidget {
  const MhsQuestionnaireTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MHS Questionnaire Tracker',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,   // ← wire up the global key
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginPage();
        }

        return HomePage(user: user);
      },
    );
  }
}