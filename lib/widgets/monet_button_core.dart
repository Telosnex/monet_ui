// ignore_for_file: prefer-single-widget-per-file, avoid-recursive-widget-calls

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart'
    show
        BoxHitTestResult,
        BoxParentData,
        ChildLayoutHelper,
        ChildLayouter,
        MatrixUtils,
        PaintingContext,
        PipelineOwner,
        RenderBox,
        RenderProxyBox,
        RenderShiftedBox;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/material_icon_ink.dart';
import 'package:monet_ui/widgets/monet_button_label.dart';
import 'package:monet_ui/widgets/monet_fallback_shapes.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/raster_mask_image_budget.dart';
import 'package:pixel_snap_fork/material.dart';

/// The surface, shadow, states and semantics that [MonetButton] and
/// MonetSurface share. Use those; a DCM banned-usage rule keeps it to them.
class MonetButtonCore extends StatelessWidget {
  static const buttonInternalPadding = HorizontalPadding.amount;

  final VoidCallback? onPressed;
  final Color shadowColor;
  final double internalPadding;
  final WidgetStatesController? statesController;
  final ButtonStyle? style;

  /// Plain Icons with registered ink bounds use their ink width, preserving
  /// glyph size. Custom widgets and already-corrected chips keep their own layout.
  final Widget? icon;
  final Widget? label;
  final Color? outlineColorWhenNoShadow;
  final Listenable? paintListenable;
  final Palette Function()? paintPalette;
  final ButtonStyle Function(BuildContext context, Palette palette)? paintStyle;
  final Color Function(Palette palette)? paintShadowColor;

  /// Optional paint-time background resolver for animations that do not
  /// change the rest of the palette.
  ///
  /// When provided, [paintListenable] repaints only the surface; foreground
  /// and shadow widgets are not rebuilt or repainted on its ticks.
  final Color Function(Set<WidgetState> states)? paintBackgroundColor;

  /// Independent surface-only ticks, such as a loading pulse. Palette ticks
  /// still use [paintListenable] for the surface, foreground, and shadow.
  final Listenable? backgroundListenable;

  /// Isolates the animated surface and foreground from each other and from
  /// the aesthetic shadow.
  ///
  /// This costs two composited layers, so it is opt-in for buttons whose
  /// foreground is substantially more expensive to paint than the button
  /// chrome (for example, a card made from several Rows and Columns). Without
  /// this isolation, the 200ms hover/press surface transition re-records the
  /// static foreground and shadow on every frame.
  final bool isolateAnimationRepaints;

  /// False for a surface that only paints: no press, hover, focus or button
  /// semantics, and enabled colors without [onPressed]. See MonetSurface.
  final bool interactive;

  const MonetButtonCore({
    super.key,
    required this.shadowColor,
    this.statesController,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.internalPadding = buttonInternalPadding,
    this.outlineColorWhenNoShadow,
    this.paintListenable,
    this.paintPalette,
    this.paintStyle,
    this.paintShadowColor,
    this.paintBackgroundColor,
    this.backgroundListenable,
    this.isolateAnimationRepaints = false,
    this.interactive = true,
    this.style,
  });

  static Size _minimumSize(BuildContext context) {
    final scale = MonetTheme.of(context).scale;
    return Size(0, minimumSizeForScale(scale).height);
  }

  static WidgetStateProperty<Size> minimumSizeProperty(BuildContext context) {
    return WidgetStatePropertyAll(_minimumSize(context));
  }

  static double iconSizeUsed(BuildContext context, ButtonStyle? style) {
    if (style?.iconSize != null) {
      final resolved = style!.iconSize!.resolve({})!;
      return resolved;
    }
    return iconSizeForTextStyle(Theme.of(context).textTheme.bodyLarge!);
  }

