import 'package:flutter/material.dart';

/// Prominent buoyant float for cards/3D art — drifts up/down, sways gently,
/// and pulses its scale, staggered per instance so siblings don't move in
/// lockstep.
class OraFloaty extends StatefulWidget {
  const OraFloaty({
    required this.child,
    this.amplitude = 14.0,
    this.scaleAmplitude = 0.045,
    this.tilt = 0.035,
    this.period = const Duration(milliseconds: 1700),
    super.key,
  });

  final Widget child;

  /// Peak-to-peak vertical drift in logical pixels.
  final double amplitude;

  /// Extra grow/shrink on top of the drift (1 ± scaleAmplitude).
  final double scaleAmplitude;

  /// Peak-to-peak rotation sway in radians (~2° at 0.035).
  final double tilt;
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
      builder: (context, child) {
        final v = _anim.value;
        return Transform.translate(
          offset: Offset(0, -widget.amplitude / 2 + widget.amplitude * v),
          child: Transform.rotate(
            angle: (v - 0.5) * widget.tilt,
            child: Transform.scale(
              scale: 1 - widget.scaleAmplitude / 2 + widget.scaleAmplitude * v,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Springy squash-and-pop for tappable surfaces — presses in fast, then
/// bounces back with an elastic overshoot (Lottie "click" style). Uses a
/// Listener so the inner InkWell still receives the tap.
class OraTapScale extends StatefulWidget {
  const OraTapScale({
    required this.child,
    this.downScale = 0.9,
    super.key,
  });

  final Widget child;

  /// Scale while the pointer is held down.
  final double downScale;

  @override
  State<OraTapScale> createState() => _OraTapScaleState();
}

class _OraTapScaleState extends State<OraTapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
    value: 1,
  );

  double _from = 1;
  double _scale = 1;
  bool _held = false;

  void _pressDown() {
    _ctrl.stop();
    _held = true;
    setState(() => _scale = widget.downScale);
  }

  void _release() {
    if (!_held) return;
    _held = false;
    _from = _scale;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _pressDown(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) {
          // elasticOut overshoots past 1 mid-flight, giving the pop, then
          // settles exactly at 1.
          final t = Curves.elasticOut.transform(_ctrl.value);
          final scale = _held ? _scale : _from + (1 - _from) * t;
          return Transform.scale(scale: scale, child: child);
        },
      ),
    );
  }
}
