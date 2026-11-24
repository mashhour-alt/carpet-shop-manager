import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'auth_page.dart';
import 'farsha_theme.dart';
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

  static const burgundy = Color(0xff861B2C);
  static const cream = Color(0xffF7F3EA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'فرشة',
      locale: const Locale('ar'),
      theme: buildFarshaTheme(),
      scrollBehavior: const NotebookScrollBehavior(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: withFarshaTextScale(context, child!),
      ),
      home: AppConfig.isConfigured ? const AuthGate() : const ConfigurationPage(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late User? _user = Supabase.instance.client.auth.currentUser;
  bool _passwordRecovery = false;
  late final StreamSubscription<AuthState> _subscription;
  @override void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (mounted) {
        setState(() {
          _user = state.session?.user;
          if (state.event == AuthChangeEvent.passwordRecovery) _passwordRecovery = true;
          if (state.event == AuthChangeEvent.signedOut) _passwordRecovery = false;
        });
      }
    });
  }
  @override void dispose() { _subscription.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => _passwordRecovery
      ? const ResetPasswordPage()
      : _user == null
          ? const AuthPage()
          : ProfileRouter(key: ValueKey(_user!.id));
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.asset('assets/images/farsha_logo.jpeg', width: 160, height: 160)),
            const SizedBox(height: 18),
            const Text('فرشة', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('نسخة البناء تحتاج SUPABASE_URL وSUPABASE_PUBLISHABLE_KEY. لا توجد قاعدة محلية بديلة حتى لا تنفصل بيانات الأجهزة.', textAlign: TextAlign.center),
          ]),
        ),
      ),
    ),
  );
}
