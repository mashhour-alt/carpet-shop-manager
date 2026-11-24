import 'package:flutter/material.dart';

/// Notebook ("دفتر") look for Farsha: ruled paper, a red margin line,
/// handwritten Ruqaa type and Arabic-Indic digits.
///
/// The bundled `FarshaRuqaa` font is Aref Ruqaa (OFL) with the Latin digit
/// code points mapped to the Arabic-Indic digit glyphs, so every number in
/// the app is drawn in Arabic digits while the underlying data stays ASCII.
class FarshaColors {
  static const paper = Color(0xffFBF7EC);
  static const paperCard = Color(0xffFFFDF6);
  static const rule = Color(0xffD3DEEA);
  static const margin = Color(0xffE07A6E);
  static const ink = Color(0xff22304A);
  static const inkBlue = Color(0xff1F3A8A);
  static const muted = Color(0xff5B6577);
  static const carpet = Color(0xff8E3328);
  static const carpetDark = Color(0xff6A231C);
  static const gold = Color(0xffE3C48B);
  static const fringe = Color(0xffEADFC4);
  static const onCarpet = Color(0xffFFF6E3);
  static const error = Color(0xffB3261E);
}

const farshaFontFamily = 'FarshaRuqaa';

/// Plain sans font for e-mails, passwords and other Latin input where
/// Arabic-shaped digits would be confusing.
const farshaLatinStyle = TextStyle(fontFamily: 'Roboto', fontFamilyFallback: ['sans-serif']);

/// Hand-drawn feeling corners: slightly uneven radii.
const farshaHandRadius = BorderRadius.only(
  topLeft: Radius.circular(6),
  topRight: Radius.circular(14),
  bottomRight: Radius.circular(7),
  bottomLeft: Radius.circular(12),
);

ThemeData buildFarshaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: FarshaColors.inkBlue,
    brightness: Brightness.light,
  ).copyWith(
    primary: FarshaColors.inkBlue,
    onPrimary: Colors.white,
    secondary: FarshaColors.carpet,
    onSecondary: FarshaColors.onCarpet,
    surface: FarshaColors.paperCard,
    onSurface: FarshaColors.ink,
    error: FarshaColors.error,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: farshaFontFamily,
    fontFamilyFallback: const ['Noto Sans Arabic', 'Roboto'],
  );
  final text = base.textTheme
      .apply(bodyColor: FarshaColors.ink, displayColor: FarshaColors.ink, fontSizeFactor: 1.08)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: FarshaColors.inkBlue,
          fontWeight: FontWeight.w700,
          fontSize: 28,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(color: FarshaColors.inkBlue, fontWeight: FontWeight.w700),
      );
  const inkSide = BorderSide(color: FarshaColors.ink, width: 1.3);
  return base.copyWith(
    textTheme: text,
    // Each page paints its own notebook paper (see NotebookPageTransitionsBuilder).
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: FarshaColors.paper,
    dividerColor: FarshaColors.rule,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: NotebookPageTransitionsBuilder(),
      TargetPlatform.iOS: NotebookPageTransitionsBuilder(),
      TargetPlatform.linux: NotebookPageTransitionsBuilder(),
      TargetPlatform.macOS: NotebookPageTransitionsBuilder(),
      TargetPlatform.windows: NotebookPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      foregroundColor: FarshaColors.ink,
      titleTextStyle: TextStyle(
        fontFamily: farshaFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: FarshaColors.inkBlue,
      ),
    ),
    cardTheme: const CardThemeData(
      color: FarshaColors.paperCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: farshaHandRadius, side: inkSide),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: FarshaColors.paperCard,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: FarshaColors.muted),
      floatingLabelStyle: TextStyle(color: FarshaColors.inkBlue),
      border: OutlineInputBorder(borderRadius: farshaHandRadius, borderSide: inkSide),
      enabledBorder: OutlineInputBorder(borderRadius: farshaHandRadius, borderSide: inkSide),
      focusedBorder: OutlineInputBorder(
        borderRadius: farshaHandRadius,
        borderSide: BorderSide(color: FarshaColors.inkBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: farshaHandRadius,
        borderSide: BorderSide(color: FarshaColors.error, width: 1.3),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: FarshaColors.inkBlue,
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 50),
      textStyle: const TextStyle(fontFamily: farshaFontFamily, fontSize: 19, fontWeight: FontWeight.w700),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(20),
        bottomRight: Radius.circular(26),
        bottomLeft: Radius.circular(22),
      )),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: FarshaColors.ink,
      minimumSize: const Size(48, 48),
      side: inkSide,
      shape: const RoundedRectangleBorder(borderRadius: farshaHandRadius),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: FarshaColors.inkBlue,
      textStyle: const TextStyle(fontFamily: farshaFontFamily, fontSize: 16),
    )),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: FarshaColors.ink,
      contentTextStyle: TextStyle(fontFamily: farshaFontFamily, fontSize: 16, color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: FarshaColors.paperCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: farshaHandRadius, side: inkSide),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FarshaColors.paper,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(iconColor: FarshaColors.ink),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: FarshaColors.paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: FarshaColors.carpet,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? FarshaColors.onCarpet : FarshaColors.ink,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: farshaFontFamily,
            fontSize: 13,
            color: FarshaColors.ink,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
          )),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: FarshaColors.paperCard,
      side: inkSide,
      labelStyle: const TextStyle(fontFamily: farshaFontFamily, color: FarshaColors.ink),
    ),
  );
}

