import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:loggy/loggy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/third_party/flutter/single_child_scroll_view_2.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:monet_ui/widgets/monet_scrollbar.dart';
import 'package:monet_ui/widgets/padding.dart';

/// Margin used to keep menus detached from screen edges slightly for aesthetics
/// and to make room for shadows.
const double _kMenuScreenMargin = 8.0;

/// Controller that manages a custom overlay-based popup menu. Widgets like
/// [MenuButton] and [MonetDropdownButton] use this to display menus without
/// relying on Flutter's [PopupMenuRoute].
class MonetMenuOverlayController with UiLoggy {
  /// Carries app scopes, such as a Riverpod container, into menu overlays.
  ///
  /// Called with the anchor's context when a menu opens. The returned
  /// function wraps the overlay's content. Inherited themes are carried
  /// automatically.
  static Widget Function(Widget child)? Function(BuildContext anchorContext)?
  overlayScopeFor;

  static const kDimissOverlayKey = Key('MonetMenuOverlay_DismissArea');
  @visibleForTesting
  static const kMenuBodyKey = Key('MonetMenuOverlay_Body');

  MonetMenuOverlayController()
    : _itemsListenable = ValueNotifier<List<MenuEntry>>(<MenuEntry>[]),
      _geometryListenable = ValueNotifier<MonetMenuGeometry?>(null),
      _appearanceListenable = ValueNotifier<MonetMenuAppearance?>(null),
      _contentWidthListenable = ValueNotifier<double?>(null),
      _isContentMeasuredListenable = ValueNotifier(false);

  /// Minimum width to ensure menu items are tappable on touch devices.
  static const double _kDefaultMinWidth = MonetThemeData.touchSize * 2;

  // Listenables allow the overlay to rebuild only when specific values change,
  // avoiding full rebuilds when only one property updates.
  final ValueNotifier<List<MenuEntry>> _itemsListenable;
  final ValueNotifier<MonetMenuGeometry?> _geometryListenable;
  final ValueNotifier<MonetMenuAppearance?> _appearanceListenable;
  final ValueNotifier<double?> _contentWidthListenable;
  final ValueNotifier<bool> _isContentMeasuredListenable;

  /// Tracks the minimum width the menu content should have, based on anchor
  /// width or constraints. Updated each time [show] is called.
  double _minContentWidth = _kDefaultMinWidth;

  /// Reference to the anchor widget's RenderBox for tracking position changes.
  /// Used to update menu position when the anchor moves (e.g., during scroll).
  RenderBox? _anchorBox;

  /// Guards against scheduling multiple postFrameCallbacks for anchor tracking.
  bool _isAnchorTrackingScheduled = false;

  // ignore: dispose-class-fields
  OverlayEntry? _overlayEntry;
  bool _isClosing = false;
  bool _isDisposedCalled = false;

  /// Whether the overlay is currently visible.
  bool get isShowing => _overlayEntry != null;

  ValueListenable<List<MenuEntry>> get itemsListenable => _itemsListenable;
  ValueListenable<MonetMenuGeometry?> get geometryListenable =>
      _geometryListenable;
  ValueListenable<MonetMenuAppearance?> get appearanceListenable =>
      _appearanceListenable;
  ValueListenable<double?> get contentWidthListenable =>
      _contentWidthListenable;
  ValueListenable<bool> get isContentMeasuredListenable =>
      _isContentMeasuredListenable;

