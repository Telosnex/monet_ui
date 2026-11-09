import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:loggy/loggy.dart';

/// How icons and text find their place on the device-pixel grid at paint.
enum PaintPlacement {
  /// Read the full paint transform (`getTransformTo(null)`) at each paint.
  /// Correct under any scroll offset, transform or unsnapped widget, and
  /// costs a walk to the root (ADR 002, D7).
  measured,

  /// Trust layout, as pixel_snap does: take the paint offset to be on the
  /// device-pixel grid, and the scale to be the view's ratio times the
  /// declared ancestor raster scale. No walk. A fractional scroll offset,
  /// an unsnapped widget or an undeclared transform above puts a snapped
  /// edge off the grid, and nothing reports it.
  trustLayout,
}

/// Runtime switches for bisecting Monet/theme paint optimizations.
///
/// These are intentionally static, source-level switches rather than user
/// settings. Flip the `return false` literals below and hot reload to separate
/// ordinary product bugs from bugs caused by paint-bus throttling or cached
/// mask/image rendering.
class MonetPerfDebugSwitches {
  const MonetPerfDebugSwitches._();

  /// Disable paint-bus theme throttling for RenderUi surfaces.
  ///
  /// When true, RenderUi palette resolution prefers inherited `MonetTheme`
  /// rebuilds over `MonetPaintColors.value` snapshots, and debounced TextInput
  /// retheming becomes immediate. This is slower/noisier but useful when
  /// checking whether stale UI came from avoiding widget rebuilds.
  ///
  /// Implemented as a getter so changing the literal below takes effect on hot
  /// reload. Static field initializers are not reliable for this use case
  /// because the existing field value can survive reload.
  static bool get disableThemeThrottling => false;

  /// Disable no-background wallpaper-theme target throttling.
  ///
  /// When false, `WallpaperPositionedTheme` coalesces fast scroll/layout theme
  /// target changes to reduce retarget churn. Flip to true if no-bg colours
  /// visibly ease toward stale targets and then jump to the final sampled
  /// palette.
  static bool get disableWallpaperThemeTargetThrottling => false;

  /// Disable cached image/mask rendering paths for text and icons.
  ///
  /// When true, `MonetRichText` avoids DPR mask tint strategies. This is
  /// much slower but useful when checking whether artifacts or stale colours
  /// are caused by cached raster assets. Icons draw vector paths and keep no
  /// raster assets.
  ///
  /// Implemented as a getter so changing the literal below takes effect on hot
  /// reload. Static field initializers are not reliable for this use case
  /// because the existing field value can survive reload.
  static bool get disableCachedRendering => false;

  /// Reuse native-equivalent direct paragraphs and unchanged spread pictures.
  /// No emoji recoloring or raster-cache/budget changes. Flip for an A/B run.
  static bool get reuseDirectTextPaint => directTextPaintReuseOverride ?? true;

  @visibleForTesting
  static bool? directTextPaintReuseOverride;

  /// EXPERIMENTAL: keep native-colour emoji separate from a tinted text mask.
  /// No-shadow, plain labels only; off until app/font fallback is validated.
  /// Colour-font shadows deliberately remain direct. A font that supplies
  /// monochrome glyphs for emoji-presentation characters needs direct painting.
  /// Hot reload after changing this getter; no libmonet changes are involved.
  static bool get enableSplitEmojiTextTint =>
      splitEmojiTextTintOverride ?? false;

  @visibleForTesting
  static bool? splitEmojiTextTintOverride;

  /// How icons and text find where they land on the pixel grid. Flip and hot
  /// reload to compare: hot reload repaints everything.
  static PaintPlacement get paintPlacement =>
      paintPlacementOverride ?? .measured;

  @visibleForTesting
  static PaintPlacement? paintPlacementOverride;

  /// Keep ancestor paint transforms for the rest of a frame's paint phase
  /// (`paintTransformToView`). Icons and text that share ancestors then
  /// walk each shared ancestor once per frame. Flip for an A/B run.
  static bool get memoizePaintTransforms => paintTransformMemoOverride ?? true;

  /// Skip an icon's paint-bus tick when the colors it would paint equal the
  /// colors it last painted. Flip for an A/B run.
  static bool get skipSameColorBusTicks => sameColorBusSkipOverride ?? true;

  @visibleForTesting
  static bool? sameColorBusSkipOverride;

  @visibleForTesting
  static bool? paintTransformMemoOverride;

  /// Count each icon paint as first, moved, recolored or unchanged against
  /// the icon's previous paint, for [logPaintCacheReuse]. Costs one
  /// comparison of transform and colors per icon paint.
  static bool get classifyIconPaints =>
      iconPaintClassificationOverride ?? (!kReleaseMode && logPaintCacheReuse);

  @visibleForTesting
  static bool? iconPaintClassificationOverride;

  /// Log no-background wallpaper theme animation lifecycle with a MEN_AT_WORK
  /// tag.
  ///
  /// This logs target theme changes from `WallpaperPositionedTheme`, plus the
  /// downstream `MonetPaintColors` ticks under `AnimatedMonetTheme`. Use it to
  /// tell whether a visual snap is caused by remounting/key churn, missing paint
  /// bus ticks, or a target update arriving all at once.
  static bool get logWallpaperThemeAnimation => false;

  /// Optional widget id filter for [logWallpaperThemeAnimation].
  ///
  /// Set this to a mod/widget id from `sample.json` to avoid logs from every
  /// no-background widget, e.g. `'019dbd57-ccfe-7052-930b-ba903834bfc0'`.
  /// Leave null to log all wallpaper-positioned themes.
  // ignore: avoid-unnecessary-nullable-return-type
  static String? get wallpaperThemeAnimationLogWidgetId =>
      'b869cf0c-c225-4b40-b140-ee13ff1fe486';

