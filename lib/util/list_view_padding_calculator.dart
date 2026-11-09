import 'dart:math' as math;

import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/widgets/padding.dart';

EdgeInsets listViewInsetsCalculator(
  BuildContext context,
  BoxConstraints constraints,
  PreferredSizeWidget? appBar,
) {
  return listViewInsetsFromMediaQueryValues(
    constraints: constraints,
    appBarHeight: appBar == null
        ? 0
        : AppBar.preferredHeightFor(context, appBar.preferredSize),
    viewPadding: MediaQuery.viewPaddingOf(context),
    viewInsets: MediaQuery.viewInsetsOf(context),
    padding: MediaQuery.paddingOf(context),
    maxContentWidth: ScreenConstrained.platformWidthOf(context),
  );
}

/// Variant of [listViewInsetsCalculator] for a layout scope below widgets such
/// as [Scaffold] that may transform MediaQuery padding.
///
/// Reading the aspect-specific values above the scaffold and passing them to a
/// leaf [LayoutBuilder] lets continuous width changes update list padding
/// without rebuilding the screen that owns the list.
///
/// [appBarHeight] must be resolved with [AppBar.preferredHeightFor] in the
/// app bar's theme, excluding the status-bar inset. Reading preferredSize.height
/// directly loses the themed toolbar height and falls back to 56 pixels.
EdgeInsets listViewInsetsFromMediaQueryValues({
  required BoxConstraints constraints,
  required double appBarHeight,
  required EdgeInsets viewPadding,
  required EdgeInsets viewInsets,
  required EdgeInsets padding,
  double maxContentWidth = ScreenConstrained.maxWidth,
}) {
  return EdgeInsets.only(
    left: _listViewPaddingForSide(
      availableWidth: constraints.maxWidth,
      baseInset: ScreenPadding.inset.left,
      viewPadding: viewPadding.left,
      viewInset: viewInsets.left,
      maxContentWidth: maxContentWidth,
    ),
    right: _listViewPaddingForSide(
      availableWidth: constraints.maxWidth,
      baseInset: ScreenPadding.inset.right,
      viewPadding: viewPadding.right,
      viewInset: viewInsets.right,
      maxContentWidth: maxContentWidth,
    ),
    top: viewPadding.top + appBarHeight,
    bottom: math.max(padding.bottom, ScreenPadding.amount),
  );
}

/// Unsafe because width has to be passed in, and may not accurately represent
/// the current width.
/// Useful when avoiding a LayoutBuilder, or, avoiding a MediaQuery.sizeOf and
/// using screenSizeNotifier instead.
double listViewLeftPaddingUnsafe({
  required double width,
  bool enforceScreenPaddingFloor = true,
  double maxContentWidth = ScreenConstrained.maxWidth,
}) {
  return _listViewPaddingForSide(
    availableWidth: width,
    baseInset: enforceScreenPaddingFloor ? ScreenPadding.inset.left : 0,
    maxContentWidth: maxContentWidth,
  );
}

/// Unsafe because width has to be passed in, and may not accurately represent
/// the current width.
/// Useful when avoiding a LayoutBuilder, or, avoiding a MediaQuery.sizeOf and
/// using screenSizeNotifier instead.

double listViewLeftPadding(
  BuildContext context,
  BoxConstraints constraints, {
  bool enforceScreenPaddingFloor = true,
  bool isScreenConstrainedEnforced = true,
}) {
  final viewPadding = MediaQuery.viewPaddingOf(context);
  final viewInsets = MediaQuery.viewInsetsOf(context);
  return _listViewPaddingForSide(
    availableWidth: constraints.maxWidth,
    baseInset: enforceScreenPaddingFloor ? ScreenPadding.inset.left : 0,
    viewPadding: viewPadding.left,
    viewInset: viewInsets.left,
    isScreenConstrainedEnforced: isScreenConstrainedEnforced,
    maxContentWidth: ScreenConstrained.platformWidthOf(context),
  );
}

double listViewRightPadding(
  BuildContext context,
  BoxConstraints constraints, {
  bool enforceScreenPaddingFloor = true,
  bool isScreenConstrainedEnforced = true,
}) {
  final viewPadding = MediaQuery.viewPaddingOf(context);
  final viewInsets = MediaQuery.viewInsetsOf(context);
  return _listViewPaddingForSide(
    availableWidth: constraints.maxWidth,
    baseInset: enforceScreenPaddingFloor ? ScreenPadding.inset.right : 0,
    viewPadding: viewPadding.right,
    viewInset: viewInsets.right,
    isScreenConstrainedEnforced: isScreenConstrainedEnforced,
    maxContentWidth: ScreenConstrained.platformWidthOf(context),
  );
}

double _listViewPaddingForSide({
  required double availableWidth,
  required double baseInset,
  double viewPadding = 0,
  double viewInset = 0,
  bool isScreenConstrainedEnforced = true,
  required double maxContentWidth,
}) {
  final constrainedInset = math.max(
    0.0,
    !isScreenConstrainedEnforced
        ? 0.0
        : (availableWidth - maxContentWidth) / 2.0,
  );

  final returnValue = math.max(
    math.max(baseInset, constrainedInset),
    math.max(viewPadding, viewInset),
  );

  return returnValue;
}
