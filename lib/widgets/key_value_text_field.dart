import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/auto_save_text_field.dart';
import 'package:monet_ui/widgets/monet_handedness.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/monet_tooltip.dart';
import 'package:monet_ui/widgets/monet_tooltip_icon.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/screen_breakpoints.dart';
import 'package:monet_ui/widgets/semantic_colors.dart';
import 'package:monet_ui/widgets/text_field_input_decoration.dart';
import 'package:monet_ui/widgets/theme_selection.dart';

/// A robust key/value text field component for editing `Map<String, String>` pairs.
///
/// Features:
/// - Auto-save text synchronization without cursor jumping
/// - Consistent theming with TextFieldRow
/// - Flexible layout (row/column based on screen size)
/// - Tooltips and accessibility
/// - Validation and error handling
/// - Customizable hints and labels
class KeyValueTextField extends HookWidget {
  final String label;
  final String tooltip;
  final String keyValue;
  final String valueValue;
  final Function(String key, String value) onChanged;
  final String keyHint;
  final String valueHint;
  final String keyLabel;
  final String valueLabel;
  final bool readOnly;
  final bool forceSmallWidth;
  final Color? labelColor;
  final Palette? colors;
  final VoidCallback? onSubmitted;
  final VoidCallback? onFocusLost;
  final String? Function(String)? keyValidator;
  final String? Function(String)? valueValidator;
  final Widget? suffixIcon;
  final bool showLabels;

