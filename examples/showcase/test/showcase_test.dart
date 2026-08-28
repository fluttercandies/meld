import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meld/meld.dart';
import 'package:meld_showcase/main.dart';
import 'package:meld_showcase/stress_test.dart';

void main() {
  testWidgets('showcase boots with the responsive preview', (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    expect(find.text('Meld'), findsOneWidget);
    expect(find.text('Explore the motion'), findsOneWidget);
  });

  testWidgets('opens the multi-instance stress page', (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.tap(
      find.byKey(const ValueKey<String>('stress-test-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Many icons, one shared scheduler'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('stress-grid')), findsOneWidget);
    expect(find.byType(MeldIcon), findsNWidgets(100));
  });

  testWidgets('stress page animates and resizes all mounted instances',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StressTestPage()));
    await tester.pump();
    expect(find.byType(MeldIcon), findsNWidgets(100));

    await tester.tap(
      find.byKey(const ValueKey<String>('stress-play-all')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final icons = tester.widgetList<MeldIcon>(find.byType(MeldIcon));
    expect(icons.every((icon) => icon.controller!.isAnimating), isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('stress-count-250')),
    );
    await tester.pump();
    expect(find.byType(MeldIcon), findsNWidgets(250));

    await tester.tap(
      find.byKey(const ValueKey<String>('stress-reset-all')),
    );
    await tester.pump();
    final resetIcons = tester.widgetList<MeldIcon>(find.byType(MeldIcon));
    expect(resetIcons.every((icon) => !icon.controller!.isAnimating), isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('stress-reverse-all')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final reversedIcons = tester.widgetList<MeldIcon>(find.byType(MeldIcon));
    expect(reversedIcons.every((icon) => icon.controller!.isAnimating), isTrue);
  });

  testWidgets('wide workbench uses four-column control grids', (tester) async {
    final originalSize = tester.view.physicalSize;
    final originalDevicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDevicePixelRatio;
    });
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;

    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.pump();

    final firstPair = tester.getRect(
      find.byKey(const ValueKey<String>('pair-0')),
    );
    final fourthPair = tester.getRect(
      find.byKey(const ValueKey<String>('pair-3')),
    );
    final fifthPair = tester.getRect(
      find.byKey(const ValueKey<String>('pair-4')),
    );

    expect(fourthPair.top, closeTo(firstPair.top, 0.01));
    expect(fourthPair.left, greaterThan(firstPair.left));
    expect(fifthPair.top, greaterThan(firstPair.bottom));
  });

  testWidgets('paint style control switches the preview treatment',
      (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.pump();

    MeldIcon preview() => tester.widget<MeldIcon>(
          find.byKey(const ValueKey<String>('preview-icon')),
        );

    expect(preview().paintStyle, MeldPaintStyle.original);
    await tester.ensureVisible(find.text('Outline'));
    await tester.tap(find.text('Outline'));
    await tester.pump();
    expect(preview().paintStyle, MeldPaintStyle.outline);
  });

  testWidgets('play starts a running transition and advances every frame',
      (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.pump();

    final controller =
        tester.widget<MeldIcon>(find.byType(MeldIcon).first).controller!;
    expect(controller.status, MeldIconStatus.paused);
    expect(controller.progress, 0);
    expect(controller.motionMode, MeldMotionMode.always);
    expect(controller.interpolation, MeldInterpolationStrategy.tangentAware);
    final initialGeometry = controller.flightPaths!
        .expand<double>((path) => path)
        .toList(growable: false);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('play-button')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('play-button')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.status, MeldIconStatus.running);
    final firstProgress = controller.progress;

    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.progress, greaterThan(firstProgress));
    expect(controller.status, MeldIconStatus.running);
    final animatedGeometry = controller.flightPaths!
        .expand<double>((path) => path)
        .toList(growable: false);
    expect(animatedGeometry, isNot(equals(initialGeometry)));

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(controller.status, MeldIconStatus.completed);
    expect(controller.progress, 1);
    expect(find.text('Reverse to start'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('play-button')));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.status, MeldIconStatus.running);
    expect(controller.progress, lessThan(1));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(controller.status, MeldIconStatus.completed);
    expect(controller.progress, 1);
    expect(find.text('Close → Menu'), findsOneWidget);
    expect(find.text('Reverse to start'), findsOneWidget);
  });

  testWidgets('first-frame play starts without a quality warmup',
      (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());

    final controller = tester
        .widget<MeldIcon>(find.byKey(const ValueKey<String>('preview-icon')))
        .controller!;
    expect(controller.status, MeldIconStatus.paused);
    expect(controller.progress, 0);

    await tester.tap(find.byKey(const ValueKey<String>('play-button')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.status, MeldIconStatus.running);
    expect(controller.progress, 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.progress, greaterThan(0));
  });

  testWidgets('path, svg, and font endpoint changes all remain animatable',
      (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.pumpAndSettle();

    Future<void> chooseAndPlay({
      required String source,
      required String from,
      required String to,
    }) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>(source)));
      await tester.tap(find.byKey(ValueKey<String>(source)));
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ValueKey<String>(source)))
            .selected,
        isTrue,
        reason: 'source chip $source should be selected after tapping',
      );
      await tester
          .ensureVisible(find.byKey(const ValueKey<String>('from-endpoint')));
      await tester.tap(find.byKey(const ValueKey<String>('from-endpoint')));
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>(from)).evaluate().isNotEmpty ||
            find
                .byKey(ValueKey<String>('to-${from.substring(5)}'))
                .evaluate()
                .isNotEmpty,
        isTrue,
        reason: 'active source $source should expose endpoint tiles',
      );
      expect(find.byKey(ValueKey<String>(from)), findsOneWidget,
          reason: 'active source $source should expose $from');
      await tester.ensureVisible(find.byKey(ValueKey<String>(from)));
      await tester.tap(find.byKey(ValueKey<String>(from)));
      await tester
          .ensureVisible(find.byKey(const ValueKey<String>('to-endpoint')));
      await tester.tap(find.byKey(const ValueKey<String>('to-endpoint')));
      await tester.pump();
      expect(find.byKey(ValueKey<String>(to)), findsOneWidget);
      await tester.ensureVisible(find.byKey(ValueKey<String>(to)));
      await tester.tap(find.byKey(ValueKey<String>(to)));

      final controller =
          tester.widget<MeldIcon>(find.byType(MeldIcon).first).controller!;
      await tester
          .ensureVisible(find.byKey(const ValueKey<String>('play-button')));
      await tester.tap(find.byKey(const ValueKey<String>('play-button')));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.status, MeldIconStatus.running);
      final firstProgress = controller.progress;
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.progress, greaterThan(firstProgress));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(controller.status, MeldIconStatus.completed);
    }

    await chooseAndPlay(
      source: 'source-path',
      from: 'from-path-plus',
      to: 'to-path-close',
    );
    await chooseAndPlay(
      source: 'source-svg',
      from: 'from-svg-ring',
      to: 'to-svg-spark',
    );
    await chooseAndPlay(
      source: 'source-font',
      from: 'from-font-add',
      to: 'to-font-clear',
    );
  });

  testWidgets('source family switch mounts its endpoint options',
      (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey<String>('source-svg')));
    await tester.tap(find.byKey(const ValueKey<String>('source-svg')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('from-svg-ring')), findsOneWidget);
  });

  testWidgets('same geometry exposes a safe no-op state', (tester) async {
    await tester.pumpWidget(const MeldShowcaseApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('from-endpoint')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('from-endpoint')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('from-path-close')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('from-path-close')));
    await tester.pump();

    final play = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('play-button')),
    );
    expect(play.onPressed, isNull);
    expect(
      find.text('These endpoints resolve to the same geometry.'),
      findsOneWidget,
    );
  });
}
