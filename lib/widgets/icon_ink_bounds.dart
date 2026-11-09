import 'package:flutter/foundation.dart';

/// Glyph ink coverage in the generated table's sampling units, in the icon's
/// square: x from the left, y from the top.
///
/// These are coordinates, not a Size: [left] and [top] are inclusive, and
/// [right] and [bottom] are exclusive.
@immutable
class IconInkBounds {
  const IconInkBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(left >= 0),
       assert(right >= left),
       assert(bottom >= top);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IconInkBounds &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'IconInkBounds(left: $left, top: $top, right: $right, bottom: $bottom)';
}
