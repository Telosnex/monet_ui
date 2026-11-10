import 'dart:math' as math;

import 'package:monet_ui/widgets/display_geometry.dart';
import 'package:pixel_snap_fork/material.dart';

/// Quantized screen-size lookups for resize performance.
///
/// Depending on `MediaQuery.sizeOf` directly rebuilds a widget on *every*
/// resize tick, even when the widget only cares about a derived value that
/// rarely changes (e.g. "is this a small screen?"). Profiling window resizing
/// showed that per-pixel rebuild breadth, not per-widget cost, dominated the
/// build phase.
///
/// [ScreenBreakpoints] reads `MediaQuery.sizeOf` once near the app root,
/// converts it to the app's calibrated logical-pixel ruler, and exposes
/// derived values as [InheritedModel] aspects. Dependents are notified only
/// when their derived value actually changes, e.g. when the width crosses a
/// threshold, so ordinary resizing causes zero rebuilds.
///
/// All lookups fall back to reading `MediaQuery` directly when no
/// [ScreenBreakpoints] ancestor is present (e.g. widget tests), preserving
/// prior behavior.
class ScreenBreakpoints extends StatelessWidget {
  static const _displayCorrectionAspect = _DisplayCorrectionAspect();

  const ScreenBreakpoints({
    super.key,
    required this.child,
    this.displayCorrection = 1,
  });

  static const screenMinColumnWidth = 240.0;
  // This is a reasonable default for grid cell width in the presence of no
  // width constraint and content that that benefit from having a "normal"
  // width.
  //
  // For example, TTS tiles gained multiple new controls in 2025, like model
  // voice pickers, language code, etc., making [screenMinColumnWidth] of 240.0
  // too narrow.
  static const screenGoodColumnWidth = 320.0;
  // Equivalent to Material guideline for phone vs. non-phones being 600dp.
  static const screenSmallWidth = 480.0;
  static const maxScreenWidth = 1040.0;

  // Supporting pane: a pane beside the screen's primary content, such as
  // Design's preview beside its settings. Material 3 calls this layout
  // "supporting pane". The primary content keeps two good columns and the
  // pane one. A screen exactly [splitMinWidth] wide gives each its minimum;
  // wider, both grow 2:1.
  static const splitMinPrimaryWidth = 2 * screenGoodColumnWidth;
  static const splitMinSupportingWidth = screenGoodColumnWidth;
  static const splitMinWidth = splitMinPrimaryWidth + splitMinSupportingWidth;
  static const splitMaxSupportingFraction =
      splitMinSupportingWidth / splitMinWidth;

  /// A slider's track keeps at least this much beside its label and value.
  static const sliderMinTrackWidth = 160.0;
  static const maxWideContentWidth = 800.0;

  static int columnCountForWidth(
    double width, {
    required double themeScale,
    double? maxWidth,
    int maxColumns = 200,
  }) {
    final minColumnWidth = screenMinColumnWidth * math.sqrt(themeScale);
    final boundedWidth = maxWidth != null ? width.clamp(0, maxWidth) : width;
    return (boundedWidth / minColumnWidth).floor().clamp(1, maxColumns);
  }

  /// Breakpoint for small width screens. For instance, control rows are split
  /// into two rows on small screens.
  ///
  /// Reads a quantized [ScreenBreakpoints] aspect: callers rebuild only when
  /// the answer changes, not on every resize tick.
  static bool isScreenSmallWidth(BuildContext context) {
    return isWidthAtMost(context, screenSmallWidth);
  }

  final Widget child;

  /// Linear conversion from platform logical pixels to calibrated logical
  /// pixels. A value of 2 means a 1920-wide platform viewport has 960 dp
  /// available for breakpoint decisions.
  final double displayCorrection;

  /// Converts a local platform-logical width, such as a [LayoutBuilder]
  /// constraint, to the same calibrated ruler used by the breakpoints.
  ///
  /// Without a [ScreenBreakpoints] ancestor the platform width is returned,
  /// matching the lookup fallbacks below.
  static double calibratedWidthOf(
    BuildContext context,
    double platformLogicalWidth,
  ) {
    final model = InheritedModel.inheritFrom<_ScreenBreakpointsModel>(
      context,
      aspect: _displayCorrectionAspect,
    );
    return calibratedLogicalSize(
      Size(platformLogicalWidth, 0),
      model?.displayCorrection ?? 1,
    ).width;
  }

  /// Converts a width expressed in calibrated dp to Flutter's platform
  /// logical-pixel coordinate space for use in layout constraints.
  ///
  /// Without a [ScreenBreakpoints] ancestor the width is already in the
  /// platform coordinate space and is returned unchanged.
  static double platformWidthOf(BuildContext context, double calibratedWidth) {
    final model = InheritedModel.inheritFrom<_ScreenBreakpointsModel>(
      context,
      aspect: _displayCorrectionAspect,
    );
    return calibratedWidth * (model?.displayCorrection ?? 1);
  }

  /// Whether the screen width, rounded, is at most [threshold].
  ///
  /// Rebuilds dependents only when the answer changes.
  static bool isWidthAtMost(BuildContext context, double threshold) {
    final aspect = _WidthAtMostAspect(threshold);
    final model = InheritedModel.inheritFrom<_ScreenBreakpointsModel>(
      context,
      aspect: aspect,
    );
    return aspect.resolve(
      model?.values ??
          _BreakpointValues(size: MediaQuery.sizeOf(context), correction: 1),
    );
  }

