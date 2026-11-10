// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/widgets/monet_fallback_shapes.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_material.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

const Duration _kExpand = Duration(milliseconds: 200);

/// Enables control over a single [ExpansionTile2]'s expanded/collapsed state.
///
/// It can be useful to expand or collapse an [ExpansionTile2]
/// programatically, for example to reconfigure an existing expansion
/// tile based on a system event. To do so, create an [ExpansionTile2]
/// with an [ExpansionTile2Controller] that's owned by a stateful widget
/// or look up the tile's automatically created [ExpansionTile2Controller]
/// with [ExpansionTile2Controller.of]
///
/// The controller's [expand] and [collapse] methods cause the
/// the [ExpansionTile2] to rebuild, so they may not be called from
/// a build method.
class ExpansionTile2Controller {
  /// Create a controller to be used with [ExpansionTile2.controller].
  ExpansionTile2Controller();

  _ExpansionTile2State? _state;

  /// Whether the [ExpansionTile2] built with this controller is in expanded state.
  ///
  /// This property doesn't take the animation into account. It reports `true`
  /// even if the expansion animation is not completed.
  ///
  /// See also:
  ///
  ///  * [expand], which expands the [ExpansionTile2].
  ///  * [collapse], which collapses the [ExpansionTile2].
  ///  * [ExpansionTile2.controller] to create an ExpansionTile with a controller.
  bool get isExpanded {
    assert(_state != null);
    return _state!._isExpanded;
  }

  /// Expands the [ExpansionTile2] that was built with this controller;
  ///
  /// Normally the tile is expanded automatically when the user taps on the header.
  /// It is sometimes useful to trigger the expansion programmatically due
  /// to external changes.
  ///
  /// If the tile is already in the expanded state (see [isExpanded]), calling
  /// this method has no effect.
  ///
  /// Calling this method may cause the [ExpansionTile2] to rebuild, so it may
  /// not be called from a build method.
  ///
  /// Calling this method will trigger an [ExpansionTile2.onExpansionChanged] callback.
  ///
  /// See also:
  ///
  ///  * [collapse], which collapses the tile.
  ///  * [isExpanded] to check whether the tile is expanded.
  ///  * [ExpansionTile2.controller] to create an ExpansionTile with a controller.
  void expand() {
    assert(_state != null);
    if (!isExpanded) {
      _state!._toggleExpansion();
    }
  }

  /// Collapses the [ExpansionTile2] that was built with this controller.
  ///
  /// Normally the tile is collapsed automatically when the user taps on the header.
  /// It can be useful sometimes to trigger the collapse programmatically due
  /// to some external changes.
  ///
  /// If the tile is already in the collapsed state (see [isExpanded]), calling
  /// this method has no effect.
  ///
  /// Calling this method may cause the [ExpansionTile2] to rebuild, so it may
  /// not be called from a build method.
  ///
  /// Calling this method will trigger an [ExpansionTile2.onExpansionChanged] callback.
  ///
  /// See also:
  ///
  ///  * [expand], which expands the tile.
  ///  * [isExpanded] to check whether the tile is expanded.
  ///  * [ExpansionTile2.controller] to create an ExpansionTile with a controller.
  void collapse() {
    assert(_state != null);
    if (isExpanded) {
      _state!._toggleExpansion();
    }
  }

