import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum RegistrationType { owner, staff, driver }

extension RegistrationTypeLabel on RegistrationType {
  String get label => switch (this) {
        RegistrationType.owner => 'صاحب مؤسسة',
        RegistrationType.staff => 'محاسب أو بائع',
        RegistrationType.driver => 'سائق مستقل',
      };
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController(text: '+966');
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  RegistrationType _type = RegistrationType.owner;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final response = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {
            'full_name': _name.text.trim(),
            'phone': _phone.text.trim(),
            'account_kind': _type == RegistrationType.driver ? 'driver' : 'institution',
            'onboarding_mode': _type.name,
          },
        );
        if (response.session == null && mounted) {
          setState(() => _register = false);
          _message('فتح رسالة التأكيد في بريدك، ثم ارجع وسجّل الدخول.');
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) _message(error.message, error: true);
    } catch (_) {
      if (mounted) _message('تعذر الاتصال. حاول مرة أخرى.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset('assets/images/farsha_logo.jpeg', width: 150, height: 150),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _register ? 'إنشاء حساب فرشة' : 'تسجيل الدخول',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    if (_register) ...[
                      SegmentedButton<RegistrationType>(
                        segments: RegistrationType.values
                            .map((type) => ButtonSegment(value: type, label: Text(type.label)))
                            .toList(),
                        selected: {_type},
                        onSelectionChanged: (value) => setState(() => _type = value.first),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                        validator: (value) => value == null || value.trim().length < 2 ? 'اكتب الاسم' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                      validator: (value) => value == null || !value.trim().contains('@')
                          ? 'اكتب بريدًا صحيحًا'
                          : null,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'رقم الجوال بصيغة دولية', hintText: '+9665xxxxxxxx'),
                        validator: (value) => value == null || !value.trim().startsWith('+') || value.trim().length < 10
                            ? 'اكتب رقمًا صحيحًا يبدأ بمفتاح الدولة'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 8 ? '8 أحرف على الأقل' : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_register ? 'إنشاء الحساب' : 'دخول'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _register = !_register),
                      child: Text(_register ? 'لديك حساب؟ سجّل الدخول' : 'مستخدم جديد؟ أنشئ حسابًا'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
