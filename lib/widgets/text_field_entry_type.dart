import 'package:pixel_snap_fork/material.dart';

enum TextFieldEntryType {
  text(isAutocorrectEnabled: false, keyboardType: null),
  textNoAutocorrect(isAutocorrectEnabled: false, keyboardType: null),
  url(isAutocorrectEnabled: false, keyboardType: .url),
  integer(
    isAutocorrectEnabled: false,
    keyboardType: TextInputType.numberWithOptions(decimal: false, signed: true),
  );

  // Set to false for fields with, say, CLI arguments or HTTP headers.
  final bool isAutocorrectEnabled;
  // If null, [TextField] takes care of settings based on if it is multiline.
  final TextInputType? keyboardType;

  const TextFieldEntryType({
    required this.isAutocorrectEnabled,
    required this.keyboardType,
  });
}
