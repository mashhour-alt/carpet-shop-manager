import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'farsha_theme.dart';

class CarpetNavItem {
  const CarpetNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Bottom navigation where the selection marker is a small carpet:
/// on a tab change it rolls up, the roll slides to the new tab, and it
/// unrolls there.
class CarpetNavBar extends StatefulWidget {
  const CarpetNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<CarpetNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<CarpetNavBar> createState() => _CarpetNavBarState();
}

class _CarpetNavBarState extends State<CarpetNavBar> with SingleTickerProviderStateMixin {
  static const _barHeight = 74.0;
  static const _carpetHeight = 58.0;

  late int _from = widget.selectedIndex;
  late int _to = widget.selectedIndex;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void didUpdateWidget(CarpetNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _to) {
      _from = _to;
      _to = widget.selectedIndex;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _slotLeft(int index, double slotWidth, double width, bool rtl) =>
      rtl ? width - (index + 1) * slotWidth : index * slotWidth;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: _barHeight + bottomInset,
      decoration: const BoxDecoration(
        color: FarshaColors.paper,
        border: Border(top: BorderSide(color: FarshaColors.ink, width: 1.3)),
      ),
      // Side room so the carpet fringes never touch the screen edge.
      padding: EdgeInsets.only(bottom: bottomInset, left: 10, right: 10),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final count = widget.items.length;
        final slotWidth = width / count;
        final carpetWidth = (slotWidth - 8).clamp(40.0, 76.0).toDouble();
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final animating = _from != _to && t < 1;
            double visible = 1;
            double slide = 1;
            if (animating) {
              if (t < 1 / 3) {
                visible = 1 - Curves.easeInOut.transform(t * 3);
                slide = 0;
              } else if (t < 2 / 3) {
                visible = 0;
                slide = Curves.easeInOut.transform((t - 1 / 3) * 3);
              } else {
                visible = Curves.easeInOut.transform((t - 2 / 3) * 3);
              }
            }
            final fromX = _slotLeft(_from, slotWidth, width, rtl);
            final toX = _slotLeft(_to, slotWidth, width, rtl);
            final left = lerpDouble(fromX, toX, slide)! + (slotWidth - carpetWidth) / 2;
            final movingRight = toX >= fromX;
            final top = (_barHeight - _carpetHeight) / 2;
            final full = Rect.fromLTWH(left, top, carpetWidth, _carpetHeight);
            return Stack(fit: StackFit.expand, children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CarpetPainter(
                      full: full,
                      visible: visible,
                      anchorRight: movingRight,
                    ),
                  ),
                ),
              ),
              Row(children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: _CarpetNavButton(
                      item: widget.items[i],
                      selected: i == widget.selectedIndex,
                      onCarpet: i == _to && !animating,
                      onTap: () {
                        if (i != widget.selectedIndex) widget.onSelected(i);
                      },
                    ),
                  ),
              ]),
            ]);
          },
        );
      }),
    );
  }
}

class _CarpetNavButton extends StatelessWidget {
  const _CarpetNavButton({
    required this.item,
    required this.selected,
    required this.onCarpet,
    required this.onTap,
  });

  final CarpetNavItem item;
  final bool selected;
  final bool onCarpet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = onCarpet ? FarshaColors.onCarpet : FarshaColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: SizedBox.expand(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(item.icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: farshaFontFamily,
                fontSize: 15,
                height: 1.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CarpetPainter extends CustomPainter {
  const _CarpetPainter({required this.full, required this.visible, required this.anchorRight});

  /// The carpet when fully unrolled.
  final Rect full;

  /// 0 = completely rolled up, 1 = fully laid out.
  final double visible;

  /// Whether the laid-out part is anchored on the right edge (the roll then
  /// sits on its left), i.e. the carpet travels towards the right.
  final bool anchorRight;

  static const _rollWidth = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = full.width * visible;
    final segment = anchorRight
        ? Rect.fromLTRB(full.right - w, full.top, full.right, full.bottom)
        : Rect.fromLTRB(full.left, full.top, full.left + w, full.bottom);

    if (w > 0.5) {
      final rrect = RRect.fromRectAndRadius(segment, const Radius.circular(3));
      canvas.drawRRect(
        rrect.shift(const Offset(0, 2)),
        Paint()
          ..color = FarshaColors.ink.withValues(alpha: .25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRRect(rrect, Paint()..color = FarshaColors.carpet);

      canvas.save();
      canvas.clipRRect(rrect);
      final pile = Paint()
        ..color = Colors.white.withValues(alpha: .05)
        ..strokeWidth = 1;
      for (var x = full.left + 1; x < full.right; x += 3) {
        if (x >= segment.left && x <= segment.right) {
          canvas.drawLine(Offset(x, full.top), Offset(x, full.bottom), pile);
        }
      }
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = FarshaColors.carpetDark;
      final fullRRect = RRect.fromRectAndRadius(full, const Radius.circular(3));
      canvas.drawRRect(fullRRect.deflate(1.5), border);
      canvas.drawRRect(
        fullRRect.deflate(4),
        border
          ..strokeWidth = 1.4
          ..color = FarshaColors.gold,
      );
      canvas.restore();

      // Fringes on the short ends of the carpet that are currently laid out.
      final fringe = Paint()
        ..color = FarshaColors.fringe
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      void fringeAt(double x, double dir) {
        for (var y = full.top + 6; y < full.bottom - 5; y += 4) {
          canvas.drawLine(Offset(x, y), Offset(x + 6 * dir, y), fringe);
        }
      }

      if (anchorRight || visible >= 0.999) fringeAt(full.right, 1);
      if (!anchorRight || visible >= 0.999) fringeAt(full.left, -1);
    }

    if (visible < 0.999) {
      final rollCenter = anchorRight ? segment.left : segment.right;
      final thickness = _rollWidth * (0.75 + 0.25 * (1 - visible));
      final rollRect = Rect.fromCenter(
        center: Offset(rollCenter, full.center.dy),
        width: thickness,
        height: full.height + 6,
      );
      final roll = RRect.fromRectAndRadius(rollRect, Radius.circular(thickness / 2));
      canvas.drawRRect(
        roll.shift(const Offset(1, 2)),
        Paint()
          ..color = FarshaColors.ink.withValues(alpha: .3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawRRect(
        roll,
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xff5E1F19),
            Color(0xffA8483A),
            FarshaColors.gold,
            Color(0xffA8483A),
            Color(0xff5E1F19),
          ], stops: [0, .3, .5, .66, 1]).createShader(rollRect),
      );
    }
  }

  @override
  bool shouldRepaint(_CarpetPainter oldDelegate) =>
      oldDelegate.full != full || oldDelegate.visible != visible || oldDelegate.anchorRight != anchorRight;
}