  /// Whether the screen width, rounded, is at least [threshold].
  ///
  /// Rebuilds dependents only when the answer changes.
  static bool isWidthAtLeast(BuildContext context, double threshold) {
    final aspect = _WidthAtLeastAspect(threshold);
    final model = InheritedModel.inheritFrom<_ScreenBreakpointsModel>(
      context,
      aspect: aspect,
    );
    return aspect.resolve(
      model?.values ??
          _BreakpointValues(size: MediaQuery.sizeOf(context), correction: 1),
    );
  }

  /// Whether the screen is taller than it is wide.
  ///
  /// Rebuilds dependents only when orientation flips.
  static bool isPortrait(BuildContext context) {
    const aspect = _PortraitAspect();
    final model = InheritedModel.inheritFrom<_ScreenBreakpointsModel>(
      context,
      aspect: aspect,
    );
    return aspect.resolve(
      model?.values ??
          _BreakpointValues(size: MediaQuery.sizeOf(context), correction: 1),
    );
  }

  /// The screen width, capped at [cap].
  ///
  /// Rebuilds dependents only when the capped value changes; once the width
  /// is at or above [cap], further resizing causes no rebuilds.
  static double widthCappedAt(BuildContext context, double cap) {
    final aspect = _WidthCappedAtAspect(cap);
    final model = InheritedModel.inheritFrom<_ScreenBreakpointsModel>(
      context,
      aspect: aspect,
    );
    return aspect.resolve(
      model?.values ??
          _BreakpointValues(size: MediaQuery.sizeOf(context), correction: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveCorrection =
        displayCorrection.isFinite && displayCorrection > 0
        ? displayCorrection
        : 1.0;
    return _ScreenBreakpointsModel(
      size: calibratedLogicalSize(
        MediaQuery.sizeOf(context),
        effectiveCorrection,
      ),
      displayCorrection: effectiveCorrection,
      child: child,
    );
  }
}

// The model is an implementation detail of ScreenBreakpoints; separating the
// files would only expose it.
// ignore: prefer-single-widget-per-file
class _ScreenBreakpointsModel
    extends InheritedModel<_BreakpointAspect<Object>> {
  const _ScreenBreakpointsModel({
    required this.size,
    required this.displayCorrection,
    required super.child,
  });

  final Size size;
  final double displayCorrection;
  _BreakpointValues get values =>
      .new(size: size, correction: displayCorrection);

  @override
  bool updateShouldNotify(_ScreenBreakpointsModel oldWidget) {
    return size != oldWidget.size ||
        displayCorrection != oldWidget.displayCorrection;
  }

  @override
  bool updateShouldNotifyDependent(
    _ScreenBreakpointsModel oldWidget,
    Set<_BreakpointAspect<Object>> dependencies,
  ) {
    return dependencies.any(
      (aspect) => aspect.resolve(values) != aspect.resolve(oldWidget.values),
    );
  }
}

class _BreakpointValues {
  const _BreakpointValues({required this.size, required this.correction});

  final Size size;
  final double correction;
}

/// A derived value of the screen size.
///
/// Implementations must have value equality: aspects are stored in a set per
/// dependent, and equality is what deduplicates repeated lookups.
sealed class _BreakpointAspect<T extends Object> {
  const _BreakpointAspect();

  T resolve(_BreakpointValues values);
}

class _DisplayCorrectionAspect extends _BreakpointAspect<double> {
  const _DisplayCorrectionAspect();

  @override
  double resolve(_BreakpointValues values) => values.correction;
}

class _WidthAtMostAspect extends _BreakpointAspect<bool> {
  const _WidthAtMostAspect(this.threshold);

  final double threshold;

  @override
  bool resolve(_BreakpointValues values) =>
      values.size.width.round() <= threshold;

  @override
  bool operator ==(Object other) {
    return other is _WidthAtMostAspect && other.threshold == threshold;
  }

  @override
  int get hashCode => Object.hash(_WidthAtMostAspect, threshold);
}

class _WidthAtLeastAspect extends _BreakpointAspect<bool> {
  const _WidthAtLeastAspect(this.threshold);

  final double threshold;

  @override
  bool resolve(_BreakpointValues values) =>
      values.size.width.round() >= threshold;

  @override
  bool operator ==(Object other) {
    return other is _WidthAtLeastAspect && other.threshold == threshold;
  }

  @override
  int get hashCode => Object.hash(_WidthAtLeastAspect, threshold);
}

class _PortraitAspect extends _BreakpointAspect<bool> {
  const _PortraitAspect();

  @override
  bool resolve(_BreakpointValues values) =>
      values.size.height > values.size.width;

  @override
  bool operator ==(Object other) => other is _PortraitAspect;

  @override
  int get hashCode => (_PortraitAspect).hashCode;
}

class _WidthCappedAtAspect extends _BreakpointAspect<double> {
  const _WidthCappedAtAspect(this.cap);

  final double cap;

  @override
  double resolve(_BreakpointValues values) => math.min(values.size.width, cap);

  @override
  bool operator ==(Object other) {
    return other is _WidthCappedAtAspect && other.cap == cap;
  }

  @override
  int get hashCode => Object.hash(_WidthCappedAtAspect, cap);
}
