import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meld_flutter/meld_flutter.dart';

const _line = PathDataSource('M3 12H21');
const _cross = PathDataSource('M5 5L19 19M19 5L5 19');

void main() {
  test('unattached controller completes safely instead of hanging', () async {
    final controller = MeldIconController(initialSource: _line);
    final result = await controller.morphTo(_cross);
    expect(result.end, MeldTransitionEnd.completed);
    expect(controller.currentSource, same(_cross));
    controller.dispose();
  });

  test('unattached reverse resolves to the opposite endpoint', () async {
    final controller = MeldIconController(initialSource: _line);
    controller.seek(_cross, 0);

    final forward = await controller.reverse();
    expect(forward.end, MeldTransitionEnd.completed);
    expect(controller.currentSource, same(_cross));
    expect(controller.progress, 1);

    final backward = await controller.reverse();
    expect(backward.end, MeldTransitionEnd.completed);
    expect(controller.currentSource, same(_line));
    expect(controller.progress, 1);
    controller.dispose();
  });

  testWidgets('reverse works from running, paused, and completed states',
      (tester) async {
    final controller = MeldIconController(initialSource: _line)
      ..motionMode = MeldMotionMode.always;
    await tester.pumpWidget(
      MaterialApp(home: MeldIcon(controller: controller, label: 'Reverse')),
    );
    controller.seek(_cross, 0);

    final forward = controller.reverse();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 96));
    expect(controller.status, MeldIconStatus.running);
    expect(controller.progress, greaterThan(0));
    final forwardProgress = controller.progress;
    final forwardVelocity = controller.velocity;
    controller.pause();
    expect(controller.status, MeldIconStatus.paused);
    final resumed = controller.reverse();
    expect(controller.progress, closeTo(forwardProgress, 1e-9));
    expect(controller.velocity, closeTo(-forwardVelocity, 1e-9));
    final reverseStart = controller.progress;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.progress, lessThan(reverseStart));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect((await resumed).end, MeldTransitionEnd.completed);
    expect((await forward).end, MeldTransitionEnd.completed);
    expect(controller.currentSource, same(_line));
    expect(controller.progress, 0);

    final completedForward = controller.reverse();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.progress, greaterThan(0));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect((await completedForward).end, MeldTransitionEnd.completed);
    expect(controller.currentSource, same(_cross));
    expect(controller.progress, 1);

    final completedBackward = controller.reverse();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.progress, lessThan(1));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect((await completedBackward).end, MeldTransitionEnd.completed);
    expect(controller.currentSource, same(_line));
    expect(controller.progress, 1);
    controller.dispose();
  });

  testWidgets('renders a labeled icon and honors controlled progress',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MeldIcon(
          from: _line,
          to: _cross,
          progress: 0.5,
          label: 'Morph sample',
          size: 48,
        ),
      ),
    );
    expect(find.bySemanticsLabel('Morph sample'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is MeldIconPainter,
      ),
      findsOneWidget,
    );
  });

  test('both fills closed geometry before drawing its outline', () async {
    const square = PathDataSource('M4 4H20V20H4Z');
    final controller = MeldIconController(initialSource: square);
    final recorder = ui.PictureRecorder();
    final painter = MeldIconPainter(
      controller: controller,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 1,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.both,
    );

    painter.paint(ui.Canvas(recorder), const Size(24, 24));
    final image = await recorder.endRecording().toImage(24, 24);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final center = bytes!.getUint8((12 * 24 + 12) * 4);

    expect(center, 255);
    controller.dispose();
  });

  test('original preserves each source declared paint style', () async {
    final outlineController = MeldIconController(
        initialSource: const PathDataSource('M4 4H20V20H4Z'));
    final outlineRecorder = ui.PictureRecorder();
    final outlinePainter = MeldIconPainter(
      controller: outlineController,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 1,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.original,
    );
    outlinePainter.paint(ui.Canvas(outlineRecorder), const Size(24, 24));
    final outlineImage = await outlineRecorder.endRecording().toImage(24, 24);
    final outlineBytes =
        await outlineImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(outlineBytes!.getUint8((12 * 24 + 12) * 4 + 3), 0);
    outlineController.dispose();

    final filledSource = CubicSource(
      <CubicPath>[
        CubicPath(
          Float64List.fromList(<double>[
            4,
            4,
            4,
            4,
            20,
            4,
            20,
            4,
            20,
            4,
            20,
            4,
            20,
            20,
            20,
            20,
            20,
            20,
            4,
            20,
            4,
            20,
            4,
            20,
            4,
            4,
          ]),
          closed: true,
        ),
      ],
      paintStyle: MeldSourcePaintStyle.fill,
    );
    final filledController = MeldIconController(initialSource: filledSource);
    final filledRecorder = ui.PictureRecorder();
    final filledPainter = MeldIconPainter(
      controller: filledController,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 1,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.original,
    );
    filledPainter.paint(ui.Canvas(filledRecorder), const Size(24, 24));
    final filledImage = await filledRecorder.endRecording().toImage(24, 24);
    final filledBytes =
        await filledImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(filledBytes!.getUint8((12 * 24 + 12) * 4 + 3), 255);
    filledController.dispose();

    final explicitFillController = MeldIconController(
      initialSource: const PathDataSource(
        'M4 4H20V20H4Z',
        paintStyle: MeldSourcePaintStyle.fill,
      ),
    );
    final explicitFillRecorder = ui.PictureRecorder();
    final explicitFillPainter = MeldIconPainter(
      controller: explicitFillController,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 1,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.original,
    );
    explicitFillPainter.paint(
        ui.Canvas(explicitFillRecorder), const Size(24, 24));
    final explicitFillImage =
        await explicitFillRecorder.endRecording().toImage(24, 24);
    final explicitFillBytes =
        await explicitFillImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(explicitFillBytes!.getUint8((12 * 24 + 12) * 4 + 3), 255);
    explicitFillController.dispose();
  });

  test('original keeps open contours visible with a stroke fallback', () async {
    final controller = MeldIconController(initialSource: _line);
    final recorder = ui.PictureRecorder();
    final painter = MeldIconPainter(
      controller: controller,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 2,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.original,
    );

    painter.paint(ui.Canvas(recorder), const Size(24, 24));
    final image = await recorder.endRecording().toImage(24, 24);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final centerAlpha = bytes!.getUint8((12 * 24 + 12) * 4 + 3);

    expect(centerAlpha, 255);
    controller.dispose();
  });

  test('original continuously transitions between source paint intents',
      () async {
    const geometry = 'M4 4H20V20H4Z';
    const outline = PathDataSource(
      geometry,
      paintStyle: MeldSourcePaintStyle.outline,
    );
    const fill = PathDataSource(
      geometry,
      paintStyle: MeldSourcePaintStyle.fill,
    );
    final controller = MeldIconController(initialSource: outline)
      ..seek(fill, 0.5);
    final recorder = ui.PictureRecorder();
    final painter = MeldIconPainter(
      controller: controller,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 1,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.original,
    );

    painter.paint(ui.Canvas(recorder), const Size(24, 24));
    final image = await recorder.endRecording().toImage(24, 24);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final centerAlpha = bytes!.getUint8((12 * 24 + 12) * 4 + 3);

    expect(centerAlpha, closeTo(128, 1));
    controller.dispose();
  });

  test('both preserves holes when filling compound paths', () async {
    const ring = PathDataSource('M4 4H20V20H4Z M8 8V16H16V8Z');
    final controller = MeldIconController(initialSource: ring);
    controller.seek(const PathDataSource('M2 2H22V22H2Z'), 0);
    final recorder = ui.PictureRecorder();
    final painter = MeldIconPainter(
      controller: controller,
      viewBox: const MeldViewBox(0, 0, 24, 24),
      color: Colors.white,
      strokeWidth: 1,
      strokeCap: ui.StrokeCap.square,
      strokeJoin: ui.StrokeJoin.miter,
      antiAlias: false,
      paintStyle: MeldPaintStyle.both,
    );

    painter.paint(ui.Canvas(recorder), const Size(24, 24));
    final image = await recorder.endRecording().toImage(24, 24);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final centerAlpha = bytes!.getUint8((12 * 24 + 12) * 4 + 3);

    expect(centerAlpha, 0);
    controller.dispose();
  });

  testWidgets('keeps a stable midpoint rendering golden', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ColoredBox(
          color: Color(0xFF11131B),
          child: Center(
            child: RepaintBoundary(
              key: ValueKey<String>('meld-icon-golden'),
              child: MeldIcon(
                from: _line,
                to: _cross,
                progress: 0.5,
                color: Color(0xFFF5F7FF),
                size: 96,
                strokeWidth: 3,
                label: 'Golden morph',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey<String>('meld-icon-golden')),
      matchesGoldenFile('goldens/meld_icon.png'),
    );
  });

  testWidgets('external controller is detached without being disposed',
      (tester) async {
    final controller = MeldIconController(initialSource: _line)
      ..motionMode = MeldMotionMode.always;
    await tester.pumpWidget(
        MaterialApp(home: MeldIcon(controller: controller, label: 'Icon')));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(controller.status, isNot(MeldIconStatus.disposed));
    controller.dispose();
  });

  testWidgets(
      'redirecting a running transition preserves a valid geometry buffer',
      (tester) async {
    final controller = MeldIconController(initialSource: _line)
      ..motionMode = MeldMotionMode.always;
    await tester
        .pumpWidget(MaterialApp(home: MeldIcon(controller: controller)));
    final first = controller.morphTo(_cross);
    await tester.pump(const Duration(milliseconds: 80));
    final second = controller.morphTo(_line);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    final result = await second;
    expect(result.end, MeldTransitionEnd.completed);
    expect(controller.lastError, isNull);
    expect(controller.currentSource, same(_line));
    await first;
    controller.dispose();
  });
}
