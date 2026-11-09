import 'package:monet_ui/theming/monet_theme.dart';
import 'package:pixel_snap_fork/material.dart';

class LinkRow {
  static TextStyle textStyle(BuildContext context) {
    final monetTheme = MonetTheme.of(context);
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: monetTheme.tertiary.text,
      decorationColor: monetTheme.tertiary.text,
      decorationStyle: .wavy,
      decoration: .underline,
    );
  }
}
