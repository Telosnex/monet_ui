import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_paint_colors.dart';
import 'package:monet_ui/theming/monet_theme_data.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/theming/palette_recipe.dart';

/// Own a palette subscription; getter reads discover its paint roles. Use a
/// MonetPalette key/resolver for built-ins so consumers share lazy frames.
/// Pass the returned binding as the paint listenable, not the scope-wide bus.
/// Keep calling the hook when disabled; it releases the old binding then.
/// Optional [roles] prewarm outputs (e.g. hover states); they are not an allowlist.
MonetPaletteBinding? useMonetPaintPalette(
  MonetPaintColors? bus,
  Object key,
  Palette Function(MonetThemeData)? resolve, {
  Set<PaletteRole>? roles,
}) {
  final owner = useMemoized(() => _PaintBindingOwner(bus), [bus]);
  useEffect(() => owner.dispose, [owner]);
  return owner.update(key, resolve, roles);
}

/// Typed recipes carry identity and resolver inputs together. Calling this
/// while disabled releases demand without changing hook order.
MonetPaletteBinding? useMonetPaintRecipe(
  MonetPaintColors? bus,
  PaletteRecipe recipe, {
  Set<PaletteRole>? roles,
}) => useMonetPaintPalette(bus, recipe, recipe.resolve, roles: roles);

class _PaintBindingOwner {
  _PaintBindingOwner(this.bus);
  final MonetPaintColors? bus;
  MonetPaletteBinding? binding;

  MonetPaletteBinding? update(
    Object key,
    Palette Function(MonetThemeData)? resolve,
    Set<PaletteRole>? roles,
  ) {
    final colors = bus;
    if (resolve == null || colors == null) {
      dispose();
      return null;
    }
    final current = binding;
    if (current == null) {
      binding = colors.bind(key, resolve, roles: roles);
    } else {
      current.update(key, resolve, roles: roles ?? const {});
    }
    return binding;
  }

  void dispose() {
    binding?.dispose();
    binding = null;
  }
}