  /// Five-second text/icon call, reuse and newly-saved-work summaries.
  /// Disabled by default. Flip true and hot reload while profiling paint caches.
  static bool get logPaintCacheReuse => false;

  /// Log cached text image geometry from `header/paint_strategy.dart`.
  ///
  /// Flip this while debugging scaled previews. It logs image dimensions, DPR,
  /// source rects, destination rects, and offsets for both the foreground mask
  /// and layered shadow image draws.
  static bool get logCachedTextImageRects => false;

  /// Log text-mask image rejections from the process-wide byte budget.
  static bool get logCachedTextImageBudget => false;

  /// Log the inherited-widget dependency list of list-tile leaf widgets
  /// (MonetRichText / MonetIcon / Material) whenever the framework
  /// rebuilds them. Used to answer "which InheritedWidget woke all 22 visible
  /// tiles on a theme publish frame?" when rebuild attribution shows them as
  /// roots (their parents did not rebuild).
  ///
  /// Flip to true + hot reload, repro the animation, then read the
  /// `[TileRebuildDeps]` log lines. Capped to avoid drowning the log.
  static bool get logListTileRebuildDependencies => false;

  static int _rebuildDepLogCount = 0;
  static bool _rebuildDepCapLogged = false;
  static DateTime? _lastRebuildDepLogAt;
  static const _rebuildDepLogCap = 300;
  static const _rebuildDepBurstGap = Duration(milliseconds: 750);

  /// Re-asserted on every ListTileTypographyScope build (cheap identity
  /// check) rather than installed once: the widget inspector's
  /// trackRebuildDirtyWidgets service extension *overwrites*
  /// [debugOnRebuildDirtyWidget] when DevTools toggles rebuild tracking
  /// (`= _onRebuildWidget` on enable, `= null` on disable), silently wiping
  /// any hook installed before a DevTools session. Chaining whatever is
  /// present at (re)install time keeps inspector tracking working when it was
  /// enabled first.
  ///
  /// Known tradeoff: if DevTools enables rebuild tracking *while* this hook
  /// is installed, the inspector asserts `debugOnRebuildDirtyWidget == null`
  /// and refuses. Flip [logListTileRebuildDependencies] off (hot reload)
  /// before capturing rebuild-count profiles.
  static void installListTileRebuildDependencyLogger() {
    if (!kDebugMode) return;
    if (identical(debugOnRebuildDirtyWidget, _logTileRebuildDeps)) return;
    _chainedRebuildHook = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _logTileRebuildDeps;
    logDebug(
      '[TileRebuildDeps] logger installed '
      '(chained: ${_chainedRebuildHook != null})',
    );
  }

  static RebuildDirtyWidgetCallback? _chainedRebuildHook;

  static void _logTileRebuildDeps(Element element, bool builtOnce) {
    _chainedRebuildHook?.call(element, builtOnce);
    if (!logListTileRebuildDependencies) return;

    final type = element.widget.runtimeType.toString();
    const interesting = {'MonetRichText', 'MonetIcon', 'Material'};
    if (!interesting.contains(type)) return;

    // The hot-reload / initial-layout burst can be huge. Make the cap per burst
    // instead of per process so it cannot consume the whole session before the
    // user starts dragging the wallpaper.
    final now = DateTime.now();
    if (_lastRebuildDepLogAt == null ||
        now.difference(_lastRebuildDepLogAt!) > _rebuildDepBurstGap) {
      _rebuildDepLogCount = 0;
      _rebuildDepCapLogged = false;
    }
    _lastRebuildDepLogAt = now;

    if (_rebuildDepLogCount >= _rebuildDepLogCap) {
      if (!_rebuildDepCapLogged) {
        _rebuildDepCapLogged = true;
        logDebug('[TileRebuildDeps] burst cap reached; suppressing until idle');
      }
      return;
    }
    _rebuildDepLogCount++;

    String deps = '(none reported)';
    for (final property in element.toDiagnosticsNode().getProperties()) {
      if (property.name == 'dependencies') {
        deps = property.toDescription();
        break;
      }
    }
    logDebug(
      '[TileRebuildDeps] #$_rebuildDepLogCount $type '
      'builtOnce=$builtOnce key=${element.widget.key} deps=$deps '
      'chain=${element.debugGetCreatorChain(8)}',
    );
  }

  /// Called from the custom app binding on hot reload so switch flips are visible
  /// in logs immediately after reassemble.
  static void logHotReloadState() {
    logDebug(
      '[MonetPerfDebugSwitches] hot reload: '
      'disableThemeThrottling=$disableThemeThrottling, '
      'disableWallpaperThemeTargetThrottling=$disableWallpaperThemeTargetThrottling, '
      'disableCachedRendering=$disableCachedRendering, '
      'reuseDirectTextPaint=$reuseDirectTextPaint, '
      'enableSplitEmojiTextTint=$enableSplitEmojiTextTint, '
      'paintPlacement=${paintPlacement.name}, '
      'memoizePaintTransforms=$memoizePaintTransforms, '
      'skipSameColorBusTicks=$skipSameColorBusTicks, '
      'classifyIconPaints=$classifyIconPaints, '
      'logWallpaperThemeAnimation=$logWallpaperThemeAnimation, '
      'wallpaperThemeAnimationLogWidgetId=$wallpaperThemeAnimationLogWidgetId, '
      'logPaintCacheReuse=$logPaintCacheReuse, '
      'logCachedTextImageRects=$logCachedTextImageRects, '
      'logCachedTextImageBudget=$logCachedTextImageBudget',
    );
  }
}
