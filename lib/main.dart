import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'auth_page.dart';
import 'home_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  }
  runApp(const FarshaApp());
}

class FarshaApp extends StatelessWidget {
  const FarshaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'فرشة',
        locale: const Locale('ar'),
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff8f1423),
          scaffoldBackgroundColor: const Color(0xfff7f3ea),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: AppConfig.isConfigured ? const AuthGate() : const ConfigurationPage(),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late User? _user = Supabase.instance.client.auth.currentUser;
  late final StreamSubscription<AuthState> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _user = state.session?.user);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _user == null ? const AuthPage() : ProfileRouter(key: ValueKey(_user!.id));
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/images/farsha_logo.jpeg', width: 160, height: 160),
                  ),
                  const SizedBox(height: 18),
                  const Text('فرشة', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text(
                    'نسخة البناء تحتاج SUPABASE_URL وSUPABASE_PUBLISHABLE_KEY. لا توجد قاعدة محلية بديلة حتى لا تنفصل بيانات الأجهزة.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
