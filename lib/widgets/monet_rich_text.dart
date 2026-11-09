import 'package:flutter/widgets.dart';

import 'package:monet_ui/widgets/ancestor_raster_scale.dart';
import 'package:monet_ui/widgets/rich_text/render_monet_rich_text.dart';

/// Bold weight when the platform asks for bold text, else null. [Text]
/// applies this itself; MonetRichText callers merge it into their
/// style.
TextStyle? boldTextStyleOf(BuildContext context) =>
    MediaQuery.boldTextOf(context) ? const .new(fontWeight: .bold) : null;

/// A text widget that guarantees trailing child widgets are never lost to
/// line-count truncation.
///
/// Unlike [Text.rich] with [WidgetSpan], where [maxLines] truncation can clip
/// trailing inline widgets, this widget reserves space for trailing children
/// on the last visible line and truncates only the text.
///
/// **Leading** children are laid out inline (via [PlaceholderSpan]) so text
/// wraps around them naturally.
///
/// **Inline** [WidgetSpan] children keep their paragraph position, alignment,
/// and baseline. Truncation removes their paint, hit testing, and semantics.
/// The inline widgets supply their own text scaling.
///
/// **Trailing** children are positioned immediately after the (possibly
/// truncated) text on the last line.
///
/// **End** children sit at the end edge of the box, centred on the last line,
/// however many lines there are. Every line is laid out narrower by their
/// width, so text never runs under them, and the box fills the width it is
/// given. Use them for a button that belongs beside the text, such as a menu.
class MonetRichText extends MultiChildRenderObjectWidget {
  MonetRichText({
    super.key,
    List<Widget> leading = const [],
    required String text,
    required this.textStyle,
    List<Widget> trailing = const [],
    List<Widget> end = const [],
    this.maxLines,
    this.ellipsis = '\u2026',
    this.textAlign = TextAlign.start,
    this.textScaler = TextScaler.noScaling,
    this.strutStyle,
    this.softWrap = true,
    this.selectionColor,
    this.paintColorListenable,
    this.paintColor,
    this.paintShadows,
    this.toneForTextMasking,
    this.paintDrivenByAncestor = false,
    this.preferDirectPaint = false,
    this.centerCapHeight = true,
    this.strokeColor,
    this.strokeWidth = 1,
    this.paintStrokeColor,
    this.paintStrokeWidth,
  }) : assert(
         toneForTextMasking == null ||
             (toneForTextMasking.isFinite &&
                 toneForTextMasking >= 0 &&
                 toneForTextMasking <= 100),
         'toneForTextMasking must be between 0 and 100.',
       ),
       textSpan = TextSpan(text: text),
       text = text,
       leadingCount = leading.length,
       endCount = end.length,
       inlineSpans = const [],
       super(children: [...leading, ...trailing, ...end]);

  MonetRichText.rich({
    super.key,
    List<Widget> leading = const [],
    required this.textSpan,
    required this.textStyle,
    List<Widget> trailing = const [],
    List<Widget> end = const [],
    this.maxLines,
    this.ellipsis = '\u2026',
    this.textAlign = TextAlign.start,
    this.textScaler = TextScaler.noScaling,
    this.strutStyle,
    this.softWrap = true,
    this.selectionColor,
    this.paintColorListenable,
    this.paintColor,
    this.paintShadows,
    this.toneForTextMasking,
    this.paintDrivenByAncestor = false,
    this.preferDirectPaint = false,
    this.centerCapHeight = true,
    this.strokeColor,
    this.strokeWidth = 1,
    this.paintStrokeColor,
    this.paintStrokeWidth,
  }) : assert(
         toneForTextMasking == null ||
             (toneForTextMasking.isFinite &&
                 toneForTextMasking >= 0 &&
                 toneForTextMasking <= 100),
         'toneForTextMasking must be between 0 and 100.',
       ),
       text = textSpan.toPlainText(
         includeSemanticsLabels: false,
         includePlaceholders: true,
       ),
       leadingCount = leading.length,
       endCount = end.length,
       inlineSpans = widgetSpansIn(textSpan),
       super(
         children: [
           ...leading,
           for (final span in widgetSpansIn(textSpan)) span.child,
           ...trailing,
           ...end,
         ],
       );

  /// Widget spans in text order. Their children occupy paragraph placeholders,
  /// unlike trailing children, which are reserved outside the paragraph.
  final List<WidgetSpan> inlineSpans;

