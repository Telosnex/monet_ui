import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/widgets/h4.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_scrollbar.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:pixel_snap_fork/material.dart';

class MonetAlertDialog extends HookWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  const MonetAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = MonetTheme.of(context);

    return ScreenConstrained(
      width: 600,
      child: MonetScrollbar(
        child: AlertDialog(
          // Distance from the screen edge.
          // Induce slight difference between horizontal padding for alert and
          // content under alert.
          insetPadding: .all(ScreenPadding.amount - 1),
          actionsAlignment: MonetHandedness.of(context) == .right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          titlePadding: EdgeInsets.all(
            ScreenPadding.amount + HorizontalPadding.amount,
          ).copyWith(bottom: 0),
          // Without:
          // - top set to 0 for contentPadding
          // - bottom set to 0 for titlePadding
          // there is excessive padding between the title and content.
          // Somehow there is still enough padding between the content and title
          // despite none being specified.
          contentPadding: EdgeInsets.all(HorizontalPadding.amount * 2)
              .copyWith(top: 0),
          actionsPadding: EdgeInsets.symmetric(
            horizontal: HorizontalPadding.amount * 2,
          ).copyWith(bottom: VerticalPadding.amount),
          title: title,
          content: content,
          // Ensure padding when buttons are stacked vertically, i.e. in short width
          actions: [
            for (int i = 0; i < actions.length; i++)
              Padding(
                padding: const .only(bottom: VerticalPadding.amount),
                child: actions[i],
              ),
          ],
          scrollable: true,
          surfaceTintColor: theme.primary.background,
          backgroundColor: theme.primary.background,
          titleTextStyle: H4.style(context).copyWith(color: theme.primary.fill),
          contentTextStyle: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: theme.primary.backgroundText),
          elevation: 0,
          shape: MonetTheme.shapesOf(context).border(
            side: BorderSide(color: theme.primary.backgroundBorder, width: 1),
          ),
        ),
      ),
    );
  }
}
