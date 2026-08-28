import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meld_core/meld_core.dart';
import 'package:meld_font/meld_font.dart';

export 'package:meld_core/meld_core.dart'
    show
        CubicPath,
        CubicSource,
        GeometryNode,
        GeometrySource,
        MeldEngine,
        MeldException,
        MeldIconSource,
        MeldInterpolationStrategy,
        MeldMotionMode,
        MeldPlan,
        MeldSource,
        MeldSourcePaintStyle,
        MeldViewBox,
        PathDataSource,
        SamplingConfig,
        SpringConfig,
        SpringPreset,
        SvgMarkupSource;

enum MeldIconStatus { idle, running, paused, completed, failed, disposed }

enum MeldTransitionEnd { completed, cancelled, disposed, failed }

/// Controls how normalized geometry is painted.
enum MeldPaintStyle {
  /// Draws contour edges without filling their interiors.
  outline,

  /// Preserves the source's declared visual intent. Path and SVG sources use
  /// outlines, while font glyph sources use filled compound contours.
  original,

  /// Fills compound contours first, then draws their edges.
  both,
}

final class MeldTransitionResult {
  const MeldTransitionResult(this.end);
  final MeldTransitionEnd end;
}

final class MeldIconThemeData {
  const MeldIconThemeData({
    this.color,
    this.strokeWidth = 2,
    this.strokeCap = ui.StrokeCap.round,
    this.strokeJoin = ui.StrokeJoin.round,
    this.antiAlias = true,
    this.paintStyle = MeldPaintStyle.original,
    this.motionMode = MeldMotionMode.user,
    this.interpolation = MeldInterpolationStrategy.polar,
  }) : assert(strokeWidth >= 0);

  final ui.Color? color;
  final double strokeWidth;
  final ui.StrokeCap strokeCap;
  final ui.StrokeJoin strokeJoin;
  final bool antiAlias;
  final MeldPaintStyle paintStyle;
  final MeldMotionMode motionMode;
  final MeldInterpolationStrategy interpolation;

  @override
  bool operator ==(Object other) =>
      other is MeldIconThemeData &&
      other.color == color &&
      other.strokeWidth == strokeWidth &&
      other.strokeCap == strokeCap &&
      other.strokeJoin == strokeJoin &&
      other.antiAlias == antiAlias &&
      other.paintStyle == paintStyle &&
      other.motionMode == motionMode &&
      other.interpolation == interpolation;

  @override
  int get hashCode => Object.hash(
        color,
        strokeWidth,
        strokeCap,
        strokeJoin,
        antiAlias,
        paintStyle,
        motionMode,
        interpolation,
      );

  MeldIconThemeData copyWith({
    ui.Color? color,
    double? strokeWidth,
    ui.StrokeCap? strokeCap,
    ui.StrokeJoin? strokeJoin,
    bool? antiAlias,
    MeldPaintStyle? paintStyle,
    MeldMotionMode? motionMode,
    MeldInterpolationStrategy? interpolation,
  }) {
    return MeldIconThemeData(
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeCap: strokeCap ?? this.strokeCap,
      strokeJoin: strokeJoin ?? this.strokeJoin,
      antiAlias: antiAlias ?? this.antiAlias,
      paintStyle: paintStyle ?? this.paintStyle,
      motionMode: motionMode ?? this.motionMode,
      interpolation: interpolation ?? this.interpolation,
    );
  }
}

final class MeldIconTheme extends InheritedTheme {
  const MeldIconTheme({required this.data, required super.child, super.key});

  final MeldIconThemeData data;

  static MeldIconThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<MeldIconTheme>();
    return theme?.data ?? const MeldIconThemeData();
  }

  @override
  bool updateShouldNotify(MeldIconTheme oldWidget) => data != oldWidget.data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      MeldIconTheme(data: data, child: child);
}

/// Converts an [IconData] glyph from caller-provided font bytes into a source.
/// The font bytes stay owned by the application.
MeldSource iconDataToSource(
  IconData icon, {
  required List<int> fontBytes,
  double grid = 24,
}) {
  return fontGlyphToSource(
    FontGlyphRef(
      fontBytes: fontBytes,
      codePoint: icon.codePoint,
      fontFamily: icon.fontFamily,
    ),
    grid: grid,
  );
}

