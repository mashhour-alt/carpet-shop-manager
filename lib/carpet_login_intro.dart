import 'package:flutter/material.dart';

/// A presentation-only gate. The existing authentication form remains mounted
/// beneath the carpet, so its controllers, validation and callbacks are intact.
class CarpetLoginIntro extends StatefulWidget {
  const CarpetLoginIntro({super.key, required this.child});
  final Widget child;

  @override
  State<CarpetLoginIntro> createState() => _CarpetLoginIntroState();
}

class _CarpetLoginIntroState extends State<CarpetLoginIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  bool _opened = false;

  void _open() {
    if (_opened) return;
    setState(() => _opened = true);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_opened && MediaQuery.disableAnimationsOf(context)) {
      _opened = true;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: t < 1,
              child: Opacity(
                opacity: ((t - .55) / .45).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 20),
                  child: widget.child,
                ),
              ),
            ),
            if (t < 1)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _open,
                  onHorizontalDragEnd: (_) => _open(),
                  onVerticalDragEnd: (_) => _open(),
                  child: ColoredBox(
                    color: surface,
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = (constraints.maxWidth - 48)
                              .clamp(180.0, 370.0);
                          final height = (constraints.maxHeight * .42)
                              .clamp(140.0, 320.0);
                          return Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform(
                                    alignment: Alignment.bottomCenter,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, .001)
                                      ..rotateX((1 - t) * -.25),
                                    child: SizedBox(
                                      width: width,
                                      height: height,
                                      child: Stack(
                                        alignment: Alignment.bottomCenter,
                                        children: [
                                          Positioned(
                                            bottom: 0,
                                            child: Container(
                                              width: width,
                                              height: height * (.25 + .75 * t),
                                              decoration: BoxDecoration(
                                                color: brand,
                                                borderRadius: BorderRadius.circular(14),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: brand.withValues(alpha: .18),
                                                    blurRadius: 22,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: Opacity(
                                                  opacity: .55 + .45 * t,
                                                  child: Image.asset(
                                                    'assets/images/farsha_logo.jpeg',
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: height * (.22 + .73 * t),
                                            child: Container(
                                              width: width,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                color: brand,
                                                borderRadius: BorderRadius.circular(18),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Colors.black26,
                                                    blurRadius: 7,
                                                    offset: Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  Text(
                                    'افرد السجادة للبدء',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.titleLarge
                                        ?.copyWith(color: brand, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'اضغط أو اسحب السجادة',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _open,
                                    child: const Text('متابعة إلى تسجيل الدخول'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