  const KeyValueTextField({
    super.key,
    required this.label,
    required this.tooltip,
    required this.keyValue,
    required this.valueValue,
    required this.onChanged,
    this.keyHint = 'Key',
    this.valueHint = 'Value',
    this.keyLabel = 'Key',
    this.valueLabel = 'Value',
    this.readOnly = false,
    this.forceSmallWidth = false,
    this.labelColor,
    this.colors,
    this.onSubmitted,
    this.onFocusLost,
    this.keyValidator,
    this.valueValidator,
    this.suffixIcon,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final keyFocusNode = useFocusNode();
    final valueFocusNode = useFocusNode();

    final keyError = useState<String?>(null);
    final valueError = useState<String?>(null);
    final currentKeyValue = useState(keyValue);
    final currentValueValue = useState(valueValue);

    // Sync state with external props when they change
    // ignore: function-always-returns-null
    useEffect(() {
      currentKeyValue.value = keyValue;
      return null;
    }, [keyValue]);

    // ignore: function-always-returns-null
    useEffect(() {
      currentValueValue.value = valueValue;
      return null;
    }, [valueValue]);

    // Handle focus changes for validation
    useEffect(
      () {
        void keyFocusListener() {
          if (!keyFocusNode.hasFocus) {
            final error = keyValidator?.call(currentKeyValue.value);
            keyError.value = error;
            if (onFocusLost != null) onFocusLost!();
          }
        }

        void valueFocusListener() {
          if (!valueFocusNode.hasFocus) {
            final error = valueValidator?.call(currentValueValue.value);
            valueError.value = error;
            if (onFocusLost != null) onFocusLost!();
          }
        }

        keyFocusNode.addListener(keyFocusListener);
        valueFocusNode.addListener(valueFocusListener);

        return () {
          keyFocusNode.removeListener(keyFocusListener);
          valueFocusNode.removeListener(valueFocusListener);
        };
      },
      [keyFocusNode, valueFocusNode, keyValidator, valueValidator, onFocusLost],
    );

    void handleKeyChanged(String newKey) {
      currentKeyValue.value = newKey;
      keyError.value = keyValidator?.call(newKey);
      onChanged(newKey, currentValueValue.value);
    }

    void handleValueChanged(String newValue) {
      currentValueValue.value = newValue;
      valueError.value = valueValidator?.call(newValue);
      onChanged(currentKeyValue.value, newValue);
    }

    void handleSubmit() {
      final keyErr = keyValidator?.call(currentKeyValue.value);
      final valueErr = valueValidator?.call(currentValueValue.value);
      keyError.value = keyErr;
      valueError.value = valueErr;

      if (keyErr == null && valueErr == null && onSubmitted != null) {
        onSubmitted!();
      }
    }

    final isSmall =
        ScreenBreakpoints.isScreenSmallWidth(context) || forceSmallWidth;
    final handededness = MonetHandedness.of(context);
    final effectiveColors = colors ?? MonetTheme.of(context).primary;

    final labelWidget = label.isEmpty
        ? SizedBox()
        : MonetTooltip(
            colors: effectiveColors,
            content: Text(tooltip),
            // Unconstrained width, as compared to other controls, because the
            // label is always on its own row.
            child: Row(
              mainAxisSize: .min,
              mainAxisAlignment: .start,
              children: [
                Text(
                  label,
                  style: labelColor == null
                      ? Theme.of(context).textTheme.labelMedium
                      : Theme.of(context).textTheme.labelMedium!
                            .copyWith(color: labelColor),
                ),
                HorizontalPaddingHalf(),
                if (labelColor == null)
                  const MonetTooltipIcon.fixed()
                else
                  MonetTooltipIcon.customColor(color: labelColor!),
              ],
            ),
          );

    // Determine if we should use row layout for the text fields.
    final useRowLayout = !isSmall;

    final keyValueFields = ThemeSelection(
      colors: colors,
      child: useRowLayout
          ? _buildRowLayout(
              context,
              effectiveColors,
              keyFocusNode,
              valueFocusNode,
              handleKeyChanged,
              handleValueChanged,
              handleSubmit,
              keyError.value,
              valueError.value,
              currentKeyValue.value,
              currentValueValue.value,
            )
          : _buildColumnLayout(
              context,
              effectiveColors,
              keyFocusNode,
              valueFocusNode,
              handleKeyChanged,
              handleValueChanged,
              handleSubmit,
              keyError.value,
              valueError.value,
              currentKeyValue.value,
              currentValueValue.value,
            ),
    );

    if (isSmall) {
      return Column(
        crossAxisAlignment: handededness == .right ? .end : .start,
        children: [labelWidget, keyValueFields],
      );
    }

    final flexibleFields = Flexible(child: keyValueFields);
    return Column(
      crossAxisAlignment: .start,
      children: [
        labelWidget,
        Row(
          mainAxisAlignment: handededness == .right ? .start : .end,
          children: [flexibleFields],
        ),
      ],
    );
  }

  Widget _buildRowLayout(
    BuildContext context,
    Palette effectiveColors,
    FocusNode keyFocusNode,
    FocusNode valueFocusNode,
    Function(String) handleKeyChanged,
    Function(String) handleValueChanged,
    VoidCallback handleSubmit,
    String? keyError,
    String? valueError,
    String currentKeyValue,
    String currentValueValue,
  ) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        if (showLabels) ...[
          Row(
            children: [
              // Slight indent to distinguish from header label
              HorizontalPaddingHalf(),
              SizedBox(
                width: ScreenBreakpoints.screenMinColumnWidth,
                child: Text(
                  keyLabel,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: effectiveColors.backgroundText),
                ),
              ),
              // Cover area between text fields.
              HorizontalPadding(),
              // Duplicate slight indent for key label for value label
              HorizontalPaddingHalf(),
              Expanded(
                child: Text(
                  valueLabel,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: effectiveColors.backgroundText),
                ),
              ),
            ],
          ),
          // Space between labels and text fields
          VerticalPaddingHalf(),
        ],
        Row(
          crossAxisAlignment: .start,
          children: [
            SizedBox(
              width: ScreenBreakpoints.screenMinColumnWidth,
              child: AutoSaveTextField(
                // At the time this was added, [KeyValueTextField] was used
                // for HTTP headers and environment variables, which both do not
                // require autocorrect.
                entryType: .textNoAutocorrect,
                externalText: currentKeyValue,
                onTextChanged: handleKeyChanged,
                focusNode: keyFocusNode,
                decoration: TFID
                    .get(context, effectiveColors)
                    .copyWith(
                      hintText: keyHint,
                      errorText: keyError,
                      contentPadding: const .symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  color: effectiveColors.backgroundText,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
                readOnly: readOnly,
                onSubmitted: (_) {
                  valueFocusNode.requestFocus();
                },
              ),
            ),
            HorizontalPadding(),
            Expanded(
              child: AutoSaveTextField(
                externalText: currentValueValue,
                onTextChanged: handleValueChanged,
                focusNode: valueFocusNode,
                decoration: TFID
                    .get(context, effectiveColors)
                    .copyWith(
                      hintText: valueHint,
                      errorText: valueError,
                      suffixIcon: suffixIcon,
                      contentPadding: const .symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  color: effectiveColors.backgroundText,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
                readOnly: readOnly,
                onSubmitted: (_) => handleSubmit(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColumnLayout(
    BuildContext context,
    Palette effectiveColors,
    FocusNode keyFocusNode,
    FocusNode valueFocusNode,
    Function(String) handleKeyChanged,
    Function(String) handleValueChanged,
    VoidCallback handleSubmit,
    String? keyError,
    String? valueError,
    String currentKeyValue,
    String currentValueValue,
  ) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        if (showLabels) ...[
          Padding(
            // Slight indent to distinguish from header label
            padding: const .only(left: HorizontalPaddingHalf.amount),
            child: Text(
              keyLabel,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: effectiveColors.backgroundText),
            ),
          ),
          VerticalPaddingHalf(),
        ],
        AutoSaveTextField(
          externalText: currentKeyValue,
          onTextChanged: handleKeyChanged,
          focusNode: keyFocusNode,
          decoration: TFID
              .get(context, effectiveColors)
              .copyWith(
                hintText: keyHint,
                errorText: keyError,
                contentPadding: const .symmetric(horizontal: 12, vertical: 12),
              ),
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
            color: effectiveColors.backgroundText,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
          readOnly: readOnly,
          onSubmitted: (_) {
            valueFocusNode.requestFocus();
          },
        ),
        VerticalPadding(),
        if (showLabels) ...[
          Padding(
            // Indent slightly so it is under the overall section label.
            padding: const .only(left: HorizontalPaddingHalf.amount),
            child: Text(
              valueLabel,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: effectiveColors.backgroundText),
            ),
          ),
          VerticalPaddingHalf(),
        ],
        AutoSaveTextField(
          externalText: currentValueValue,
          onTextChanged: handleValueChanged,
          focusNode: valueFocusNode,
          decoration: TFID
              .get(context, effectiveColors)
              .copyWith(
                hintText: valueHint,
                errorText: valueError,
                suffixIcon: suffixIcon,
                contentPadding: const .symmetric(horizontal: 12, vertical: 12),
              ),
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
            color: effectiveColors.backgroundText,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
          readOnly: readOnly,
          onSubmitted: (_) => handleSubmit(),
        ),
      ],
    );
  }
}

/// A complete key/value pair management widget that handles a
/// `Map<String, String>` with add/remove functionality.
// ignore: prefer-single-widget-per-file
class KeyValueMapField extends HookWidget {
  final String label;
  final String tooltip;
  final Map<String, String> keyValuePairs;
  final Function(String key, String value) onAdd;
  final Function(String key) onRemove;
  final void Function(String oldKey, String newKey, String newValue) onUpdate;
  final String keyHint;
  final String valueHint;
  final bool forceSmallWidth;
  final Color? labelColor;
  final Palette? colors;
  final String? Function(String)? keyValidator;
  final String? Function(String)? valueValidator;
  final IconData? icon;

  const KeyValueMapField({
    super.key,
    required this.label,
    required this.tooltip,
    required this.keyValuePairs,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
    this.keyHint = 'Key',
    this.valueHint = 'Value',
    this.forceSmallWidth = false,
    this.labelColor,
    this.colors,
    this.keyValidator,
    this.valueValidator,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // Row identity follows a local rename even if the caller removes and
    // appends the map entry, moving its position in insertion order.
    final rowKeys = useRef(<String, Key>{});
    rowKeys.value.removeWhere((key, _) => !keyValuePairs.containsKey(key));
    for (final key in keyValuePairs.keys) {
      rowKeys.value.putIfAbsent(key, UniqueKey.new);
    }
    final newKey = useState('');
    final newValue = useState('');
    final resetKey = useState(0); // Used to force widget rebuild
    final effectiveColors = colors ?? MonetTheme.of(context).primary;

    String? validateKey(String key, {String? existingKey}) {
      if (key != existingKey && keyValuePairs.containsKey(key)) {
        return 'Key already exists';
      }
      return keyValidator?.call(key);
    }

    void handleAdd() {
      final key = newKey.value.trim();
      // rationale: clarity
      // ignore: move-variable-closer-to-its-usage
      final value = newValue.value.trim();

      if (key.isNotEmpty) {
        final keyError = validateKey(key);
        final valueError = valueValidator?.call(value);

        if (keyError == null && valueError == null) {
          onAdd(key, value);
          newKey.value = '';
          newValue.value = '';
          // Force widget rebuild to reset text fields
          resetKey.value = resetKey.value + 1;
        }
      }
    }

    final bool hasExistingPairs = keyValuePairs.isNotEmpty;

    final newPair = KeyValueTextField(
      key: ValueKey('new_pair_${resetKey.value}'),
      label: '',
      tooltip: tooltip,
      keyValue: newKey.value,
      valueValue: newValue.value,
      onChanged: (key, value) {
        newKey.value = key;
        newValue.value = value;
      },
      keyHint: keyHint,
      valueHint: valueHint,
      showLabels: false,
      forceSmallWidth: forceSmallWidth,
      labelColor: labelColor,
      colors: colors,
      keyValidator: (key) => validateKey(key.trim()),
      valueValidator: valueValidator,
      onSubmitted: handleAdd,
      suffixIcon: IconButton(
        icon: const MonetIcon(MonetIcons.add),
        onPressed: handleAdd,
        tooltip: 'Add entry',
        style: iconButtonStyle(SemanticColors.successPalette(context)).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(0, 0)),
          fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
        ),
      ),
    );

    final Widget existingPairs;
    if (!hasExistingPairs) {
      existingPairs = SizedBox();
    } else {
      existingPairs = Column(
        children: keyValuePairs.entries
            .map(
              (entry) => KeyValueTextField(
                key: rowKeys.value[entry.key],
                label: '', // No individual labels needed
                tooltip: 'Edit ${entry.key}',
                keyValue: entry.key,
                valueValue: entry.value,
                showLabels: false, // Already shown in container header
                onChanged: (newKey, newValue) {
                  if (newKey != entry.key) {
                    // Keep a conflicting rename (and its value) in the row's
                    // local draft until the user enters a unique key.
                    if (keyValuePairs.containsKey(newKey)) return;
                    final identity = rowKeys.value.remove(entry.key);
                    if (identity != null) rowKeys.value[newKey] = identity;
                  }
                  onUpdate(entry.key, newKey, newValue);
                },
                suffixIcon: IconButton(
                  icon: const MonetIcon(MonetIcons.remove),
                  style: iconButtonStyle(
                    SemanticColors.errorPalette(
                      context,
                      bgColor: effectiveColors.background,
                    ),
                  ),
                  tooltip: 'Remove ${entry.key}',
                  onPressed: () => onRemove(entry.key),
                ),
                keyValidator: (key) => validateKey(key, existingKey: entry.key),
                valueValidator: valueValidator,
                colors: colors,
                forceSmallWidth: forceSmallWidth,
              ),
            )
            .expand((widget) => [widget, const VerticalPaddingHalf()])
            .take(keyValuePairs.length * 2 - 1)
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: .start,
      children: [
        MonetTooltip(
          colors: effectiveColors,
          content: Text(tooltip),
          // Unconstrained width, as compared to other controls, because the
          // label is always on its own row.
          child: Row(
            mainAxisSize: .min,
            mainAxisAlignment: .start,
            children: [
              Text(
                label,
                style: labelColor == null
                    ? Theme.of(context).textTheme.labelMedium
                    : Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: labelColor),
              ),
              HorizontalPaddingHalf(),
              if (labelColor == null)
                const MonetTooltipIcon.fixed()
              else
                MonetTooltipIcon.customColor(color: labelColor!),
            ],
          ),
        ),
        // Existing pairs list
        if (hasExistingPairs) ...[existingPairs, VerticalPadding()],
        newPair,
      ],
    );
  }
}