final class MeldIconController extends ChangeNotifier {
  MeldIconController({MeldEngine? engine, MeldSource? initialSource})
      : engine = engine ?? MeldEngine(),
        _current = initialSource {
    if (initialSource != null) _validateSource(initialSource);
  }

  final MeldEngine engine;
  MeldSource? _current;
  MeldSource? _target;
  MeldPlan? _plan;
  List<Float64List>? _outputs;
  List<bool>? _closed;
  List<CubicPath>? _currentPaths;
  List<CubicPath>? _targetPaths;
  MeldSource? _targetPathsSource;
  MeldSpring _spring = MeldSpring();
  Ticker? _ticker;
  Duration? _lastTick;
  Completer<MeldTransitionResult>? _transition;
  MeldIconStatus _status = MeldIconStatus.idle;
  MeldException? _lastError;
  double _progress = 1;
  double _velocity = 0;
  MeldMotionMode motionMode = MeldMotionMode.user;
  MeldInterpolationStrategy interpolation = MeldInterpolationStrategy.polar;
  bool userAnimationsDisabled = false;

  MeldIconStatus get status => _status;
  MeldSource? get currentSource => _current;
  MeldSource? get target => _target ?? _current;
  MeldSourcePaintStyle get currentPaintStyle =>
      _current?.paintStyle ?? MeldSourcePaintStyle.outline;
  MeldSourcePaintStyle get targetPaintStyle =>
      (_target ?? _current)?.paintStyle ?? MeldSourcePaintStyle.outline;
  double get progress => _progress;
  double get velocity => _velocity;
  MeldException? get lastError => _lastError;
  bool get isAnimating => _status == MeldIconStatus.running;
  List<Float64List>? get flightPaths => _outputs;
  List<bool>? get closedPaths => _closed;
  PlanDiagnostics? get diagnostics => _plan?.diagnostics;
  List<CubicPath>? get currentPaths {
    if (_currentPaths == null && _current != null)
      _currentPaths = iconToCubics(_current!);
    return _currentPaths;
  }

  /// Returns the canonical cubic paths for the endpoint currently being
  /// displayed. Resting endpoints use canonical curves instead of sampled
  /// flight polylines, keeping small icons crisp and continuous.
  List<CubicPath>? get canonicalPaths {
    if (_progress >= 1 - 1e-6) return _targetCanonicalPaths;
    return currentPaths;
  }

  List<CubicPath>? get _targetCanonicalPaths {
    final source = _target ?? _current;
    if (source == null) return null;
    if (!identical(_targetPathsSource, source)) {
      _targetPathsSource = source;
      _targetPaths = iconToCubics(source);
    }
    return _targetPaths;
  }

  void attach(TickerProvider vsync) {
    if (_status == MeldIconStatus.disposed) return;
    _ticker ??= vsync.createTicker(_onTick);
    if (_status == MeldIconStatus.running && !_ticker!.isActive)
      _ticker!.start();
  }

  void detach() {
    _ticker?.dispose();
    _ticker = null;
    _cancel(MeldTransitionEnd.cancelled);
  }

  Future<MeldTransitionResult> morphTo(MeldSource source,
      {SpringConfig? spring, SpringPreset? preset}) {
    _ensureAlive();
    try {
      _validateSource(source);
    } on MeldException catch (error) {
      _fail(error);
      return Future.error(error);
    }
    if (_current == null) {
      set(source);
      return Future.value(
          const MeldTransitionResult(MeldTransitionEnd.completed));
    }
    if (motionMode == MeldMotionMode.never ||
        (motionMode == MeldMotionMode.user && userAnimationsDisabled)) {
      set(source);
      return Future.value(
          const MeldTransitionResult(MeldTransitionEnd.completed));
    }
    if (identical(source, target) && _status == MeldIconStatus.running)
      return _transition!.future;
    final config = spring ??
        (preset == null
            ? springPreset(SpringPreset.snappy)
            : springPreset(preset));
    try {
      _lastError = null;
      _ticker?.stop();
      final hasInFlightGeometry = _status == MeldIconStatus.running ||
          _plan != null && _progress > 0 && _progress < 1;
      final sourceForPlan =
          hasInFlightGeometry ? _sourceFromOutputs() : _current!;
      _plan = engine.plan(sourceForPlan, source);
      _outputs = allocateOutputs(_plan!);
      _closed = <bool>[for (final item in _plan!.items) item.closed];
      _target = source;
      _targetPathsSource = source;
      _targetPaths = iconToCubics(source);
      final inheritedVelocity = _velocity;
      _spring = MeldSpring(config)..start(inheritedVelocity: inheritedVelocity);
      _progress = 0;
      _velocity = _spring.velocity;
      _status = MeldIconStatus.running;
      _completePrevious(MeldTransitionEnd.cancelled);
      _transition = Completer<MeldTransitionResult>();
      final future = _transition!.future;
      _lastTick = null;
      _ticker?.start();
      notifyListeners();
      if (_ticker == null) {
        _finishImmediately();
      }
      return future;
    } on MeldException catch (error) {
      _fail(error);
      return Future.error(error);
    }
  }