  @override
  Widget build(BuildContext context) {
    // Forked from ElevatedButton/ButtonStyleButton. The SDK button delivers
    // colors at BUILD time: every color change re-runs ButtonStyleButton.build
    // (~77 WidgetStateProperty/Theme resolutions) and republishes a cloned
    // ThemeData via AnimatedTheme to the button's subtree. Under paint-bus
    // animation that meant a full subtree rebuild per button per tick (30Hz).
    //
    // This fork delivers colors at PAINT time (same model as
    // _TintedAestheticShadow / MonetIcon): the widget tree is static, and a
    // render object resolves current colors from the states controller +
    // paint bus when painting. Hover/press/paint ticks are repaints, not
    // rebuilds; only the foreground text/icon colors rebuild (scoped to a
    // single DefaultTextStyle around the label).
    final paintListenable = this.paintListenable;
    final paintPalette = this.paintPalette;
    final palettePaintDriven = paintListenable != null && paintPalette != null;
    final backgroundPaintDriven =
        (paintListenable != null || backgroundListenable != null) &&
        paintBackgroundColor != null;

    // Foreground content, identical composition to the old ElevatedButton
    // branches (including the configurable icon/label gap that
    // ElevatedButton.icon never allowed).
    final icon = this.icon == null ? null : MaterialIconInk.wrap(this.icon!);
    final Widget? content;
    if (icon != null && label != null) {
      content = Row(
        mainAxisSize: .min,
        children: [
          icon,
          SizedBox(width: internalPadding),
          Flexible(child: label!),
        ],
      );
    } else {
      content = icon ?? label;
    }

    final theme = Theme.of(context);
    final monetScale = palettePaintDriven ? MonetTheme.of(context).scale : null;
    // Stock ElevatedButton renders labels with labelLarge; the old code let
    // that flow through Material's textStyle. Color is applied per-state in
    // _ButtonForeground.
    final baseTextStyle =
        style?.textStyle?.resolve(const {}) ?? theme.textTheme.labelLarge!;
    final resolvedIconSize = iconSizeUsed(context, style);
    final buttonShape =
        (style?.shape?.resolve(const {}) ??
                monetShapesOrDefault(context).border())
            .copyWith(side: .none);

    // Preserved verbatim from the old build: shadow color doubles as the
    // 1px border, with an outline fallback when there is no shadow.
    BorderSide sideFor(Color shadow) {
      final hasOutline =
          shadow == Colors.transparent && outlineColorWhenNoShadow != null;
      final hasShadow = shadow != Colors.transparent;
      return hasOutline
          ? BorderSide(color: outlineColorWhenNoShadow!, width: 1)
          : hasShadow
          ? BorderSide(color: shadow, width: 1)
          : BorderSide.none;
    }

    // NOTE: called at paint time when paint-driven. paintStyle/paintPalette/
    // paintShadowColor closures must not read inherited widgets. Capture
    // theme geometry at build time.
    ButtonStyle currentStyle(Palette? palette) {
      if (palettePaintDriven) {
        final colors = palette ?? paintPalette();
        return paintStyle?.call(context, colors) ??
            colorButtonStyle(colors, scale: monetScale!);
      }
      return style ?? const ButtonStyle();
    }

    Palette? cachedShadowPalette;
    Color? cachedPaletteShadowColor;
    Color currentShadowColor([Palette? palette]) {
      if (!palettePaintDriven) return shadowColor;
      final colors = palette ?? paintPalette();
      final cachedColor = cachedPaletteShadowColor;
      if (cachedColor != null && identical(colors, cachedShadowPalette)) {
        return cachedColor;
      }
      final color = paintShadowColor?.call(colors) ?? colors.colorBorder;
      cachedShadowPalette = colors;
      cachedPaletteShadowColor = color;
      return color;
    }

    Palette? cachedVisualsPalette;
    int? cachedVisualsStatesSignature;
    _ButtonVisuals? cachedBaseVisuals;
    _ButtonVisuals resolveVisuals(Set<WidgetState> states) {
      final palette = palettePaintDriven ? paintPalette() : null;
      final statesSignature = _widgetStatesSignature(states);
      var visuals = cachedBaseVisuals;
      if (visuals == null ||
          statesSignature != cachedVisualsStatesSignature ||
          palettePaintDriven && !identical(palette, cachedVisualsPalette)) {
        final s = currentStyle(palette);
        final foreground =
            s.foregroundColor?.resolve(states) ??
            baseTextStyle.color ??
            theme.colorScheme.onPrimary;
        visuals = _ButtonVisuals(
          background: paintBackgroundColor == null
              ? (s.backgroundColor?.resolve(states) ?? Colors.transparent)
              : Colors.transparent,
          foreground: foreground,
          iconColor: s.iconColor?.resolve(states) ?? foreground,
          side: sideFor(currentShadowColor(palette)),
        );
        cachedVisualsPalette = palette;
        cachedVisualsStatesSignature = statesSignature;
        cachedBaseVisuals = visuals;
      }

      final backgroundResolver = paintBackgroundColor;
      if (backgroundResolver == null) return visuals;
      final background = backgroundResolver(states);
      if (background == visuals.background) return visuals;
      return _ButtonVisuals(
        background: background,
        foreground: visuals.foreground,
        iconColor: visuals.iconColor,
        side: visuals.side,
      );
    }

    // Foreground colors at the *settled* palette (`style`, which `.color`
    // builds from the caller's settled `colors`). While the palette is
    // paint-driven these are what the inherited DefaultTextStyle / IconTheme
    // carry — they change on hover/press/disable, never on a bus tick — and
    // paint-aware label leaves get the in-flight color from resolveVisuals via
    // PaintDrivenColorScope. Without a paint-driven palette the two agree.
    _ButtonVisuals resolveSettledVisuals(Set<WidgetState> states) {
      if (!palettePaintDriven) return resolveVisuals(states);
      final s = style ?? const ButtonStyle();
      final foreground =
          s.foregroundColor?.resolve(states) ??
          baseTextStyle.color ??
          theme.colorScheme.onPrimary;
      return _ButtonVisuals(
        background: Colors.transparent,
        foreground: foreground,
        iconColor: s.iconColor?.resolve(states) ?? foreground,
        side: .none,
      );
    }

    // Geometry math preserved from ButtonStyleButton with
    // VisualDensity.compact (what colorButtonStyle always sets):
    // baseSizeAdjustment == (-8, -8); horizontal padding reduction is
    // disallowed per Material guidance in the SDK source.
    const densityAdjustment = Offset(-8, -8);
    const dx = 0.0;
    const dy = -8.0;
    final basePadding = EdgeInsets.only(
      left: internalPadding,
      right: internalPadding,
      // For some reason, ElevatedButton default is 8/2 on iOS and 8/12 on
      // ex. macOS; see the old build's note about its conditional logic.
      top: VerticalPaddingHalf.amount,
      bottom: VerticalPaddingHalf.amount,
    );
    final effectivePadding = basePadding
        .add(.fromLTRB(dx, dy, dx, dy))
        .clamp(EdgeInsets.zero, .infinity);

    final minimumSize =
        style?.minimumSize?.resolve(const {}) ?? _minimumSize(context);
    final constraints = BoxConstraints(
      minWidth: math.max(0, minimumSize.width + densityAdjustment.dx),
      minHeight: math.max(0, minimumSize.height + densityAdjustment.dy),
    );
    final tapTargetSize = switch (theme.materialTapTargetSize) {
      .padded => Size(
        kMinInteractiveDimension + densityAdjustment.dx,
        kMinInteractiveDimension + densityAdjustment.dy,
      ),
      .shrinkWrap => Size.zero,
    };

    final core = _MonetButtonCore(
      onPressed: onPressed,
      statesController: statesController,
      visualsResolver: resolveVisuals,
      settledVisualsResolver: resolveSettledVisuals,
      surfaceRepaint: palettePaintDriven || backgroundPaintDriven
          ? Listenable.merge([paintListenable, backgroundListenable])
          : null,
      foregroundRepaint: palettePaintDriven ? paintListenable : null,
      constraints: constraints,
      tapTargetSize: tapTargetSize,
      padding: effectivePadding,
      baseTextStyle: baseTextStyle,
      textStyle: style?.textStyle,
      iconSize: resolvedIconSize,
      shape: buttonShape,
      isolateAnimationRepaints: isolateAnimationRepaints,
      interactive: interactive,
      child: content,
    );

    return SelectionContainer.disabled(
      child: _TintedAestheticShadow(
        shadowColor: shadowColor,
        shape: buttonShape,
        repaint: palettePaintDriven ? paintListenable : null,
        shadowColorResolver: palettePaintDriven ? currentShadowColor : null,
        // Stop the surface's paint-site tween at this inner boundary instead
        // of dirtying the shadow (and the caller's whole repaint boundary).
        child: isolateAnimationRepaints ? RepaintBoundary(child: core) : core,
      ),
    );
  }
}

