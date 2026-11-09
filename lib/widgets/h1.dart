import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pixel_snap_fork/material.dart';

class H1 extends HookWidget {
  final String text;

  const H1(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style(context));
  }

  static TextStyle style(BuildContext context) {
    return Theme.of(context).textTheme.displayLarge!;
  }
}
