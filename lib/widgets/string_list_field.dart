import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:monet_ui/theming/button_style.dart';
import 'package:monet_ui/theming/monet_theme.dart';
import 'package:monet_ui/theming/palette.dart';
import 'package:monet_ui/widgets/auto_save_text_field.dart';
import 'package:monet_ui/widgets/control_row_header.dart';
import 'package:monet_ui/widgets/monet_icon.dart';
import 'package:monet_ui/widgets/monet_icons.dart';
import 'package:monet_ui/widgets/padding.dart';
import 'package:monet_ui/widgets/semantic_colors.dart';
import 'package:monet_ui/widgets/text_field_input_decoration.dart';
import 'package:monet_ui/widgets/theme_selection.dart';

/// A robust string list field component for editing `List<String>` values.
///
/// Features:
/// - Auto-save text synchronization without cursor jumping
/// - Consistent theming with TextFieldRow
/// - Drag-and-drop reordering
/// - Add/remove functionality
/// - Tooltips and accessibility
/// - Validation and error handling
/// - Customizable hints and labels
class StringListField extends HookWidget {
  final String label;
  final String tooltip;
  final List<String> values;
  final Function(List<String>) onChanged;
  final String itemHint;
  final String newItemLabel;
  final bool readOnly;
  final Color? labelColor;
  final Palette? colors;
  final String? Function(String)? itemValidator;
  final bool allowReordering;
  final bool showContainer;
  final String emptyStateText;

  const StringListField({
    super.key,
    required this.label,
    required this.tooltip,
    required this.values,
    required this.onChanged,
    this.itemHint = 'Enter value',
    this.newItemLabel = 'New Item',
    this.readOnly = false,
    this.labelColor,
    this.colors,
    this.itemValidator,
    this.allowReordering = true,
    this.showContainer = true,
    this.emptyStateText = 'No items defined',
  });

  @override
  Widget build(BuildContext context) {
    final newItemText = useState('');
    final resetKey = useState(0); // Used to force widget rebuild
    final theme = MonetTheme.of(context);
    final effectiveColors = colors ?? theme.primary;

    void addItem() {
      if (newItemText.value.trim().isEmpty) return;

      final trimmedValue = newItemText.value.trim();
      final error = itemValidator?.call(trimmedValue);

      if (error == null) {
        final newValues = [...values, trimmedValue];
        onChanged(newValues);
        newItemText.value = '';
        // Force widget rebuild to reset text field
        resetKey.value = resetKey.value + 1;
      }
    }

    void removeItem(int index) {
      final newValues = List.of(values);
      newValues.removeAt(index);
      onChanged(newValues);
    }

    void updateItem(int index, String newValue) {
      final newValues = List.of(values);
      newValues[index] = newValue.trim();
      onChanged(newValues);
    }

    void reorderItems(int oldIndex, int newIndex) {
      if (readOnly || !allowReordering) return;

      final newValues = List.of(values);
      final item = newValues.removeAt(oldIndex);
      newValues.insert(newIndex, item);
      onChanged(newValues);
    }

    final bool hasExistingItems = values.isNotEmpty;
    final bool showReadOnlyEmptyState = readOnly && !hasExistingItems;

    // New item input - styled consistently with existing items
    final newItemWidget = !readOnly
        ? _StringListItem(
            key: ValueKey('new_item_${resetKey.value}'),
            text: newItemText.value,
            onUpdate: (value) => newItemText.value = value,
            onSubmitted: addItem,
            itemValidator: itemValidator,
            colors: effectiveColors,
            itemHint: itemHint,
            showDragHandle: false,
            suffixIcon: IconButton(
              icon: const MonetIcon(MonetIcons.add),
              onPressed: addItem,
              tooltip: 'New item',
              style: iconButtonStyle(SemanticColors.successPalette(context))
                  .copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 0)),
                    fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
                  ),
            ),
          )
        : null;

    // Existing items list
    final Widget existingItems;
    if (!hasExistingItems) {
      existingItems = const SizedBox();
    } else {
      if (showContainer) {
        existingItems = Container(
          decoration: ShapeDecoration(
            shape: MonetTheme.shapesOf(context).border(),
            color: effectiveColors.background,
          ),
          child: _EditableStringList(
            values: values,
            onReorderItem: !readOnly && allowReordering ? reorderItems : null,
            onRemove: readOnly ? null : removeItem,
            onUpdate: readOnly ? null : updateItem,
            itemValidator: itemValidator,
            colors: effectiveColors,
            allowReordering: !readOnly && allowReordering,
          ),
        );
      } else {
        existingItems = _EditableStringList(
          values: values,
          onReorderItem: !readOnly && allowReordering ? reorderItems : null,
          onRemove: readOnly ? null : removeItem,
          onUpdate: readOnly ? null : updateItem,
          itemValidator: itemValidator,
          colors: effectiveColors,
          allowReordering: !readOnly && allowReordering,
        );
      }
    }

    return Column(
      crossAxisAlignment: .start,
      children: [
        ControlRowHeader(
          colors: effectiveColors,
          label: label,
          tooltip: tooltip,
          isSmall: true,
        ),
        // Existing items list
        if (hasExistingItems) ...[existingItems, const VerticalPaddingHalf()],
        // Empty state (read-only only — edit mode shows the input field below
        // which is itself an affordance).
        if (showReadOnlyEmptyState) ...[
          Text(
            emptyStateText,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontStyle: .italic, color: effectiveColors.text),
          ),
          const VerticalPaddingHalf(),
        ],
        // New item input
        ?newItemWidget,
      ],
    );
  }
}

