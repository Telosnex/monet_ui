import 'package:monet_ui/widgets/padding.dart';

/// From the content edge of a tile to its leading icon slot. Headers center
/// icons within a shared slot so their labels align. Standalone pills place
/// their leading glyph here, and their backgrounds overhang it.
const kIconAlignmentLeft = HorizontalPaddingHalf.amount + 2.0;

/// From the start of a pill's background to the ink of its leading glyph.
/// The background overhangs by this much (LeadingOverhang), so the glyph is
/// at [kIconAlignmentLeft] when the pill is placed directly in a row.
const kPillLeadingInset = 3.0;

/// From the ink of a pill's leading glyph to its second icon.
const kPillIconGap = HorizontalPaddingHalf.amount;
// Chosen as the amount needed to make ESPN.com look good -- it bumps directly
// against its borders, and needs protection in dark mode.
const kFavIconPadding = 2.0;
const kIconVerticalPadding = 2.0;
const kLoomTileVerticalPadding = 1.0;