  final InlineSpan textSpan;
  final String text;
  final TextStyle textStyle;
  final int? maxLines;
  final int leadingCount;

  /// Number of end children, the last [children].
  final int endCount;
  final String ellipsis;
  final TextAlign textAlign;
  final TextScaler textScaler;
  final StrutStyle? strutStyle;

  /// The colour used to paint selected text ranges when this widget is under
  /// a [SelectionArea].
  ///
  /// If null, falls back to [DefaultSelectionStyle.selectionColor], then to
  /// [DefaultSelectionStyle.defaultColor].
  final Color? selectionColor;

  /// Optional paint-only color source.
  ///
  /// When provided, the render object listens directly to this object and
  /// repaints/rebuilds its paragraph in-place when it changes. The widget tree
  /// does not rebuild and no layout is triggered. This is intended for fast
  /// animated palette channels such as `MonetPaintColors`; see Mod ADR 004.
  ///
  /// The listenable is separated from [paintColor]/[paintShadows] on purpose:
  /// the listenable answers "when did paint data change?", while the closures
  /// answer "what is the current paint data?" at paint time.
  final Listenable? paintColorListenable;

  /// Resolves the current paint color.
  ///
  /// This closure may be invoked during paint or in-place paragraph rebuilds,
  /// so keep it cheap and side-effect-free. It should usually read from a
  /// stable controller such as `MonetPaintColors.value` rather than call
  /// `MonetTheme.of(context)`.
  final Color Function()? paintColor;

  /// Resolves current paint-only text shadows.
  ///
  /// Like [paintColor], this lets wallpaper protection shadows follow the
  /// paint-color bus without rebuilding the widget tree or invalidating layout.
  /// Keep the shadow base paired with the palette that produced [paintColor]
  /// (for example `palette.text` with `palette.background`) so contrast remains
  /// intentional at black/white wallpaper seams.
  final List<Shadow> Function()? paintShadows;

  /// Optional stable tone used to choose the platform-specific glyph mask.
  ///
  /// Values use the usual perceptual tone range of 0 (black) through 100
  /// (white). When null, the mask tone is derived from the effective text
  /// color, preserving the default behavior. Supply this when foreground
  /// colors intentionally animate across light and dark tones; using the
  /// resting text tone avoids a mask swap when the animation settles.
  ///
  /// This affects only cached mask generation; it never changes the color
  /// ultimately used to paint the text.
  final double? toneForTextMasking;

  /// Prefer direct paragraph painting instead of cached image/mask strategies.
  ///
  /// Use this for scaled previews where vector text fidelity matters more than
  /// paint-bus throughput. Full-size runtime surfaces should usually leave this
  /// false so colour-only animation can use the cached mask paths.
  final bool preferDirectPaint;

  /// If true, an ancestor render object is responsible for listening to the
  /// paint bus and repainting this subtree.
  ///
  /// This avoids one listener/repaint-boundary per text leaf. During paint the
  /// render object lazily checks [paintColor]/[paintShadows] and rebuilds the
  /// paragraph only when those resolved values changed. Intended for dense
  /// composites such as `ListTileWithMenu`, where one tile-level repaint driver
  /// is cheaper than many leaf-level drivers.
  final bool paintDrivenByAncestor;

  /// Centres the font's capitals in the line box instead of its ascent and
  /// descent.
  ///
  /// Leading and trailing children are centred on the line box. Without this,
  /// text in fonts with uneven ascent and descent, such as caps-only fonts,
  /// sits above or below those children. The text moves inside the same box,
  /// so layout size does not change. Wrapped lines all move by the same
  /// amount. Fonts without a measured cap height are not moved.
  ///
  /// Defaults to true. Turn it off where text must share a baseline with
  /// text drawn by another widget in a different font.
  final bool centerCapHeight;

  /// When false, text is laid out on a single line (`maxLines` forced to 1)
  /// and truncated for trailing children. Matches the common "chip with
  /// trailing icon" shape; no horizontal overflow is produced either way.
  final bool softWrap;

  /// A stroke on the glyph edges, or null for none. Shadows paint under the
  /// stroke, and the stroke under the fill, as `MonetIcon`
  /// draw them. While the stroke and the shadows share one RGB, a colour
  /// animation reuses one cached underlay mask for both.
  final Color? strokeColor;

  /// The visible outer stroke's width in logical pixels. Defaults to 1.
  /// The renderer doubles it for the centered stroke under the fill.
  final double strokeWidth;