  /// Finds the [ExpansionTile2Controller] for the closest [ExpansionTile2] instance
  /// that encloses the given context.
  ///
  /// If no [ExpansionTile2] encloses the given context, calling this
  /// method will cause an assert in debug mode, and throw an
  /// exception in release mode.
  ///
  /// To return null if there is no [ExpansionTile2] use [maybeOf] instead.
  ///
  /// {@tool dartpad}
  /// Typical usage of the [ExpansionTile2Controller.of] function is to call it from within the
  /// `build` method of a descendant of an [ExpansionTile2].
  ///
  /// When the [ExpansionTile2] is actually created in the same `build`
  /// function as the callback that refers to the controller, then the
  /// `context` argument to the `build` function can't be used to find
  /// the [ExpansionTile2Controller] (since it's "above" the widget
  /// being returned in the widget tree). In cases like that you can
  /// add a [Builder] widget, which provides a new scope with a
  /// [BuildContext] that is "under" the [ExpansionTile]:
  ///
  /// ** See code in examples/api/lib/material/expansion_tile/expansion_tile.1.dart **
  /// {@end-tool}
  ///
  /// A more efficient solution is to split your build function into
  /// several widgets. This introduces a new context from which you
  /// can obtain the [ExpansionTile2Controller]. With this approach you
  /// would have an outer widget that creates the [ExpansionTile2]
  /// populated by instances of your new inner widgets, and then in
  /// these inner widgets you would use [ExpansionTile2Controller.of].
  static ExpansionTile2Controller of(BuildContext context) {
    final _ExpansionTile2State? result = context
        .findAncestorStateOfType<_ExpansionTile2State>();
    if (result != null) {
      return result._tileController;
    }
    throw FlutterError.fromParts([
      ErrorSummary(
        'ExpansionTileController.of() called with a context that does not contain a ExpansionTile.',
      ),
      ErrorDescription(
        'No ExpansionTile ancestor could be found starting from the context that was passed to ExpansionTileController.of(). '
        'This usually happens when the context provided is from the same StatefulWidget as that '
        'whose build function actually creates the ExpansionTile widget being sought.',
      ),
      ErrorHint(
        'There are several ways to avoid this problem. The simplest is to use a Builder to get a '
        'context that is "under" the ExpansionTile. For an example of this, please see the '
        'documentation for ExpansionTileController.of():\n'
        '  https://api.flutter.dev/pixel_snap/material/ExpansionTile/of.html',
      ),
      ErrorHint(
        'A more efficient solution is to split your build function into several widgets. This '
        'introduces a new context from which you can obtain the ExpansionTile. In this solution, '
        'you would have an outer widget that creates the ExpansionTile populated by instances of '
        'your new inner widgets, and then in these inner widgets you would use ExpansionTileController.of().\n'
        'An other solution is assign a GlobalKey to the ExpansionTile, '
        'then use the key.currentState property to obtain the ExpansionTile rather than '
        'using the ExpansionTileController.of() function.',
      ),
      context.describeElement('The context used was'),
    ]);
  }

  /// Finds the [ExpansionTile2] from the closest instance of this class that
  /// encloses the given context and returns its [ExpansionTile2Controller].
  ///
  /// If no [ExpansionTile2] encloses the given context then return null.
  /// To throw an exception instead, use [of] instead of this function.
  ///
  /// See also:
  ///
  ///  * [of], a similar function to this one that throws if no [ExpansionTile2]
  ///    encloses the given context. Also includes some sample code in its
  ///    documentation.
  static ExpansionTile2Controller? maybeOf(BuildContext context) {
    return context
        .findAncestorStateOfType<_ExpansionTile2State>()
        ?._tileController;
  }
}

/// A single-line [ListTile] with an expansion arrow icon that expands or collapses
/// the tile to reveal or hide the [children].
///
/// This widget is typically used with [ListView] to create an "expand /
/// collapse" list entry. When used with scrolling widgets like [ListView], a
/// unique [PageStorageKey] must be specified as the [key], to enable the
/// [ExpansionTile2] to save and restore its expanded state when it is scrolled
/// in and out of view.
///
/// This class overrides the [ListTileThemeData.iconColor] and [ListTileThemeData.textColor]
/// theme properties for its [ListTile]. These colors animate between values when
/// the tile is expanded and collapsed: between [iconColor], [collapsedIconColor] and
/// between [textColor] and [collapsedTextColor].
///
/// The expansion arrow icon is shown on the right by default in left-to-right languages
/// (i.e. the trailing edge). This can be changed using [controlAffinity]. This maps
/// to the [leading] and [trailing] properties of [ExpansionTile2].
///
/// {@tool dartpad}
/// This example demonstrates how the [ExpansionTile2] icon's location and appearance
/// can be customized.
///
/// ** See code in examples/api/lib/material/expansion_tile/expansion_tile.0.dart **
/// {@end-tool}
///
/// {@tool dartpad}
/// This example demonstrates how an [ExpansionTile2Controller] can be used to
/// programatically expand or collapse an [ExpansionTile2].
///
/// ** See code in examples/api/lib/material/expansion_tile/expansion_tile.1.dart **
/// {@end-tool}
///
/// See also:
///
///  * [ListTile], useful for creating expansion tile [children] when the
///    expansion tile represents a sublist.
///  * The "Expand and collapse" section of
///    <https://material.io/components/lists#types>
class ExpansionTile2 extends StatefulWidget {
  /// Creates a single-line [ListTile] with an expansion arrow icon that expands or collapses
  /// the tile to reveal or hide the [children]. The [initiallyExpanded] property must
  /// be non-null.
  const ExpansionTile2({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.onExpansionChanged,
    this.children = const <Widget>[],
    this.trailing,
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.shrinkToFit = false,
    this.tilePadding,
    this.expandedCrossAxisAlignment,
    this.expandedAlignment,
    this.childrenPadding,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.shape,
    this.collapsedShape,
    this.clipBehavior,
    this.controlAffinity,
    this.controller,
    this.titleExpandRowMainAxisAlignment,
  }) : assert(
         expandedCrossAxisAlignment != .baseline,
         'CrossAxisAlignment.baseline is not supported since the expanded children '
         'are aligned in a column, not a row. Try to use another constant.',
       );

