import 'package:flutter/material.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meld/meld.dart';
import 'package:meld_showcase/main.dart';

void main() {
  cockpitTestWidgets(
    'chooses path, svg, and font endpoints, then exercises the motion controls',
    app: () => const MeldShowcaseApp(),
    body: (cockpit) async {
      await cockpit.expectVisible('Explore the motion');
      await cockpit.expectVisible('@pair-0');

      final initialController = cockpit.flutter
          .widget<MeldIcon>(find.byType(MeldIcon).first)
          .controller!;
      expect(
        cockpit.flutter
            .widget<SegmentedButton<int>>(
              find.byKey(const ValueKey<String>('quality-selector')),
            )
            .selected,
        <int>{64},
      );
      expect(initialController.status, MeldIconStatus.paused);
      expect(initialController.progress, 0);
      await cockpit.flutter.ensureVisible(
        find.byKey(const ValueKey<String>('play-button')),
      );
      await cockpit.flutter.tap(
        find.byKey(const ValueKey<String>('play-button')),
      );
      await cockpit.flutter.pump(const Duration(milliseconds: 40));
      expect(initialController.status, MeldIconStatus.running);
      expect(initialController.progress, greaterThan(0));
      for (
        var frame = 0;
        frame < 180 && initialController.isAnimating;
        frame++
      ) {
        await cockpit.flutter.pump(const Duration(milliseconds: 16));
      }
      expect(initialController.status, MeldIconStatus.completed);
      expect(initialController.progress, 1);
      await cockpit.expectVisible('Reverse to start');
      await cockpit.flutter.tap(
        find.byKey(const ValueKey<String>('play-button')),
      );
      await cockpit.flutter.pump(const Duration(milliseconds: 16));
      await cockpit.flutter.pump(const Duration(milliseconds: 32));
      expect(initialController.status, MeldIconStatus.running);
      expect(initialController.progress, lessThan(1));
      await cockpit.flutter.pumpAndSettle(const Duration(milliseconds: 16));
      expect(initialController.status, MeldIconStatus.completed);
      expect(initialController.progress, 1);
      await cockpit.expectVisible('Close → Menu');
      await cockpit.expectVisible('Reverse to start');

      await cockpit.tap('@from-path-circle');
      await cockpit.tap('@to-endpoint');
      await cockpit.tap('@to-path-diamond');
      expect(
        cockpit.flutter
            .widget<Semantics>(
              find.byKey(const ValueKey<String>('to-path-diamond')),
            )
            .properties
            .selected,
        isTrue,
      );
      await cockpit.tap('@swap-endpoints');
      expect(
        cockpit.flutter
            .widget<Semantics>(
              find.byKey(const ValueKey<String>('from-endpoint')),
            )
            .properties
            .label,
        contains('Diamond'),
      );

      await cockpit.tap('@pair-4');
      final selectedTile = cockpit.flutter.widget<Semantics>(
        find.byKey(const ValueKey<String>('pair-4')),
      );
      expect(selectedTile.properties.selected, isTrue);

      await cockpit.tap('@source-svg');
      await cockpit.tap('@from-endpoint');
      await cockpit.flutter.ensureVisible(
        find.byKey(const ValueKey<String>('from-svg-chevron')),
      );
      await cockpit.tap('@from-svg-chevron');
      await cockpit.flutter.ensureVisible(find.text('Chevron → Square'));
      await cockpit.expectVisible('Chevron → Square');
      await cockpit.tap('@to-endpoint');
      await cockpit.flutter.ensureVisible(
        find.byKey(const ValueKey<String>('to-svg-spark')),
      );
      await cockpit.tap('@to-svg-spark');
      await cockpit.flutter.ensureVisible(find.text('Chevron → Spark'));
      await cockpit.expectVisible('Chevron → Spark');

      await cockpit.flutter.pumpAndSettle();
      await cockpit.expectVisible('Text["Font glyphs"]');
      await cockpit.tap('@source-font');
      await cockpit.tap('@from-endpoint');
      await cockpit.flutter.ensureVisible(
        find.byKey(const ValueKey<String>('from-font-add')),
      );
      await cockpit.expectVisible('@from-font-add');
      await cockpit.tap('@from-font-add');
      await cockpit.flutter.ensureVisible(find.text('Add → Spark'));
      await cockpit.expectVisible('Add → Spark');
      await cockpit.tap('@to-endpoint');
      await cockpit.flutter.ensureVisible(
        find.byKey(const ValueKey<String>('to-font-clear')),
      );
      await cockpit.tap('@to-font-clear');
      await cockpit.flutter.ensureVisible(find.text('Add → Close'));
      await cockpit.expectVisible('Add → Close');

      final sliderBefore = cockpit.flutter
          .widget<Slider>(find.byKey(const ValueKey<String>('progress-slider')))
          .value;
      await cockpit.increase('@progress-slider');
      final sliderAfter = cockpit.flutter
          .widget<Slider>(find.byKey(const ValueKey<String>('progress-slider')))
          .value;
      expect(sliderAfter, greaterThan(sliderBefore));

      await cockpit.tap('@play-button');
      await cockpit.flutter.pump(const Duration(milliseconds: 40));
      await cockpit.decrease('@progress-slider');
      await cockpit.flutter.ensureVisible(find.text('status: paused'));
      await cockpit.expectText('Text["status: paused"]', 'status: paused');

      await cockpit.tap('@play-button');
      await cockpit.waitForUi();
      await cockpit.flutter.ensureVisible(find.text('status: completed'));
      await cockpit.expectText(
        'Text["status: completed"]',
        'status: completed',
      );

      await cockpit.flutter.ensureVisible(
        find.byKey(const ValueKey<String>('paint-style-selector')),
      );
      await cockpit.tap('Outline');
      expect(
        cockpit.flutter
            .widget<SegmentedButton<MeldPaintStyle>>(
              find.byKey(const ValueKey<String>('paint-style-selector')),
            )
            .selected,
        <MeldPaintStyle>{MeldPaintStyle.outline},
      );
      await cockpit.tap('Original');
      expect(
        cockpit.flutter
            .widget<SegmentedButton<MeldPaintStyle>>(
              find.byKey(const ValueKey<String>('paint-style-selector')),
            )
            .selected,
        <MeldPaintStyle>{MeldPaintStyle.original},
      );
      await cockpit.tap('Both');
      expect(
        cockpit.flutter
            .widget<SegmentedButton<MeldPaintStyle>>(
              find.byKey(const ValueKey<String>('paint-style-selector')),
            )
            .selected,
        <MeldPaintStyle>{MeldPaintStyle.both},
      );

      await cockpit.tap('Detailed');
      await cockpit.expectText('96 samples', '96 samples');
      await cockpit.screenshot(name: 'showcase-flow');
    },
  );
}
