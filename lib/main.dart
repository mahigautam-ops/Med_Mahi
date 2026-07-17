import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'core/models/patient.dart';
import 'core/providers/call_provider.dart';
import 'core/providers/patient_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/ai_settings.dart';
import 'screens/in_call_screen.dart';
import 'screens/main_layout.dart';
import 'screens/login_screen.dart';
import 'screens/setup_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── App entry point ────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PatientProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AiSettingsProvider()..load()),
        ChangeNotifierProvider(
          create: (_) {
            final cp = CallProvider();
            cp.initialize().then((_) => cp.startBackgroundService());
            return cp;
          },
        ),
      ],
      child: const MedCallerApp(),
    ),
  );
}

// ── Main App ───────────────────────────────────────────────────────────────────
class MedCallerApp extends StatefulWidget {
  const MedCallerApp({super.key});

  @override
  State<MedCallerApp> createState() => _MedCallerAppState();
}

class _MedCallerAppState extends State<MedCallerApp> {
  final _navKey = GlobalKey<NavigatorState>();
  bool _inCallShowing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, cp, _) {
        if (cp.isInCall && !_inCallShowing) {
          _inCallShowing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => const InCallScreen(),
                fullscreenDialog: true,
              ),
            ).then((_) {
              _inCallShowing = false;
            });
          });
        }
        return MaterialApp(
          title: 'MedCaller',
          navigatorKey: _navKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ── Auth gate + first-launch setup ────────────────────────────────────────────────
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _setupDone = true; // assume done until checked
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('setup_complete') ?? false;
    setState(() {
      _setupDone = done;
      _loading = false;
    });
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_complete', true);
    setState(() => _setupDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          backgroundColor: Color(0xFF0F172A),
          body: Center(child: CircularProgressIndicator()));
    }

    if (!_setupDone) {
      return SetupScreen(onComplete: _completeSetup);
    }

    return _buildAuthGate();
  }

  Widget _buildAuthGate() {
    return FutureBuilder<String>(
      future: _getSavedPhone(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final savedPhone = snapshot.data ?? '';
        if (savedPhone.isNotEmpty) {
          return const _ApprovalGate();
        }
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasData && snapshot.data != null) {
              return const _ApprovalGate();
            }
            return const LoginScreen();
          },
        );
      },
    );
  }

  Future<String> _getSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loggedInPhone') ?? '';
  }
}

// ── Approval gate: checks Firestore approval status ───────────────────────────
class _ApprovalGate extends StatefulWidget {
  const _ApprovalGate();
  @override
  State<_ApprovalGate> createState() => _ApprovalGateState();
}

class _ApprovalGateState extends State<_ApprovalGate> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkApproval();
  }

  Future<void> _checkApproval() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String phone = '';
      if (user != null && user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        phone = user.phoneNumber!;
      } else {
        final prefs = await SharedPreferences.getInstance();
        phone = prefs.getString('loggedInPhone') ?? '';
      }

      if (phone.isEmpty) {
        setState(() { _loading = false; });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .get();

      if (!doc.exists) {
        setState(() { _loading = false; });
        return;
      }

      final data = doc.data()!;
      if (data['isRejected'] == true) {
        await FirebaseAuth.instance.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('loggedInPhone');
        setState(() { _error = 'Account rejected: ${data['rejectionReason'] ?? "Contact support"}'; _loading = false; });
        return;
      }

      if (data['isApproved'] == false) {
        await FirebaseAuth.instance.signOut();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('loggedInPhone');
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => PendingVerificationScreen(phoneNumber: phone)),
            (route) => false,
          );
        }
        return;
      }

      setState(() { _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => Navigator.pushReplacementNamed(context, '/login'), child: const Text('Back to Login')),
        ])),
      );
    }
    return const MainLayout();
  }
}
