import 'package:pixel_snap_fork/material.dart';
import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/border_metrics.dart';

/// Text style for tool and reasoning headers.
TextStyle toolHeaderTextStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium!
        .copyWith(textBaseline: .alphabetic);

/// Icon size that matches the letters of [toolHeaderTextStyle], rounded to a
/// whole logical pixel ([iconSizeForTextStyle]).
///
/// Icons in headers use this size: tool and reasoning icons, the reasoning
/// pills, and the tile menu dots.
double toolHeaderIconSize(BuildContext context) =>
    iconSizeForTextStyle(toolHeaderTextStyle(context)).roundToDouble();

/// Icon size that visually matches header text, accounting for
/// [kTelosnexBorderWidth]. Pass [toolHeaderIconSize].
double toolIconSizeFor(double fontSize) =>
    fontSize + ((3.0 - kTelosnexBorderWidth) * 2).floorToDouble();
