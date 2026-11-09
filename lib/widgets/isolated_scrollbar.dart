import 'dart:async';

import 'package:flutter/gestures.dart';

import 'package:material_ui/material_ui.dart';

/// Desktop vertical scrollbar with the content and thumb in sibling layers.
///
/// RawScrollbar puts the content *inside* its animated paint boundary. Retaining
/// content pictures there still detaches/attaches their descendant layers on
/// each thumb fade/hover frame. Here only the small overlay boundary repaints.
/// Scrollable still owns content gestures, physics, notifications and semantics.
/// Flutter's ScrollbarPainter supplies geometry, clipping and overscroll visuals.
class IsolatedScrollbar extends StatefulWidget {
  const IsolatedScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<IsolatedScrollbar> createState() => _IsolatedScrollbarState();
}

class _IsolatedScrollbarState extends State<IsolatedScrollbar>
    with TickerProviderStateMixin {
  final _paintKey = GlobalKey();
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final _opacity = CurvedAnimation(
    parent: _fade,
    curve: Curves.fastOutSlowIn,
  );
  late final _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(_updateStyle);
  late final _painter = ScrollbarPainter(
    color: Colors.transparent,
    textDirection: .ltr,
    thickness: 7,
    fadeoutOpacityAnimation: _opacity,
  );
  late ScrollbarThemeData _theme;
  late ColorScheme _colors;
  Timer? _fadeTimer;
  bool _hovered = false;
  bool _dragging = false;
  Drag? _drag;
  ScrollHoldController? _hold;
  double _dragStartY = 0;
  double _dragThumbStart = 0;
  double _lastDragY = 0;

  Set<WidgetState> get _states => {
    if (_hovered) WidgetState.hovered,
    if (_dragging) WidgetState.dragged,
  };
  bool get _alwaysVisible => _theme.thumbVisibility?.resolve(_states) ?? false;
  bool get _interactive => _theme.interactive ?? true;
  ScrollPosition? get _position => widget.controller.positions.length == 1
      ? widget.controller.position
      : null;
  RenderBox? get _paintBox =>
      _paintKey.currentContext?.findRenderObject() as RenderBox?;
  Offset _local(Offset global) => _paintBox!.globalToLocal(global);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = ScrollbarTheme.of(context);
    _colors = Theme.of(context).colorScheme;
    _updateStyle();
    if (_alwaysVisible) {
      _show();
    } else {
      _scheduleFade();
    }
  }

  @override
  void didUpdateWidget(IsolatedScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _cancelDrag();
      _fadeTimer?.cancel();
      _fade.value = 0;
      if (_alwaysVisible) _show();
      // A replaced viewport sends its own metrics after layout. A controller
      // swap on an existing Scrollable can retain the same ScrollPosition.
    }
  }

  void _updateStyle() {
    final states = _states;
    final dark = _colors.brightness == .dark;
    final showTrack = _theme.trackVisibility?.resolve(states) ?? false;
    final hoverColor =
        _theme.thumbColor?.resolve({.hovered}) ??
        _colors.onSurface.withValues(alpha: dark ? 0.65 : 0.5);
    final Color thumbColor;
    if (_dragging) {
      thumbColor =
          _theme.thumbColor?.resolve(states) ??
          _colors.onSurface.withValues(alpha: dark ? 0.75 : 0.6);
    } else if (showTrack) {
      thumbColor = _theme.thumbColor?.resolve(states) ?? hoverColor;
    } else {
      final idleColor =
          _theme.thumbColor?.resolve(const {}) ??
          _colors.onSurface.withValues(alpha: dark ? 0.3 : 0.1);
      thumbColor = Color.lerp(idleColor, hoverColor, _hover.value)!;
    }
    _painter
      ..color = thumbColor
      ..trackColor = _alwaysVisible && showTrack
          ? (_theme.trackColor?.resolve(states) ??
                _colors.onSurface.withValues(alpha: dark ? 0.05 : 0.03))
          : Colors.transparent
      ..trackBorderColor = _alwaysVisible && showTrack
          ? (_theme.trackBorderColor?.resolve(states) ??
                _colors.onSurface.withValues(alpha: dark ? 0.25 : 0.1))
          : Colors.transparent
      ..thickness =
          _theme.thickness?.resolve(states) ?? (_hovered && showTrack ? 12 : 8)
      ..radius = _theme.radius ?? const Radius.circular(8)
      ..crossAxisMargin = _theme.crossAxisMargin ?? 2
      ..mainAxisMargin = _theme.mainAxisMargin ?? 0
      ..minLength = _theme.minThumbLength ?? 48
      ..textDirection = Directionality.of(context)
      ..padding = MediaQuery.paddingOf(context)
      ..ignorePointer = !_interactive;
  }

  void _show() {
    _fadeTimer?.cancel();
    if (!_fade.isForwardOrCompleted) _fade.forward();
  }

  void _scheduleFade() {
    _fadeTimer?.cancel();
    if (!_alwaysVisible && !_hovered && !_dragging) {
      _fadeTimer = Timer(const Duration(milliseconds: 600), _fade.reverse);
    }
  }

  // Observe without consuming: ancestor notification listeners still run once.
  // ignore: function-always-returns-same-value
  bool _metrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != .vertical) {
      return false;
    }
    _painter.update(notification.metrics, notification.metrics.axisDirection);
    if (_alwaysVisible) _show();
    return false;
  }

  // ignore: function-always-returns-same-value
  bool _scroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != .vertical) {
      return false;
    }
    _painter.update(notification.metrics, notification.metrics.axisDirection);
    if (notification.metrics.maxScrollExtent <=
        notification.metrics.minScrollExtent) {
      _fade.reverse();
    } else if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _show();
    } else if (notification is ScrollEndNotification) {
      _scheduleFade();
    }
    return false;
  }

  bool _thumbEvent(PointerEvent event) =>
      _paintBox != null &&
      _interactive &&
      _position != null &&
      _painter.hitTestOnlyThumbInteractive(_local(event.position), event.kind);

  bool _trackEvent(PointerEvent event) =>
      _paintBox != null &&
      _interactive &&
      _position != null &&
      _painter.hitTestInteractive(_local(event.position), event.kind) &&
      !_thumbEvent(event);

  void _handleHover(PointerHoverEvent event) {
    final hovered =
        _interactive &&
        _painter.hitTestInteractive(
          _local(event.position),
          event.kind,
          forHover: true,
        );
    if (hovered) _show();
    if (_hovered == hovered) return;
    _hovered = hovered;
    _updateStyle();
    if (hovered) {
      _hover.forward();
    } else {
      _hover.reverse();
      _scheduleFade();
    }
  }

  void _exit(PointerExitEvent event) {
    _hovered = false;
    _hover.reverse();
    _updateStyle();
    _scheduleFade();
  }

  void _dragDown(DragDownDetails details) {
    _show();
    _hold = _position?.hold(() => _hold = null);
  }

  void _dragStart(DragStartDetails details) {
    final position = _position;
    if (position == null) return;
    _dragging = true;
    _updateStyle();
    _dragStartY = _local(details.globalPosition).dy;
    _lastDragY = _dragStartY;
    _dragThumbStart = _painter.getThumbScrollOffset();
    _drag = position.drag(details, () => _drag = null);
  }

  void _dragUpdate(DragUpdateDetails details) {
    final position = _position;
    // ScrollPhysics explicitly takes the ScrollPosition whose physics it is.
    if (position == null ||
        _drag == null ||
        // ignore: avoid-passing-self-as-argument
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final local = _local(details.globalPosition);
    final sign = axisDirectionIsReversed(position.axisDirection) ? -1.0 : 1.0;
    final distance = (local.dy - _dragStartY) * sign;
    var target = _painter.getTrackToScroll(_dragThumbStart + distance);
    if (distance > 0 && target < position.pixels ||
        distance < 0 && target > position.pixels) {
      target =
          position.pixels +
          _painter.getTrackToScroll((local.dy - _lastDragY) * sign);
    }
    if (!target.isFinite) return;
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    final delta = (position.pixels - target) * sign;
    _drag!.update(
      DragUpdateDetails(
        delta: Offset(0, delta),
        primaryDelta: delta,
        globalPosition: details.globalPosition,
        localPosition: local,
      ),
    );
    _lastDragY = local.dy;
  }

  void _dragEnd(DragEndDetails details) {
    // Desktop thumb releases do not fling; content/trackpad scrolling still do.
    _drag?.end(
      DragEndDetails(
        primaryVelocity: 0,
        globalPosition: details.globalPosition,
      ),
    );
    _cancelDrag();
    _scheduleFade();
  }

  void _cancelDrag() {
    _drag?.cancel();
    _drag = null;
    _hold?.cancel();
    _hold = null;
    _dragging = false;
    _updateStyle();
    _scheduleFade();
  }

  void _trackTap(TapDownDetails details) {
    final position = _position;
    if (position == null ||
        // ignore: avoid-passing-self-as-argument
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final pixelsPerTrackPixel = _painter.getTrackToScroll(1);
    if (!pixelsPerTrackPixel.isFinite || pixelsPerTrackPixel <= 0) return;
    final travel =
        (position.maxScrollExtent - position.minScrollExtent) /
        pixelsPerTrackPixel;
    final thumbOffset =
        (position.pixels - position.minScrollExtent) / pixelsPerTrackPixel;
    final thumbStart =
        _painter.padding.resolve(Directionality.of(context)).top +
        _painter.mainAxisMargin +
        (axisDirectionIsReversed(position.axisDirection)
            ? travel - thumbOffset
            : thumbOffset);
    final direction = _local(details.globalPosition).dy > thumbStart
        ? AxisDirection.down
        : AxisDirection.up;
    final state = Scrollable.maybeOf(position.context.notificationContext!);
    if (state == null) return;
    final increment = ScrollAction.getDirectionalIncrement(
      state,
      ScrollIntent(direction: direction, type: .page),
    );
    position.moveTo(
      position.pixels + increment,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _drag?.cancel();
    _hold?.cancel();
    _painter.dispose();
    _hover.dispose();
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollMetricsNotification>(
    onNotification: _metrics,
    child: NotificationListener<ScrollNotification>(
      onNotification: _scroll,
      child: Stack(
        fit: .passthrough,
        children: [
          RepaintBoundary(child: widget.child),
          Positioned.fill(
            child: RepaintBoundary(
              child: RawGestureDetector(
                behavior: .translucent,
                excludeFromSemantics: true,
                gestures: {
                  _ThumbDrag: GestureRecognizerFactoryWithHandlers<_ThumbDrag>(
                    // Owned and disposed by RawGestureDetector.
                    // ignore: avoid-undisposed-instances
                    () => _ThumbDrag(_thumbEvent),
                    (recognizer) => recognizer
                      // Match RawScrollbar: mouse thumb motion must win the
                      // arena immediately and include the first movement.
                      ..gestureSettings = const DeviceGestureSettings(
                        touchSlop: 0,
                      )
                      ..dragStartBehavior = .down
                      ..onDown = _dragDown
                      ..onStart = _dragStart
                      ..onUpdate = _dragUpdate
                      ..onEnd = _dragEnd
                      ..onCancel = _cancelDrag,
                  ),
                  _TrackTap: GestureRecognizerFactoryWithHandlers<_TrackTap>(
                    // Owned and disposed by RawGestureDetector.
                    // ignore: avoid-undisposed-instances
                    () => _TrackTap(_trackEvent),
                    (recognizer) => recognizer..onTapDown = _trackTap,
                  ),
                },
                child: MouseRegion(
                  opaque: false,
                  hitTestBehavior: .translucent,
                  onHover: _handleHover,
                  onExit: _exit,
                  child: CustomPaint(
                    key: _paintKey,
                    foregroundPainter: _painter,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ThumbDrag extends VerticalDragGestureRecognizer {
  _ThumbDrag(this.accepts);
  final bool Function(PointerEvent event) accepts;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      accepts(event) && super.isPointerAllowed(event);

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;
}

class _TrackTap extends TapGestureRecognizer {
  _TrackTap(this.accepts);
  final bool Function(PointerEvent event) accepts;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      accepts(event) && super.isPointerAllowed(event);
}
