import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';
import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';
import 'package:monet_ui/widgets/paint_transform_memo.dart';
import 'package:monet_ui/widgets/raster_cache_diagnostics.dart';
import 'package:monet_ui/widgets/rich_text/paint_strategy.dart';
import 'package:monet_ui/widgets/snapped_icons/icon_shadow.dart';

final _processLogger = PaintCacheReuseLogger();

/// Call only from app startup / hot reload, never a renderer. Widget tests
/// collect scalar counters without silently creating persistent timers.
void syncPaintCacheReuseLogging() {
  if (!kReleaseMode && MonetPerfDebugSwitches.logPaintCacheReuse) {
    _processLogger.start();
  } else {
    _processLogger.stop();
  }
}

/// One process-wide five-second report, with interval and cumulative counts.
/// No widget/image references, per-call clocks, strings or log allocations in
/// the hot path. Release builds retain the existing scalar diagnostics, but
/// never start this logger. Counts are decisions, NOT percent CPU time saved.
class PaintCacheReuseLogger {
  PaintCacheReuseLogger({
    void Function(String)? log,
    Map<String, int> Function()? snapshot,
  }) : _log = log ?? ((message) => logInfo(message)),
       _snapshotOverride = snapshot;

  final void Function(String) _log;
  final Map<String, int> Function()? _snapshotOverride;

  // Resolve the default at report time: the process logger survives hot reload
  // and must not retain the old diagnostics-only function tear-off forever.
  Map<String, int> _takeSnapshot() =>
      _snapshotOverride?.call() ?? _snapshotWithTextBudget();
  Timer? _timer;
  Map<String, int> _previous = const {};

  void start() {
    if (_timer != null) return;
    _previous = _takeSnapshot();
    _log(
      '[PaintCacheReuse] every 5s: skipped = reuse decisions; '
      'new-opt = subset newly saved by shadow/snapshot-color optimization. '
      'Percentages are of method calls, NOT CPU time. '
      'Image cache hits are separate and pre-existing. '
      'Totals are process counters: hot reload may add newer counters mid-run. '
      'Rebuild categories count actual work; same-input also includes skipped calls. '
      'Flags overlap; fallback paints are separate from rebuild calls. '
      'Budget rejections are actual requests, memo-skips reuse an earlier denial. '
      'Image creations are deferred requests, not GPU completions; pixels are '
      'image area, not bytes. Invalidation reasons count dropped images. '
      'Icon paint causes compare each paint with the same icon\'s previous '
      'paint: moved = other paint transform, recolored = other fill, stroke '
      'or shadow color. Paint transform steps are ancestor transforms '
      'applied; a walk to the root applies one per ancestor.',
    );
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _report());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _previous = const {};
  }

  void _report() {
    final total = _takeSnapshot();
    final interval = {
      for (final entry in total.entries)
        entry.key: entry.value - (_previous[entry.key] ?? 0),
    };
    _previous = total;
    _log(
      '[PaintCacheReuse]\n'
      '${_formatBudget(total)}\n'
      '${_formatCounts('last 5s', interval)}\n'
      '${_formatCounts('total', total)}',
    );
  }
}

Map<String, int> _snapshotWithTextBudget() {
  final budget = textMaskImageCacheStats;
  return {
    ...RasterCacheDiagnostics.snapshot(),
    ...PaintTransformMemo.snapshot(),
    ...LayerOwnerDiagnostics.snapshot(),
    'text.budgetBytes': budget.estimatedBytes,
    'text.budgetPeakBytes': budget.peakEstimatedBytes,
    'text.budgetLimit': budget.maxBytes,
    'text.budgetImageLimit': budget.maxImageBytes,
    'text.budgetImages': budget.imageCount,
    'text.budgetRejected': budget.rejections,
    'text.budgetRejectedImage': budget.perImageRejections,
    'text.budgetRejectedGroup': budget.groupRejections,
    'text.budgetRejectedVisible': budget.visibleSetRejections,
    'icon.vectorBlurIcons': IconVectorBlurCensus.icons,
    'icon.vectorBlurs': IconVectorBlurCensus.blurs,
  };
}

