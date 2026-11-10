import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/util/use_animation_controller2.dart';
import 'package:monet_ui/widgets/monet_button_icon.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:pixel_snap_fork/material.dart';

/// The "loading pulse" treatment for Monet buttons and chips.
///
/// The resting or selected background breathes toward a tone±40 variant.
/// Interaction states retain their feedback colors. Protection shadows use
/// the unpulsed background, including the live palette during theme changes.
class MonetPulseResult {
  final ButtonStyle style;
  final List<Shadow> contentShadows;
  final Listenable? repaint;
  final Color Function(Set<WidgetState> states)? paintBackgroundColor;
  const MonetPulseResult({
    required this.style,
    required this.contentShadows,
    this.repaint,
    this.paintBackgroundColor,
  });
}

MonetPulseResult useMonetPulse({
  required ButtonStyle style,
  required bool isAnimating,
  Color Function(Set<WidgetState> states)? paintBaseColor,
}) {
  final baseResolver = style.backgroundColor;
  final restingBackground =
      baseResolver?.resolve(const {}) ?? Colors.transparent;
  final canPulse = restingBackground != Colors.transparent;
  final pulse = useAnimationController2(
    duration: const Duration(milliseconds: 1000),
  );
  final active = isAnimating && canPulse;
  // ignore: function-always-returns-null
  useEffect(() {
    if (active) {
      pulse.repeat(reverse: true);
    } else {
      pulse.reverse();
    }
    return null;
  }, [pulse, active]);
  final colors = useMemoized(_PulseColors.new);
  // The surface listens to every animation tick directly. This widget only
  // needs one rebuild when a graceful reverse reaches rest so it can remove
  // the paint listener and protection shadows.
  final settledRevision = useState(0);
  useEffect(() {
    if (isAnimating) return null;
    void handleStatus(AnimationStatus status) {
      if (status == .dismissed) settledRevision.value++;
    }

    pulse.addStatusListener(handleStatus);
    return () => pulse.removeStatusListener(handleStatus);
  }, [pulse, isAnimating]);
  // Stay in the pulsing branch while gracefully reversing back to rest after
  // isAnimating flips false; pulse.animation goes idle once settled.
  final isIdle = !isAnimating && pulse.status == .dismissed;
  if (isIdle || !canPulse) {
    return MonetPulseResult(
      style: style,
      contentShadows: const [],
      repaint: null,
      paintBackgroundColor: null,
    );
  }
  return MonetPulseResult(
    style: style,
    contentShadows: protectionShadows(restingBackground),
    repaint: pulse,
    paintBackgroundColor: (states) {
      final base =
          paintBaseColor?.call(states) ??
          baseResolver?.resolve(states) ??
          Colors.transparent;
      final canPulseState = states.every((state) => state == .selected);
      return canPulseState ? colors.resolve(base, pulse.value) : base;
    },
  );
}

/// One base-color cache per mounted pulse. Palette changes replace it.
class _PulseColors {
  Color? _base;
  Color? _destination;
  final Map<int, Color> _frames = {};

  Color resolve(Color base, double value) {
    if (base.a == 0 || value == 0) return base;
    if (base != _base) {
      final hct = Hct.fromColor(base);
      final tone = hct.tone > 50 ? hct.tone - 40 : hct.tone + 40;
      _base = base;
      _destination = Hct.from(hct.hue, hct.chroma, tone).color;
      _frames.clear();
    }
    return _frames.putIfAbsent(
      (value * 100).round(),
      () => Hct.lerpKeepHue(base, _destination!, value),
    );
  }
}

/// Icon for pulsing buttons: takes color and size from the enclosing
/// button's [IconTheme] and draws [shadows] with a MonetIcon.
class MonetPulseIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final List<Shadow> shadows;

  const MonetPulseIcon({
    super.key,
    required this.icon,
    required this.shadows,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return MonetButtonIcon(
      shadows: shadows,
      child: MonetIcon(icon, size: size),
    );
  }
}