/// Snapshot of state-dependent button colors, resolved at paint/notify time.
class _ButtonVisuals {
  const _ButtonVisuals({
    required this.background,
    required this.foreground,
    required this.iconColor,
    required this.side,
  });

  final Color background;
  final Color foreground;
  final Color iconColor;
  final BorderSide side;
}

typedef _ButtonVisualsResolver = _ButtonVisuals Function(Set<WidgetState>);

int _widgetStatesSignature(Set<WidgetState> states) {
  var signature = 0;
  for (final state in states) {
    signature |= 1 << state.index;
  }
  return signature;
}

/// The forked button chassis: focus/hover/press/semantics without Material,
/// InkWell, or Theme republication. Surface colors paint via
/// [_ButtonSurface]; foreground colors are settled in a DefaultTextStyle /
/// IconTheme and in-flight on a [PaintDrivenColorScope] in
/// [_ButtonForeground].
class _MonetButtonCore extends StatefulWidget {
  const _MonetButtonCore({
    required this.onPressed,
    required this.statesController,
    required this.visualsResolver,
    required this.settledVisualsResolver,
    required this.surfaceRepaint,
    required this.foregroundRepaint,
    required this.constraints,
    required this.tapTargetSize,
    required this.padding,
    required this.baseTextStyle,
    required this.textStyle,
    required this.iconSize,
    required this.shape,
    required this.isolateAnimationRepaints,
    required this.interactive,
    required this.child,
  });

  final VoidCallback? onPressed;
  final WidgetStatesController? statesController;
  final _ButtonVisualsResolver visualsResolver;
  final _ButtonVisualsResolver settledVisualsResolver;
  final Listenable? surfaceRepaint;
  final Listenable? foregroundRepaint;
  final BoxConstraints constraints;
  final Size tapTargetSize;
  final EdgeInsetsGeometry padding;
  final TextStyle baseTextStyle;
  final WidgetStateProperty<TextStyle?>? textStyle;
  final double iconSize;
  final OutlinedBorder shape;
  final bool isolateAnimationRepaints;
  final bool interactive;
  final Widget? child;

  @override
  State<_MonetButtonCore> createState() => _MonetButtonCoreState();
}

class _MonetButtonCoreState extends State<_MonetButtonCore> {
  WidgetStatesController? _internalController;

  WidgetStatesController get _states =>
      widget.statesController ?? (_internalController ??= .new());

