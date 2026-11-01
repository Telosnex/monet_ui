## Unreleased

- Font data: the font's `cmap` decides whether it has Latin letters, not the
  catalog's `latin` subset. 111 more families get a line height, among them
  the 104 Playwrite families and the math fonts.
- Font data: a font that maps an accented letter to an empty glyph is
  measured from A–Z and a–z (Knewave).
- Font data: a family with only italics is measured from its italic (Molle).
  It gets a visual-height scale.

## 1.0.1

- Add `MonetGdtRule20261030` (`extract/monet_gdt_rule_2026_10_30.dart`):
  the color rule that monet_gdt 2026.10.30 is trained on. It chooses
  colorful colors before large areas, and needs 128 `QuantizerCelebi`
  clusters. It is slower than `ScorerTriad` and can pick small colorful
  areas; see the file header.

## 1.0.0

- First release on pub.dev, as monet_ui (the repository was libmonet).
  Its library is package:monet_ui/monet_ui.dart.