/// The three layers whose repaints repainted the most unchanged icons.
String _topLayerOwners(Map<String, int> counts) {
  const prefix = LayerOwnerDiagnostics.prefix;
  final owners = [
    for (final entry in counts.entries)
      if (entry.key.startsWith(prefix) && entry.value > 0) entry,
  ]..sort((a, b) => b.value.compareTo(a.value));
  if (owners.isEmpty) return 'none';
  return owners
      .take(3)
      .map((e) => '[${e.key.substring(prefix.length)}] ×${e.value}')
      .join(', ');
}

String _formatBudget(Map<String, int> total) {
  final bytes = total['text.budgetBytes'] ?? 0;
  final peakBytes = total['text.budgetPeakBytes'] ?? bytes;
  final limit = total['text.budgetLimit'] ?? 0;
  final limitLabel = limit < 0 ? 'unlimited' : '${(limit / 1024).round()}';
  final utilization = limit < 0 ? '' : ' (${_percent(bytes, limit)}%)';
  return '  text.budget NOW estimatedKiB=${(bytes / 1024).round()}/$limitLabel'
      '$utilization peakEstimatedKiB=${(peakBytes / 1024).round()} '
      'maxImageKiB=${((total['text.budgetImageLimit'] ?? 0) / 1024).round()} '
      'images=${total['text.budgetImages'] ?? 0}\n'
      '  icon.vectorBlurs NOW icons=${total['icon.vectorBlurIcons'] ?? 0} '
      'blurs=${total['icon.vectorBlurs'] ?? 0} '
      '(redone on every frame; 0 when icons use the shadow cache)';
}

