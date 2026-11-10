import 'dart:math' as math;

import 'package:loggy/loggy.dart';
import 'package:monet_ui/flux/flux.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/animated_color_hook.dart';
import 'package:monet_ui/widgets/menu/menu_controller.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/menu/monet_menu_overlay.dart';
import 'package:monet_ui/widgets/monet_fallback_shapes.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/stateful_color_resolver.dart';
import 'package:pixel_snap_fork/material.dart';

typedef MenuButtonItemBuilder = List<MenuEntry> Function(BuildContext context);

class MenuButton extends StatefulWidget {
  static const kElevation = 16.0;

  /// Shifts every menu from its anchor. Apps set this for screen recordings
  /// whose capture area is offset from the window.
  static Offset debugAnchorOffset = Offset.zero;
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? shadowColor;
  final MenuButtonItemBuilder? itemsBuilder;
  final List<MenuEntry> items;
  final double? elevation;
  final Function()? onOpened;

  /// Overrides the primary-button action without changing secondary click.
  /// When null, primary and secondary clicks both open the menu.
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  /// Opt-in interaction shape for compound content, independent of the popup.
  /// Other callers retain the historical circular surface.
  final OutlinedBorder surfaceShape;

  /// Fit the painted surface to the child while retaining the surrounding
  /// minimum/parent-constrained hit target. Useful in fixed-height footers.
  final bool shrinkWrapSurface;
  final MenuButtonController? controller;
  final WidgetStatesController? statesController;

  /// Default: false. If true, the menu button shrinks to fit its child.
  /// If false, the lightweight interaction surface expands to the same
  /// compact touch target previously supplied by [IconButton].
  final bool naturalSize;

  /// Only applies when [naturalSize] is true.
  /// If true, shows a circular background behind the child that changes color
  /// on hover/pressed, similar to [ExpandArrow].
  final bool showCircularBackground;

  final BoxConstraints? constraints;

  /// When set, the button and popup use this palette instead of
  /// [MonetTheme.of(context).primary]. The popup entries inherit it via a
  /// [MonetTheme] override created lazily inside the overlay controller's
  /// [show] method, so there is zero widget-construction cost at build time.
  final Palette? palette;

  /// Optional label for debugging. Shown in error logs to identify which
  /// MenuButton is having issues.
  final String? debugLabel;

  /// Optional tooltip shown on hover/long-press for either button size.
  final String? tooltip;
  final String? semanticLabel;
  final String? semanticHint;

  /// Register controller callbacks without building a visible/clickable button.
  /// Used by hidden context anchors that are opened externally.
  final bool anchorOnly;

  const MenuButton({
    super.key,
    required this.items,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.shadowColor,
    this.naturalSize = false,
    this.showCircularBackground = false,
    this.elevation = kElevation,
    this.itemsBuilder,
    this.constraints,
    this.onOpened,
    this.onPressed,
    this.style,
    this.surfaceShape = const CircleBorder(),
    this.shrinkWrapSurface = false,
    this.controller,
    this.statesController,
    this.palette,
    this.debugLabel,
    this.tooltip,
    this.semanticLabel,
    this.semanticHint,
    this.anchorOnly = false,
  });

