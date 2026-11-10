import 'package:monet_ui/theming/monet_shape_theme.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

class TFID {
  static const kVerticalPadding = VerticalPadding.amount;

  static InputBorder _border(
    MonetShapes shapes,
    TextDirection textDirection,
    Color color, {
    required double width,
    BorderStyle style = .solid,
  }) => shapes.inputBorder(
    borderSide: BorderSide(width: width, color: color, style: style),
    textDirection: textDirection,
  );

  /// Layout-matching transparent border for paint-bus-driven fields: the
  /// visible border is painted by TextFieldPaintChrome at paint time, but
  /// InputDecorator layout must still reserve the same border widths.
  static InputBorder _paintDrivenBorder(
    MonetShapes shapes,
    TextDirection textDirection,
    double width,
  ) => _border(shapes, textDirection, Colors.transparent, width: width);

  static InputDecoration get(
    BuildContext context,
    Palette colors, {
    String? hintText,
    IconData? prefixIconData,
    TextStyle? hintStyle,
    bool showBorderWhileUnfocused = true,
    // When true, all borders are transparent (widths preserved): the border
    // is painted per-tick by TextFieldPaintChrome instead.
    bool paintDrivenChrome = false,
    // Live hint widget (takes precedence over hintText/hintStyle). Used by
    // paint-bus fields: the decorator rebuilds the hint on its own schedule
    // with whatever style it was built with, overwriting render-level
    // recolors — so the hint itself must subscribe to the bus.
    Widget? hint,
  }) {
    final shapes = MonetTheme.shapesOf(context);
    final textDirection = Directionality.of(context);
    if (paintDrivenChrome) {
      final border = _paintDrivenBorder(shapes, textDirection, 1);
      return InputDecoration(
        // Fill is painted per-tick by TextFieldPaintChrome; keep the
        // decorator's own fill invisible or it freezes at the build-time
        // palette while the bus animates.
        fillColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        hint: hint,
        hintText: hint == null ? hintText : null,
        hintStyle: hint == null ? hintStyle : null,
        contentPadding: const .symmetric(
          vertical: kVerticalPadding,
          horizontal: HorizontalPadding.amount,
        ),
        prefixIcon: prefixIconData != null
            ? MonetIcon(
                prefixIconData,
                size: iconSizeForTextStyleOrNull(hintStyle),
                color: colors.text,
              )
            : null,
        border: border,
        disabledBorder: border,
        enabledBorder: border,
        focusedBorder: _paintDrivenBorder(shapes, textDirection, 2),
      );
    }
    final border = showBorderWhileUnfocused
        ? _border(shapes, textDirection, colors.backgroundBorder, width: 1)
        : _border(
            shapes,
            textDirection,
            colors.backgroundBorder,
            width: 0,
            style: .none,
          );
    return InputDecoration(
      fillColor: colors.background,
      hoverColor: Colors.transparent,
      focusColor: colors.background,
      hintText: hintText,
      hintStyle: hintStyle,
      contentPadding: const .symmetric(
        vertical: kVerticalPadding,
        horizontal: HorizontalPadding.amount,
      ),
      // Specifying this avoids some unexpected feature of there being a hover
      // color. Ex. for the search icon in Chat searches, sometimes it'd flip
      // from white to black when hovered when background was at a midtone.
      prefixIcon: prefixIconData != null
          ? MonetIcon(
              prefixIconData,
              size: iconSizeForTextStyleOrNull(hintStyle),
              color: colors.text,
            )
          : null,
      border: border,
      disabledBorder: border,
      enabledBorder: border,
      focusedBorder: _border(shapes, textDirection, colors.text, width: 2),
    );
  }

  static InputDecoration getMultiline(
    BuildContext context,
    Palette colors, {
    String? hintText,
    TextStyle? hintStyle,
    bool showBorderWhileUnfocused = false,
  }) {
    final shapes = MonetTheme.shapesOf(context);
    final textDirection = Directionality.of(context);
    final border = showBorderWhileUnfocused
        ? _border(shapes, textDirection, colors.backgroundBorder, width: 1)
        : _border(
            shapes,
            textDirection,
            colors.backgroundBorder,
            width: 0,
            style: .none,
          );
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      contentPadding: const .symmetric(
        vertical: HorizontalPadding.amount,
        horizontal: HorizontalPadding.amount,
      ),
      border: border,
      disabledBorder: border,
      enabledBorder: border,
      focusedBorder: _border(shapes, textDirection, colors.fill, width: 2),
    );
  }
}
