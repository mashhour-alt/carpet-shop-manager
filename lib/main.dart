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
          fontFamilyFallback: const ['Noto Sans Arabic', 'Arial'],
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.symmetric(vertical: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xffeee8df)),
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: Color(0x1a8f1423),
            elevation: 4,
            labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xffe7dfd4))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xffe7dfd4))),
            filled: true,
            fillColor: Colors.white,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13)),
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
