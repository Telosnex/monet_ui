import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/colorspaces/color_model.dart';
import 'package:monet_ui/colorspaces/hct.dart';
import 'package:monet_ui/effects/over_image.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:pixel_snap_fork/material.dart';

/// The one border every chip over [background] shares, for chips drawn in
/// [theme]'s primary, secondary and tertiary.
///
/// Solve for the colors actually drawn: a border is only checked against the
/// surfaces it's solved for, and a chip in another color can end up with a
/// border far from, or on top of, its own tone.
///
/// Pass the target theme (`monetThemeData.target`), not an animation frame,
/// then ease it with [useEasedBorderTone]: a theme crossfade is then one
/// solve per endpoint, not one per frame.
SharedBorder sharedBorderForTheme(
  AnyBackground background,
  MonetThemeData theme,
) => background.sharedBorder([
  theme.primary.color.toARGB32(),
  theme.secondary.color.toARGB32(),
  theme.tertiary.color.toARGB32(),
], colorModel: theme.colorModel);

/// Applies a [SharedBorder] to any palette.
extension SharedBorderForPalette on SharedBorder {
  /// This border's tone in [palette]'s hue and chroma.
  ///
  /// For a palette whose color was one of the solved surfaces this equals its
  /// entry in [SharedBorder.borderArgbs]. Solve with the target theme's
  /// colors, then call this with the palette being drawn: during a theme
  /// crossfade the border follows the chip's current hue at the final tone,
  /// with no solve per frame.
  ///
  /// [colorModel] must match the one the border was solved in.
  Color forPalette(Palette palette, {ColorModel colorModel = .kDefault}) {
    final hct = Hct.fromColor(palette.color, model: colorModel);
    return Hct.from(hct.hue, hct.chroma, tone, model: colorModel).color;
  }
}

/// A border tone, applied in any palette's hue and chroma: what chips sharing
/// a [SharedBorder] draw, possibly partway between two.
@immutable
class BorderTone {
  const BorderTone(this.tone, {this.colorModel = ColorModel.kDefault});

  /// 0..100.
  final double tone;

  /// The model the tone was solved in.
  final ColorModel colorModel;

  /// [tone] in [palette]'s current hue and chroma. During a theme crossfade
  /// that's the chip's hue for this frame.
  Color forPalette(Palette palette) {
    final hct = Hct.fromColor(palette.color, model: colorModel);
    return Hct.from(hct.hue, hct.chroma, tone, model: colorModel).color;
  }

  @override
  bool operator ==(Object other) =>
      other is BorderTone &&
      tone == other.tone &&
      colorModel == other.colorModel;

  @override
  int get hashCode => Object.hash(tone, colorModel);
}

/// Eases a border tone between endpoints by a theme's transition progress
/// ([MonetThemeData.transitionProgress]), so a crossfade solves the border
/// once per endpoint and the tone never jumps.
///
/// Partway through, the tone isn't checked against the chips' partway colors.
/// Lerped palette roles have the same limitation.
class BorderToneEasing {
  double? _shown;
  double _from = 0;
  double _to = 0;
  double _fromProgress = 1;
  double _lastProgress = 1;

  /// The tone to draw for endpoint [to] at [progress], 0..1.
  ///
  /// A new endpoint, or progress restarting (a retarget), eases from the
  /// tone last drawn over the rest of the progress. A new endpoint at rest
  /// (e.g. the wallpaper's pixels arriving) is drawn at once.
  double update(double to, double progress) {
    final shown = _shown;
    if (shown == null) {
      _from = to;
      _to = to;
      _fromProgress = 1;
    } else if (to != _to || progress < _lastProgress) {
      _from = shown;
      _to = to;
      _fromProgress = progress;
    }
    _lastProgress = progress;
    final span = 1 - _fromProgress;
    final value = span <= 0
        ? _to
        : _from +
              (_to - _from) *
                  ((progress - _fromProgress) / span).clamp(0.0, 1.0);
    _shown = value;
    return value;
  }
}

/// [border], solved for [theme]'s target, eased through [theme]'s
/// transitions: see [BorderToneEasing]. [theme] is the theme as drawn this
/// frame, e.g. `MonetTheme.of(context).monetThemeData`.
BorderTone useEasedBorderTone(SharedBorder border, MonetThemeData theme) {
  final easing = useMemoized(BorderToneEasing.new);
  return BorderTone(
    easing.update(border.tone, theme.transitionProgress),
    colorModel: theme.target.colorModel,
  );
}

/// Gives every colour MonetButton below one border, from [border]: see
/// [AnyBackground.sharedBorder]. Chips the border was not solved for still get
/// its tone in their own hue, so solve with every palette drawn below.
/// Paint-driven chips (`paintPalette`) keep their palette's `colorBorder`.
class SharedBorderScope extends InheritedWidget {
  const SharedBorderScope({
    super.key,
    required this.border,
    required super.child,
  });

  final BorderTone border;

  /// The shared border for [palette], or null outside a scope.
  static Color? borderFor(BuildContext context, Palette palette) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SharedBorderScope>();
    return scope?.border.forPalette(palette);
  }

  @override
  bool updateShouldNotify(SharedBorderScope oldWidget) =>
      border != oldWidget.border;
}