  /// The current stroke colour, read at paint time. Replaces [strokeColor].
  final Color Function()? paintStrokeColor;

  /// The current visible outer stroke width, read at paint time. Replaces
  /// [strokeWidth]. Notify [paintColorListenable] when it changes. Paint-only:
  /// a wider stroke does not change layout.
  final double Function()? paintStrokeWidth;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderMonetRichText(
      textSpan: textSpan,
      text: text,
      textStyle: textStyle,
      maxLines: maxLines,
      leadingCount: leadingCount,
      inlineSpans: inlineSpans,
      endCount: endCount,
      textDirection: Directionality.of(context),
      ellipsis: ellipsis,
      textAlign: textAlign,
      textScaler: textScaler,
      strutStyle: strutStyle,
      softWrap: softWrap,
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: _effectiveSelectionColor(context),
      paintColorListenable: paintColorListenable,
      paintColor: paintColor,
      paintShadows: paintShadows,
      toneForTextMasking: toneForTextMasking,
      paintDrivenByAncestor: paintDrivenByAncestor,
      preferDirectPaint: preferDirectPaint,
      centerCapHeight: centerCapHeight,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      paintStrokeColor: paintStrokeColor,
      paintStrokeWidth: paintStrokeWidth,
      ancestorRasterScaleSignal: AncestorRasterScaleScope.of(context),
    );
  }

  @override
  // textSpan/text are updated atomically by updateText so the render object
  // can decide whether the newly shaped paragraph changed geometry.
  // ignore: consistent-update-render-object
  void updateRenderObject(
    BuildContext context,
    RenderMonetRichText renderObject,
  ) {
    renderObject
      ..updateText(textSpan: textSpan, text: text)
      ..textStyle = textStyle
      ..maxLines = maxLines
      ..leadingCount = leadingCount
      ..inlineSpans = inlineSpans
      ..endCount = endCount
      ..textDirection = Directionality.of(context)
      ..ellipsis = ellipsis
      ..textAlign = textAlign
      ..textScaler = textScaler
      ..strutStyle = strutStyle
      ..softWrap = softWrap
      ..selectionRegistrar = SelectionContainer.maybeOf(context)
      ..selectionColor = _effectiveSelectionColor(context)
      ..paintColorListenable = paintColorListenable
      ..paintColor = paintColor
      ..paintShadows = paintShadows
      ..toneForTextMasking = toneForTextMasking
      ..paintDrivenByAncestor = paintDrivenByAncestor
      ..preferDirectPaint = preferDirectPaint
      ..centerCapHeight = centerCapHeight
      ..strokeWidth = strokeWidth
      ..strokeColor = strokeColor
      ..paintStrokeColor = paintStrokeColor
      ..paintStrokeWidth = paintStrokeWidth
      ..ancestorRasterScaleSignal = AncestorRasterScaleScope.of(context);
  }

  Color _effectiveSelectionColor(BuildContext context) {
    // getInheritedWidgetOfExactType, not DefaultSelectionStyle.of: read the
    // current selection color WITHOUT registering an inherited dependency.
    //
    // Material's Theme widget republishes DefaultSelectionStyle on every theme
    // publish, and its updateShouldNotify fires whenever selectionColor
    // changes -- which is every frame of wallpaper-driven theme animation.
    // Subscribing here made every visible text leaf (list tiles, button
    // labels) rebuild ~30x/s during theme motion for a highlight most text
    // doesn't have active.
    //
    // Tradeoff: an active selection's highlight tint lags the animating theme
    // until this widget next rebuilds (selection remains fully functional;
    // registration via SelectionContainer.maybeOf is unchanged, and the
    // registrar's identity is stable so that dependency never fires during
    // animation). A settled theme refreshes the tint on the next rebuild of
    // this text, e.g. any config/typography change.
    return selectionColor ??
        context
            .getInheritedWidgetOfExactType<DefaultSelectionStyle>()
            ?.selectionColor ??
        DefaultSelectionStyle.defaultColor;
  }
}

/// Inline widgets in paragraph order, including nested span trees.
List<WidgetSpan> widgetSpansIn(InlineSpan span) => switch (span) {
  WidgetSpan() => [span],
  TextSpan() => [
    for (final child in span.children ?? const <InlineSpan>[])
      ...widgetSpansIn(child),
  ],
  _ => const [],
};
