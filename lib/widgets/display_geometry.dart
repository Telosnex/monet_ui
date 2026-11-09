import 'dart:ui' show FlutterView, Size;

/// Physical pixel size of the display the view is on.
///
/// Prefers [FlutterView.display] so a small window on a large monitor does not
/// masquerade as a small panel. Some embedders (flutter-pi) report an empty
/// display; there the view is fullscreen and its physical size is the panel.
Size? displayPhysicalPixels(FlutterView view) {
  final display = view.display.size;
  if (!display.isEmpty && display.width.isFinite && display.height.isFinite) {
    return display;
  }
  final window = view.physicalSize;
  if (!window.isEmpty && window.width.isFinite && window.height.isFinite) {
    return window;
  }
  return null;
}

/// Converts the platform's logical viewport to Telosnex's calibrated viewport.
Size calibratedLogicalSize(Size platformLogicalSize, double correction) {
  if (!correction.isFinite || correction <= 0) return platformLogicalSize;
  return platformLogicalSize / correction;
}
