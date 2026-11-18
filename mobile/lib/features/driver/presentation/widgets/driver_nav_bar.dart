import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_typography.dart';

/// Destinations on the driver bottom bar. `trips` and `earnings` map to
/// shell pages; `wallet` and `profile` are handled by callbacks.
enum DriverNavDestination { home, trips, earnings, wallet, profile }

class _DriverNavItem {
  const _DriverNavItem(
    this.destination,
    this.icon,
    this.selectedIcon,
    this.label,
  );

  final DriverNavDestination destination;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _driverNavItems = <_DriverNavItem>[
  _DriverNavItem(
    DriverNavDestination.home,
    Icons.home_outlined,
    Icons.home_rounded,
    'Home',
  ),
  _DriverNavItem(
    DriverNavDestination.trips,
    Icons.directions_car_outlined,
    Icons.directions_car_rounded,
    'Trips',
  ),
  _DriverNavItem(
    DriverNavDestination.earnings,
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded,
    'Earnings',
  ),
  _DriverNavItem(
    DriverNavDestination.wallet,
    Icons.account_balance_outlined,
    Icons.account_balance_rounded,
    'Wallet',
  ),
  _DriverNavItem(
    DriverNavDestination.profile,
    Icons.person_outline_rounded,
    Icons.person_rounded,
    'Profile',
  ),
];

/// Driver bottom bar — identical construction to the passenger
/// [OraModuleBottomBar]: warm champagne bar, concave notch under the
/// selected tab and a floating orange-gradient badge that slides between
/// destinations.
class DriverNavBar extends StatelessWidget {
  const DriverNavBar({
    required this.selected,
    required this.onSelect,
    this.tripsLabel = 'Trips',
    super.key,
  });

  final DriverNavDestination? selected;
  final ValueChanged<DriverNavDestination> onSelect;

  /// Label for the trips destination — 'Trips' for drivers, 'Jobs' for
  /// logistics partners.
  final String tripsLabel;

  static const double _barHeight = 68;
  static const double _badgeLift = 24;

  @override
  Widget build(BuildContext context) {
    final items = tripsLabel == 'Trips'
        ? _driverNavItems
        : [
            for (final item in _driverNavItems)
              item.destination == DriverNavDestination.trips
                  ? _DriverNavItem(
                      item.destination,
                      item.icon,
                      item.selectedIcon,
                      tripsLabel,
                    )
                  : item,
          ];
    final index = items.indexWhere((i) => i.destination == selected);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: _barHeight + _badgeLift,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / items.length;
            final targetX = index < 0
                ? -1.0
                : itemWidth * index + itemWidth / 2;
            return TweenAnimationBuilder<double>(
              tween: Tween(end: targetX),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (context, notchX, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      top: _badgeLift,
                      child: CustomPaint(
                        painter: _DriverNotchBarPainter(notchX: notchX),
                      ),
                    ),
                    Positioned.fill(
                      top: _badgeLift,
                      child: Row(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _DriverNavItemWidget(
                              item: items[i],
                              selected: i == index,
                              onTap: () =>
                                  onSelect(items[i].destination),
                            ),
                        ],
                      ),
                    ),
                    if (index >= 0)
                      Positioned(
                        left: notchX - 23,
                        top: 0,
                        child: IgnorePointer(
                          child: _DriverFloatingBadge(
                            icon: items[index].selectedIcon,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The popped-up circular icon that sits inside the notch.
class _DriverFloatingBadge extends StatelessWidget {
  const _DriverFloatingBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 14 * (1 - t)),
        child: Transform.scale(scale: t, child: child),
      ),
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFA14A), OraColors.goldSharp],
          ),
          border: Border.fromBorderSide(
            BorderSide(color: Color(0xB3FFFFFF), width: 1.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x73FF6A0D),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Icon(icon, size: 21, color: Colors.white),
      ),
    );
  }
}

class _DriverNavItemWidget extends StatefulWidget {
  const _DriverNavItemWidget({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _DriverNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DriverNavItemWidget> createState() => _DriverNavItemWidgetState();
}

class _DriverNavItemWidgetState extends State<_DriverNavItemWidget> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? OraColors.goldSharp : OraColors.textMuted;
    final lift = _pressed ? 1.0 : (_hovered ? -2.0 : 0.0);
    final scale = _pressed ? 0.88 : (_hovered ? 1.15 : 1.0);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.item.label,
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: InkWell(
              excludeFromSemantics: true,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: selected ? 0 : 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutBack,
                        transform: Matrix4.translationValues(0, lift, 0)
                          ..scaleByDouble(scale, scale, scale, 1),
                        transformAlignment: Alignment.center,
                        child: _DriverIconBadge(icon: widget.item.icon),
                      ),
                    ),
                    SizedBox(height: selected ? 3 : 2),
                    Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.caption(color).copyWith(
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small 3D orange-gradient circle badge for unselected tabs.
class _DriverIconBadge extends StatelessWidget {
  const _DriverIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFA14A), OraColors.goldSharp],
        ),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xB3FFFFFF), width: 1.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x73FF6A0D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x2E2A211D),
            blurRadius: 12,
            offset: Offset(0, 7),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Icon(icon, size: 20, color: Colors.white),
    );
  }
}

/// Warm champagne bar with a smooth concave dip under the selected item —
/// copy of the passenger notch painter so both bars look identical.
class _DriverNotchBarPainter extends CustomPainter {
  const _DriverNotchBarPainter({required this.notchX});

  final double notchX;

  static const double _corner = 22;
  static const double _notchHalf = 36;
  static const double _notchDepth = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final hasNotch = notchX > _notchHalf && notchX < size.width - _notchHalf;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, _corner)
      ..quadraticBezierTo(0, 0, _corner, 0);

    if (hasNotch) {
      path
        ..lineTo(notchX - _notchHalf, 0)
        ..cubicTo(
          notchX - _notchHalf * 0.4,
          0,
          notchX - _notchDepth,
          _notchDepth * 1.7,
          notchX,
          _notchDepth * 1.7,
        )
        ..cubicTo(
          notchX + _notchDepth,
          _notchDepth * 1.7,
          notchX + _notchHalf * 0.4,
          0,
          notchX + _notchHalf,
          0,
        );
    }

    path
      ..lineTo(size.width - _corner, 0)
      ..quadraticBezierTo(size.width, 0, size.width, _corner)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawShadow(path, const Color(0x4DFF6A0D), 12, true);
    canvas.drawPath(path, Paint()..color = OraColors.navyElevated);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x73FF6A0D),
    );
  }

  @override
  bool shouldRepaint(_DriverNotchBarPainter oldDelegate) =>
      oldDelegate.notchX != notchX;
}
