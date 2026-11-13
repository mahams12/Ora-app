import 'package:flutter/material.dart';

/// Gentle up-down float for 3D art/icons — lightweight loop, staggered per
/// instance so sibling elements don't bob in lockstep.
class OraFloaty extends StatefulWidget {
  const OraFloaty({
    required this.child,
    this.amplitude = 8.0,
    this.period = const Duration(milliseconds: 2200),
    super.key,
  });

  final Widget child;
  final double amplitude;
  final Duration period;

  @override
  State<OraFloaty> createState() => _OraFloatyState();
}

class _OraFloatyState extends State<OraFloaty>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: true);
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.value = (widget.child.hashCode.abs() % 100) / 100;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          -widget.amplitude / 2 + widget.amplitude * _anim.value,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Press-in scale for tappable surfaces — pairs with InkWell: tracks
/// down/up/cancel for the squash while the inner InkWell fires the tap.
class OraTapScale extends StatefulWidget {
  const OraTapScale({
    required this.child,
    this.scale = 0.95,
    this.duration = const Duration(milliseconds: 130),
    super.key,
  });

  final Widget child;
  final double scale;
  final Duration duration;

  @override
  State<OraTapScale> createState() => _OraTapScaleState();
}

class _OraTapScaleState extends State<OraTapScale> {
  var _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