  bool get _enabled => widget.interactive && widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _syncEnabledState();
  }

  @override
  void didUpdateWidget(covariant _MonetButtonCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statesController != widget.statesController ||
        oldWidget.interactive != widget.interactive ||
        (oldWidget.onPressed == null) != !_enabled) {
      _syncEnabledState();
    }
  }

  void _syncEnabledState() {
    // A surface that only paints keeps its enabled colors.
    _states.update(.disabled, widget.interactive && !_enabled);
    if (!_enabled) _states.update(.pressed, false);
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_enabled) return;
    Feedback.forTap(context);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final states = _states;
    final foreground = _ButtonForeground(
      visualsResolver: widget.visualsResolver,
      settledVisualsResolver: widget.settledVisualsResolver,
      statesController: states,
      repaint: widget.foregroundRepaint,
      baseTextStyle: widget.baseTextStyle,
      textStyle: widget.textStyle,
      iconSize: widget.iconSize,
      child: widget.child ?? const SizedBox.shrink(),
    );

    final control = _InputPadding(
      minSize: widget.tapTargetSize,
      child: ConstrainedBox(
        constraints: widget.constraints,
        child: FocusableActionDetector(
          enabled: _enabled,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowHoverHighlight: (value) => states.update(.hovered, value),
          onShowFocusHighlight: (value) => states.update(.focused, value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              // ignore: function-always-returns-null
              onInvoke: (_) {
                _handleTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: .opaque,
            onTapDown: _enabled ? (_) => states.update(.pressed, true) : null,
            onTapUp: _enabled ? (_) => states.update(.pressed, false) : null,
            onTapCancel: _enabled ? () => states.update(.pressed, false) : null,
            onTap: _enabled ? _handleTap : null,
            child: _ButtonSurface(
              visualsResolver: widget.visualsResolver,
              statesController: states,
              repaint: widget.surfaceRepaint,
              shape: widget.shape,
              child: Padding(
                padding: widget.padding,
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1.0,
                  heightFactor: 1.0,
                  // Surface smoothing repaints for 200ms after a discrete
                  // hover/press change. Retain a complex foreground while
                  // those background-only frames are recorded.
                  child: widget.isolateAnimationRepaints
                      ? RepaintBoundary(child: foreground)
                      : foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.interactive) return control;
    // Paint listeners consume state changes without rebuilding the control.
    // Rebuild only this semantics wrapper so externally controlled selection
    // remains accurate for accessibility.
    return ListenableBuilder(
      listenable: states,
      child: control,
      builder: (context, child) => Semantics(
        container: true,
        button: true,
        enabled: _enabled,
        selected: states.value.contains(WidgetState.selected),
        child: child,
      ),
    );
  }
}

/// Paints the themed fill and border with colors resolved at paint time.
/// Hover/press (states controller) and paint-bus ticks are repaints only.
class _ButtonSurface extends SingleChildRenderObjectWidget {
  const _ButtonSurface({
    required this.visualsResolver,
    required this.statesController,
    required this.repaint,
    required this.shape,
    required super.child,
  });

  final _ButtonVisualsResolver visualsResolver;
  final WidgetStatesController statesController;
  final Listenable? repaint;
  final OutlinedBorder shape;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderButtonSurface(visualsResolver, statesController, repaint, shape);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderButtonSurface renderObject,
  ) {
    renderObject
      ..visualsResolver = visualsResolver
      ..statesController = statesController
      ..repaint = repaint
      ..shape = shape;
  }
}

/// Duration used for discrete widget-state transitions. Style and paint-time
/// animation values paint directly; they already have an animation owner.
const _kColorStepSmoothing = Duration(milliseconds: 200);

class _DiscretePaintTransition<T> {
  _DiscretePaintTransition(this._lerp);

  final T Function(T, T, double) _lerp;
  T? _displayed;
  T? _from;
  Duration _start = .zero;
  bool _changePending = false;
  bool _animating = false;

  bool get animating => _animating;

  /// Marks a discrete widget-state change, such as hover or press.
  /// Style rebuilds and paint-listenable ticks deliberately do not call this.
  void markChanged() {
    _changePending = true;
  }

  T evaluate(T target, Duration now) {
    if (_displayed == null) {
      _displayed = target;
      _changePending = false;
      return target;
    }

    if (_changePending) {
      _changePending = false;
      _from = _displayed;
      _start = now;
      _animating = _displayed != target;
    }

    if (!_animating) {
      // Continuous paint-time values land directly instead of being fed into
      // a second tween that chases and attenuates their animation.
      _displayed = target;
      return target;
    }

    final t =
        ((now - _start).inMicroseconds / _kColorStepSmoothing.inMicroseconds)
            .clamp(0.0, 1.0);
    _displayed = t >= 1.0 ? target : _lerp(_from as T, target, t);
    if (t >= 1.0) _animating = false;
    return _displayed!;
  }
}

mixin _SelfAnimatingPaint on RenderObject {
  bool _continuationPending = false;
  Duration _lastPaintNow = .zero;

  /// Frame timestamp for paint-site tweening.
  ///
  /// `currentFrameTimeStamp` asserts when paint happens outside a frame
  /// (golden tests paint via a hand-built PaintingContext with no frame in
  /// progress). Fall back to the last in-frame timestamp: outside a frame
  /// time simply doesn't advance, so smoothing holds its current value —
  /// exactly what a synchronous out-of-band paint should show.
  Duration get paintNow {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != .idle &&
        binding.schedulerPhase != .postFrameCallbacks) {
      _lastPaintNow = binding.currentFrameTimeStamp;
    }
    // ignore: match-getter-setter-field-names
    return _lastPaintNow;
  }

  /// Asks for one more frame; safe to call from paint().
  void requestPaintContinuation() {
    if (_continuationPending) return;
    _continuationPending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _continuationPending = false;
      if (attached) markNeedsPaint();
    });
  }
}

class _RenderButtonSurface extends RenderProxyBox with _SelfAnimatingPaint {
  _RenderButtonSurface(
    this._visualsResolver,
    this._statesController,
    this._repaint,
    this._shape,
  );

  final Paint _fillPaint = Paint()..isAntiAlias = true;
  final Paint _sidePaint = Paint()
    ..isAntiAlias = true
    ..style = .stroke;
  ShapeBorder? _cachedOuterPathShape;
  Rect? _cachedOuterPathRect;
  Path? _cachedOuterPath;

  OutlinedBorder _shape;
  set shape(OutlinedBorder value) {
    if (_shape == value) return;
    _shape = value;
    _cachedOuterPathShape = null;
    _cachedOuterPathRect = null;
    _cachedOuterPath = null;
    markNeedsPaint();
  }

  Path _outerPath(Rect rect) {
    final cachedPath = _cachedOuterPath;
    if (cachedPath != null &&
        (identical(_cachedOuterPathShape, _shape) ||
            _cachedOuterPathShape == _shape) &&
        _cachedOuterPathRect == rect) {
      return cachedPath;
    }
    final path = _shape.getOuterPath(rect);
    _cachedOuterPathShape = _shape;
    _cachedOuterPathRect = rect;
    _cachedOuterPath = path;
    return path;
  }

