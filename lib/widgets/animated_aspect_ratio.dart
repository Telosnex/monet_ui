import 'package:pixel_snap_fork/material.dart';

class AnimatedAspectRatio extends ImplicitlyAnimatedWidget {
  final Widget child;
  final double aspectRatio;

  const AnimatedAspectRatio({
    super.key,
    required this.aspectRatio,
    required this.child,
    required super.duration,
    super.curve = Curves.linear,
  });

  @override
  AnimatedAspectRatioState createState() => .new();
}

class AnimatedAspectRatioState
    extends AnimatedWidgetBaseState<AnimatedAspectRatio> {
  Tween<double>? _aspectRatio;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _aspectRatio = visitor(
      _aspectRatio,
      widget.aspectRatio,
      (dynamic value) =>
          // rationale: needed to avoid run time error
          // type 'Tween<Object?>' is not a subtype of type
          // 'Tween<double>?' in type cast
          // ignore: avoid-inferrable-type-arguments
          Tween<double>(begin: value as double, end: widget.aspectRatio),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspectRatio!.evaluate(animation),
      child: widget.child,
    );
  }
}
