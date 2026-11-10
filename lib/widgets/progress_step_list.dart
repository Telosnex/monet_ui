// ignore_for_file: prefer-single-widget-per-file

import 'dart:async';

import 'package:monet_ui/widgets/icon_size.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/semantic_colors.dart';
import 'package:monet_ui/widgets/tiny_spinner.dart';
import 'package:pixel_snap_fork/material.dart';

/// One step in a [ProgressStepList].
@immutable
class ProgressStep {
  final String label;

  /// How far the step is, such as "12 of 40". Shown only while it runs.
  final String? detail;

  /// How far the step is, from 0 to 1, shown as a bar under [detail]. Only
  /// shown while it runs.
  final double? fraction;

  /// The key of the step's row.
  final Key? key;

  const ProgressStep(this.label, {this.detail, this.fraction, this.key});
}

/// A checklist of steps that run in order: done steps are checked, the
/// running step spins, and steps not reached yet are dimmed.
///
/// If the running step shows no progress for [slowAfter], the list says it
/// is taking longer than usual. A new step, or a new [ProgressStep.detail],
/// restarts that clock.
class ProgressStepList extends StatefulWidget {
  static const defaultSlowAfter = Duration(seconds: 10);

  final List<ProgressStep> steps;

  /// The index of the running step. [steps]' length means every step is
  /// done.
  final int current;

  final Duration slowAfter;

  /// The key of the running step's label, a [Text].
  final Key? statusKey;

  /// The key of "Taking longer than usual…".
  final Key? slowKey;

  const ProgressStepList({
    super.key,
    required this.steps,
    required this.current,
    this.slowAfter = defaultSlowAfter,
    this.statusKey,
    this.slowKey,
  });

  @override
  State<ProgressStepList> createState() => _ProgressStepListState();
}

final class _ProgressStepListState extends State<ProgressStepList> {
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _startSlowTimer();
  }

  @override
  void didUpdateWidget(ProgressStepList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current == widget.current &&
        _detail(oldWidget) == _detail(widget)) {
      return;
    }
    // Flutter rebuilds after didUpdateWidget, so no setState is needed.
    _slow = false;
    _startSlowTimer();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  static String? _detail(ProgressStepList list) =>
      list.current < list.steps.length ? list.steps[list.current].detail : null;

  void _startSlowTimer() {
    _slowTimer?.cancel();
    if (widget.current >= widget.steps.length) return;
    _slowTimer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final success = SemanticColors.successPalette(context);
    final slot =
        iconSizeForTextStyleOrNull(Theme.of(context).textTheme.bodyLarge) ?? 16;
    Widget leading(int index) {
      if (index < current) {
        return MonetIcon(MonetIcons.check, size: slot, color: success.fill);
      }
      if (index == current) return const TinySpinner();
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        for (var index = 0; index < widget.steps.length; index++) ...[
          if (index > 0) const VerticalPaddingHalf(),
          Column(
            key: widget.steps[index].key,
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: slot,
                    child: Center(child: leading(index)),
                  ),
                  const HorizontalPadding(),
                  Flexible(
                    child: Opacity(
                      opacity: index > current ? 0.5 : 1,
                      child: Text(
                        widget.steps[index].label,
                        key: index == current ? widget.statusKey : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (index == current)
                Padding(
                  // Under the label, not the spinner.
                  padding: EdgeInsetsDirectional.only(
                    start: slot + HorizontalPadding.amount,
                  ),
                  child: _Progress(widget.steps[index]),
                ),
            ],
          ),
        ],
        if (_slow) ...[
          const VerticalPadding(),
          Text('Taking longer than usual…', key: widget.slowKey),
        ],
      ],
    );
  }
}

/// A running step's detail and progress bar, if it has them.
class _Progress extends StatelessWidget {
  final ProgressStep step;

  const _Progress(this.step);

  @override
  Widget build(BuildContext context) {
    final detail = step.detail;
    final fraction = step.fraction;
    return Column(
      crossAxisAlignment: .start,
      children: [
        if (detail != null)
          SizedBox(
            width: .infinity,
            child: Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (fraction != null)
          Padding(
            padding: const .only(top: VerticalPaddingHalf.amount),
            child: LinearProgressIndicator(value: fraction.clamp(0, 1)),
          ),
      ],
    );
  }
}