/// Wraps every page in opaque notebook paper so pushed routes never show
/// the page underneath, then applies the normal zoom transition.
class NotebookPageTransitionsBuilder extends PageTransitionsBuilder {
  const NotebookPageTransitionsBuilder();

  static const _inner = ZoomPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _inner.buildTransitions<T>(route, context, animation, secondaryAnimation, NotebookPaper(child: child));
}

/// Ruled notebook paper with a double red margin line on the reading side.
class NotebookPaper extends StatelessWidget {
  const NotebookPaper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _NotebookPainter(rtl: Directionality.of(context) == TextDirection.rtl),
        child: child,
      );
}

class _NotebookPainter extends CustomPainter {
  const _NotebookPainter({required this.rtl});
  final bool rtl;

  static const _lineGap = 36.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = FarshaColors.paper);
    final rule = Paint()
      ..color = FarshaColors.rule
      ..strokeWidth = 1;
    for (var y = _lineGap + 18; y < size.height; y += _lineGap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    final margin = Paint()
      ..color = FarshaColors.margin
      ..strokeWidth = 1.6;
    final x = rtl ? size.width - 28 : 28.0;
    final x2 = rtl ? x - 4 : x + 4;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), margin);
    canvas.drawLine(
      Offset(x2, 0),
      Offset(x2, size.height),
      margin
        ..strokeWidth = 0.8
        ..color = FarshaColors.margin.withValues(alpha: .55),
    );
  }

  @override
  bool shouldRepaint(_NotebookPainter oldDelegate) => oldDelegate.rtl != rtl;
}

/// Arabic text for Supabase Auth errors (the API answers in English).
String arabicAuthMessage(String message) {
  final m = message.toLowerCase();
  if (m.contains('invalid login credentials')) return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
  if (m.contains('email not confirmed')) return 'لم يتم تأكيد البريد بعد. افتح رسالة التأكيد في بريدك.';
  if (m.contains('already registered') || m.contains('already been registered')) {
    return 'هذا البريد مسجل بالفعل. سجّل الدخول أو استعد كلمة المرور.';
  }
  if (m.contains('rate limit') || m.contains('too many')) return 'محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى.';
  if (m.contains('password') && (m.contains('weak') || m.contains('at least') || m.contains('pwned'))) {
    return 'كلمة المرور ضعيفة. اختر كلمة أطول وأصعب.';
  }
  if (m.contains('network') || m.contains('socket') || m.contains('failed host lookup')) {
    return 'تعذر الاتصال بالإنترنت. تحقق من الشبكة وحاول مرة أخرى.';
  }
  return 'تعذر تسجيل الدخول. حاول مرة أخرى.';
}

/// Arabic decimal (٫) and thousands (٬) separators; digits themselves are
/// drawn as Arabic-Indic by the FarshaRuqaa font.
String arabicSeparators(String number) =>
    number.replaceAll(',', '٬').replaceAll('.', '٫');

/// A loose sheet of paper laid on the notebook: card colour, ink outline,
/// uneven corners.
BoxDecoration farshaPaperDecoration({Color? color}) => BoxDecoration(
      color: color ?? FarshaColors.paperCard,
      borderRadius: farshaHandRadius,
      border: Border.all(color: FarshaColors.ink, width: 1.2),
    );