  _ButtonVisualsResolver _visualsResolver;
  set visualsResolver(_ButtonVisualsResolver value) {
    if (identical(_visualsResolver, value)) return;
    _visualsResolver = value;
    markNeedsPaint();
  }

  WidgetStatesController _statesController;
  set statesController(WidgetStatesController value) {
    if (identical(_statesController, value)) return;
    if (attached) _statesController.removeListener(_handleStatesChanged);
    _statesController = value;
    if (attached) _statesController.addListener(_handleStatesChanged);
    _backgroundTransition.markChanged();
    markNeedsPaint();
  }

  Listenable? _repaint;
  set repaint(Listenable? value) {
    if (identical(_repaint, value)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  void _handleStatesChanged() {
    _backgroundTransition.markChanged();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _statesController.addListener(_handleStatesChanged);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _statesController.removeListener(_handleStatesChanged);
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  final _DiscretePaintTransition<Color> _backgroundTransition =
      _DiscretePaintTransition((a, b, t) => Color.lerp(a, b, t)!);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.width > 0 && size.height > 0) {
      final visuals = _visualsResolver(_statesController.value);
      final now = paintNow;
      final background = _backgroundTransition.evaluate(
        visuals.background,
        now,
      );
      final side = visuals.side;
      if (_backgroundTransition.animating) requestPaintContinuation();
      final rect = offset & size;
      final path = _outerPath(rect);
      if (background.a > 0) {
        _fillPaint.color = background;
        context.canvas.drawPath(path, _fillPaint);
      }
      if (side.style != .none && side.width > 0) {
        _sidePaint
          ..color = side.color
          ..strokeWidth = side.width;
        context.canvas.drawPath(path, _sidePaint);
      }
    }
    super.paint(context, offset);
  }
}

/// Foreground colors for the button content.
///
/// Two channels, because `DefaultTextStyle` and `IconTheme` are inherited
/// widgets: publishing a new color through them notifies *every* `Text` /
/// `Icon` beneath (each `Text` dragging ~6 elements with it). That is fine for
/// a hover or press — one rebuild per interaction — but it is exactly wrong
/// for a paint bus ticking 30–60×/s during a theme or wallpaper animation.
///
///  * **Settled** colors (the caller's palette, resolved for the current
///    states) go in `DefaultTextStyle` / `IconTheme`. They change on state
///    changes only. Plain `Text` / `Icon` children read these and pick up a new
///    palette when the inherited theme publishes it.
///  * **In-flight** colors (the paint-driven palette, resolved for the current
///    states) go on a [PaintDrivenColorScope]. Paint-aware leaves —
///    [MonetButtonLabel]'s `MonetRichText` and `MonetIcon` — listen to the
///    bus at the render layer and repaint in place; no widget rebuilds.
class _ButtonForeground extends StatelessWidget {
  const _ButtonForeground({
    required this.visualsResolver,
    required this.settledVisualsResolver,
    required this.statesController,
    required this.repaint,
    required this.baseTextStyle,
    required this.textStyle,
    required this.iconSize,
    required this.child,
  });

  final _ButtonVisualsResolver visualsResolver;
  final _ButtonVisualsResolver settledVisualsResolver;
  final WidgetStatesController statesController;

  /// Paint bus for the in-flight palette; null when the palette is static.
  final Listenable? repaint;
  final TextStyle baseTextStyle;
  final WidgetStateProperty<TextStyle?>? textStyle;
  final double iconSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: statesController,
      child: child,
      builder: (context, child) {
        final visuals = settledVisualsResolver(statesController.value);
        Widget result = DefaultTextStyle(
          style: (textStyle?.resolve(statesController.value) ?? baseTextStyle)
              .copyWith(color: visuals.foreground),
          child: IconTheme.merge(
            data: IconThemeData(color: visuals.iconColor, size: iconSize),
            child: child!,
          ),
        );
        final repaint = this.repaint;
        if (repaint != null) {
          result = PaintDrivenColorScope(
            color: visuals.foreground,
            iconColor: visuals.iconColor,
            repaint: repaint,
            paintColor: () =>
                visualsResolver(statesController.value).foreground,
            paintIconColor: () =>
                visualsResolver(statesController.value).iconColor,
            child: result,
          );
        }
        return result;
      },
    );
  }
}

/// Redirects hits within the padded tap target to the visual child.
/// Copied from ButtonStyleButton's private _InputPadding (BSD, Flutter
/// Authors) so mobile tap targets keep kMinInteractiveDimension behavior.
class _InputPadding extends SingleChildRenderObjectWidget {
  const _InputPadding({required this.minSize, required super.child});

  final Size minSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderInputPadding(minSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderInputPadding renderObject,
  ) {
    renderObject.minSize = minSize;
  }
}

class _RenderInputPadding extends RenderShiftedBox {
  _RenderInputPadding(this._minSize, [RenderBox? child]) : super(child);

  Size _minSize;
  Size get minSize => _minSize;
  set minSize(Size value) {
    if (_minSize == value) return;
    _minSize = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => child != null
      ? math.max(child!.getMinIntrinsicWidth(height), minSize.width)
      : 0.0;

  @override
  double computeMinIntrinsicHeight(double width) => child != null
      ? math.max(child!.getMinIntrinsicHeight(width), minSize.height)
      : 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) => child != null
      ? math.max(child!.getMaxIntrinsicWidth(height), minSize.width)
      : 0.0;