  void set(MeldSource source) {
    _ensureAlive();
    _validateSource(source);
    _stopTicker();
    _completePrevious(MeldTransitionEnd.cancelled);
    try {
      _current = source;
      _currentPaths = iconToCubics(source);
      _target = source;
      _targetPathsSource = source;
      _targetPaths = _currentPaths;
      _plan = null;
      _outputs = null;
      _closed = null;
      _progress = 1;
      _velocity = 0;
      _status = MeldIconStatus.completed;
      _lastError = null;
      notifyListeners();
    } on MeldException catch (error) {
      _fail(error);
    }
  }

  void seek(MeldSource source, double value) {
    _ensureAlive();
    final t = value.clamp(0, 1).toDouble();
    try {
      _validateSource(source);
      final base = _current ?? source;
      final targetChanged = _target == null ||
          canonicalPathData(_target!) != canonicalPathData(source);
      if (_plan == null || targetChanged) _plan = engine.plan(base, source);
      _outputs ??= allocateOutputs(_plan!);
      _closed ??= <bool>[for (final item in _plan!.items) item.closed];
      interpolatePlan(_plan!, t, _outputs!, strategy: interpolation);
      _target = source;
      _targetPathsSource = source;
      _targetPaths = iconToCubics(source);
      _progress = t;
      _velocity = 0;
      _stopTicker();
      _status = t == 1 ? MeldIconStatus.completed : MeldIconStatus.paused;
      notifyListeners();
    } on MeldException catch (error) {
      _fail(error);
    }
  }