  final MainAxisAlignment? titleExpandRowMainAxisAlignment;

  /// A widget to display before the title.
  ///
  /// Typically a [CircleAvatar] widget.
  ///
  /// Depending on the value of [controlAffinity], the [leading] widget
  /// may replace the rotating expansion arrow icon.
  final Widget? leading;

  /// The primary content of the list item.
  ///
  /// Typically a [Text] widget.
  final Widget title;

  /// Additional content displayed below the title.
  ///
  /// Typically a [Text] widget.
  final Widget? subtitle;

  /// Called when the tile expands or collapses.
  ///
  /// When the tile starts expanding, this function is called with the value
  /// true. When the tile starts collapsing, this function is called with
  /// the value false.
  final ValueChanged<bool>? onExpansionChanged;

  /// The widgets that are displayed when the tile expands.
  ///
  /// Typically [ListTile] widgets.
  final List<Widget> children;

  /// The color to display behind the sublist when expanded.
  ///
  /// If this property is null then [ExpansionTileThemeData.backgroundColor] is used. If that
  /// is also null then Colors.transparent is used.
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Color? backgroundColor;

  /// When not null, defines the background color of tile when the sublist is collapsed.
  ///
  /// If this property is null then [ExpansionTileThemeData.collapsedBackgroundColor] is used.
  /// If that is also null then Colors.transparent is used.
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Color? collapsedBackgroundColor;

  /// A widget to display after the title.
  ///
  /// Depending on the value of [controlAffinity], the [trailing] widget
  /// may replace the rotating expansion arrow icon.
  final Widget? trailing;

  /// Specifies if the list tile is initially expanded (true) or collapsed (false, the default).
  final bool initiallyExpanded;

  /// Specifies whether the state of the children is maintained when the tile expands and collapses.
  ///
  /// When true, the children are kept in the tree while the tile is collapsed.
  /// When false (default), the children are removed from the tree when the tile is
  /// collapsed and recreated upon expansion.
  final bool maintainState;

  /// When true, interior rows are set to MainAxisSize.min rather than leaving
  /// it unset. This is not a standard Flutter option or behavior, it is added
  /// to allow Mods to not have to expand to their max constrained width just
  /// because an expansion tile is present.
  final bool shrinkToFit;

  /// Specifies padding for the [ListTile].
  ///
  /// Analogous to [ListTile.contentPadding], this property defines the insets for
  /// the [leading], [title], [subtitle] and [trailing] widgets. It does not inset
  /// the expanded [children] widgets.
  ///
  /// If this property is null then [ExpansionTileThemeData.tilePadding] is used. If that
  /// is also null then the tile's padding is `EdgeInsets.symmetric(horizontal: 16.0)`.
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final EdgeInsetsGeometry? tilePadding;

