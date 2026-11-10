import 'package:flutter_test/flutter_test.dart';
import 'package:monet_ui/widgets/monet_mono_text_style.dart';
import 'package:pixel_snap_fork/material.dart';

void main() {
  testWidgets('uses the fallback without a provider', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          style = MonetMonoTextStyle.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(style, MonetMonoTextStyle.fallback);
  });

  testWidgets('sizedTo keeps the provided family', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MonetMonoTextStyle(
        style: const TextStyle(fontFamily: 'Fira Code'),
        child: Builder(
          builder: (context) {
            style = MonetMonoTextStyle.sizedTo(
              context,
              const TextStyle(fontSize: 20),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(style.fontFamily, 'Fira Code');
    expect(style.fontSize, isNotNull);
  });
}