  void pause() {
    if (_status != MeldIconStatus.running) return;
    _ticker?.stop();
    _status = MeldIconStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_status != MeldIconStatus.paused || _ticker == null) return;
    _status = MeldIconStatus.running;
    _lastTick = null;
    _ticker!.start();
    notifyListeners();
  }

  void reset() {
    if (_current != null) set(_current!);
  }

  Future<MeldTransitionResult> playSequence(Iterable<MeldSource> sources,
      {SpringPreset preset = SpringPreset.snappy}) async {
    var result = const MeldTransitionResult(MeldTransitionEnd.completed);
    for (final source in sources) {
      result = await morphTo(source, preset: preset);
      if (result.end != MeldTransitionEnd.completed) break;
    }
    return result;
  }

  @override
  void dispose() {
    if (_status == MeldIconStatus.disposed) return;
    _stopTicker();
    _completePrevious(MeldTransitionEnd.disposed);
    _status = MeldIconStatus.disposed;
    _plan = null;
    _outputs = null;
    _closed = null;
    super.dispose();
  }

  MeldSource _sourceFromOutputs() {
    final output = _outputs;
    final closed = _closed;
    final plan = _plan;
    if (output == null || closed == null || plan == null) return _current!;
    final paths = <CubicPath>[];
    for (var p = 0; p < output.length; p++) {
      final points = output[p];
      final pointCount = points.length ~/ 2;
      final cubic = <double>[points[0], points[1]];
      void addLine(double x0, double y0, double x1, double y1) {
        cubic.addAll(<double>[
          x0 + (x1 - x0) / 3,
          y0 + (y1 - y0) / 3,
          x0 + 2 * (x1 - x0) / 3,
          y0 + 2 * (y1 - y0) / 3,
          x1,
          y1,
        ]);
      }

      for (var i = 1; i < pointCount; i++) {
        addLine(points[(i - 1) * 2], points[(i - 1) * 2 + 1], points[i * 2],
            points[i * 2 + 1]);
      }
      if (closed[p]) {
        addLine(points[(pointCount - 1) * 2], points[(pointCount - 1) * 2 + 1],
            points[0], points[1]);
      }
      paths.add(CubicPath(Float64List.fromList(cubic), closed: closed[p]));
    }
    return CubicSource(paths);
  }

  void _onTick(Duration elapsed) {
    if (_status != MeldIconStatus.running) return;
    final previous = _lastTick;
    _lastTick = elapsed;
    final dt =
        previous == null ? 0.0 : (elapsed - previous).inMicroseconds / 1000000;
    final settled = _spring.step(dt);
    _progress = _spring.position;
    _velocity = _spring.velocity;
    final plan = _plan;
    final outputs = _outputs;
    if (plan != null && outputs != null)
      interpolatePlan(plan, _progress, outputs, strategy: interpolation);
    notifyListeners();
    if (settled) {
      _stopTicker();
      final destination = _target;
      if (destination != null) _current = destination;
      if (destination != null) {
        _currentPaths = iconToCubics(destination);
        _targetPathsSource = destination;
        _targetPaths = _currentPaths;
      }
      _plan = null;
      _outputs = null;
      _closed = null;
      _progress = 1;
      _velocity = 0;
      _status = MeldIconStatus.completed;
      _completePrevious(MeldTransitionEnd.completed);
      notifyListeners();
    }
  }

  void _stopTicker() {
    _ticker?.stop();
    _lastTick = null;
  }

  void _cancel(MeldTransitionEnd end) {
    _stopTicker();
    if (end == MeldTransitionEnd.cancelled &&
        _status == MeldIconStatus.running) {
      _status = MeldIconStatus.paused;
    }
    _completePrevious(end);
  }

  void _completePrevious(MeldTransitionEnd end) {
    final completer = _transition;
    if (completer != null && !completer.isCompleted)
      completer.complete(MeldTransitionResult(end));
    _transition = null;
  }

  void _fail(MeldException error) {
    _stopTicker();
    _lastError = error;
    _status = MeldIconStatus.failed;
    _completePrevious(MeldTransitionEnd.failed);
    notifyListeners();
  }

  void _validateSource(MeldSource source) {
    try {
      final paths = iconToCubics(source);
      if (paths.isEmpty)
        throw MeldException(
            'empty-icon', 'The icon contains no drawable geometry.');
    } on MeldException {
      rethrow;
    } catch (error) {
      throw MeldException(
          'invalid-source', 'Unable to normalize icon source: $error');
    }
  }

  void _finishImmediately() {
    final destination = _target;
    if (destination != null) {
      _current = destination;
      _currentPaths = iconToCubics(destination);
      _targetPathsSource = destination;
      _targetPaths = _currentPaths;
    }
    _plan = null;
    _outputs = null;
    _closed = null;
    _progress = 1;
    _velocity = 0;
    _status = MeldIconStatus.completed;
    _completePrevious(MeldTransitionEnd.completed);
    notifyListeners();
  }

  void _ensureAlive() {
    if (_status == MeldIconStatus.disposed)
      throw StateError('MeldIconController has been disposed.');
  }
}

final class MeldIconPainter extends CustomPainter {
  MeldIconPainter({
    required this.controller,
    required this.viewBox,
    required this.color,
    required this.strokeWidth,
    required this.strokeCap,
    required this.strokeJoin,
    required this.antiAlias,
    required this.paintStyle,
  }) : super(repaint: controller);