  /// Specifies the alignment of [children], which are arranged in a column when
  /// the tile is expanded.
  ///
  /// The internals of the expanded tile make use of a [Column] widget for
  /// [children], and [Align] widget to align the column. The [expandedAlignment]
  /// parameter is passed directly into the [Align].
  ///
  /// Modifying this property controls the alignment of the column within the
  /// expanded tile, not the alignment of [children] widgets within the column.
  /// To align each child within [children], see [expandedCrossAxisAlignment].
  ///
  /// The width of the column is the width of the widest child widget in [children].
  ///
  /// If this property is null then [ExpansionTileThemeData.expandedAlignment]is used. If that
  /// is also null then the value of [expandedAlignment] is [Alignment.center].
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Alignment? expandedAlignment;

  /// Specifies the alignment of each child within [children] when the tile is expanded.
  ///
  /// The internals of the expanded tile make use of a [Column] widget for
  /// [children], and the `crossAxisAlignment` parameter is passed directly into
  /// the [Column].
  ///
  /// Modifying this property controls the cross axis alignment of each child
  /// within its [Column]. The width of the [Column] that houses [children] will
  /// be the same as the widest child widget in [children]. The width of the
  /// [Column] might not be equal to the width of the expanded tile.
  ///
  /// To align the [Column] along the expanded tile, use the [expandedAlignment]
  /// property instead.
  ///
  /// When the value is null, the value of [expandedCrossAxisAlignment] is
  /// [CrossAxisAlignment.center].
  final CrossAxisAlignment? expandedCrossAxisAlignment;

  /// Specifies padding for [children].
  ///
  /// If this property is null then [ExpansionTileThemeData.childrenPadding] is used. If that
  /// is also null then the value of [childrenPadding] is [EdgeInsets.zero].
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final EdgeInsetsGeometry? childrenPadding;

  /// The icon color of tile's expansion arrow icon when the sublist is expanded.
  ///
  /// Used to override to the [ListTileThemeData.iconColor].
  ///
  /// If this property is null then [ExpansionTileThemeData.iconColor] is used. If that
  /// is also null then the value of [ColorScheme.primary] is used.
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Color? iconColor;

  /// The icon color of tile's expansion arrow icon when the sublist is collapsed.
  ///
  /// Used to override to the [ListTileThemeData.iconColor].
  ///
  /// If this property is null then [ExpansionTileThemeData.collapsedIconColor] is used. If that
  /// is also null and [ThemeData.useMaterial3] is true, [ColorScheme.onSurface] is used. Otherwise,
  /// defaults to [ThemeData.unselectedWidgetColor] color.
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Color? collapsedIconColor;

  /// The color of the tile's titles when the sublist is expanded.
  ///
  /// Used to override to the [ListTileThemeData.textColor].
  ///
  /// If this property is null then [ExpansionTileThemeData.textColor] is used. If that
  /// is also null then and [ThemeData.useMaterial3] is true, color of the [TextTheme.bodyLarge]
  /// will be used for the [title] and [subtitle]. Otherwise, defaults to [ColorScheme.primary] color.
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Color? textColor;

  /// The color of the tile's titles when the sublist is collapsed.
  ///
  /// Used to override to the [ListTileThemeData.textColor].
  ///
  /// If this property is null then [ExpansionTileThemeData.collapsedTextColor] is used.
  /// If that is also null and [ThemeData.useMaterial3] is true, color of the
  /// [TextTheme.bodyLarge] will be used for the [title] and [subtitle]. Otherwise,
  /// defaults to color of the [TextTheme.titleMedium].
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Color? collapsedTextColor;

  /// The tile's border shape when the sublist is expanded.
  ///
  /// If this property is null, the [ExpansionTileThemeData.shape] is used. If that
  /// is also null, a [Border] with vertical sides default to [ThemeData.dividerColor] is used
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final ShapeBorder? shape;

  /// The tile's border shape when the sublist is collapsed.
  ///
  /// If this property is null, the [ExpansionTileThemeData.collapsedShape] is used. If that
  /// is also null, a [Border] with vertical sides default to Color [Colors.transparent] is used
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final ShapeBorder? collapsedShape;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// If this property is null, the [ExpansionTileThemeData.clipBehavior] is used. If that
  /// is also null, a [Clip.none] is used
  ///
  /// See also:
  ///
  /// * [ExpansionTileTheme.of], which returns the nearest [ExpansionTileTheme]'s
  ///   [ExpansionTileThemeData].
  final Clip? clipBehavior;

