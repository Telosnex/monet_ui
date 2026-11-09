// ignore_for_file: prefer-single-widget-per-file

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:pixel_snap_fork/material.dart';

/// Constrains a Tooltip widget based on screen width.
class MonetTooltip extends HookWidget {
  static const longWait = Duration(milliseconds: 500);

  final Widget child;
  final Widget content;
  final Palette? colors;
  final Duration waitDuration;

  /// On platforms without a mouse pointer, tapping the widget will show the
  /// tooltip when this is true.
  ///
  /// Defaults to false because most [MonetTooltip] children are interactive;
  /// touch taps should activate the child, not produce tooltip UI. When enabled,
  /// touch handling is still passive and does not compete with the child's tap.
  final bool allowTapForToolip;
  final bool allowLongPressForTooltip;
  final TooltipTriggerMode triggerMode;

  const MonetTooltip({
    super.key,
    required this.colors,
    required this.content,
    this.waitDuration = longWait,
    this.allowTapForToolip = false,
    this.allowLongPressForTooltip = true,
    this.triggerMode = TooltipTriggerMode.longPress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColors = colors ?? MonetTheme.of(context).tertiary;

    final isMouseConnected = useState(
      defaultTargetPlatform != .android && defaultTargetPlatform != .iOS,
    );

    // Memoize the tooltip key to avoid recreating it
    final tooltipKey = useMemoized(() => GlobalKey<TooltipState>());

    // Pass only the data needed, not the whole context
    return _MonetTooltipInner(
      colors: effectiveColors,
      content: content,
      waitDuration: waitDuration,
      allowTapForTooltip: allowTapForToolip,
      allowLongPressForTooltip: allowLongPressForTooltip,
      isMouseConnected: isMouseConnected,
      tooltipKey: tooltipKey,
      triggerMode: triggerMode,
      child: child,
    );
  }
}

// This widget is const-constructable and doesn't access Theme directly
// It won't rebuild when theme changes
class _MonetTooltipInner extends HookWidget {
  final Palette colors;
  final Widget content;
  final Duration waitDuration;
  final bool allowTapForTooltip;
  final bool allowLongPressForTooltip;
  final ValueNotifier<bool> isMouseConnected;
  final GlobalKey<TooltipState> tooltipKey;
  final TooltipTriggerMode triggerMode;
  final Widget child;

  const _MonetTooltipInner({
    required this.colors,
    required this.content,
    required this.waitDuration,
    required this.allowTapForTooltip,
    required this.allowLongPressForTooltip,
    required this.isMouseConnected,
    required this.tooltipKey,
    required this.triggerMode,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final preferBelow = isMouseConnected.value;
    final isTouchOnly = !isMouseConnected.value;
    final touchTooltipTimer = useRef<Timer?>(null);
    final touchPointerDownPosition = useRef<Offset?>(null);
    final touchTooltipWasShown = useRef(false);

    void cancelTouchTooltipTimer() {
      touchTooltipTimer.value?.cancel();
      touchTooltipTimer.value = null;
    }

    useEffect(() {
      return cancelTouchTooltipTimer;
    }, []);

    // Memoize shadow computation since it's expensive
    final shadows = useMemoized(
      () => [
        ...?kElevationToShadow[4]?.map(
          (e) => BoxShadow(
            color: colors.color.withValues(alpha: e.color.a),
            blurRadius: e.blurRadius,
            offset: e.offset,
          ),
        ),
      ],
      [colors.color],
    );

    final tooltip = Tooltip(
      // On touch devices, avoid Tooltip's built-in GestureDetector. It enters
      // the gesture arena above the child and can steal taps from buttons,
      // dropdowns, and menu entries. Touch activation is handled below with a
      // raw pointer Listener, which observes events without competing for them.
      triggerMode: isTouchOnly ? .manual : triggerMode,
      preferBelow: preferBelow,
      key: tooltipKey,
      richMessage: WidgetSpan(
        alignment: .middle,
        baseline: .alphabetic,
        child: _TooltipContent(textColor: colors.colorText, content: content),
      ),
      padding: const .symmetric(horizontal: 8.0, vertical: 4.0),
      child: child,
    );

    final themedTooltip = _ThemedTooltip(
      colors: colors,
      waitDuration: waitDuration,
      preferBelow: preferBelow,
      shadows: shadows,
      child: tooltip,
    );

    if (!isTouchOnly ||
        triggerMode == .manual ||
        (!allowTapForTooltip && !allowLongPressForTooltip)) {
      return themedTooltip;
    }

    return Listener(
      onPointerDown: (event) {
        touchTooltipWasShown.value = false;
        touchPointerDownPosition.value = event.position;
        cancelTouchTooltipTimer();
        if (!allowLongPressForTooltip) return;

        touchTooltipTimer.value = Timer(kLongPressTimeout, () {
          touchTooltipWasShown.value = true;
          tooltipKey.currentState?.ensureTooltipVisible();
        });
      },
      onPointerMove: (event) {
        final startPosition = touchPointerDownPosition.value;
        if (startPosition == null) return;
        if ((event.position - startPosition).distance > kTouchSlop) {
          cancelTouchTooltipTimer();
        }
      },
      onPointerCancel: (_) {
        cancelTouchTooltipTimer();
        touchPointerDownPosition.value = null;
      },
      onPointerUp: (_) {
        final wasShownByLongPress = touchTooltipWasShown.value;
        cancelTouchTooltipTimer();
        touchPointerDownPosition.value = null;
        touchTooltipWasShown.value = false;

        if (allowTapForTooltip && !wasShownByLongPress) {
          tooltipKey.currentState?.ensureTooltipVisible();
        }
      },
      child: themedTooltip,
    );
  }
}

// Only this widget accesses Theme for text style
// It will rebuild when theme changes, but it's isolated
class _TooltipContent extends StatelessWidget {
  final Color textColor;
  final Widget content;

  const _TooltipContent({required this.textColor, required this.content});

  @override
  Widget build(BuildContext context) {
    // Isolated theme access - only this widget rebuilds on text style changes
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: textColor),
      child: Container(
        // 25-06-20: increased from 320 to 480 to fix "Reasoning Tokens Out"
        // at scale 200%.
        constraints: const BoxConstraints(maxWidth: 480),
        child: content,
      ),
    );
  }
}

// Only this widget accesses Theme for tooltip theming
// It will rebuild when theme changes, but it's isolated
class _ThemedTooltip extends HookWidget {
  final Palette colors;
  final Duration waitDuration;
  final bool preferBelow;
  final List<BoxShadow> shadows;
  final Widget child;

  const _ThemedTooltip({
    required this.colors,
    required this.waitDuration,
    required this.preferBelow,
    required this.shadows,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Memoize the decoration since it's expensive to create
    final decoration = useMemoized(
      () => ShapeDecoration(
        shape: MonetTheme.shapesOf(context)
            .border(side: BorderSide(width: 1, color: colors.colorBorder)),
        color: colors.color,
        shadows: shadows,
      ),
      [colors.color, colors.colorBorder],
    );

    // Isolated theme access - only this widget rebuilds on theme changes
    return TooltipTheme(
      data: TooltipTheme.of(context).copyWith(
        waitDuration: waitDuration,
        preferBelow: preferBelow,
        // showDuration is misleading, at least on macOS, its actually how long
        // the tooltip will stay up if hover is not maintained.
        showDuration: const Duration(milliseconds: 100),
        decoration: decoration,
        textStyle: Theme.of(context).textTheme.labelLarge!
            .copyWith(color: colors.colorText),
      ),
      child: child,
    );
  }
}
