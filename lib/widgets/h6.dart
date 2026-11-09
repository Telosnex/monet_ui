import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pixel_snap_fork/material.dart';

class H6 extends HookWidget {
  static TextStyle style(BuildContext context, {Color? color}) {
    final base = Theme.of(context).textTheme.headlineSmall!;
    if (color != null) {
      return base.copyWith(color: color);
    }
    return base;
  }

  final String text;
  final TextAlign? textAlign;
  final Color? color;

  const H6(this.text, {this.color, this.textAlign, super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style(context, color: color),
      textAlign: textAlign,
    );
  }
}