  static ShapeBorder shapeBorder(BuildContext context, Color? borderColor) {
    // Double width because clipping is applied to the center of the border,
    // and clipping is required to avoid shape of menu being over-width.
    return MonetTheme.shapesOf(context).border(
      borderRadius: BorderRadiusGeometry.circular(kOverlayRadius),
      side: BorderSide(color: borderColor ?? Colors.transparent, width: 1),
    );
  }

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> with UiLoggy {
  late final MonetMenuOverlayController _overlayController =
      MonetMenuOverlayController();
  late final FluxCurve _entryCurve = FluxCurve(spring: FluxSpring.snappy);
  WidgetStatesController? _ownStatesController;
  BuildContext? _anchorContext;
  bool _overlayUpdateScheduled = false;

  WidgetStatesController get _effectiveStatesController =>
      widget.statesController ?? (_ownStatesController ??= .new());

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant MenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.dispose();
      _attachController(widget.controller);
    }
  }

  void _attachController(MenuButtonController? controller) {
    controller?.setShowCallback(_openFromController);
    controller?.setShowFromPositionCallback(
      (position) => _openFromController(pointerPosition: position),
    );
  }

  @override
  void dispose() {
    widget.controller?.dispose();
    _ownStatesController?.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  MonetMenuAppearance _resolveAppearance(BuildContext context) {
    final primaryTheme = widget.palette ?? MonetTheme.of(context).primary;
    final resolvedBackground =
        widget.backgroundColor ?? primaryTheme.background;
    return MonetMenuAppearance(
      backgroundColor: resolvedBackground,
      elevation: widget.elevation ?? MenuButton.kElevation,
      shadowColor: widget.shadowColor ?? primaryTheme.color,
      surfaceTintColor: resolvedBackground,
      clipBehavior: .antiAlias,
      constraints:
          widget.constraints ??
          const BoxConstraints(maxWidth: ScreenBreakpoints.screenSmallWidth),
      shape: MenuButton.shapeBorder(
        context,
        widget.borderColor ?? primaryTheme.backgroundBorder,
      ),
      entryCurve: _entryCurve,
      entryDuration: _entryCurve.duration,
    );
  }

  List<MenuEntry> _resolveItems(BuildContext context) =>
      widget.itemsBuilder?.call(context) ?? widget.items;

  void _scheduleOpenOverlayUpdate() {
    if (!_overlayController.isShowing || _overlayUpdateScheduled) return;
    _overlayUpdateScheduled = true;
    Future.microtask(() {
      _overlayUpdateScheduled = false;
      if (!mounted) {
        loggy.warning('Cannot update menu - context not available');
        return;
      }
      _overlayController.updateItems(_resolveItems(context));
      _overlayController.updateAppearance(_resolveAppearance(context));
    });
  }

  void _openFromController({Offset? pointerPosition}) {
    final anchorContext = _anchorContext;
    if (anchorContext == null || !anchorContext.mounted) {
      loggy.warning('Cannot open menu - controller anchor not available');
      return;
    }
    _openMenu(anchorContext, pointerPosition: pointerPosition);
  }

  void _openMenu(BuildContext anchorContext, {Offset? pointerPosition}) {
    widget.onOpened?.call();
    final currentItems = _resolveItems(anchorContext);
    if (currentItems.isEmpty) {
      if (widget.onOpened == null) {
        loggy.error(
          'no items to show and no onOpened callback. What is the menu being used for, then?\n${StackTrace.current}',
        );
      }
      return;
    }

    Offset? adjustedPointer = pointerPosition;
    RenderBox? anchorBox;
    Rect? anchorRect;
    if (adjustedPointer != null) {
      adjustedPointer = adjustedPointer + MenuButton.debugAnchorOffset;
    } else {
      final renderObject = anchorContext.findRenderObject();
      if (renderObject is! RenderBox) {
        loggy.error('MenuButton: renderObject is not a RenderBox');
        return;
      }
      anchorBox = renderObject;
      final origin = renderObject.localToGlobal(.zero);
      anchorRect = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        renderObject.size.width,
        renderObject.size.height,
      );
      anchorRect = anchorRect.shift(MenuButton.debugAnchorOffset);
    }

    final isPointer = adjustedPointer != null;
    _overlayController.show(
      context: anchorContext,
      items: currentItems,
      geometry: isPointer
          ? MonetMenuGeometry.pointer(position: adjustedPointer)
          : MonetMenuGeometry.anchor(anchorRect: anchorRect!),
      appearance: _resolveAppearance(anchorContext),
      anchorBox: isPointer ? null : anchorBox,
      palette: widget.palette,
    );
  }

  Widget _withTooltip(Widget button) => widget.tooltip == null
      ? button
      : Tooltip(message: widget.tooltip!, child: button);

  void _handlePrimaryTap(BuildContext anchorContext) {
    final onPressed = widget.onPressed;
    if (onPressed != null) {
      onPressed();
      return;
    }
    _openMenu(anchorContext);
  }

  Widget _gestureSurface(
    BuildContext anchorContext,
    Widget child,
    WidgetStatesController statesController,
  ) {
    return FocusableActionDetector(
      onShowFocusHighlight: (value) => statesController.update(.focused, value),
      shortcuts: const {
        SingleActivator(.enter): ActivateIntent(),
        SingleActivator(.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          // ignore: function-always-returns-null
          onInvoke: (_) {
            _handlePrimaryTap(anchorContext);
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: true,
        label: widget.semanticLabel ?? widget.tooltip,
        hint: widget.semanticHint,
        onTap: () => _handlePrimaryTap(anchorContext),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => statesController.update(.hovered, true),
          onExit: (_) => statesController.update(.hovered, false),
          child: GestureDetector(
            behavior: .opaque,
            excludeFromSemantics: true,
            onTapDown: (_) => statesController.update(.pressed, true),
            onTapUp: (_) => statesController.update(.pressed, false),
            onTapCancel: () => statesController.update(.pressed, false),
            onSecondaryTap: () => _openMenu(anchorContext),
            onTap: () => _handlePrimaryTap(anchorContext),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext anchorContext) {
    final statesController = _effectiveStatesController;
    final monetTheme = widget.palette == null || widget.showCircularBackground
        ? MonetTheme.of(context)
        : null;
    final palette = widget.palette ?? monetTheme!.primary;
    final style =
        widget.style ?? (widget.naturalSize ? null : iconButtonStyle(palette));
    final iconColorByState = widgetPropertyByState(
      normal: () => palette.fill,
      hover: () => palette.backgroundHoveredFill,
      splash: () => palette.backgroundSplashedFill,
    );
    final backgroundColorByState = widgetPropertyByState(
      normal: () => Colors.transparent,
      hover: () => palette.backgroundHovered,
      splash: () => palette.backgroundSplashed,
    );

    Color resolveIconColor(Set<WidgetState> states) =>
        style?.iconColor?.resolve(states) ??
        style?.foregroundColor?.resolve(states) ??
        iconColorByState.resolve(states);

    Color resolveBackground(Set<WidgetState> states) =>
        style?.backgroundColor?.resolve(
          states.contains(WidgetState.focused)
              ? {...states, WidgetState.hovered}
              : states,
        ) ??
        backgroundColorByState.resolve(
          states.contains(WidgetState.focused)
              ? {...states, WidgetState.hovered}
              : states,
        );

    Widget applyCompactTouchTarget(Widget child, Set<WidgetState> states) {
      if (widget.naturalSize) return child;
      final visualDensity = style!.visualDensity ?? .standard;
      final adjustment = visualDensity.baseSizeAdjustment;
      final minimumSize =
          style.minimumSize?.resolve(states) ?? const Size.square(40);
      final padding = style.padding?.resolve(states) ?? EdgeInsets.zero;
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.max(0, minimumSize.width + adjustment.dx),
          minHeight: math.max(0, minimumSize.height + adjustment.dy),
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    if (widget.showCircularBackground) {
      final safeColors = Palette.from(
        palette.fill,
        backgroundTone: monetTheme!.backgroundTone,
        contrast: monetTheme.contrast,
      );
      Color foregroundColor() =>
          iconColorByState.resolve(statesController.value);
      Color backgroundColor() => resolveBackgroundColor(
        safeColors,
        statesController.value.contains(WidgetState.focused)
            ? {...statesController.value, WidgetState.hovered}
            : statesController.value,
      );
      return _withTooltip(
        _gestureSurface(
          anchorContext,
          PaintDrivenShapeFill(
            color: backgroundColor(),
            repaint: statesController,
            paintColor: backgroundColor,
            shape: const CircleBorder(),
            child: RepaintBoundary(
              child: PaintDrivenColorScope(
                color: foregroundColor(),
                repaint: statesController,
                paintColor: foregroundColor,
                child: widget.child,
              ),
            ),
          ),
          statesController,
        ),
      );
    }

    return ListenableBuilder(
      listenable: statesController,
      builder: (context, _) {
        final states = statesController.value;
        final child = IconTheme.merge(
          data: IconThemeData(color: resolveIconColor(states)),
          child: widget.child,
        );
        final surface = DecoratedBox(
          decoration: ShapeDecoration(
            shape: widget.borderColor != null
                ? widget.surfaceShape.copyWith(
                    side: BorderSide(color: widget.borderColor!, width: 2),
                  )
                : widget.surfaceShape,
            color: resolveBackground(states),
          ),
          child: widget.shrinkWrapSurface
              ? child
              : applyCompactTouchTarget(child, states),
        );
        final button = _gestureSurface(
          anchorContext,
          widget.shrinkWrapSurface
              ? applyCompactTouchTarget(
                  Center(widthFactor: 1, heightFactor: 1, child: surface),
                  states,
                )
              : surface,
          statesController,
        );
        return _withTooltip(button);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOpenOverlayUpdate();
    if (widget.anchorOnly) {
      return SizedBox(
        width: 0,
        height: 0,
        child: Builder(
          builder: (anchorContext) {
            _anchorContext = anchorContext;
            return const SizedBox.shrink();
          },
        ),
      );
    }
    return Builder(
      builder: (anchorContext) {
        _anchorContext = anchorContext;
        return _buildButton(anchorContext);
      },
    );
  }
}
