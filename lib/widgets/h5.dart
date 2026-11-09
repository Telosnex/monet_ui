import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pixel_snap_fork/material.dart';

class H5 extends HookWidget {
  static TextStyle style(BuildContext context) {
    return Theme.of(context).textTheme.headlineMedium!;
  }

  final String text;

  const H5(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style(context));
  }
}
