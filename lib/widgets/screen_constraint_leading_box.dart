import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pixel_snap_fork/material.dart';

import 'package:monet_ui/util/list_view_padding_calculator.dart';
import 'package:monet_ui/widgets/padding.dart';

class ScreenConstraintLeadingBox extends HookWidget {
  const ScreenConstraintLeadingBox({super.key});
  @override
  Widget build(BuildContext context) {
    final leading = listViewLeftPaddingUnsafe(
      width: MediaQuery.widthOf(context),
      maxContentWidth: ScreenConstrained.platformWidthOf(context),
    );

    return SizedBox(width: leading);
  }
}
