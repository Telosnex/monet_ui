import 'package:flutter/foundation.dart';

/// Fixed-cardinality scalar counters. No image references, widget IDs, text,
/// stack traces, timers or per-frame logs. Counters survive in release and can
/// be differenced across navigation/theme ticks by the existing diagnostics.
/// Creation counts refer to deferred image requests, NOT GPU completion or RAM.
enum RasterCacheFamily { text, icon }

enum RasterCacheEvent {
  hit,
  miss,
  created,
  createdPixels,
  invalidatedImages,
  invalidatedPixels,
  generation,
  shadowShape,
  rasterScale,
  rasterPhase,
  budgetEviction,
  pairRebuild,
  assetRebuild,
  ownerDispose,
  rasterFailure,
  admissionDenied,
  layoutInputChanged,
  layoutInputUnchanged,
  strategyChanged,
  paintPolicyChanged,
  iconGeometryChanged,
  iconColorChanged,
  iconShadowChanged,
  iconCallbackChanged,
  systemFontsChanged,
  // Call/decision counters: not timings or estimates of GPU work saved.
  paintCalls,
  textStyleCalls,
  textStyleUnchanged,
  textStyleMaskReused,
  textStyleShadowReuse,
  paragraphRebuildCalls,
  layoutResultCalls,
  layoutCoverageReused,
  layoutSnapshotColorReuse,
  paintersCalls,
  paintersRebuilt,
  paintersReused,
  paintersUpdateReuse,
  // Rebuild classification is counted at actual work, not invalidation time.
  paragraphSameInput,
  paragraphDirectForced,
  paragraphDirectEmoji,
  paragraphDirectLongText,
  paragraphDirectStyle,
  paragraphDirectOther,
  paragraphCached,
  paragraphStrategyTransition,
  paragraphMaskToneChanged,
  directFallbackPaints,
  paragraphRebuildSkipped,
  emojiSplitPaints,
  emojiSplitBuilds,
  emojiAlphaBuilds,
  emojiSplitReused,
  emojiGeometryFallbacks,
  paragraphEmojiWithShadows,
  admissionMemoHit,
  admissionRecovered,
  paragraphNativePaintReused,
  directSpreadBuilt,
  directSpreadReused,
  directSpreadPaintReuse,
  emojiFillOnlyChanged,
  emojiShadowOnlyChanged,
  emojiFillAndShadowChanged,
  emojiOtherRebuild,
  // Icon paints against the icon's previous paint, while
  // MonetPerfDebugSwitches.classifyIconPaints is on. Moved: another paint
  // transform or device pixel ratio. Recolored: another fill, stroke or
  // shadow color.
  iconPaintFirst,
  iconPaintMoved,
  iconPaintMovedRecolored,
  iconPaintRecolored,
  iconPaintUnchanged,
  // What triggered an iconPaintUnchanged paint. Bus: the icon's own
  // paint-bus listener. RasterScale: the ancestor raster-scale signal.
  // Self: another mark of the icon (a setter, a boundary change, hot
  // reload). AncestorLayer: an ancestor-driven icon, repainted with its
  // ancestor's layer. Layer: any other icon, repainted with its layer.
  iconUnchangedByBus,
  iconUnchangedByRasterScale,
  iconUnchangedBySelf,
  iconUnchangedByAncestorLayer,
  iconUnchangedByLayer,
  // A paint-bus tick skipped: the icon's colors had not changed.
  iconBusTickSkipped,
}

/// Counts [RasterCacheEvent.iconUnchangedByLayer] paints by the layer that
/// repainted, named by its repaint boundary's widget and the app widgets
/// above it. Keys are capped at [maxOwners]. Later owners count as `other`.
/// Unlike [RasterCacheDiagnostics], this keeps strings: icons record only
/// while [MonetPerfDebugSwitches.classifyIconPaints] is on.
class LayerOwnerDiagnostics {
  const LayerOwnerDiagnostics._();

  static const maxOwners = 200;
  static const prefix = 'layerOwner.';
  static final _counts = <String, int>{};

  static void record(String owner) {
    final key = _counts.containsKey(owner) || _counts.length < maxOwners
        ? owner
        : 'other';
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  static Map<String, int> snapshot() => {
    for (final entry in _counts.entries) '$prefix${entry.key}': entry.value,
  };

  @visibleForTesting
  static void reset() => _counts.clear();
}

class RasterCacheDiagnostics {
  const RasterCacheDiagnostics._();

  static final _counts = List.generate(
    RasterCacheFamily.values.length,
    (_) => List.filled(RasterCacheEvent.values.length, 0),
  );

  static void record(
    RasterCacheFamily family,
    RasterCacheEvent event, [
    int count = 1,
  ]) {
    _familyCounts(family)[event.index] += count;
  }

  /// Only call for an existing image, not every invalidation notification.
  static void invalidated(
    RasterCacheFamily family,
    RasterCacheEvent reason,
    int pixels,
  ) {
    record(family, .invalidatedImages);
    record(family, .invalidatedPixels, pixels);
    record(family, reason);
  }

  // Adding counter enum members during hot reload keeps old static arrays.
  // Preserve existing totals while allocating the new slots once per family.
  static List<int> _familyCounts(RasterCacheFamily family) {
    final counts = _counts[family.index];
    final missing = RasterCacheEvent.values.length - counts.length;
    if (missing <= 0) return counts;
    return _counts[family.index] = [...counts, ...List.filled(missing, 0)];
  }

  static Map<String, int> snapshot() {
    final result = <String, int>{};
    for (final family in RasterCacheFamily.values) {
      final counts = _familyCounts(family);
      for (final event in RasterCacheEvent.values) {
        result['${family.name}.${event.name}'] = counts[event.index];
      }
    }
    return result;
  }

  static Map<String, int> since(Map<String, int> baseline) {
    final now = snapshot();
    return {
      for (final entry in now.entries)
        if (entry.value != (baseline[entry.key] ?? 0))
          entry.key: entry.value - (baseline[entry.key] ?? 0),
    };
  }
}