  final MeldIconController controller;
  final MeldViewBox viewBox;
  final ui.Color color;
  final double strokeWidth;
  final ui.StrokeCap strokeCap;
  final ui.StrokeJoin strokeJoin;
  final bool antiAlias;
  final MeldPaintStyle paintStyle;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final scale =
        math.min(size.width / viewBox.width, size.height / viewBox.height);
    if (!scale.isFinite || scale <= 0) return;
    canvas.save();
    canvas.translate(
        (size.width - viewBox.width * scale) / 2 - viewBox.minX * scale,
        (size.height - viewBox.height * scale) / 2 - viewBox.minY * scale);
    canvas.scale(scale, scale);
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap
      ..strokeJoin = strokeJoin
      ..isAntiAlias = antiAlias;
    final progress = controller.progress;
    final atCanonicalEndpoint = progress <= 1e-6 || progress >= 1 - 1e-6;
    final outputs = atCanonicalEndpoint ? null : controller.flightPaths;
    final closed = controller.closedPaths;
    final allPath = ui.Path();
    final closedPath = ui.Path()..fillType = ui.PathFillType.evenOdd;
    final openPath = ui.Path();
    var hasOpenContours = false;
    if (outputs != null && closed != null) {
      for (var i = 0; i < outputs.length; i++) {
        final path = _flightPath(outputs[i], closed[i]);
        allPath.addPath(path, ui.Offset.zero);
        if (closed[i]) {
          closedPath.addPath(path, ui.Offset.zero);
        } else {
          openPath.addPath(path, ui.Offset.zero);
          hasOpenContours = true;
        }
      }
    } else {
      final paths = controller.canonicalPaths;
      if (paths != null) {
        for (final cubic in paths) {
          final path = _cubicPath(cubic);
          allPath.addPath(path, ui.Offset.zero);
          if (cubic.closed) {
            closedPath.addPath(path, ui.Offset.zero);
          } else {
            openPath.addPath(path, ui.Offset.zero);
            hasOpenContours = true;
          }
        }
      }
    }
    _draw(canvas, allPath, closedPath, openPath, hasOpenContours, paint);
    canvas.restore();
  }

  void _draw(
    ui.Canvas canvas,
    ui.Path allPath,
    ui.Path closedPath,
    ui.Path openPath,
    bool hasOpenContours,
    ui.Paint paint,
  ) {
    switch (paintStyle) {
      case MeldPaintStyle.outline:
        canvas.drawPath(allPath, paint);
      case MeldPaintStyle.original:
        _drawOriginal(
          canvas,
          allPath,
          closedPath,
          openPath,
          hasOpenContours,
          paint,
        );
      case MeldPaintStyle.both:
        final fill = _paint(ui.PaintingStyle.fill);
        canvas.drawPath(closedPath, fill);
        canvas.drawPath(allPath, paint);
    }
  }

  void _drawOriginal(
    ui.Canvas canvas,
    ui.Path allPath,
    ui.Path closedPath,
    ui.Path openPath,
    bool hasOpenContours,
    ui.Paint paint,
  ) {
    final currentIsFill =
        controller.currentPaintStyle == MeldSourcePaintStyle.fill;
    final targetIsFill =
        controller.targetPaintStyle == MeldSourcePaintStyle.fill;
    final progress = controller.progress.clamp(0, 1).toDouble();
    if (currentIsFill == targetIsFill) {
      if (currentIsFill) {
        canvas.drawPath(closedPath, _paint(ui.PaintingStyle.fill));
        if (hasOpenContours) canvas.drawPath(openPath, paint);
      } else {
        canvas.drawPath(allPath, paint);
      }
      return;
    }

    final fillOpacity = targetIsFill ? progress : 1 - progress;
    final strokeOpacity = 1 - fillOpacity;
    if (fillOpacity > 1e-6) {
      canvas.drawPath(
        closedPath,
        _paint(ui.PaintingStyle.fill, opacity: fillOpacity),
      );
    }
    if (strokeOpacity > 1e-6) {
      canvas.drawPath(
        allPath,
        _paint(ui.PaintingStyle.stroke, opacity: strokeOpacity),
      );
    }
    if (hasOpenContours) canvas.drawPath(openPath, paint);
  }

  ui.Paint _paint(ui.PaintingStyle style, {double opacity = 1}) {
    return ui.Paint()
      ..color = color.withValues(alpha: color.a * opacity)
      ..style = style
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap
      ..strokeJoin = strokeJoin
      ..isAntiAlias = antiAlias;
  }

  ui.Path _flightPath(Float64List points, bool close) {
    final count = points.length ~/ 2;
    final path = ui.Path()..moveTo(points[0], points[1]);
    if (count < 2) return path;

    double coordinate(int index, int axis) {
      if (close) {
        index %= count;
      } else {
        index = index.clamp(0, count - 1);
      }
      return points[index * 2 + axis];
    }

    double cornerWeight(int index) {
      if (!close && (index <= 0 || index >= count - 1)) return 1;
      final previousX = coordinate(index - 1, 0);
      final previousY = coordinate(index - 1, 1);
      final currentX = coordinate(index, 0);
      final currentY = coordinate(index, 1);
      final nextX = coordinate(index + 1, 0);
      final nextY = coordinate(index + 1, 1);
      final incomingX = currentX - previousX;
      final incomingY = currentY - previousY;
      final outgoingX = nextX - currentX;
      final outgoingY = nextY - currentY;
      final incomingLength = math.sqrt(
        incomingX * incomingX + incomingY * incomingY,
      );
      final outgoingLength = math.sqrt(
        outgoingX * outgoingX + outgoingY * outgoingY,
      );
      if (incomingLength < 1e-9 || outgoingLength < 1e-9) return 0;
      final turn = math.atan2(
        (incomingX * outgoingY - incomingY * outgoingX).abs(),
        incomingX * outgoingX + incomingY * outgoingY,
      );
      const softenUntil = 0.28;
      const sharpAt = 0.62;
      if (turn <= softenUntil) return 1;
      if (turn >= sharpAt) return 0;
      return (sharpAt - turn) / (sharpAt - softenUntil);
    }

    (double, double) limitControl(
      double baseX,
      double baseY,
      double controlX,
      double controlY,
      double maxDistance,
    ) {
      final deltaX = controlX - baseX;
      final deltaY = controlY - baseY;
      final distance = math.sqrt(deltaX * deltaX + deltaY * deltaY);
      if (distance <= maxDistance || distance < 1e-9) {
        return (controlX, controlY);
      }
      final scale = maxDistance / distance;
      return (baseX + deltaX * scale, baseY + deltaY * scale);
    }

    final segmentCount = close ? count : count - 1;
    for (var segment = 0; segment < segmentCount; segment++) {
      final startX = coordinate(segment, 0);
      final startY = coordinate(segment, 1);
      final endX = coordinate(segment + 1, 0);
      final endY = coordinate(segment + 1, 1);
      final previousX = coordinate(segment - 1, 0);
      final previousY = coordinate(segment - 1, 1);
      final nextNextX = coordinate(segment + 2, 0);
      final nextNextY = coordinate(segment + 2, 1);
      final startWeight = cornerWeight(segment);
      final endWeight = cornerWeight(segment + 1);
      final startHandleX = startX + (endX - previousX) * startWeight / 6;
      final startHandleY = startY + (endY - previousY) * startWeight / 6;
      final endHandleX = endX - (nextNextX - startX) * endWeight / 6;
      final endHandleY = endY - (nextNextY - startY) * endWeight / 6;
      final chord = math.sqrt(
        math.pow(endX - startX, 2) + math.pow(endY - startY, 2),
      );
      final maxHandle = chord * 0.5;
      final limitedStart = limitControl(
        startX,
        startY,
        startHandleX,
        startHandleY,
        maxHandle,
      );
      final limitedEnd = limitControl(
        endX,
        endY,
        endHandleX,
        endHandleY,
        maxHandle,
      );
      path.cubicTo(
        limitedStart.$1,
        limitedStart.$2,
        limitedEnd.$1,
        limitedEnd.$2,
        endX,
        endY,
      );
    }
    if (close) path.close();
    return path;
  }

  ui.Path _cubicPath(CubicPath source) {
    final points = source.points;
    final path = ui.Path()..moveTo(points[0], points[1]);
    for (var i = 2; i < points.length; i += 6) {
      path.cubicTo(points[i], points[i + 1], points[i + 2], points[i + 3],
          points[i + 4], points[i + 5]);
    }
    if (source.closed) path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant MeldIconPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.viewBox != viewBox ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.strokeCap != strokeCap ||
      oldDelegate.strokeJoin != strokeJoin ||
      oldDelegate.antiAlias != antiAlias ||
      oldDelegate.paintStyle != paintStyle;
}

