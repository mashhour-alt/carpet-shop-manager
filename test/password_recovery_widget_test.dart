import 'package:farsha/auth_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login shows password recovery actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthPage()));

    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    expect(find.text('نسيت البريد الإلكتروني؟ تواصل مع الدعم'), findsOneWidget);
  });
}