  /// Show the menu overlay using the provided [items], [geometry], and
  /// [appearance].
  ///
  /// When [palette] is provided the overlay content is wrapped in a
  /// [MonetTheme] whose primary palette is replaced with [palette]. This
  /// lets callers render the entire popup (entries, shadows, etc.) in a
  /// different palette without constructing a theme widget up-front.
  void show({
    required BuildContext context,
    required List<MenuEntry> items,
    required MonetMenuGeometry geometry,
    required MonetMenuAppearance appearance,
    RenderBox? anchorBox,
    Palette? palette,
  }) {
    if (items.isEmpty) {
      // Defensive guard against developer error: showing an empty menu would
      // flash an empty overlay and is almost certainly a bug in the caller
      // (e.g. building items from a list that is still loading). We log and
      // return silently rather than surfacing user-facing feedback because
      // "no items" mid-interaction is not a meaningful message to end users;
      // the correct fix is at the call site.
      loggy.warning('MonetMenuOverlayController.show called with no items');
      return;
    }

    _itemsListenable.value = List<MenuEntry>.unmodifiable(items);
    _geometryListenable.value = geometry;
    _appearanceListenable.value = appearance;
    _contentWidthListenable.value = null;
    _isContentMeasuredListenable.value = false;
    _minContentWidth = _computeBaselineWidth(geometry, appearance);
    _anchorBox = anchorBox;
    _ensureAnchorTracking();

    if (_overlayEntry == null) {
      final wrapInScope = overlayScopeFor?.call(context);
      final overlayState = Overlay.of(context, rootOverlay: true);

      // Build the palette-override theme lazily — only when the menu is
      // actually shown, so there is zero cost at widget-build time.
      final MonetThemeData? paletteTheme;
      if (palette != null) {
        paletteTheme = MonetTheme.of(context).monetThemeData
            .copyWith(primary: palette);
      } else {
        paletteTheme = null;
      }

      _overlayEntry = OverlayEntry(
        builder: (overlayContext) {
          Widget overlayContent = _MonetMenuOverlay(controller: this);
          // Place our override *inside* captureAll so it is the innermost
          // MonetTheme and wins over the captured ambient one.
          if (paletteTheme != null) {
            overlayContent = MonetTheme(
              monetThemeData: paletteTheme,
              child: overlayContent,
            );
          }
          final overlayChild = InheritedTheme.captureAll(
            context,
            overlayContent,
          );
          return TickerMode(
            // The popup is rendered in an Overlay/Navigator island. Flutter's
            // route OverlayEntries toggle their own TickerMode while they are
            // being built. State management that pauses on TickerMode (for
            // example Riverpod Consumers) can then try to rebuild during
            // that build. Keep the menu active so those transient changes do
            // not reach menu items.
            enabled: true,
            child: wrapInScope == null
                ? overlayChild
                : wrapInScope(overlayChild),
          );
        },
      );
      overlayState.insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  /// Update the currently displayed items when the menu is already open.
  void updateItems(List<MenuEntry> items) {
    if (!isShowing) {
      return;
    }
    _itemsListenable.value = List<MenuEntry>.unmodifiable(items);
  }

  /// Update the menu appearance while it is already open.
  void updateAppearance(MonetMenuAppearance appearance) {
    if (!isShowing) {
      return;
    }
    _appearanceListenable.value = appearance;
    _overlayEntry?.markNeedsBuild();
  }

  /// Hide the menu overlay if it is visible.
  void hide() {
    final overlayEntry = _overlayEntry;
    if (overlayEntry == null || _isClosing) {
      return;
    }
    _isClosing = true;
    try {
      overlayEntry.remove();
      overlayEntry.dispose();
    } finally {
      _overlayEntry = null;
      _isClosing = false;
      _minContentWidth = _kDefaultMinWidth;
      _anchorBox = null;
    }
  }

  /// Dispose of the controller and any resources it holds.
  void dispose() {
    _isDisposedCalled = true;
    hide();
    _itemsListenable.dispose();
    _geometryListenable.dispose();
    _appearanceListenable.dispose();
    _contentWidthListenable.dispose();
    _isContentMeasuredListenable.dispose();
  }

  /// Called by [_MenuSizeObserver] after the menu content is laid out.
  /// Updates the menu width to match intrinsic content width, clamped to
  /// [_minContentWidth]. The menu is hidden (opacity 0) until this is called
  /// to prevent visual "jump" as the width settles.
  void updateContentWidth(double width) {
    if (_isDisposedCalled) {
      loggy.warning(
        'MonetMenuOverlayController.updateContentWidth called after dispose',
      );
      return;
    }
    final double rounded = width.isFinite ? width : 0;
    if (rounded <= 0) {
      return;
    }
    final double clamped = math.max(rounded, _minContentWidth);
    final double? current = _contentWidthListenable.value;
    // Avoid rebuilds for sub-pixel changes.
    if (current != null && (current - clamped).abs() < 0.5) {
      return;
    }
    _contentWidthListenable.value = clamped;
    _isContentMeasuredListenable.value = true;
  }

  /// Computes the minimum width the menu should have before content is
  /// measured. Prefers anchor width so dropdown-style menus match their
  /// trigger, falls back to touch-friendly default.
  double _computeBaselineWidth(
    MonetMenuGeometry geometry,
    MonetMenuAppearance appearance,
  ) {
    final double anchorWidth = geometry.anchorRect.width;
    final double minConstraint = appearance.constraints?.minWidth ?? 0;
    final double minBase = anchorWidth > 0
        ? anchorWidth
        : MonetThemeData.touchSize * 2;
    return math.max(minConstraint, minBase);
  }

  void _ensureAnchorTracking() {
    if (_isAnchorTrackingScheduled) {
      return;
    }
    if (_anchorBox == null) {
      return;
    }
    _isAnchorTrackingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  /// Per-frame callback that tracks anchor position changes.
  /// Re-schedules itself while the menu is open to handle scroll/resize.
  void _onFrame(Duration _) {
    _isAnchorTrackingScheduled = false;
    // Skip tracking for pointer-positioned menus (context menus) since they
    // don't have a widget anchor to follow.
    if (!isShowing ||
        _anchorBox == null ||
        (_geometryListenable.value?.isPointerPosition ?? true)) {
      return;
    }
    final renderBox = _anchorBox!;
    if (!renderBox.attached) {
      return;
    }
    final Offset topLeft = renderBox.localToGlobal(.zero);
    final Size size = renderBox.size;
    final Rect newRect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      size.width,
      size.height,
    );
    final MonetMenuGeometry? currentGeometry = _geometryListenable.value;
    // Only update if position changed meaningfully to avoid unnecessary rebuilds.
    const double tolerance = 0.75;
    final bool shouldUpdate =
        currentGeometry == null ||
        currentGeometry.isPointerPosition ||
        (currentGeometry.anchorRect.left - newRect.left).abs() > tolerance ||
        (currentGeometry.anchorRect.top - newRect.top).abs() > tolerance ||
        (currentGeometry.anchorRect.width - newRect.width).abs() > tolerance ||
        (currentGeometry.anchorRect.height - newRect.height).abs() > tolerance;

    if (shouldUpdate) {
      _geometryListenable.value = MonetMenuGeometry.anchor(anchorRect: newRect);
    }

    // Continue tracking while menu is open.
    if (isShowing && _anchorBox != null) {
      WidgetsBinding.instance.addPostFrameCallback(_onFrame);
      _isAnchorTrackingScheduled = true;
    }
  }
}

/// Describes where on the screen the menu overlay should appear.
class MonetMenuGeometry {
  const MonetMenuGeometry._({
    required this.anchorRect,
    required this.isPointerPosition,
  });

  /// Creates geometry anchored to a widget's bounds.
  factory MonetMenuGeometry.anchor({required Rect anchorRect}) {
    return MonetMenuGeometry._(
      anchorRect: anchorRect,
      isPointerPosition: false,
    );
  }

  /// Creates geometry anchored to an arbitrary pointer position.
  factory MonetMenuGeometry.pointer({required Offset position}) {
    return MonetMenuGeometry._(
      anchorRect: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      isPointerPosition: true,
    );
  }

  /// The rectangle used to position the menu. For pointer-based geometry, this
  /// will have zero width and height.
  final Rect anchorRect;

  /// True if the rect represents a pointer position rather than a widget.
  final bool isPointerPosition;
}

/// Visual configuration for the overlay menu including colors, shape,
/// elevation, and size constraints.
class MonetMenuAppearance {
  const MonetMenuAppearance({
    required this.backgroundColor,
    required this.elevation,
    required this.shape,
    this.shadowColor,
    this.surfaceTintColor,
    this.clipBehavior = Clip.antiAliasWithSaveLayer,
    this.constraints,
    this.entryCurve,
    this.entryDuration,
  });

  final Color backgroundColor;
  final double elevation;
  final ShapeBorder shape;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final Clip clipBehavior;
  final BoxConstraints? constraints;
  final Curve? entryCurve;
  final Duration? entryDuration;
}

class _MonetMenuOverlay extends StatefulWidget {
  const _MonetMenuOverlay({required this.controller});

  final MonetMenuOverlayController controller;

  @override
  State<_MonetMenuOverlay> createState() => _MonetMenuOverlayState();
}

class _MonetMenuOverlayState extends State<_MonetMenuOverlay> with UiLoggy {
  late final FocusNode _focusNode = FocusNode(debugLabel: 'MonetMenuOverlay');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.isShowing) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _dismiss() {
    widget.controller.hide();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == .escape) {
      _dismiss();
      return .handled;
    }
    return .ignored;
  }