final class MeldIcon extends StatefulWidget {
  const MeldIcon({
    super.key,
    this.icon,
    this.from,
    this.to,
    this.progress,
    this.controller,
    this.size = 24,
    this.viewBox = const MeldViewBox(0, 0, 24, 24),
    this.color,
    this.strokeWidth,
    this.strokeCap,
    this.strokeJoin,
    this.antiAlias,
    this.paintStyle,
    this.motionMode,
    this.interpolation,
    this.label,
    this.excludeFromSemantics = false,
  })  : assert(icon != null ||
            (from != null && to != null) ||
            controller != null ||
            (icon == null && from == null && to == null)),
        assert(size > 0),
        assert(strokeWidth == null || strokeWidth >= 0);

  final MeldSource? icon;
  final MeldSource? from;
  final MeldSource? to;
  final double? progress;
  final MeldIconController? controller;
  final double size;
  final MeldViewBox viewBox;
  final ui.Color? color;
  final double? strokeWidth;
  final ui.StrokeCap? strokeCap;
  final ui.StrokeJoin? strokeJoin;
  final bool? antiAlias;
  final MeldPaintStyle? paintStyle;
  final MeldMotionMode? motionMode;
  final MeldInterpolationStrategy? interpolation;
  final String? label;
  final bool excludeFromSemantics;

