import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../super_app/presentation/widgets/ora_module_card.dart';
import '../../recent/driver_recents.dart';

/// Shared visual kit for the driver module — matches the driver prototype
/// screens: peach canvas, floating white 3D cards, bright-orange CTAs,
/// segmented tabs and big Accept/Decline actions.

/// 3D orange-gradient circular icon badge — same construction as the
/// passenger bottom-bar badges (gradient + white ring + orange glow shadow).
class DriverIconBadge extends StatelessWidget {
  const DriverIconBadge({
    required this.icon,
    super.key,
    this.size = 40,
    this.iconSize = 20,
    this.colors = const [Color(0xFFFFA14A), OraColors.goldSharp],
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0xB3FFFFFF), width: 1.4),
        boxShadow: const [
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
      child: Icon(icon, size: iconSize, color: Colors.white),
    );
  }
}

/// Bright-orange gradient stat card — "Today's Earnings / Rs. 4,850 >".
/// Floats via [OraFloaty] when [floating] is set.
class DriverStatCard extends StatelessWidget {
  const DriverStatCard({
    required this.label,
    required this.value,
    super.key,
    this.onTap,
    this.trailing,
    this.floating = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final card = OraTapScale(
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            OraSpacing.md,
            OraSpacing.md,
            OraSpacing.sm,
            OraSpacing.md,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
            ),
            borderRadius: BorderRadius.circular(OraRadius.card),
            border: Border.all(color: const Color(0x59FFFFFF), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59FF6A0D),
                blurRadius: 18,
                offset: Offset(0, 8),
                spreadRadius: -6,
              ),
              BoxShadow(
                color: Color(0x332A211D),
                blurRadius: 26,
                offset: Offset(0, 14),
                spreadRadius: -10,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.caption(
                        const Color(0xE6FFFFFF),
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.display(
                        Colors.white,
                      ).copyWith(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xCCFFFFFF),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
    if (!floating) return card;
    return OraFloaty(
      amplitude: 6,
      period: const Duration(seconds: 4),
      child: card,
    );
  }
}

/// Floating glass-blob tile — identical construction to the passenger
/// home module cards: yellowish glass gradient + orange sun + white rim,
/// real 3D [assetPath] image (orange [DriverIconBadge] fallback), label
/// row with orange chevron, and [OraFloaty] bobbing. Optional accent
/// caption like "(2 New)".
class DriverQuickTile extends StatelessWidget {
  const DriverQuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.badge,
    this.badgeColor = OraColors.danger,
    this.assetPath,
  });

  final IconData? icon;
  final String? assetPath;
  final String label;
  final String? badge;
  final Color badgeColor;
  final VoidCallback onTap;

  static const _imageOverlap = 26.0;