  @override
  double computeMaxIntrinsicHeight(double width) => child != null
      ? math.max(child!.getMaxIntrinsicHeight(width), minSize.height)
      : 0.0;

  Size _computeSize({
    required BoxConstraints constraints,
    required ChildLayouter layoutChild,
  }) {
    if (child != null) {
      final childSize = layoutChild(child!, constraints);
      final height = math.max(childSize.width, minSize.width);
      final width = math.max(childSize.height, minSize.height);
      return constraints.constrain(Size(height, width));
    }
    return .zero;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _computeSize(
    constraints: constraints,
    layoutChild: ChildLayoutHelper.dryLayoutChild,
  );

  @override
  void performLayout() {
    size = _computeSize(
      constraints: constraints,
      layoutChild: ChildLayoutHelper.layoutChild,
    );
    if (child != null) {
      final childParentData = child!.parentData! as BoxParentData;
      childParentData.offset = Alignment.center.alongOffset(
        size - child!.size as Offset,
      );
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) {
      return true;
    }
    final center = child!.size.center(.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, position) {
        assert(position == center);
        return child!.hitTest(result, position: center);
      },
    );
  }
}

/// Paint-bus-friendly shadow wrapper for [MonetButtonCore].
///
/// The old wrapper used `DecoratedBox(ShapeDecoration(shadows: ...))`, which
/// means every shadow colour change flows through Flutter's decoration/shadow
/// painting path as a fully coloured blur. During Monet paint-bus animation
/// that can visually lag/snap relative to text/icon mask tinting.
///
/// This render object follows the same model as `MonetRichText`: cache
/// the squircle shadow coverage as a white/alpha image,
/// then tint that cached mask at paint time with the current shadow colour.
/// Shadow geometry only depends on shape/size/DPR/blur/spread/offset, so
/// normal colour ticks repaint cheaply without rebuilding the blurred mask.
class _TintedAestheticShadow extends SingleChildRenderObjectWidget {
  final Color shadowColor;
  final OutlinedBorder shape;

  /// Paint-bus tick source; when set with [shadowColorResolver], shadow tint
  /// follows the bus with repaints only (no widget rebuilds).
  final Listenable? repaint;
  final Color Function()? shadowColorResolver;

  const _TintedAestheticShadow({
    required this.shadowColor,
    required this.shape,
    this.repaint,
    this.shadowColorResolver,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTintedAestheticShadow(
          cachedShadowColor: shadowColor,
          cachedDevicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          shape: shape,
        )
        ..shadowColorResolver = shadowColorResolver
        ..repaint = repaint;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTintedAestheticShadow renderObject,
  ) {
    renderObject
      ..shadowColor = shadowColor
      ..shape = shape
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..shadowColorResolver = shadowColorResolver
      ..repaint = repaint;
  }
}

class _RenderTintedAestheticShadow extends RenderProxyBox {
  _RenderTintedAestheticShadow({
    required this.cachedShadowColor,
    required this.cachedDevicePixelRatio,
    required this._shape,
  });

  Color cachedShadowColor;
  double cachedDevicePixelRatio;
  OutlinedBorder _shape;
  Color Function()? shadowColorResolver;
  final Paint _maskPaint = Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = true;
  List<BoxShadow>? _maskShadowSource;
  List<BoxShadow>? _whiteMaskShadowCache;
  double? _maskShadowMargin;
  _AestheticShadowMaskKey? _maskKey;
  _AestheticShadowMask? _observedMask;
  _AestheticShadowMaskKey? _deniedKey;
  int? _deniedRevision;
  bool _evictionRepaintScheduled = false;

  void _observeMask(_AestheticShadowMask? mask) {
    if (identical(_observedMask, mask)) return;
    final previous = _observedMask;
    _observedMask = mask;
    if (mask != null) {
      mask
        ..addListener(_onMaskEvicted)
        ..acquire();
    }
    if (previous != null) {
      previous
        ..removeListener(_onMaskEvicted)
        ..releaseUse();
    }
  }

  void _onMaskEvicted() {
    _observeMask(null);
    _deniedKey = _maskKey;
    _deniedRevision = _buttonShadowImageBudget.availabilityRevision;
    // Like text masks, drop the retained display list's native reference too.
    // Budget eviction can occur inside another render object's paint.
    if (_evictionRepaintScheduled) return;
    _evictionRepaintScheduled = true;
    scheduleMicrotask(() {
      _evictionRepaintScheduled = false;
      if (attached) markNeedsPaint();
    });
  }