// ignore: prefer-single-widget-per-file
class _EditableStringList extends StatelessWidget {
  final List<String> values;
  final Function(int, int)? onReorderItem;
  final Function(int)? onRemove;
  final Function(int, String)? onUpdate;
  final String? Function(String)? itemValidator;
  final Palette colors;
  final bool allowReordering;

  const _EditableStringList({
    required this.values,
    this.onReorderItem,
    this.onRemove,
    this.onUpdate,
    this.itemValidator,
    required this.colors,
    required this.allowReordering,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text(
        'No items defined',
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(fontStyle: .italic, color: colors.fillText),
      );
    }

    if (!allowReordering || onReorderItem == null) {
      // Simple list without reordering
      return Column(
        children: [
          for (int i = 0; i < values.length; i++)
            Container(
              color: colors.background,
              padding: const .symmetric(vertical: 4.0),
              child: _StringListItem(
                index: i,
                text: values[i],
                onUpdate: onUpdate != null
                    ? (value) => onUpdate!(i, value)
                    : null,
                itemValidator: itemValidator,
                colors: colors,
                showDragHandle: false,
                suffixIcon: onRemove != null
                    ? IconButton(
                        style: iconButtonStyle(
                          SemanticColors.errorPalette(
                            context,
                            bgColor: colors.background,
                          ),
                        ),
                        icon: const MonetIcon(MonetIcons.remove),
                        onPressed: () => onRemove!(i),
                        tooltip: 'Remove item',
                      )
                    : null,
              ),
            ),
        ],
      );
    }

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorderItem: onReorderItem!,
      buildDefaultDragHandles: false,
      children: [
        for (int i = 0; i < values.length; i++)
          Container(
            color: colors.background,
            key: ValueKey('string-item-$i'),
            padding: .only(top: i == 0 ? 0 : VerticalPaddingHalf.amount),
            child: _StringListItem(
              index: i,
              text: values[i],
              onUpdate: onUpdate != null
                  ? (value) => onUpdate!(i, value)
                  : null,
              itemValidator: itemValidator,
              colors: colors,
              showDragHandle: true,
              suffixIcon: onRemove != null
                  ? IconButton(
                      style: iconButtonStyle(
                        SemanticColors.errorPalette(
                          context,
                          bgColor: colors.background,
                        ),
                      ),
                      icon: const MonetIcon(MonetIcons.remove),
                      onPressed: () => onRemove!(i),
                      tooltip: 'Remove item',
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

/// A single string list item widget that can be used for both new and existing items
// ignore: prefer-single-widget-per-file
class _StringListItem extends HookWidget {
  final String text;
  final Function(String)? onUpdate;
  final VoidCallback? onSubmitted;
  final String? itemHint;
  final String? Function(String)? itemValidator;
  final Palette colors;
  final bool showDragHandle;
  final Widget? suffixIcon;
  final int? index;

  const _StringListItem({
    super.key,
    required this.text,
    this.onUpdate,
    this.onSubmitted,
    this.itemHint,
    this.itemValidator,
    required this.colors,
    this.showDragHandle = false,
    this.suffixIcon,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final focusNode = useFocusNode();
    final validationError = useState<String?>(null);

    void handleTextChanged(String newText) {
      final error = itemValidator?.call(newText);
      validationError.value = error;
      if (onUpdate != null) {
        onUpdate!(newText);
      }
    }

    return Row(
      children: [
        if (showDragHandle && index != null) ...[
          ReorderableDragStartListener(
            index: index!,
            child: MonetIcon(MonetIcons.dragToMove, color: colors.fill),
          ),
          const HorizontalPaddingHalf(),
        ],
        Expanded(
          child: ThemeSelection(
            colors: colors,
            child: AutoSaveTextField(
              externalText: text,
              // At the time this was added, [StringListField] was used
              // CLI arguments, which do not require autocorrect.
              entryType: .textNoAutocorrect,
              onTextChanged: handleTextChanged,
              focusNode: focusNode,
              decoration: TFID
                  .get(context, colors, hintText: itemHint ?? 'Enter value')
                  .copyWith(
                    errorText: validationError.value,
                    suffixIcon: suffixIcon,
                    contentPadding: const .symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colors.backgroundText),
              readOnly: onUpdate == null,
              onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
            ),
          ),
        ),
      ],
    );
  }
}