String _formatCounts(String label, Map<String, int> counts) {
  int count(String key) => counts[key] ?? 0;
  String method(String name, String calls, String skipped, String newlySaved) {
    final total = count(calls);
    final reused = count(skipped);
    final saved = count(newlySaved);
    return '$name calls=$total skipped=$reused (${_percent(reused, total)}%) '
        'new-opt=$saved (${_percent(saved, total)}%)';
  }

  String images(String family) {
    final hits = count('$family.hit');
    final misses = count('$family.miss');
    return '$family.images checks=${hits + misses} hits=$hits '
        '(${_percent(hits, hits + misses)}%) misses=$misses '
        'created=${count('$family.created')} '
        'createdPixels=${count('$family.createdPixels')} '
        'invalidatedImages=${count('$family.invalidatedImages')} '
        'invalidatedPixels=${count('$family.invalidatedPixels')}';
  }

  String invalidations(String family) {
    return '$family.invalidations generation=${count('$family.generation')} '
        'shadowShape=${count('$family.shadowShape')} '
        'rasterScale=${count('$family.rasterScale')} '
        'budgetEviction=${count('$family.budgetEviction')} '
        'pairRebuild=${count('$family.pairRebuild')} '
        'assetRebuild=${count('$family.assetRebuild')} '
        'ownerDispose=${count('$family.ownerDispose')} '
        'rasterFailure=${count('$family.rasterFailure')}';
  }

  final transformCalls = count('transform.calls');
  final walked = transformCalls - count('transform.direct');
  final transformFrames = count('transform.frames');
  return '  $label: paints text=${count('text.paintCalls')} icon=${count('icon.paintCalls')}; '
      'text._rebuildParagraphInPlace calls=${count('text.paragraphRebuildCalls')} '
      'skipped=${count('text.paragraphRebuildSkipped')} '
      '(${_percent(count('text.paragraphRebuildSkipped'), count('text.paragraphRebuildCalls'))}%)\n'
      '    text.rebuilds direct[forced=${count('text.paragraphDirectForced')} '
      'emoji=${count('text.paragraphDirectEmoji')} '
      'long=${count('text.paragraphDirectLongText')} '
      'style=${count('text.paragraphDirectStyle')} '
      'other=${count('text.paragraphDirectOther')}] '
      'cached=${count('text.paragraphCached')}; '
      'flags[same-input=${count('text.paragraphSameInput')} '
      'strategy-change=${count('text.paragraphStrategyTransition')} '
      'mask-tone=${count('text.paragraphMaskToneChanged')}]\n'
      '    text.directReuse native-equivalent=${count('text.paragraphNativePaintReused')}; '
      'spread pictures built=${count('text.directSpreadBuilt')} '
      'reused=${count('text.directSpreadReused')} '
      'across-paint-changes=${count('text.directSpreadPaintReuse')}\n'
      '    text.directEmoji changes fill-only=${count('text.emojiFillOnlyChanged')} '
      'shadow-only=${count('text.emojiShadowOnlyChanged')} '
      'both=${count('text.emojiFillAndShadowChanged')} '
      'other=${count('text.emojiOtherRebuild')}\n'
      '    text.emojiSplit paints=${count('text.emojiSplitPaints')} '
      'built=${count('text.emojiSplitBuilds')} reused=${count('text.emojiSplitReused')} '
      '(${_percent(count('text.emojiSplitReused'), count('text.emojiSplitPaints'))}%) '
      'alpha-builds=${count('text.emojiAlphaBuilds')} '
      'geometry-fallbacks=${count('text.emojiGeometryFallbacks')}; '
      'direct-emoji-with-shadows=${count('text.paragraphEmojiWithShadows')}\n'
      '    text.directFallback paints=${count('text.directFallbackPaints')} '
      '(${_percent(count('text.directFallbackPaints'), count('text.paintCalls'))}% of text paints) '
      'rejected-requests=${count('text.budgetRejected')} '
      'memo-skips=${count('text.admissionMemoHit')} '
      'recovered=${count('text.admissionRecovered')} '
      'evicted-images=${count('text.budgetEviction')}\n'
      '    text.rejections per-image=${count('text.budgetRejectedImage')} '
      'group-too-large=${count('text.budgetRejectedGroup')} '
      'visible-set-full=${count('text.budgetRejectedVisible')}\n'
      '    ${method('text.textStyle', 'text.textStyleCalls', 'text.textStyleMaskReused', 'text.textStyleShadowReuse')} '
      'unchanged=${count('text.textStyleUnchanged')}\n'
      '    ${method('text._replaceLayoutResult', 'text.layoutResultCalls', 'text.layoutCoverageReused', 'text.layoutSnapshotColorReuse')}\n'
      '    ${method('icon._ensurePainters', 'icon.paintersCalls', 'icon.paintersReused', 'icon.paintersUpdateReuse')} '
      'rebuilt=${count('icon.paintersRebuilt')}\n'
      '    ${images('text')}\n'
      '    ${invalidations('text')}\n'
      '    ${images('icon')}\n'
      '    ${invalidations('icon')}\n'
      '    icon.paintCauses first=${count('icon.iconPaintFirst')} '
      'moved=${count('icon.iconPaintMoved')} '
      'moved+recolored=${count('icon.iconPaintMovedRecolored')} '
      'recolored=${count('icon.iconPaintRecolored')} '
      'unchanged=${count('icon.iconPaintUnchanged')}\n'
      '    icon.busTicksSkipped=${count('icon.iconBusTickSkipped')} '
      'unchangedBy bus=${count('icon.iconUnchangedByBus')} '
      'rasterScale=${count('icon.iconUnchangedByRasterScale')} '
      'self=${count('icon.iconUnchangedBySelf')} '
      'ancestorLayer=${count('icon.iconUnchangedByAncestorLayer')} '
      'layer=${count('icon.iconUnchangedByLayer')}\n'
      '    icon.layerOwners ${_topLayerOwners(counts)}\n'
      '    paintTransform trusted=${count('transform.trusted')} '
      'calls=$transformCalls '
      'direct=${count('transform.direct')} '
      'frames=$transformFrames '
      '(${_ratio(walked, transformFrames)}/frame) '
      'steps=${count('transform.steps')} '
      '(${_ratio(count('transform.steps'), walked)}/call)';
}

String _ratio(int count, int per) =>
    per == 0 ? '0' : (count / per).toStringAsFixed(1);

int _percent(int saved, int calls) =>
    calls == 0 ? 0 : (100 * saved / calls).round();
