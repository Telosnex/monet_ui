import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pixel_snap_fork/material.dart';

class H4 extends HookWidget {
  static TextStyle style(BuildContext context, {Color? color}) {
    final base = Theme.of(context).textTheme.headlineLarge!;
    if (color != null) {
      return base.copyWith(color: color);
    }
    return base;
  }

  final String text;
  final Color? color;

  const H4(this.text, {this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style(context, color: color));
  }
}