  @override
  State<MeldIcon> createState() => _MeldIconState();
}

/// A compact, opt-in diagnostics panel for development and issue reports.
/// It never changes layout or painter behavior of the icon itself.
final class MeldDiagnosticsOverlay extends StatelessWidget {
  const MeldDiagnosticsOverlay(
      {required this.controller,
      super.key,
      this.padding = const EdgeInsets.all(12)});

  final MeldIconController controller;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final diagnostics = controller.diagnostics;
        final stats = controller.engine.cacheStats;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xDD11131A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x335F6BFF)),
          ),
          child: Padding(
            padding: padding,
            child: DefaultTextStyle(
              style: const TextStyle(
                  color: Color(0xFFE8EAF2), fontSize: 12, height: 1.35),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('status: ${controller.status.name}'),
                  Text('progress: ${controller.progress.toStringAsFixed(3)}'),
                  Text('velocity: ${controller.velocity.toStringAsFixed(3)}'),
                  if (diagnostics != null) ...<Widget>[
                    Text('samples: ${diagnostics.sampleCount}'),
                    Text(
                        'residual: ${diagnostics.meanResidual.toStringAsFixed(5)}'),
                    Text('plan: ${diagnostics.elapsedMicros} µs'),
                  ],
                  Text('cache: ${stats.hits}/${stats.misses} hits'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _MeldIconState extends State<MeldIcon>
    with TickerProviderStateMixin {
  late MeldIconController controller;
  late bool ownsController;
  var _didInitializeDependencies = false;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller = widget.controller ??
        MeldIconController(
            initialSource: widget.icon ?? widget.from ?? widget.to);
    controller.attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyOptions();
    if (!_didInitializeDependencies &&
        widget.from != null &&
        widget.to != null) {
      controller.set(widget.from!);
      controller.seek(widget.to!, widget.progress ?? 0);
    }
    _didInitializeDependencies = true;
  }

  @override
  void didUpdateWidget(covariant MeldIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      controller.detach();
      if (ownsController) controller.dispose();
      ownsController = widget.controller == null;
      controller = widget.controller ??
          MeldIconController(
              initialSource: widget.icon ?? widget.from ?? widget.to);
      controller.attach(this);
      _didInitializeDependencies = false;
    }
    _applyOptions();
    if (widget.from != null && widget.to != null) {
      if (widget.from != oldWidget.from) controller.set(widget.from!);
      controller.seek(widget.to!, widget.progress ?? 0);
    } else if (widget.icon != null && widget.icon != oldWidget.icon) {
      unawaited(controller.morphTo(widget.icon!));
    }
  }

  @override
  void dispose() {
    controller.detach();
    if (ownsController) controller.dispose();
    super.dispose();
  }

  void _applyOptions() {
    final theme = MeldIconTheme.of(context);
    controller.motionMode = widget.motionMode ?? theme.motionMode;
    controller.interpolation = widget.interpolation ?? theme.interpolation;
    controller.userAnimationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = MeldIconTheme.of(context);
    final color = widget.color ??
        theme.color ??
        DefaultTextStyle.of(context).style.color ??
        const ui.Color(0xFF000000);
    final width = widget.strokeWidth ?? theme.strokeWidth;
    final cap = widget.strokeCap ?? theme.strokeCap;
    final join = widget.strokeJoin ?? theme.strokeJoin;
    final antiAlias = widget.antiAlias ?? theme.antiAlias;
    final paintStyle = widget.paintStyle ?? theme.paintStyle;
    final Widget child = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: MeldIconPainter(
          controller: controller,
          viewBox: widget.viewBox,
          color: color,
          strokeWidth: width,
          strokeCap: cap,
          strokeJoin: join,
          antiAlias: antiAlias,
          paintStyle: paintStyle,
        ),
      ),
    );
    if (widget.excludeFromSemantics) return ExcludeSemantics(child: child);
    return Semantics(
        label: widget.label, image: widget.label != null, child: child);
  }
}
