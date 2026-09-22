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

  static const burgundy = Color(0xff861B2C);
  static const cream = Color(0xffF7F3EA);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: burgundy,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'فرشة',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: cream,
        fontFamilyFallback: const ['Noto Sans Arabic', 'Arial'],
        appBarTheme: const AppBarTheme(
          backgroundColor: cream,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 68,
          backgroundColor: Colors.white,
          indicatorColor: burgundy.withValues(alpha: .12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? burgundy : const Color(0xff625E5B),
          )),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xffEAE3DA)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xffE7DED4))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: burgundy, width: 1.4)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
          backgroundColor: burgundy,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        )),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        )),
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
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
  late final StreamSubscription<AuthState> _subscription;
  @override void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _user = state.session?.user);
    });
  }
  @override void dispose() { _subscription.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => _user == null ? const AuthPage() : ProfileRouter(key: ValueKey(_user!.id));
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
