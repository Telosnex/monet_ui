import 'package:pixel_snap_fork/material.dart' hide ScrollController;

import 'package:monet_ui/widgets/monet_material.dart';

/// A minimal, Scaffold-shaped container that does *not* wrap its body in a
/// `LayoutBuilder`.
///
/// Why this exists:
/// - Material's [Scaffold] wraps its body in `_BodyBuilder`, which is a
///   [LayoutBuilder]. That turns every descendant rebuild (AnimatedBuilder,
///   FadeTransition, TweenAnimationBuilder, HookConsumer, etc.) into a
///   layout-phase rebuild scope. On a screen like [ConversationScreen] that
///   has many running animations (fades, expansions, color cycles, sliver
///   list updates), that pays a significant per-frame cost with no feature
///   payoff — we use none of Scaffold's slotting/drawer/SnackBar/etc.
/// - This widget replicates only what we actually use: a Material surface,
///   a full-bleed body (equivalent of `extendBody` +
///   `extendBodyBehindAppBar` + `resizeToAvoidBottomInset: false`), and an
///   optional [PreferredSizeWidget] app bar pinned to the top. The caller
///   is responsible for any top padding inside the body (via
///   [AppBar.preferredHeightFor] plus the system top inset), the same
///   way we do in the space screen.
///
/// Mirrors the pattern used in `space_screen.dart`.
class MonetScaffold extends StatelessWidget {
  const MonetScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundColor,
  });

  /// App bar, pinned to the top with `Positioned(top: 0, left: 0, right: 0)`.
  ///
  /// Must be a [PreferredSizeWidget] so the body can reserve top space using
  /// [AppBar.preferredHeightFor] (we intentionally do not inset the body
  /// here — callers render "extend body behind app bar" style).
  ///
  /// When `null`, the body fills the entire [Material] directly, with no
  /// surrounding [Stack] — useful for screens like Home that paint their
  /// own top chrome (HomeDateTime) inside the body rather than via an
  /// AppBar slot.
  final PreferredSizeWidget? appBar;

  /// Full-bleed body. Receives the full screen constraints; the caller is
  /// responsible for reserving space for [appBar] inside.
  final Widget body;

  /// Passed to the wrapping [Material]. Pass `Colors.transparent` when the
  /// screen paints its own background (e.g. wallpaper).
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final appBar = this.appBar;
    return MonetMaterial(
      color: backgroundColor,
      child: appBar == null
          ? body
          : Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Match Scaffold's finite, theme-resolved app-bar constraint.
                  // In particular, an AppBar with a bottom uses a flex Column
                  // and cannot lay out under an unbounded Positioned height.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          AppBar.preferredHeightFor(
                            context,
                            appBar.preferredSize,
                          ) +
                          MediaQuery.paddingOf(context).top,
                    ),
                    child: appBar,
                  ),
                ),
              ],
            ),
    );
  }
}
