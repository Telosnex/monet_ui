import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/menu/menu_entry.dart';
import 'package:pixel_snap_fork/material.dart';

/// A simple divider that can be placed among [MenuEntry] items in a custom
/// menu overlay.
class MenuEntryDivider extends MenuEntry {
  const MenuEntryDivider({
    super.key,
    this.color,
    this.thickness,
    this.padding,
    this.indent,
    this.endIndent,
  });

  /// Optional override for the divider color. If not provided the divider will
  /// use the menu's primary fill color.
  final Color? color;

  /// Optional override for the divider thickness.
  final double? thickness;

  /// Optional padding surrounding the divider. Defaults to none so the divider
  /// spans the full width of the menu.
  final EdgeInsetsGeometry? padding;

  /// Optional indentation applied to the leading edge of the divider.
  final double? indent;

  /// Optional indentation applied to the trailing edge of the divider.
  final double? endIndent;

  @override
  bool get isEnabled => false;

  @override
  Element createElement() => _MenuEntryDividerElement(this);
}

class _MenuEntryDividerElement extends ComponentElement {
  _MenuEntryDividerElement(MenuEntryDivider super.widget);

  @override
  MenuEntryDivider get widget => super.widget as MenuEntryDivider;

  @override
  Widget build() {
    return _MenuEntryDividerBody(
      color: widget.color,
      thickness: widget.thickness,
      padding: widget.padding,
      indent: widget.indent,
      endIndent: widget.endIndent,
    );
  }
}

// ignore: prefer-single-widget-per-file
class _MenuEntryDividerBody extends StatelessWidget {
  const _MenuEntryDividerBody({
    this.color,
    this.thickness,
    this.padding,
    this.indent,
    this.endIndent,
  });

  final Color? color;
  final double? thickness;
  final EdgeInsetsGeometry? padding;
  final double? indent;
  final double? endIndent;

  @override
  Widget build(BuildContext context) {
    final monetTheme = MonetTheme.of(context);

    final Color effectiveColor = color ?? monetTheme.primary.fill;
    final double effectiveThickness = thickness ?? 1.0;
    final EdgeInsetsGeometry effectivePadding = padding ?? EdgeInsets.zero;
    final double effectiveIndent = indent ?? 0;
    final double effectiveEndIndent = endIndent ?? 0;

    return Padding(
      padding: effectivePadding,
      child: Divider(
        color: effectiveColor,
        height: effectiveThickness,
        thickness: effectiveThickness,
        indent: effectiveIndent,
        endIndent: effectiveEndIndent,
      ),
    );
  }
}