  @override
  Widget build(BuildContext context) {
    return OraFloaty(
      amplitude: 5,
      period: const Duration(seconds: 4),
      child: OraTapScale(
        downScale: 0.95,
        child: AspectRatio(
          aspectRatio: 1.0,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: _imageOverlap,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: CustomPaint(
                    painter: const OraBlobCardPainter(),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: 0.42,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                          child: Row(
                            children: [
                              Icon(
                                icon ?? Icons.circle,
                                color: OraColors.goldSharp,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: OraTypography.bodyEmphasis(
                                        OraColors.textPrimary,
                                      ).copyWith(fontSize: 13),
                                    ),
                                    if (badge != null)
                                      Text(
                                        badge!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: OraTypography.caption(badgeColor)
                                            .copyWith(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFF8A3D),
                                      Color(0xFFFF6A0D),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x66FF6A0D),
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  top: _imageOverlap - 6,
                  child: Align(
                    alignment: const Alignment(0, -0.15),
                    child: FractionallySizedBox(
                      heightFactor: 0.66,
                      child: assetPath != null
                          ? Image.asset(
                              assetPath!,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, __, ___) => DriverIconBadge(
                                icon: icon ?? Icons.circle,
                                size: 52,
                                iconSize: 26,
                              ),
                            )
                          : DriverIconBadge(
                              icon: icon ?? Icons.circle,
                              size: 52,
                              iconSize: 26,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented pill control — white track, selected segment is the bright
/// orange gradient with glow (Active / Upcoming / Completed etc.).
class DriverSegmentedTabs extends StatelessWidget {
  const DriverSegmentedTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OraColors.surfaceElevated,
        borderRadius: BorderRadius.circular(OraRadius.pill),
        border: Border.all(color: OraColors.border),
        boxShadow: OraElevation.cardShadow,
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _Segment(
                label: tabs[i],
                selected: i == selectedIndex,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(i);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: OraMotion.select,
        curve: OraMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
                )
              : null,
          borderRadius: BorderRadius.circular(OraRadius.pill),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x59FF6A0D),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                    spreadRadius: -3,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OraTypography.caption(
            selected ? Colors.white : OraColors.textSecondary,
          ).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    );
  }
}

/// Screen header — circular back/menu button + centered Sora title +
/// optional trailing slot (e.g. countdown ring).
class DriverScreenHeader extends StatelessWidget {
  const DriverScreenHeader({
    required this.title,
    super.key,
    this.onLeading,
    this.leadingIcon = Icons.arrow_back_rounded,
    this.leadingTooltip = 'Back',
    this.trailing,
    this.bright = false,
  });

  final String title;
  final VoidCallback? onLeading;
  final IconData leadingIcon;
  final String leadingTooltip;
  final Widget? trailing;

  /// Bright-orange gradient bar — used for subpage top bars so they match
  /// the passenger screens' orange accents.
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        OraTypography.title(
          bright ? Colors.white : OraColors.textPrimary,
        ).copyWith(
          fontFamily: OraTypography.displayFamily,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        );
    final row = Row(
      children: [
        _HeaderCircleButton(
          icon: leadingIcon,
          tooltip: leadingTooltip,
          onTap: onLeading,
          bright: bright,
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        SizedBox(width: 40, height: 40, child: Center(child: trailing)),
      ],
    );
    if (!bright) return row;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.xs,
        vertical: OraSpacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
        ),
        borderRadius: BorderRadius.circular(OraRadius.pill),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59FF6A0D),
            blurRadius: 16,
            offset: Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: row,
    );
  }
}

/// Solid bright-orange top bar — full-bleed edge-to-edge, covers the
/// status-bar area, white title. Used on every driver subpage (home keeps
/// its blended hero instead).
class DriverOrangeTopBar extends StatelessWidget {
  const DriverOrangeTopBar({
    required this.title,
    super.key,
    this.onLeading,
    this.leadingIcon,
    this.leadingTooltip = 'Menu',
    this.trailing,
  });

  final String title;
  final VoidCallback? onLeading;
  final IconData? leadingIcon;
  final String leadingTooltip;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x59FF6A0D),
            blurRadius: 16,
            offset: Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + OraSpacing.xs,
        left: OraSpacing.xs,
        right: OraSpacing.xs,
        bottom: OraSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: leadingIcon == null
                ? null
                : _HeaderCircleButton(
                    icon: leadingIcon!,
                    tooltip: leadingTooltip,
                    onTap: onLeading,
                    bright: true,
                  ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OraTypography.title(Colors.white).copyWith(
                fontFamily: OraTypography.displayFamily,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          SizedBox(width: 40, height: 40, child: Center(child: trailing)),
        ],
      ),
    );
  }
}

/// Artwork top header — the skyline/sedan artwork extracted from the
/// passenger-style mockups spans the full top area, with floating
/// controls and a title/subtitle overlaid on the soft left gradient.
/// Used on the Active Ride and My Earnings screens.
class DriverHeroArtHeader extends StatelessWidget {
  const DriverHeroArtHeader({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingTooltip = 'Menu',
    this.onLeading,
    this.trailingIcon,
    this.trailingTooltip = '',
    this.onTrailing,
    this.showLogo = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final String leadingTooltip;
  final VoidCallback? onLeading;
  final IconData? trailingIcon;
  final String trailingTooltip;
  final VoidCallback? onTrailing;
  final bool showLogo;

  static const _artHeight = 122.0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: top + _artHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed artwork; bottom edge melts into the page.
          Align(
            alignment: Alignment.topCenter,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.72, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: Image.asset(
                'assets/driver_tiles/screen_hero.png',
                width: double.infinity,
                height: top + _artHeight,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          // Left wash into the page background so the title stays readable
          // whatever part of the artwork shows behind it.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFFF9EDE6),
                  Color(0xE6F9EDE6),
                  Color(0x00F9EDE6),
                ],
                stops: [0.0, 0.42, 0.78],
              ),
            ),
          ),
          // Floating controls.
          Positioned(
            top: top + OraSpacing.xs,
            left: OraSpacing.sm,
            right: OraSpacing.sm,
            child: Row(
              children: [
                if (leadingIcon != null)
                  _HeaderCircleButton(
                    icon: leadingIcon!,
                    tooltip: leadingTooltip,
                    onTap: onLeading,
                  ),
                const Spacer(),
                if (trailingIcon != null)
                  _HeaderCircleButton(
                    icon: trailingIcon!,
                    tooltip: trailingTooltip,
                    onTap: onTrailing,
                  ),
              ],
            ),
          ),
          if (showLogo)
            Positioned(
              top: top + OraSpacing.xs + 6,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Image.asset('assets/brand/ora_logo.png', height: 26),
                ),
              ),
            ),
          // Title block on the soft left gradient.
          Positioned(
            left: OraSpacing.lg,
            right: OraSpacing.lg,
            bottom: OraSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: OraTypography.headline(
                    OraColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: OraTypography.caption(OraColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.bright = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OraTapScale(
        downScale: 0.9,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bright
                  ? const Color(0x33FFFFFF)
                  : OraColors.surfaceElevated,
              border: Border.all(
                color: bright ? const Color(0x66FFFFFF) : OraColors.border,
              ),
              boxShadow: bright ? null : OraElevation.cardShadow,
            ),
            child: Icon(
              icon,
              size: 19,
              color: bright ? Colors.white : OraColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Big gradient CTA — orange by default; green for Accept, red for Decline.
/// Squash-and-pop press, trailing arrow like the prototype.
class DriverActionButton extends StatefulWidget {
  const DriverActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.trailingIcon = Icons.arrow_forward_rounded,
    this.colors = const [Color(0xFFFF9A3E), OraColors.goldSharp],
    this.isLoading = false,
  });

  /// Green "Accept" treatment.
  const DriverActionButton.accept({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    Key? key,
  }) : this(
         key: key,
         label: label,
         onPressed: onPressed,
         isLoading: isLoading,
         icon: Icons.check_rounded,
         trailingIcon: null,
         colors: const [Color(0xFF34D399), Color(0xFF16A34A)],
       );

  /// Red "Decline" treatment.
  const DriverActionButton.decline({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
  }) : this(
         key: key,
         label: label,
         onPressed: onPressed,
         icon: Icons.close_rounded,
         trailingIcon: null,
         colors: const [Color(0xFFF87171), Color(0xFFDC2626)],
       );

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final List<Color> colors;
  final bool isLoading;

  @override
  State<DriverActionButton> createState() => _DriverActionButtonState();
}

class _DriverActionButtonState extends State<DriverActionButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.colors.last.withValues(alpha: 0.42);
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: OraMotion.press,
      curve: OraMotion.standard,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onPressed?.call();
                }
              : null,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: BorderRadius.circular(OraRadius.pill),
          child: Ink(
            height: 54,
            decoration: BoxDecoration(
              gradient: _enabled
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.colors,
                    )
                  : null,
              color: _enabled ? null : OraColors.disabled,
              borderRadius: BorderRadius.circular(OraRadius.pill),
              border: Border.all(color: const Color(0x59FFFFFF), width: 1.2),
              boxShadow: _enabled
                  ? [
                      BoxShadow(
                        color: glow,
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                        spreadRadius: -6,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 20, color: Colors.white),
                          const SizedBox(width: OraSpacing.xs),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.button(Colors.white).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.trailingIcon != null) ...[
                          const SizedBox(width: OraSpacing.xs),
                          Icon(
                            widget.trailingIcon,
                            size: 19,
                            color: Colors.white,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular countdown ring — orange progress arc + "0:25" label.
class DriverCountdownRing extends StatelessWidget {
  const DriverCountdownRing({
    required this.remaining,
    required this.total,
    super.key,
    this.size = 40,
    this.bright = false,
  });

  final Duration remaining;
  final Duration total;
  final double size;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final seconds = remaining.inSeconds.clamp(0, 1 << 20);
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final label = seconds >= 60
        ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '0:${seconds.toString().padLeft(2, '0')}';
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: bright
                  ? const Color(0x40FFFFFF)
                  : OraColors.primaryMuted,
              valueColor: AlwaysStoppedAnimation(
                bright ? Colors.white : OraColors.goldSharp,
              ),
            ),
          ),
          Text(
            label,
            style: OraTypography.caption(
              bright ? Colors.white : OraColors.goldSharp,
            ).copyWith(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Small white info tile inside the ride-request stats row
/// ("12.4 km" / "24 min" / "Cash").
class DriverStatPill extends StatelessWidget {
  const DriverStatPill({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: OraSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: OraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(OraRadius.md),
          border: Border.all(color: OraColors.border),
          boxShadow: OraElevation.cardShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: OraColors.textSecondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OraTypography.caption(
                  OraColors.textPrimary,
                ).copyWith(fontWeight: FontWeight.w700, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pickup → drop-off card with green/orange pin column — matches the
/// "New Ride Request" route card.
class DriverRouteCard extends StatelessWidget {
  const DriverRouteCard({
    required this.pickupLabel,
    required this.destinationLabel,
    super.key,
    this.pickupCaption,
  });

  final String pickupLabel;
  final String destinationLabel;
  final String? pickupCaption;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OraRadius.card),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.white],
                  stops: [0.0, 0.45],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: Image.asset(
                  'assets/driver_tiles/route_card_art.png',
                  width: 150,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(OraSpacing.md),
              child: Column(
                children: [
                  _RouteRow(
                    dotColor: const Color(0xFF22C55E),
                    title: pickupCaption ?? 'Pickup',
                    address: pickupLabel,
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 5),
                    alignment: Alignment.centerLeft,
                    height: 18,
                    child: Container(
                      width: 2,
                      height: 18,
                      color: OraColors.border,
                    ),
                  ),
                  _RouteRow(
                    dotColor: OraColors.goldSharp,
                    title: 'Drop-off',
                    address: destinationLabel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.dotColor,
    required this.title,
    required this.address,
  });

  final Color dotColor;
  final String title;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: 0.45),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: OraTypography.bodyEmphasis(
                  OraColors.textPrimary,
                ).copyWith(fontSize: 14),
              ),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: OraTypography.caption(
                  OraColors.textMuted,
                ).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// New-ride-request sheet header — bright-orange wave band with a grab
/// handle, glass back circle, centered white title and a trailing slot
/// (countdown ring). Matches the request-sheet mockup.
class DriverRequestSheetHeader extends StatelessWidget {
  const DriverRequestSheetHeader({
    required this.title,
    super.key,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layered wave edge — lighter band peeking under the main band.
        Container(
          height: 108,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFB35E), Color(0xFFFF8A2B)],
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
          ),
        ),
        Container(
          width: double.infinity,
          height: 96,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Color(0x59FF6A0D),
                blurRadius: 18,
                offset: Offset(0, 8),
                spreadRadius: -8,
              ),
            ],
          ),
          padding: const EdgeInsets.only(
            left: OraSpacing.xs,
            right: OraSpacing.xs,
            bottom: OraSpacing.md,
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 6, bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x8AFFFFFF),
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    _HeaderCircleButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: onBack,
                      bright: true,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OraTypography.title(Colors.white).copyWith(
                          fontFamily: OraTypography.displayFamily,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(child: trailing),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Passenger-offer display card — big orange amount + 3D money image,
/// optional edit affordance for counter offers.
class DriverOfferCard extends StatelessWidget {
  const DriverOfferCard({
    required this.label,
    required this.amountLabel,
    super.key,
    this.trailing,
    this.onEdit,
  });

  final String label;
  final String amountLabel;
  final Widget? trailing;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: OraTypography.caption(
                    OraColors.textMuted,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  amountLabel,
                  style: OraTypography.display(
                    OraColors.goldDeep,
                  ).copyWith(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            Padding(
              padding: const EdgeInsets.only(right: OraSpacing.xs),
              child: OraTapScale(
                downScale: 0.92,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Semantics(
                    label: 'Counter Offer',
                    button: true,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OraColors.gold.withValues(alpha: 0.12),
                        border: Border.all(
                          color: OraColors.gold.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: OraColors.goldSharp,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// "Frequently used" strip — matches the passenger RecentActivitySection:
/// OraCard rows with a 3D thumb, title, subtitle and chevron, ordered by
/// the driver's most recently opened areas.
class DriverRecentSection extends ConsumerWidget {
  const DriverRecentSection({required this.onOpen, super.key});

  /// Called with the destination the driver tapped.
  final ValueChanged<DriverRecentDestination> onOpen;

  static const _meta =
      <DriverRecentDestination, (String, String, String?, IconData)>{
        DriverRecentDestination.requests: (
          'Open ride requests',
          'Open invites near you',
          'assets/marketplace/modules/rides.webp',
          Icons.travel_explore_rounded,
        ),
        DriverRecentDestination.bookings: (
          'My Rides',
          'Active & previous rides',
          'assets/marketplace/rides/premium.webp',
          Icons.route_rounded,
        ),
        DriverRecentDestination.earnings: (
          'Earnings',
          'Today, week & month totals',
          'assets/marketplace/services/subs/accounting_tax.webp',
          Icons.bar_chart_rounded,
        ),
        DriverRecentDestination.wallet: (
          'Wallet',
          'Balance & payouts',
          'assets/driver_tiles/wallet_3d.png',
          Icons.account_balance_wallet_rounded,
        ),
        DriverRecentDestination.profile: (
          'My Profile',
          'Account & documents',
          null,
          Icons.person_rounded,
        ),
        DriverRecentDestination.activeRide: (
          'Active Ride',
          'Resume your current trip',
          null,
          Icons.route_rounded,
        ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(driverRecentsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OraSectionHeader(title: 'Frequently used'),
        const SizedBox(height: OraSpacing.xs),
        for (final destination in recents)
          Padding(
            padding: const EdgeInsets.only(bottom: OraSpacing.xs),
            child: _DriverRecentRow(
              destination: destination,
              onTap: () => onOpen(destination),
            ),
          ),
      ],
    );
  }
}

class _DriverRecentRow extends StatelessWidget {
  const _DriverRecentRow({required this.destination, required this.onTap});

  final DriverRecentDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, asset, icon) =
        DriverRecentSection._meta[destination]!;
    return OraTapScale(
      downScale: 0.98,
      child: OraCard(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        padding: const EdgeInsets.all(OraSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(OraRadius.sm),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF9EF), Color(0xFFFCE9CE)],
                ),
                border: Border.all(color: OraColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: asset != null
                  ? Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        asset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stackTrace) =>
                            DriverIconBadge(icon: icon, size: 40, iconSize: 20),
                      ),
                    )
                  : Center(
                      child: DriverIconBadge(
                        icon: icon,
                        size: 40,
                        iconSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(OraColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: OraSpacing.xs),
            const Icon(Icons.chevron_right_rounded, color: OraColors.textMuted),
          ],
        ),
      ),
    );
  }
}