  /// Typically used to force the expansion arrow icon to the tile's leading or trailing edge.
  ///
  /// By default, the value of [controlAffinity] is [ListTileControlAffinity.platform],
  /// which means that the expansion arrow icon will appear on the tile's trailing edge.
  final ListTileControlAffinity? controlAffinity;

  /// If provided, the controller can be used to expand and collapse tiles.
  ///
  /// In cases were control over the tile's state is needed from a callback triggered
  /// by a widget within the tile, [ExpansionTile2Controller.of] may be more convenient
  /// than supplying a controller.
  final ExpansionTile2Controller? controller;

  @override
  State<ExpansionTile2> createState() => _ExpansionTile2State();
}

class _ExpansionTile2State extends State<ExpansionTile2>
    with SingleTickerProviderStateMixin {
  static final Animatable<double> _easeOutTween = CurveTween(
    curve: Curves.easeOut,
  );
  static final Animatable<double> _easeInTween = CurveTween(
    curve: Curves.easeIn,
  );
  static final Animatable<double> _halfTween = Tween(begin: 0.0, end: 0.5);

  final ShapeBorderTween _borderTween = ShapeBorderTween();
  final ColorTween _headerColorTween = ColorTween();
  final ColorTween _iconColorTween = ColorTween();
  final ColorTween _backgroundColorTween = ColorTween();

  late AnimationController _animationController;
  late Animation<double> _iconTurns;
  late Animation<double> _heightFactor;
  late Animation<Color?> _headerColor;
  late Animation<Color?> _iconColor;
  late Animation<Color?> _backgroundColor;

  bool _isExpanded = false;
  late ExpansionTile2Controller _tileController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: _kExpand, vsync: this);
    _heightFactor = _animationController.drive(_easeInTween);
    _iconTurns = _animationController.drive(_halfTween.chain(_easeInTween));
    // _border = _animationController.drive(_borderTween.chain(_easeOutTween));
    _headerColor = _animationController.drive(
      _headerColorTween.chain(_easeInTween),
    );
    _iconColor = _animationController.drive(
      _iconColorTween.chain(_easeInTween),
    );
    _backgroundColor = _animationController.drive(
      _backgroundColorTween.chain(_easeOutTween),
    );

    _isExpanded =
        PageStorage.maybeOf(context)?.readState(context) as bool? ??
        widget.initiallyExpanded;
    if (_isExpanded) {
      _animationController.value = 1.0;
    }

    assert(widget.controller?._state == null);
    _tileController = widget.controller ?? ExpansionTile2Controller();
    _tileController._state = this;
  }

  @override
  void dispose() {
    _tileController._state = null;
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    final TextDirection textDirection = WidgetsLocalizations.of(context)
        .textDirection;
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse().then<void>((void value) {
          // rationale: false positive, executed after future completes
          // ignore: avoid-mounted-in-setstate
          if (!mounted) {
            return;
          }
          // ignore: avoid-empty-setstate, no-empty-block
          setState(() {
            // Rebuild without widget.children.
          });
        });
      }
      PageStorage.maybeOf(context)?.writeState(context, _isExpanded);
    });
    final String stateHint = _isExpanded
        ? localizations.expandedHint
        : localizations.collapsedHint;
    widget.onExpansionChanged?.call(_isExpanded);
    SemanticsService.sendAnnouncement(
      View.of(context),
      stateHint,
      textDirection,
    );
  }

  void _handleTap() {
    _toggleExpansion();
  }

  // Platform or null affinity defaults to trailing.
  ListTileControlAffinity _effectiveAffinity(
    ListTileControlAffinity? affinity,
  ) {
    switch (affinity ?? .trailing) {
      case .leading:
        return .leading;
      case .trailing:
      case .platform:
        return .trailing;
    }
  }

  Widget _buildIcon(BuildContext _) {
    return RotationTransition(
      turns: _iconTurns,
      child: const MonetIcon(
        Icons.expand_more,
        size: MonetThemeData.touchSize - 8,
      ),
    );
  }

  Widget? _buildLeadingIcon(BuildContext context) {
    if (_effectiveAffinity(widget.controlAffinity) != .leading) {
      return null;
    }
    return _buildIcon(context);
  }

  Widget? _buildTrailingIcon(BuildContext context) {
    if (_effectiveAffinity(widget.controlAffinity) != .trailing) {
      return null;
    }
    return _buildIcon(context);
  }

  Widget _buildChildren(BuildContext context, Widget? child) {
    // final shapeBorder = _borderTween.evaluate(_animationController);
    final ThemeData theme = Theme.of(context);
    final isCollapsed = !_isExpanded && _animationController.isDismissed;
    final collapsedShapeIsBorderOfWidth0 =
        isCollapsed &&
            (widget.collapsedShape is Border &&
                (widget.collapsedShape as Border).top.width == 0) ||
        (widget.collapsedShape is OutlinedBorder &&
            (widget.collapsedShape as OutlinedBorder).side.width == 0);
    // Whether the expanded shape explicitly requests an invisible border.
    final expandedShapeIsTransparent =
        widget.shape is Border && (widget.shape as Border).top.width == 0;
    final ExpansionTileThemeData expansionTileTheme = ExpansionTileTheme.of(
      context,
    );
    // 0 for interesting problem:
    // - LoomErrorTile uses ExpansionTile2 in a column with LoomTilePadding
    // - The error tile is one pixel inset.
    // - This is easiest to test when the column below has a parent of
    //   a container with a background color.
    // - Previous width value was 1.
    // - It is unclear to me what all the `collapsedShapeIsBorderOfWidth0`
    //   was added for.
    final ShapeBorder expansionTileBorder = monetShapesOrDefault(context)
        .border(
          side: BorderSide(
            width: 1,
            color: collapsedShapeIsBorderOfWidth0 || expandedShapeIsTransparent
                ? Colors.transparent
                : (_iconColor.value ??
                      expansionTileTheme.iconColor ??
                      Colors.transparent),
          ),
        );
    final Clip clipBehavior =
        widget.clipBehavior ?? expansionTileTheme.clipBehavior ?? .none;
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final String onTapHint = _isExpanded
        ? localizations.expansionTileExpandedTapHint
        : localizations.expansionTileCollapsedTapHint;
    String? semanticsHint;
    switch (theme.platform) {
      case .iOS:
      case .macOS:
        semanticsHint = _isExpanded
            ? '${localizations.collapsedHint}\n ${localizations.expansionTileExpandedHint}'
            : '${localizations.expandedHint}\n ${localizations.expansionTileCollapsedHint}';
      case .android:
      case .fuchsia:
      case .linux:
      case .windows:
        break;
    }

    return Container(
      clipBehavior: clipBehavior,
      // decoration: ShapeDecoration(
      //   shape: expansionTileBorder,
      // ),
      // color: _backgroundColor.value ?? expansionTileTheme.backgroundColor,
      child: MonetMaterial(
        clipBehavior: clipBehavior,
        type: .canvas,
        shape: expansionTileBorder,
        color: _backgroundColor.value ?? expansionTileTheme.backgroundColor,
        child: Column(
          crossAxisAlignment: widget.expandedCrossAxisAlignment ?? .center,
          mainAxisSize: .min,
          children: [
            Semantics(
              hint: semanticsHint,
              onTapHint: onTapHint,
              child: ListTileTheme.merge(
                minVerticalPadding: 0,
                shape: monetShapesOrDefault(context).border(
                  side: const BorderSide(width: 1, color: Colors.transparent),
                ),
                iconColor: _iconColor.value ?? expansionTileTheme.iconColor,
                textColor: _headerColor.value,
                child: Builder(
                  builder: (context) {
                    final possibleTrailingIcon = _buildTrailingIcon(context);
                    return DefaultTextStyle(
                      style: TextStyle(color: _headerColor.value),
                      child: IconTheme(
                        data: IconTheme.of(context).copyWith(
                          color:
                              _iconColor.value ?? expansionTileTheme.iconColor,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                (ListTileTheme.of(context).minTileHeight ??
                                    kMinInteractiveDimension) +
                                (ListTileTheme.of(context).minVerticalPadding ??
                                        VerticalPaddingHalf.amount) *
                                    2,
                          ),
                          child: Builder(
                            builder: (context) {
                              return InkWell(
                                onTap: _handleTap,
                                customBorder: monetShapesOrDefault(context)
                                    .border(
                                      side: const BorderSide(
                                        width: 1,
                                        color: Colors.transparent,
                                      ),
                                    ),
                                child: Padding(
                                  padding:
                                      widget.tilePadding ??
                                      expansionTileTheme.tilePadding ??
                                      EdgeInsets.zero,
                                  child: Row(
                                    mainAxisSize: widget.shrinkToFit
                                        ? .min
                                        : .max,
                                    children: [
                                      if (widget.leading != null)
                                        widget.leading!
                                      else if (_buildLeadingIcon(context) !=
                                          null)
                                        _buildLeadingIcon(context)!,
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: .min,
                                          crossAxisAlignment: .start,
                                          children: [
                                            Row(
                                              mainAxisSize: widget.shrinkToFit
                                                  ? .min
                                                  : .max,
                                              mainAxisAlignment:
                                                  widget
                                                      .titleExpandRowMainAxisAlignment ??
                                                  .spaceBetween,
                                              children: [
                                                Flexible(child: widget.title),
                                                if (possibleTrailingIcon !=
                                                    null)
                                                  Padding(
                                                    padding: const .only(
                                                      left:
                                                          HorizontalPaddingHalf
                                                              .amount,
                                                      right: HorizontalPadding
                                                          .amount,
                                                    ),
                                                    child: possibleTrailingIcon,
                                                  ),
                                              ],
                                            ),
                                            ?widget.subtitle,
                                          ],
                                        ),
                                      ),
                                      if (widget.trailing != null &&
                                          (widget.trailing is! SizedBox ||
                                              (widget.trailing as SizedBox)
                                                      .width !=
                                                  0))
                                        Padding(
                                          padding: const .symmetric(
                                            horizontal:
                                                HorizontalPadding.amount,
                                          ),
                                          child: widget.trailing!,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            ClipRect(
              child: Align(
                alignment:
                    widget.expandedAlignment ??
                    expansionTileTheme.expandedAlignment ??
                    Alignment.center,
                // Without 1.0, it expands to the full width of the parent
                widthFactor: widget.shrinkToFit ? 1.0 : null,
                heightFactor: _heightFactor.value,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ExpansionTile2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ExpansionTileThemeData expansionTileTheme = ExpansionTileTheme.of(
      context,
    );
    final ExpansionTileThemeData defaults = _ExpansionTile2DefaultsM3(context);
    if (widget.collapsedShape != oldWidget.collapsedShape ||
        widget.shape != oldWidget.shape) {
      final ThemeData theme = Theme.of(context);
      _updateShapeBorder(expansionTileTheme, theme);
    }
    if (widget.collapsedTextColor != oldWidget.collapsedTextColor ||
        widget.textColor != oldWidget.textColor) {
      _updateHeaderColor(expansionTileTheme, defaults);
    }
    if (widget.collapsedIconColor != oldWidget.collapsedIconColor ||
        widget.iconColor != oldWidget.iconColor) {
      _updateIconColor(expansionTileTheme, defaults);
    }
    if (widget.backgroundColor != oldWidget.backgroundColor ||
        widget.collapsedBackgroundColor != oldWidget.collapsedBackgroundColor) {
      _updateBackgroundColor(expansionTileTheme);
    }
  }

  @override
  void didChangeDependencies() {
    final ThemeData theme = Theme.of(context);
    final ExpansionTileThemeData expansionTileTheme = ExpansionTileTheme.of(
      context,
    );
    final ExpansionTileThemeData defaults = _ExpansionTile2DefaultsM3(context);
    _updateShapeBorder(expansionTileTheme, theme);
    _updateHeaderColor(expansionTileTheme, defaults);
    _updateIconColor(expansionTileTheme, defaults);
    _updateBackgroundColor(expansionTileTheme);
    super.didChangeDependencies();
  }

  void _updateShapeBorder(
    ExpansionTileThemeData expansionTileTheme,
    ThemeData theme,
  ) {
    _borderTween
      ..begin =
          widget.collapsedShape ??
          expansionTileTheme.collapsedShape ??
          const Border(
            top: BorderSide(color: Colors.transparent),
            bottom: BorderSide(color: Colors.transparent),
          )
      ..end =
          widget.shape ??
          expansionTileTheme.shape ??
          Border(
            top: BorderSide(color: theme.dividerColor),
            bottom: BorderSide(color: theme.dividerColor),
          );
  }

  void _updateHeaderColor(
    ExpansionTileThemeData expansionTileTheme,
    ExpansionTileThemeData defaults,
  ) {
    _headerColorTween
      ..begin =
          widget.collapsedTextColor ??
          expansionTileTheme.collapsedTextColor ??
          defaults.collapsedTextColor
      ..end =
          widget.textColor ??
          expansionTileTheme.textColor ??
          defaults.textColor;
  }

  void _updateIconColor(
    ExpansionTileThemeData expansionTileTheme,
    ExpansionTileThemeData defaults,
  ) {
    _iconColorTween
      ..begin =
          widget.collapsedIconColor ??
          expansionTileTheme.collapsedIconColor ??
          defaults.collapsedIconColor
      ..end =
          widget.iconColor ??
          expansionTileTheme.iconColor ??
          defaults.iconColor;
  }

  void _updateBackgroundColor(ExpansionTileThemeData expansionTileTheme) {
    _backgroundColorTween
      ..begin =
          widget.collapsedBackgroundColor ??
          expansionTileTheme.collapsedBackgroundColor
      ..end = widget.backgroundColor ?? expansionTileTheme.backgroundColor;
  }

  @override
  Widget build(BuildContext context) {
    final ExpansionTileThemeData expansionTileTheme = ExpansionTileTheme.of(
      context,
    );
    final bool closed = !_isExpanded && _animationController.isDismissed;
    final bool shouldRemoveChildren = closed && !widget.maintainState;

    final Widget result = Offstage(
      offstage: closed,
      child: TickerMode(
        enabled: !closed,
        child: Padding(
          padding:
              widget.childrenPadding ??
              expansionTileTheme.childrenPadding ??
              EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: widget.expandedCrossAxisAlignment ?? .center,
            children: widget.children,
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _animationController.view,
      builder: _buildChildren,
      child: shouldRemoveChildren ? null : result,
    );
  }
}

// BEGIN GENERATED TOKEN PROPERTIES - ExpansionTile

// Do not edit by hand. The code between the "BEGIN GENERATED" and
// "END GENERATED" comments are generated from data in the Material
// Design token database by the script:
//   dev/tools/gen_defaults/bin/gen_defaults.dart.

class _ExpansionTile2DefaultsM3 extends ExpansionTileThemeData {
  _ExpansionTile2DefaultsM3(this.context);

  final BuildContext context;
  late final ThemeData _theme = Theme.of(context);
  late final ColorScheme _colors = _theme.colorScheme;

  @override
  // rationale: This is a new DCM lint on a class we copied out of Flutter,
  // so we're not going to follow it.
  Color get textColor => _colors.onSurface;

  @override
  // rationale: This is a new DCM lint on a class we copied out of Flutter,
  // so we're not going to follow it.
  Color get iconColor => _colors.primary;

  @override
  // rationale: This is a new DCM lint on a class we copied out of Flutter,
  // so we're not going to follow it.
  Color get collapsedTextColor => _colors.onSurface;

  @override
  // rationale: This is a new DCM lint on a class we copied out of Flutter,
  // so we're not going to follow it.
  Color get collapsedIconColor => _colors.onSurfaceVariant;

  @override
  bool operator ==(Object other) {
    final _ExpansionTile2DefaultsM3 otherM3 =
        other as _ExpansionTile2DefaultsM3;
    if (identical(this, other)) return true;
    return otherM3.context == context &&
        otherM3._theme == _theme &&
        otherM3._colors == _colors;
  }

  @override
  int get hashCode {
    return Object.hash(context, _theme, _colors);
  }
}