  /// Builds the overlay with nested ValueListenableBuilders for granular
  /// rebuilds. The Stack contains a full-screen dismiss gesture detector
  /// behind the positioned menu content.
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder(
        valueListenable: widget.controller.appearanceListenable,
        builder: (context, appearance, _) {
          if (appearance == null) {
            // Same class of developer-error guard as the items.isEmpty check in
            // show(): appearance should never be null by the time the overlay
            // builds. Render nothing rather than surfacing user-facing feedback;
            // this path indicates a programming mistake, not a user-actionable
            // condition.
            loggy.warning(
              'MonetMenuOverlayController.show called with no appearance',
            );
            return const SizedBox.shrink();
          }
          return ValueListenableBuilder(
            valueListenable: widget.controller.geometryListenable,
            builder: (context, geometry, _) {
              if (geometry == null) {
                // Developer-error guard, see appearance == null branch above.
                // Not a user-facing failure mode; the overlay is simply not
                // rendered when geometry is missing.
                loggy.warning(
                  'MonetMenuOverlayController.show called with no geometry',
                );
                return const SizedBox.shrink();
              }
              return ValueListenableBuilder(
                valueListenable: widget.controller.contentWidthListenable,
                builder: (context, contentWidth, _) {
                  return ValueListenableBuilder(
                    valueListenable:
                        widget.controller.isContentMeasuredListenable,
                    builder: (context, isMeasured, ignoredChild) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            key: MonetMenuOverlayController.kDimissOverlayKey,
                            child: GestureDetector(
                              behavior: .opaque,
                              onTap: _dismiss,
                              onSecondaryTap: _dismiss,
                            ),
                          ),
                          _MonetMenuPositioned(
                            controller: widget.controller,
                            appearance: appearance,
                            geometry: geometry,
                            contentWidth: contentWidth,
                            isContentMeasured: isMeasured,
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Handles all positioning logic for the menu overlay.
///
/// Key positioning decisions:
/// - Opens above or below anchor based on available space (measured from
///   anchor center to give a fair comparison).
/// - Clamps horizontal position to keep menu within safe area.
/// - Calculates maxHeight from actual menu top/bottom position to ensure
///   menu fits within screen bounds.
/// - Menu is invisible (opacity 0) until content is measured to prevent
///   visual "jump" during initial layout.
// ignore: prefer-single-widget-per-file
class _MonetMenuPositioned extends StatelessWidget {
  const _MonetMenuPositioned({
    required this.controller,
    required this.appearance,
    required this.geometry,
    required this.contentWidth,
    required this.isContentMeasured,
  });

  final MonetMenuOverlayController controller;
  final MonetMenuAppearance appearance;
  final MonetMenuGeometry geometry;
  final double? contentWidth;
  final bool isContentMeasured;

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);

    final Rect anchor = geometry.anchorRect;

    // Define horizontal safe zone accounting for system UI and aesthetic margin.
    final double leftLimit = padding.left + _kMenuScreenMargin;
    final double rightLimit =
        screenSize.width - padding.right - _kMenuScreenMargin;

    final BoxConstraints constraints =
        appearance.constraints ?? const BoxConstraints(maxWidth: .infinity);
    final double availableWidth = math.max(0, rightLimit - leftLimit);

    // Cap width at 90% of screen if no explicit constraint, prevents menus
    // from feeling too wide on large screens.
    double maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : math.min(availableWidth, screenSize.width * 0.9);
    if (constraints.hasBoundedWidth) {
      maxWidth = math.min(maxWidth, availableWidth);
    }

    // Determine width for horizontal positioning. Before content is measured,
    // use anchor width or constraints as a reasonable estimate.
    final double widthForClamp;
    final double? cw = contentWidth;
    if (cw == null || !cw.isFinite || cw <= 0) {
      final double anchorWidth = anchor.width;
      if (anchorWidth > 0) {
        widthForClamp = math.min(anchorWidth, maxWidth);
      } else {
        final double minConstraint = appearance.constraints?.minWidth ?? 0;
        if (minConstraint > 0) {
          widthForClamp = math.min(minConstraint, maxWidth);
        } else {
          widthForClamp = maxWidth;
        }
      }
    } else {
      widthForClamp = math.min(cw, maxWidth);
    }

    // Align menu left edge with anchor, but clamp to keep within safe zone.
    double left = anchor.left;
    left = left.clamp(
      leftLimit,
      math.max(leftLimit, rightLimit - widthForClamp),
    );

    // --- Vertical positioning ---
    // Decide whether to open above or below based on which direction has more
    // space. We measure from anchor.center.dy to give a fair comparison.
    const double margin = _kMenuScreenMargin;
    final double availableBelow =
        screenSize.height - padding.bottom - margin - anchor.center.dy;
    final double availableAbove = anchor.center.dy - padding.top - margin;
    final bool openAbove = availableAbove > availableBelow;

    double? top;
    double? bottom;
    double maxHeight;

    if (openAbove) {
      // Position menu bottom edge just above the anchor with margin.
      // Menu grows upward from there.
      top = null;
      bottom = screenSize.height - anchor.top + margin;
      // Menu bottom is at (anchor.top - margin). Calculate max height to keep
      // menu top within safe area with margin.
      final double menuBottomY = anchor.top - margin;
      maxHeight = math.max(0, menuBottomY - padding.top - margin);
    } else {
      // Opening below: position menu top edge below anchor.
      final bool pointerAnchor =
          geometry.isPointerPosition && anchor.height == 0;
      // For pointer anchors (context menus), start at pointer position.
      // For widget anchors, start below the widget.
      final double computedTop = pointerAnchor
          ? anchor.top + margin
          : math.max(padding.top + margin, anchor.bottom + margin);
      top = computedTop;
      bottom = null;
      // Calculate maxHeight from actual top position to bottom safe area.
      maxHeight = screenSize.height - padding.bottom - margin - computedTop;
    }

    // Apply additional constraints.
    final double maxAvailableHeight =
        screenSize.height - padding.top - padding.bottom - (margin * 2);
    if (constraints.hasBoundedHeight) {
      maxHeight = math.min(maxHeight, constraints.maxHeight);
    }
    maxHeight = math.min(maxHeight, maxAvailableHeight);

    // Honor minimum height constraint if possible, but don't exceed available.
    final double minHeightConstraint = constraints.minHeight;
    if (minHeightConstraint > 0) {
      final double desiredMin = math.min(
        minHeightConstraint,
        maxAvailableHeight,
      );
      if (maxHeight < desiredMin) {
        maxHeight = desiredMin;
      }
    }

    // Final safety clamp.
    maxHeight = math.max(0, maxHeight);

    // Put the menu's edges on physical pixels. A fractional edge blurs the
    // border and shadow, and its anti-aliasing differs between GPUs.
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    double? snap(double? v) =>
        v == null ? null : (v * dpr).roundToDouble() / dpr;
    // IgnorePointer + Opacity: Menu is invisible and non-interactive until
    // content measurement completes. This prevents visual "jump" as the
    // intrinsic width is calculated.
    return Positioned(
      left: snap(left),
      top: snap(top),
      bottom: snap(bottom),
      child: IgnorePointer(
        ignoring: !isContentMeasured,
        child: AnimatedScale(
          scale: isContentMeasured ? 1.0 : 0.92,
          duration: appearance.entryDuration ?? .zero,
          curve: appearance.entryCurve ?? Curves.linear,
          child: AnimatedOpacity(
            opacity: isContentMeasured ? 1 : 0,
            duration: appearance.entryDuration ?? .zero,
            curve: appearance.entryCurve ?? Curves.linear,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: _MonetMenuShell(
                controller: controller,
                appearance: appearance,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the menu content in a Navigator to handle dismiss gestures and
/// keyboard shortcuts (Escape, Back). The Navigator also provides proper
/// semantics for accessibility.
// ignore: prefer-single-widget-per-file
class _MonetMenuShell extends StatelessWidget {
  const _MonetMenuShell({
    required this.controller,
    required this.appearance,
    required this.maxHeight,
  });

  final MonetMenuOverlayController controller;
  final MonetMenuAppearance appearance;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // Navigator used to get standard dismiss behavior (back button, escape key)
    // and proper focus management.
    return Navigator(
      clipBehavior: .none,
      // Prevent Flutter's default page pop animation (introduced in 3.38) from
      // translating the menu sideways as it dismisses. The overlay already
      // handles its own appearance/disappearance.
      transitionDelegate: const NoAnimationTransitionDelegate(),
      onDidRemovePage: (page) {
        controller.hide();
      },
      pages: [
        // TransitionDelegate alone doesn’t stop the Material route animation,
        // because we still push/pop a standard MaterialPageRoute
        // (via MaterialPage). That route’s own transition was sliding out even
        // though the delegate said “no animation”.
        _NoAnimationPage<void>(
          // Note this is required for a *unit test* to succeed: by accident.
          // Somehow, if Patrol taps via $(MenuButton).tap(), the framework
          // knows the semantics role of the menu should be set.
          //
          // Error:
          // The following assertion was thrown during a scheduler callback:
          // A menu item must be a child of a menu or a menu bar.
          child: TickerMode(
            // Shadow the Navigator route's transient TickerMode with a stable
            // value. This avoids Riverpod Consumer subscriptions in menu items
            // being synchronously resumed while the route OverlayEntry builds.
            enabled: true,
            child: Semantics(
              role: .menu,
              child: _MonetMenuBody(
                controller: controller,
                appearance: appearance,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The actual menu content: styled container with scrollable list of items.
// ignore: prefer-single-widget-per-file
class _MonetMenuBody extends StatelessWidget {
  const _MonetMenuBody({
    required this.controller,
    required this.appearance,
    required this.maxHeight,
  });

  final MonetMenuOverlayController controller;
  final MonetMenuAppearance appearance;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // FocusScope with autofocus ensures keyboard navigation works immediately.
    return FocusScope(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(.escape): DismissIntent(),
          SingleActivator(.goBack): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction(
              // ignore: function-always-returns-null
              onInvoke: (intent) {
                controller.hide();
                return null;
              },
            ),
          },
          child: Material(
            // Intentionally no clipBehavior on the Material wrapper — the
            // drop-shadow is painted by the inner Container's
            // [ShapeDecoration.shadows], and clipping at this level would
            // also clip the shadow. The inner Container handles clipping
            // of menu content against the shape.
            color: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shape: appearance.shape,
            child: Container(
              key: MonetMenuOverlayController.kMenuBodyKey,
              foregroundDecoration: ShapeDecoration(shape: appearance.shape),
              clipBehavior: .antiAlias,
              decoration: ShapeDecoration(
                shape: appearance.shape,
                color: appearance.backgroundColor,
                shadows: fabShadows(
                  MonetTheme.of(context).primary.backgroundBorder,
                ),
              ),
              padding: .symmetric(vertical: VerticalPaddingHalf.amount),
              constraints: BoxConstraints(
                // Honor the caller-supplied minWidth so menus can be forced
                // wider than their intrinsic content (e.g. dropdowns that
                // want to match their anchor's width).
                minWidth: appearance.constraints?.minWidth ?? 0,
                maxWidth: appearance.constraints?.maxWidth ?? .infinity,
                minHeight: appearance.constraints?.minHeight ?? 0,
                maxHeight: maxHeight,
              ),
              child: ValueListenableBuilder<List<MenuEntry>>(
                valueListenable: controller.itemsListenable,
                builder: (context, items, _) {
                  if (items.isEmpty) {
                    // Race path: items went from non-empty (when show() was
                    // called) to empty mid-interaction — e.g. the underlying
                    // data source mutated while the menu was open. Auto-
                    // dismissing is the right call: a menu with no actions is
                    // not actionable, and surfacing a "no items" state mid-
                    // interaction would be more confusing than helpful. If
                    // callers need a visible empty state they should show a
                    // disabled entry instead of an empty list.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      controller.hide();
                    });
                    return const SizedBox.shrink();
                  }
                  return ScrollConfiguration(
                    behavior: const ScrollBehavior().copyWith(
                      scrollbars: false,
                    ),
                    child: MonetScrollbar(
                      child: SingleChildScrollView2(
                        clipBehavior: .none,
                        padding: EdgeInsets.zero,
                        primary: false,
                        child: _MenuSizeObserver(
                          onSize: controller.updateContentWidth,
                          child: IntrinsicWidth(
                            // Whole physical pixels, so the right edge is
                            // as sharp as the left edge.
                            stepWidth:
                                1 / MediaQuery.devicePixelRatioOf(context),
                            child: Column(
                              mainAxisSize: .min,
                              // ignore: telosnex_lints/telosnex_avoid_cross_axis_stretch
                              crossAxisAlignment: .stretch,
                              children: items,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Observes size changes of the menu content during layout.
/// Reports width to controller so the menu can size itself to fit content.
// ignore: prefer-single-widget-per-file
class _MenuSizeObserver extends SingleChildRenderObjectWidget {
  const _MenuSizeObserver({required this.onSize, required super.child});

  final void Function(double width) onSize;

  @override
  _MenuSizeRender createRenderObject(BuildContext context) {
    return _MenuSizeRender(onSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MenuSizeRender renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _MenuSizeRender extends RenderProxyBox {
  _MenuSizeRender(this.onSize);

  void Function(double width) onSize;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final Size newSize = child?.size ?? .zero;
    if (_oldSize == newSize) {
      return;
    }
    _oldSize = newSize;
    scheduleMicrotask(() {
      onSize(newSize.width);
    });
  }
}

/// Transition delegate that suppresses route animations.
/// Used by the menu's internal Navigator to prevent slide/fade transitions
/// when the menu appears or disappears.
class NoAnimationTransitionDelegate<T> extends TransitionDelegate<T> {
  const NoAnimationTransitionDelegate();

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord>
    locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
    pageRouteToPagelessRoutes,
  }) {
    final List<RouteTransitionRecord> results = <RouteTransitionRecord>[];

    for (final RouteTransitionRecord route in newPageRouteHistory) {
      if (route.isWaitingForEnteringDecision) {
        route.markForAdd();
      }
      results.add(route);
    }

    for (final RouteTransitionRecord exitingRoute
        in locationToExitingPageRoute.values) {
      if (exitingRoute.isWaitingForExitingDecision) {
        exitingRoute.markForComplete(exitingRoute.route.currentResult);
        final List<RouteTransitionRecord>? pagelessRoutes =
            pageRouteToPagelessRoutes[exitingRoute];
        if (pagelessRoutes != null) {
          for (final RouteTransitionRecord pagelessRoute in pagelessRoutes) {
            if (pagelessRoute.isWaitingForExitingDecision) {
              pagelessRoute.markForComplete(pagelessRoute.route.currentResult);
            }
          }
        }
      }
      results.add(exitingRoute);
    }

    return results;
  }
}

/// A Page that creates a route with zero transition duration.
/// Complements [NoAnimationTransitionDelegate] to ensure the menu
/// appears/disappears instantly without any animation artifacts.
class _NoAnimationPage<T> extends Page<T> {
  const _NoAnimationPage({required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
      settings: this,
      // Navigator updates an existing route's settings when this Page is
      // rebuilt. Do not capture [child] here: PageRouteBuilder can retain the
      // route and its first pageBuilder result, which would leave live menu
      // constraints (such as the height available around a moving anchor)
      // stale. ModalRoute.settingsOf establishes the dependency needed to
      // rebuild this Builder with the current Page and child.
      pageBuilder: (_, _, _) => Builder(
        builder: (context) {
          final page = ModalRoute.settingsOf(context) as _NoAnimationPage<T>;
          return page.child;
        },
      ),
      transitionDuration: .zero,
      reverseTransitionDuration: .zero,
    );
  }
}
