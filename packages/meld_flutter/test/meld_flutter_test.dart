import 'dart:ui' as ui;

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

  test('fillAndStroke fills closed geometry before drawing its outline',
      () async {
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
      paintStyle: MeldPaintStyle.fillAndStroke,
    );

    painter.paint(ui.Canvas(recorder), const Size(24, 24));
    final image = await recorder.endRecording().toImage(24, 24);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final center = bytes!.getUint8((12 * 24 + 12) * 4);

    expect(center, 255);
    controller.dispose();
  });

  test('compound paths preserve holes when filled', () async {
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
      paintStyle: MeldPaintStyle.fillAndStroke,
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
