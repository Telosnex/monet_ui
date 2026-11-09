import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_clip.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/util/blur_radius.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/monet_button_label.dart';
import 'package:monet_ui/widgets/monet_icon.dart';

class MonetSegmented<T> extends HookWidget {
  final List<MonetSegment<T>> options;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final bool isSmall;
  final Palette? colors;

  const MonetSegmented({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.isSmall = true,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Use the passed-in colors directly
    final safeColors = colors ?? MonetTheme.of(context).primary;
    final shape = MonetTheme.shapesOf(context).border();

    return SelectionContainer.disabled(
      child: Container(
        decoration: ShapeDecoration(
          // Buttons paint the surface; a fill here creates an antialias seam.
          shape: shape,
          // n.b. intent here is to copy MonetElevated
          shadows: aestheticShadows(safeColors.fillBorder),
        ),
        child: MonetClip(
          shape: shape,
          child: _SegmentedRow(
            dividerColor: safeColors.fillBorder,
            selectedIndex: options.indexWhere((o) => o.value == selectedValue),
            children: [
              for (final option in options)
                _SegmentButton(
                  option: option,
                  isSelected: option.value == selectedValue,
                  onTap: () => onChanged(option.value),
                  isSmall: isSmall,
                  colors: safeColors,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MonetSegment<T> {
  final Key? key;
  final IconData? icon;
  final Widget? iconWidget;
  final String label;

  /// Content after the label, such as a price or compact status.
  final Widget? trailing;
  final String? tooltip;
  final T value;

  const MonetSegment({
    this.key,
    this.icon,
    this.iconWidget,
    this.trailing,
    this.tooltip,
    required this.label,
    required this.value,
  });
}

// ignore: prefer-single-widget-per-file
class MonetSegmentedWrap<T> extends StatelessWidget {
  final List<MonetSegment<T>> options;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final bool isSmall;
  final Palette? colors;
  final double spacing;
  final double runSpacing;

  const MonetSegmentedWrap({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.isSmall = true,
    this.colors,
    this.spacing = HorizontalPaddingHalf.amount,
    this.runSpacing = VerticalPaddingHalf.amount,
  });

  @override
  Widget build(BuildContext context) {
    final safeColors = colors ?? MonetTheme.of(context).primary;
    final shape = MonetTheme.shapesOf(context).border();

    return SelectionContainer.disabled(
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [
          for (final option in options)
            Container(
              decoration: ShapeDecoration(
                // Buttons paint the surface; a fill here creates an antialias seam.
                shape: shape,
                shadows: aestheticShadows(safeColors.fillBorder),
              ),
              child: MonetClip(
                shape: shape,
                child: _SegmentButton(
                  option: option,
                  isSelected: option.value == selectedValue,
                  onTap: () => onChanged(option.value),
                  isSmall: isSmall,
                  colors: safeColors,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ignore: prefer-single-widget-per-file
class _SegmentedRow extends MultiChildRenderObjectWidget {
  final Color dividerColor;
  final int selectedIndex;

  const _SegmentedRow({
    // ignore: unused_element_parameter
    super.key,
    required this.dividerColor,
    required this.selectedIndex,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSegmentedRow(
    dividerColor: dividerColor,
    selectedIndex: selectedIndex,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSegmentedRow renderObject,
  ) {
    renderObject
      ..dividerColor = dividerColor
      ..selectedIndex = selectedIndex;
  }
}

class _SegmentedRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSegmentedRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SegmentedRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SegmentedRowParentData> {
  _RenderSegmentedRow({
    required this._dividerColor,
    required this._selectedIndex,
  });

  // coverage:ignore-start
  Color get dividerColor => _dividerColor;
  // coverage:ignore-end
  Color _dividerColor;
  set dividerColor(Color value) {
    if (_dividerColor == value) return;
    // coverage:ignore-start
    _dividerColor = value;
    markNeedsPaint();
    // coverage:ignore-end
  }

  // coverage:ignore-start
  int get selectedIndex => _selectedIndex;
  // coverage:ignore-end
  int _selectedIndex;
  set selectedIndex(int value) {
    if (_selectedIndex == value) return;
    _selectedIndex = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentedRowParentData) {
      child.parentData = _SegmentedRowParentData();
    }
  }

  /// Returns the width each child should receive given [maxWidth] total space.
  ///
  /// Each child's width is proportional to its intrinsic width, scaled so the
  /// total equals [maxWidth].  When [maxWidth] is infinite the intrinsic widths
  /// are returned as-is.
  ///
  /// Each segment is given at least [MonetThemeData.touchSize] width when there
  /// is enough room; when there isn't, widths are scaled proportionally.
  List<double> _childWidths(double maxWidth) {
    const minSegmentWidth = MonetThemeData.touchSize;
    final desired = <double>[];
    RenderBox? child = firstChild;
    while (child != null) {
      // Motivation: 'on' 'off' 'custom' for compaction segmented had on too
      // small otherwise.
      desired.add(
        math.max(minSegmentWidth, child.getMaxIntrinsicWidth(.infinity)),
      );
      child = childAfter(child);
    }
    if (desired.isEmpty) return desired;

    final total = desired.reduce((a, b) => a + b);
    if (total == 0 || !maxWidth.isFinite || total <= maxWidth) return desired;

    final scale = maxWidth / total;
    return [for (final w in desired) w * scale];
  }

  // coverage:ignore-start
  @override
  double computeMinIntrinsicWidth(double height) {
    double total = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      total += child.getMinIntrinsicWidth(height);
      child = childAfter(child);
    }
    return total;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    double total = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      total += child.getMaxIntrinsicWidth(height);
      child = childAfter(child);
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final widths = _childWidths(width);
    double maxH = 0;
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      maxH = math.max(
        maxH,
        child.getMinIntrinsicHeight(i < widths.length ? widths[i] : 0),
      );
      child = childAfter(child);
      i++;
    }
    return maxH;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final widths = _childWidths(width);
    double maxH = 0;
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      maxH = math.max(
        maxH,
        child.getMaxIntrinsicHeight(i < widths.length ? widths[i] : 0),
      );
      child = childAfter(child);
      i++;
    }
    return maxH;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final widths = _childWidths(constraints.maxWidth);
    if (widths.isEmpty) return constraints.constrain(.zero);

    double maxH = 0;
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      maxH = math.max(maxH, child.getMaxIntrinsicHeight(widths[i]));
      child = childAfter(child);
      i++;
    }
    return constraints.constrain(Size(widths.reduce((a, b) => a + b), maxH));
  }
  // coverage:ignore-end

  @override
  void performLayout() {
    final widths = _childWidths(constraints.maxWidth);
    if (widths.isEmpty) {
      size = constraints.constrain(.zero); // coverage:ignore-line
      return;
    }

    // Find the tallest child at its assigned width.
    double maxH = 0;
    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      maxH = math.max(maxH, child.getMaxIntrinsicHeight(widths[i]));
      child = childAfter(child);
      i++;
    }

    // Lay out each child with tight constraints and position left-to-right.
    child = firstChild;
    i = 0;
    double x = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: widths[i], height: maxH),
        parentUsesSize: true,
      );
      final parentData = child.parentData! as _SegmentedRowParentData;
      parentData.offset = Offset(x, 0);
      x += child.size.width;
      child = childAfter(child);
      i++;
    }

    size = constraints.constrain(Size(x, maxH));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);

    final divPaint = Paint()
      ..color = _dividerColor
      ..strokeWidth = 1.0;
    final inset = 0.0;

    RenderBox? child = firstChild;
    int i = 0;
    while (child != null) {
      final next = childAfter(child);
      if (next != null && i != _selectedIndex && (i + 1) != _selectedIndex) {
        final pd = child.parentData! as _SegmentedRowParentData;
        final x = offset.dx + pd.offset.dx + child.size.width;
        context.canvas.drawLine(
          Offset(x, offset.dy + inset),
          Offset(x, offset.dy + size.height - inset),
          divPaint,
        );
      }
      child = next;
      i++;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

// ignore: prefer-single-widget-per-file
class _SegmentButton<T> extends HookWidget {
  final MonetSegment<T> option;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isSmall;
  final Palette colors;

  const _SegmentButton({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.isSmall,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final statesController = useWidgetStatesController();
    useListenable(statesController);
    final isSplashed = statesController.value.contains(WidgetState.pressed);
    final isHovered = statesController.value.contains(WidgetState.hovered);
    final Color iconColor;
    final Color backgroundColor;
    final Color textColor;
    if (isSelected) {
      // coverage:ignore-start
      if (isSplashed) {
        backgroundColor = colors.fillSplashed;
        iconColor = colors.fillSplashedText;
        textColor = colors.fillSplashedText;
      } else if (isHovered) {
        backgroundColor = colors.fillHovered;
        iconColor = colors.fillHoveredText;
        textColor = colors.fillHoveredText;
      } else {
        // coverage:ignore-end
        backgroundColor = colors.fill;
        iconColor = colors.fillText;
        textColor = colors.fillText;
      }
    } else {
      // coverage:ignore-start
      if (isSplashed) {
        backgroundColor = colors.backgroundSplashed;
        iconColor = colors.backgroundSplashedText;
        textColor = colors.backgroundSplashedText;
      } else if (isHovered) {
        backgroundColor = colors.backgroundHovered;
        iconColor = colors.backgroundHoveredText;
        textColor = colors.backgroundHoveredText;
      } else {
        // coverage:ignore-end
        backgroundColor = colors.background;
        iconColor = colors.text;
        textColor = colors.text;
      }
    }

    final textStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: textColor);
    final horizontalPadding = isSmall
        ? HorizontalPaddingHalf.amount
        : HorizontalPadding.amount;

    final button = Material(
      key: option.key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.backgroundHovered,
        splashColor: colors.backgroundSplashed,
        statesController: statesController,
        child: AnimatedContainer(
          duration: kThemeAnimationDuration,
          padding: .symmetric(horizontal: horizontalPadding),
          color: backgroundColor,
          child: Row(
            mainAxisAlignment: .center,
            mainAxisSize: .min,
            children: [
              Flexible(
                child: IconTheme(
                  data: IconThemeData(
                    opacity: 1.0,
                    size: iconSizeForTextStyleOrNull(textStyle),
                    color: iconColor,
                  ),
                  child: DefaultTextStyle(
                    style: textStyle ?? const TextStyle(),
                    child: MonetButtonLabel(
                      label: option.label,
                      gap: 4,
                      icon:
                          option.iconWidget ??
                          (option.icon == null
                              ? null
                              : MonetIcon(
                                  option.icon,
                                  size: iconSizeForTextStyleOrNull(textStyle),
                                  color: iconColor,
                                )),
                    ),
                  ),
                ),
              ),
              if (option.trailing != null) ...[
                const HorizontalPaddingHalf(),
                DefaultTextStyle(
                  style: textStyle ?? const TextStyle(),
                  maxLines: 1,
                  overflow: .ellipsis,
                  child: option.trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final tooltip = option.tooltip;
    if (tooltip == null) return button;

    return MonetTooltip(
      colors: colors,
      content: Text(tooltip),
      allowTapForToolip: false,
      child: button,
    );
  }
}