  Listenable? _repaint;
  set repaint(Listenable? value) {
    if (identical(_repaint, value)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    _observeMask(null);
    super.detach();
  }

  @override
  void dispose() {
    _observeMask(null);
    super.dispose();
  }

  Color get _currentShadowColor =>
      shadowColorResolver?.call() ?? cachedShadowColor;

  OutlinedBorder get shape => _shape;
  set shape(OutlinedBorder value) {
    if (_shape == value) return;
    _shape = value;
    _maskKey = null;
    markNeedsPaint();
  }

  // ignore: match-getter-setter-field-names
  Color get shadowColor => cachedShadowColor;
  set shadowColor(Color value) {
    if (cachedShadowColor == value) return;
    // ignore: match-getter-setter-field-names
    cachedShadowColor = value;
    // Only tint changed; cached white/alpha mask remains valid.
    markNeedsPaint();
  }

  // ignore: match-getter-setter-field-names
  double get devicePixelRatio => cachedDevicePixelRatio;
  set devicePixelRatio(double value) {
    if (cachedDevicePixelRatio == value) return;
    // ignore: match-getter-setter-field-names
    cachedDevicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final tint = _currentShadowColor;
    if (tint != Colors.transparent && size.width > 0 && size.height > 0) {
      final dpr = cachedDevicePixelRatio;
      final mask = _ensureMask(dpr);
      if (mask != null) {
        _drawTintedMask(context.canvas, mask, offset + mask.offset, dpr, tint);
      } else {
        // No full-size snapshot/saveLayer when the byte budget rejects a mask.
        // Keep the original shape/shadows and live tint on the direct path.
        _paintShadowDecoration(
          context.canvas,
          shape: _shape,
          shadows: [
            for (final shadow in _whiteMaskShadowCache ?? const <BoxShadow>[])
              shadow.copyWith(
                color: tint.withValues(alpha: tint.a * shadow.color.a),
              ),
          ],
          offset: offset,
          childSize: size,
        );
      }
    }
    super.paint(context, offset);
  }

  _AestheticShadowMask? _ensureMask(double dpr) {
    final shadowSource = aestheticShadows(Colors.white, includeOutline: false);
    if (!identical(shadowSource, _maskShadowSource)) {
      final whiteShadows = _whiteMaskShadows(shadowSource);
      _maskShadowSource = shadowSource;
      _whiteMaskShadowCache = whiteShadows;
      _maskShadowMargin = _shadowMargin(whiteShadows);
      _maskKey = null;
    }
    final shadows = _whiteMaskShadowCache!;
    if (shadows.isEmpty) return null;

    var key = _maskKey;
    if (key == null ||
        !identical(key.shadowSource, shadowSource) ||
        key.childWidth != size.width ||
        key.childHeight != size.height ||
        key.dpr != dpr ||
        key.shape != _shape) {
      final margin = _maskShadowMargin!;
      final logicalSize = Size(
        size.width + margin * 2,
        size.height + margin * 2,
      );
      key = _AestheticShadowMaskKey(
        width: math.max(1, (logicalSize.width * dpr).ceil()),
        height: math.max(1, (logicalSize.height * dpr).ceil()),
        logicalWidth: logicalSize.width,
        logicalHeight: logicalSize.height,
        childWidth: size.width,
        childHeight: size.height,
        dpr: dpr,
        margin: margin,
        shadowSource: shadowSource,
        shape: _shape,
      );
      _maskKey = key;
    }
    final cached = _aestheticShadowMaskCache[key];
    if (cached != null) {
      _buttonShadowImageBudget.touch(cached.budgetKey);
      _observeMask(cached);
      return cached;
    }
    _observeMask(null);
    if (_deniedKey == key &&
        _deniedRevision == _buttonShadowImageBudget.availabilityRevision) {
      return null;
    }
    final mask = _tryRasterizeShadowMask(key, shadows);
    if (mask == null) {
      _deniedKey = key;
      _deniedRevision = _buttonShadowImageBudget.availabilityRevision;
      return null;
    }
    _deniedKey = null;
    _deniedRevision = null;
    _observeMask(mask);
    return mask;
  }

  void _drawTintedMask(
    Canvas canvas,
    _AestheticShadowMask mask,
    Offset offset,
    double dpr,
    Color tint,
  ) {
    final width = mask.logicalSize.width * dpr;
    final height = mask.logicalSize.height * dpr;
    _maskPaint.colorFilter = ui.ColorFilter.mode(tint, .srcIn);
    canvas.drawImageRect(
      mask.image,
      Rect.fromLTWH(0, 0, width, height),
      offset & mask.logicalSize,
      _maskPaint,
    );
    _maskPaint.colorFilter = null;
  }

  static List<BoxShadow> _whiteMaskShadows(List<BoxShadow> shadows) => [
    for (final shadow in shadows)
      BoxShadow(
        color: Color.from(alpha: shadow.color.a, red: 1, green: 1, blue: 1),
        offset: shadow.offset,
        blurRadius: shadow.blurRadius,
        spreadRadius: shadow.spreadRadius,
        blurStyle: shadow.blurStyle,
      ),
  ];

  static double _shadowMargin(List<BoxShadow> shadows) {
    var margin = 0.0;
    for (final shadow in shadows) {
      margin = math.max(
        margin,
        shadow.blurRadius +
            shadow.spreadRadius.abs() +
            shadow.offset.dx.abs() +
            shadow.offset.dy.abs() +
            2,
      );
    }
    return margin;
  }
}

// Reuse text-mask admission/accounting code, not its cache or ownership.
// Button shadows have their own entries and counters.
final _buttonShadowImageBudget = RasterMaskImageBudget(
  debugLabel: 'ButtonShadowImageBudget',
  maxBytes: RasterMaskImageCacheConfig.maxBytes,
  maxImageBytes: RasterMaskImageCacheConfig.maxImageBytes,
);

RasterMaskImageCacheStats get buttonShadowImageCacheStats =>
    _buttonShadowImageBudget.stats;

void clearButtonShadowImageCache() => _buttonShadowImageBudget.clear();

@visibleForTesting
void debugConfigureButtonShadowImageCache({
  required int maxBytes,
  required int maxImageBytes,
}) => _buttonShadowImageBudget.debugConfigure(
  maxBytes: maxBytes,
  maxImageBytes: maxImageBytes,
);

@visibleForTesting
void debugResetButtonShadowImageCache() =>
    _buttonShadowImageBudget.debugReset();

final _aestheticShadowMaskCache =
    <_AestheticShadowMaskKey, _AestheticShadowMask>{};

// Masks that no render object uses. A mask in use lives as long as its users.
// An unused mask stays here so that remounts and same-size rebuilds reuse it.
// The oldest unused masks are disposed when the pool exceeds its limits.
const _kIdleShadowMaskMaxCount = 64;
const _kIdleShadowMaskMaxBytes = 16 * 1024 * 1024;
final _idleShadowMasks = LinkedHashSet<_AestheticShadowMask>.identity();
var _idleShadowMaskBytes = 0;

void _trimIdleShadowMasks() {
  while (_idleShadowMasks.length > _kIdleShadowMaskMaxCount ||
      _idleShadowMaskBytes > _kIdleShadowMaskMaxBytes) {
    final oldest = _idleShadowMasks.first;
    _aestheticShadowMaskCache.remove(oldest.key);
    // Removes itself from the idle pool.
    oldest.dispose();
  }
}

@visibleForTesting
int get debugIdleButtonShadowMaskCount => _idleShadowMasks.length;

_AestheticShadowMask? _tryRasterizeShadowMask(
  _AestheticShadowMaskKey key,
  List<BoxShadow> shadows,
) {
  final budgetKey = Object();
  if (!_buttonShadowImageBudget.tryReserveAll([
    RasterMaskImageReservation(
      key: budgetKey,
      estimatedBytes: estimateRasterMaskImageBytes(key.width, key.height),
      // Do not capture a render object in this process-wide cache.
      evict: () => _aestheticShadowMaskCache.remove(key)?.dispose(),
    ),
  ])) {
    return null;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(key.dpr, key.dpr);
  ui.Picture? picture;
  try {
    _paintShadowDecoration(
      canvas,
      shape: key.shape,
      shadows: shadows,
      offset: Offset(key.margin, key.margin),
      childSize: Size(key.childWidth, key.childHeight),
    );
    picture = recorder.endRecording();
    final mask = _AestheticShadowMask(
      key: key,
      budgetKey: budgetKey,
      estimatedBytes: estimateRasterMaskImageBytes(key.width, key.height),
      image: picture.toImageSync(key.width, key.height),
      logicalSize: Size(key.logicalWidth, key.logicalHeight),
      offset: Offset(-key.margin, -key.margin),
    );
    _aestheticShadowMaskCache[key] = mask;
    return mask;
  } catch (_) {
    _buttonShadowImageBudget.release(budgetKey);
    rethrow;
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    picture?.dispose();
  }
}

void _paintShadowDecoration(
  Canvas canvas, {
  required OutlinedBorder shape,
  required List<BoxShadow> shadows,
  required Offset offset,
  required Size childSize,
}) {
  final painter = ShapeDecoration(
    shape: shape,
    shadows: shadows,
    // Flutter's ShapeDecoration requires a callback even without an image;
    // no image means this callback cannot actually be invoked.
    // ignore: no-empty-block
  ).createBoxPainter(() {});
  try {
    painter.paint(canvas, offset, ImageConfiguration(size: childSize));
  } finally {
    painter.dispose();
  }
}

class _AestheticShadowMask extends ChangeNotifier {
  _AestheticShadowMask({
    required this.key,
    required this.budgetKey,
    required this.estimatedBytes,
    required this.image,
    required this.logicalSize,
    required this.offset,
  });

  final _AestheticShadowMaskKey key;
  final Object budgetKey;
  final int estimatedBytes;
  final ui.Image image;
  final Size logicalSize;
  final Offset offset;
  int _users = 0;
  bool _disposed = false;

  void acquire() {
    assert(!_disposed);
    if (_users++ == 0 && _idleShadowMasks.remove(this)) {
      _idleShadowMaskBytes -= estimatedBytes;
    }
  }

  void releaseUse() {
    assert(_users > 0);
    _users--;
    // An evicted mask notifies its users, who then release it.
    if (_users > 0 || _disposed) return;
    _idleShadowMasks.add(this);
    _idleShadowMaskBytes += estimatedBytes;
    _trimIdleShadowMasks();
  }

  @override
  void dispose() {
    assert(!_disposed);
    _disposed = true;
    if (_idleShadowMasks.remove(this)) _idleShadowMaskBytes -= estimatedBytes;
    _buttonShadowImageBudget.release(budgetKey);
    image.dispose();
    notifyListeners();
    super.dispose();
  }
}

class _AestheticShadowMaskKey {
  _AestheticShadowMaskKey({
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.childWidth,
    required this.childHeight,
    required this.dpr,
    required this.margin,
    required this.shadowSource,
    required this.shape,
  }) : _hashCode = Object.hash(
         width,
         height,
         logicalWidth,
         logicalHeight,
         childWidth,
         childHeight,
         dpr,
         margin,
         identityHashCode(shadowSource),
         shape,
       );

  final int width;
  final int height;
  final double logicalWidth;
  final double logicalHeight;
  final double childWidth;
  final double childHeight;
  final double dpr;
  final double margin;
  final List<BoxShadow> shadowSource;
  final OutlinedBorder shape;
  final int _hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AestheticShadowMaskKey &&
          width == other.width &&
          height == other.height &&
          logicalWidth == other.logicalWidth &&
          logicalHeight == other.logicalHeight &&
          childWidth == other.childWidth &&
          childHeight == other.childHeight &&
          dpr == other.dpr &&
          margin == other.margin &&
          shape == other.shape &&
          identical(shadowSource, other.shadowSource);

  @override
  int get hashCode => _hashCode;
}
