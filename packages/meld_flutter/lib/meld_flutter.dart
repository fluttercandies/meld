import 'dart:async';
import 'dart:collection';
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

  /// Preserves the source's declared or parsed visual intent, including
  /// fill-plus-outline sources. Geometry-only sources use their constructor's
  /// explicit style; SVG markup derives one from inline paint attributes.
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

_MeldTickerHub? _tickerHub;

_MeldTickerHub _globalTickerHub() {
  final existing = _tickerHub;
  if (existing != null && !existing._disposed) return existing;
  final created = _MeldTickerHub();
  _tickerHub = created;
  return created;
}

/// Shares one engine ticker between all Meld controllers in this Flutter
/// isolate, avoiding one platform ticker per icon instance.
final class _MeldTickerHub {
  _MeldTickerHub() {
    _ticker = Ticker(_onTick);
  }

  late final Ticker _ticker;
  final Set<MeldIconController> _attached =
      LinkedHashSet<MeldIconController>.identity();
  final List<MeldIconController> _running = <MeldIconController>[];
  bool _disposed = false;

  void attach(MeldIconController controller) {
    if (_disposed) throw StateError('Ticker hub has been disposed.');
    _attached.add(controller);
  }

  void detach(MeldIconController controller) {
    _running.remove(controller);
    _attached.remove(controller);
    if (_attached.isEmpty) {
      _ticker.stop();
      _disposed = true;
      _ticker.dispose();
      if (identical(_tickerHub, this)) _tickerHub = null;
    } else if (_running.isEmpty) {
      _ticker.stop();
    }
  }

  void start(MeldIconController controller) {
    if (_disposed ||
        !_attached.contains(controller) ||
        !controller.tickerEnabled) return;
    if (!_running.contains(controller)) _running.add(controller);
    if (!_ticker.isActive) _ticker.start();
  }

  void stop(MeldIconController controller) {
    _running.remove(controller);
    if (_running.isEmpty) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    if (_disposed) return;
    var index = 0;
    while (index < _running.length) {
      final controller = _running[index];
      controller._onTick(elapsed);
      if (index < _running.length && identical(_running[index], controller)) {
        index++;
      }
    }
    if (_running.isEmpty) _ticker.stop();
  }
}

final class MeldIconController extends ChangeNotifier {
  MeldIconController({MeldEngine? engine, MeldSource? initialSource})
      : engine = engine ?? MeldEngine(),
        _current = initialSource {
    if (initialSource != null) {
      _validateSource(initialSource);
      _currentPaintStyle = initialSource.paintStyle;
      _targetPaintStyle = _currentPaintStyle;
    }
  }

  final MeldEngine engine;
  MeldSource? _current;
  MeldSource? _target;
  MeldSource? _previousSource;
  MeldSource? _planStartSource;
  MeldPlan? _plan;
  List<Float64List>? _outputs;
  List<Float64List>? _outputViews;
  List<bool>? _closed;
  List<CubicPath>? _currentPaths;
  List<CubicPath>? _targetPaths;
  MeldSource? _targetPathsSource;
  MeldSpring _spring = MeldSpring();
  _MeldTickerHub? _tickerHub;
  Duration? _lastTick;
  Completer<MeldTransitionResult>? _transition;
  MeldIconStatus _status = MeldIconStatus.idle;
  MeldException? _lastError;
  double _progress = 1;
  double _velocity = 0;
  MeldSourcePaintStyle _currentPaintStyle = MeldSourcePaintStyle.outline;
  MeldSourcePaintStyle _targetPaintStyle = MeldSourcePaintStyle.outline;
  MeldSourcePaintStyle _planStartPaintStyle = MeldSourcePaintStyle.outline;
  MeldSourcePaintStyle _planTargetPaintStyle = MeldSourcePaintStyle.outline;
  MeldMotionMode motionMode = MeldMotionMode.user;
  MeldInterpolationStrategy interpolation = MeldInterpolationStrategy.polar;
  bool userAnimationsDisabled = false;
  bool _tickerEnabled = true;

  /// Whether this controller participates in frame scheduling.
  ///
  /// [MeldIcon] keeps this in sync with [TickerMode]. It remains public so a
  /// custom host can apply the same policy when driving a controller directly.
  bool get tickerEnabled => _tickerEnabled;

  set tickerEnabled(bool value) {
    if (_tickerEnabled == value) return;
    _tickerEnabled = value;
    if (value && _status == MeldIconStatus.running) {
      _startTicker();
    } else if (!value) {
      _stopTicker();
    }
  }

  MeldIconStatus get status => _status;
  MeldSource? get currentSource => _current;
  MeldSource? get target => _target ?? _current;
  MeldSourcePaintStyle get currentPaintStyle => _currentPaintStyle;
  MeldSourcePaintStyle get targetPaintStyle => _targetPaintStyle;
  double get progress => _progress;
  double get velocity => _velocity;
  MeldException? get lastError => _lastError;
  bool get isAnimating => _status == MeldIconStatus.running;
  List<Float64List>? get flightPaths => _outputViews;
  List<bool>? get closedPaths => _closed;
  PlanDiagnostics? get diagnostics => _plan?.diagnostics;
  List<CubicPath>? get currentPaths {
    if (_currentPaths == null && _current != null) {
      _currentPaths = List<CubicPath>.unmodifiable(iconToCubics(_current!));
    }
    return _currentPaths;
  }

  /// Returns the canonical cubic paths for the endpoint currently being
  /// displayed. Resting endpoints use canonical curves instead of sampled
  /// flight polylines, keeping small icons crisp and continuous.
  List<CubicPath>? get canonicalPaths {
    if (!_isAtCanonicalEndpoint) return null;
    if (_progress >= 1 - 1e-6) return _targetCanonicalPaths;
    return currentPaths;
  }

  /// A clamped progress value can reach an endpoint while a spring is still
  /// overshooting. Canonical geometry is safe only after the controller has
  /// actually stopped, otherwise the painter would alternate between the
  /// sampled flight buffer and the endpoint path during the same transition.
  bool get _isAtCanonicalEndpoint =>
      _status != MeldIconStatus.running &&
      (_progress <= 1e-6 || _progress >= 1 - 1e-6);

  List<CubicPath>? get _targetCanonicalPaths {
    final source = _target ?? _current;
    if (source == null) return null;
    if (!identical(_targetPathsSource, source)) {
      _targetPathsSource = source;
      _targetPaths = List<CubicPath>.unmodifiable(iconToCubics(source));
    }
    return _targetPaths;
  }

  void attach(TickerProvider vsync) {
    if (_status == MeldIconStatus.disposed) return;
    final hub = _globalTickerHub();
    if (!identical(_tickerHub, hub)) {
      _tickerHub?.detach(this);
      _tickerHub = hub;
    }
    _tickerHub!.attach(this);
    if (_status == MeldIconStatus.running) _startTicker();
  }

  void detach() {
    _tickerHub?.detach(this);
    _tickerHub = null;
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
      _stopTicker();
      final hasInFlightGeometry = _status == MeldIconStatus.running ||
          _plan != null && _progress > 0 && _progress < 1;
      _previousSource = _current;
      final sourceForPlan =
          hasInFlightGeometry ? _sourceFromOutputs() : _current!;
      _planStartSource = sourceForPlan;
      _planStartPaintStyle = sourceForPlan.paintStyle;
      _planTargetPaintStyle = source.paintStyle;
      _plan = engine.plan(sourceForPlan, source);
      _outputs = allocateOutputs(_plan!);
      _outputViews = List<Float64List>.unmodifiable(
          _outputs!.map((buffer) => buffer.asUnmodifiableView()));
      interpolatePlan(_plan!, 0, _outputs!, strategy: interpolation);
      _closed = List<bool>.unmodifiable(
          [for (final item in _plan!.items) item.closed]);
      _target = source;
      _targetPaintStyle = source.paintStyle;
      if (!identical(_targetPathsSource, source)) {
        _targetPathsSource = source;
        _targetPaths = List<CubicPath>.unmodifiable(iconToCubics(source));
      }
      final inheritedVelocity = _velocity;
      _spring = MeldSpring(config)..start(inheritedVelocity: inheritedVelocity);
      _progress = 0;
      _velocity = _spring.velocity;
      _status = MeldIconStatus.running;
      _completePrevious(MeldTransitionEnd.cancelled);
      _transition = Completer<MeldTransitionResult>();
      final future = _transition!.future;
      _lastTick = null;
      _startTicker();
      notifyListeners();
      if (_tickerHub == null) {
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
    try {
      if (!identical(_target, source)) _validateSource(source);
      _stopTicker();
      _completePrevious(MeldTransitionEnd.cancelled);
      _current = source;
      _previousSource = null;
      _planStartSource = null;
      _currentPaintStyle = source.paintStyle;
      _targetPaintStyle = _currentPaintStyle;
      _currentPaths = List<CubicPath>.unmodifiable(iconToCubics(source));
      _target = source;
      _targetPathsSource = source;
      _targetPaths = _currentPaths;
      _plan = null;
      _outputs = null;
      _outputViews = null;
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
    try {
      if (!value.isFinite) {
        throw MeldException('invalid-progress', 'Progress must be finite.');
      }
      final t = value.clamp(0, 1).toDouble();
      if (!identical(_target, source)) _validateSource(source);
      _lastError = null;
      final base = _current ?? source;
      if (_current == null) _currentPaintStyle = base.paintStyle;
      _previousSource ??= _current;
      final targetChanged = _target == null ||
          (!identical(_target, source) && !_sameGeometry(_target!, source));
      if (_plan == null || targetChanged) {
        _plan = engine.plan(base, source);
        _planStartSource = base;
        _planStartPaintStyle = base.paintStyle;
      }
      _planTargetPaintStyle = source.paintStyle;
      if (_outputs == null) {
        _outputs = allocateOutputs(_plan!);
        _outputViews = List<Float64List>.unmodifiable(
            _outputs!.map((buffer) => buffer.asUnmodifiableView()));
      }
      _closed ??= List<bool>.unmodifiable(
          [for (final item in _plan!.items) item.closed]);
      interpolatePlan(_plan!, t, _outputs!, strategy: interpolation);
      _target = source;
      _targetPaintStyle = source.paintStyle;
      if (!identical(_targetPathsSource, source)) {
        _targetPathsSource = source;
        _targetPaths = List<CubicPath>.unmodifiable(iconToCubics(source));
      }
      _progress = t;
      final endpoint = t >= 1 - 1e-6 ? source : _planStartSource ?? base;
      _current = endpoint;
      _currentPaintStyle = endpoint.paintStyle;
      _velocity = 0;
      _spring.target = 1;
      _spring.position = t;
      _spring.velocity = 0;
      _spring.running = false;
      _stopTicker();
      _status = t == 1 ? MeldIconStatus.completed : MeldIconStatus.paused;
      notifyListeners();
    } on MeldException catch (error) {
      _fail(error);
    }
  }

  void pause() {
    if (_status != MeldIconStatus.running) return;
    _stopTicker();
    _status = MeldIconStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_status != MeldIconStatus.paused) return;
    if (!_spring.running) {
      _spring.retarget(_spring.target);
      _transition ??= Completer<MeldTransitionResult>();
    }
    _status = MeldIconStatus.running;
    _lastTick = null;
    _startTicker();
    notifyListeners();
    if (_tickerHub == null) _finishAtSpringTarget();
  }

  /// Reverses the current transition from its current shape.
  ///
  /// The existing geometry plan is kept, while the spring target and velocity
  /// direction are exchanged in place. This preserves the visible position
  /// and spring phase, so the first effective frame travels immediately in the
  /// opposite direction without a restart hitch. At a settled endpoint the
  /// opposite source is instead played as a fresh forward transition, keeping
  /// the endpoint canonical and avoiding a reverse-path flash.
  Future<MeldTransitionResult> reverse({
    SpringConfig? spring,
    SpringPreset? preset,
  }) {
    _ensureAlive();
    try {
      return _reverse(spring: spring, preset: preset);
    } on MeldException catch (error) {
      _fail(error);
      return Future.error(error);
    }
  }

  Future<MeldTransitionResult> _reverse({
    SpringConfig? spring,
    SpringPreset? preset,
  }) {
    _lastError = null;
    final plan = _plan;
    final outputs = _outputs;
    if (plan != null && outputs != null && _target != null) {
      final start = _progress.clamp(0, 1).toDouble();
      final atStart = start <= 1e-6;
      final atEnd = start >= 1 - 1e-6;
      if (_status == MeldIconStatus.completed && (atStart || atEnd)) {
        final destination = atEnd ? _planStartSource : _target;
        if (destination != null) {
          return morphTo(destination, spring: spring, preset: preset);
        }
      }
      final end = atStart && _status != MeldIconStatus.running
          ? 1.0
          : atEnd && _status != MeldIconStatus.running
              ? 0.0
              : (_spring.target == 1 ? 0.0 : 1.0);
      final config =
          spring ?? (preset == null ? _spring.config : springPreset(preset));
      _spring.configure(config);
      _prepareReversePaintStyles(end);
      // The spring itself lives in the same normalized coordinate as the
      // geometry plan. Preserve the exact visible position and reverse the
      // velocity sign so the first effective frame travels immediately in
      // the opposite direction without restarting the spring phase.
      _spring.position = start;
      if (_motionDisabled) {
        _spring.retarget(end, inheritedVelocity: 0);
        _finishAtSpringTarget();
        return Future.value(
            const MeldTransitionResult(MeldTransitionEnd.completed));
      }
      _spring.retarget(end, inheritedVelocity: -_velocity);
      _velocity = _spring.velocity;
      final transition = _transition ??= Completer<MeldTransitionResult>();
      final future = transition.future;
      _status = MeldIconStatus.running;
      _lastTick = null;
      _startTicker();
      notifyListeners();
      if (_tickerHub == null) _finishAtSpringTarget();
      return future;
    }

    final previous = _previousSource;
    if (previous == null) {
      return Future.value(
          const MeldTransitionResult(MeldTransitionEnd.completed));
    }
    return morphTo(previous, spring: spring, preset: preset);
  }

  void reset() {
    if (_current != null) set(_current!);
  }

  bool get _motionDisabled =>
      motionMode == MeldMotionMode.never ||
      (motionMode == MeldMotionMode.user && userAnimationsDisabled);

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
    _tickerHub?.detach(this);
    _tickerHub = null;
    _completePrevious(MeldTransitionEnd.disposed);
    _status = MeldIconStatus.disposed;
    _plan = null;
    _outputs = null;
    _outputViews = null;
    _closed = null;
    _previousSource = null;
    _planStartSource = null;
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
    return CubicSource(paths, paintStyle: currentPaintStyle);
  }

  void _onTick(Duration elapsed) {
    if (_status != MeldIconStatus.running) return;
    final previous = _lastTick;
    _lastTick = elapsed;
    final dt =
        previous == null ? 0.0 : (elapsed - previous).inMicroseconds / 1000000;
    late final bool settled;
    try {
      settled = _spring.step(dt);
    } on MeldException catch (error) {
      _fail(error);
      return;
    }
    _progress = _spring.position.clamp(0, 1).toDouble();
    _velocity = _spring.velocity;
    final plan = _plan;
    final outputs = _outputs;
    if (plan != null && outputs != null)
      interpolatePlan(plan, _progress, outputs, strategy: interpolation);
    notifyListeners();
    if (settled) {
      _stopTicker();
      _finishAtSpringTarget();
    }
  }

  void _stopTicker() {
    _tickerHub?.stop(this);
    _lastTick = null;
  }

  void _startTicker() {
    _tickerHub?.start(this);
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
    _finishAtSpringTarget();
  }

  void _finishAtSpringTarget() {
    final movingForward = _spring.target >= 1 - 1e-6;
    final target = _spring.target;
    final destination = movingForward ? _target : _planStartSource ?? _current;
    if (movingForward) {
      if (_planStartSource != null) _previousSource = _planStartSource;
    } else if (_target != null) {
      _previousSource = _target;
    }
    if (destination != null) {
      _current = destination;
      _currentPaintStyle = destination.paintStyle;
      _targetPaintStyle = _currentPaintStyle;
      _currentPaths = List<CubicPath>.unmodifiable(iconToCubics(destination));
      if (movingForward) {
        _target = destination;
        _targetPathsSource = destination;
        _targetPaths = _currentPaths;
      }
    }
    _spring.position = target;
    _spring.velocity = 0;
    _spring.running = false;
    _progress = target;
    _velocity = 0;
    _status = MeldIconStatus.completed;
    _completePrevious(MeldTransitionEnd.completed);
    notifyListeners();
  }

  void _prepareReversePaintStyles(double target) {
    if (target >= 1 - 1e-6) {
      _currentPaintStyle = _planStartPaintStyle;
      _targetPaintStyle = _planTargetPaintStyle;
    } else {
      _currentPaintStyle = _planTargetPaintStyle;
      _targetPaintStyle = _planStartPaintStyle;
    }
  }

  void _ensureAlive() {
    if (_status == MeldIconStatus.disposed)
      throw StateError('MeldIconController has been disposed.');
  }
}

bool _sameGeometry(MeldSource a, MeldSource b) {
  final left = iconToCubics(a);
  final right = iconToCubics(b);
  if (left.length != right.length) return false;
  for (var path = 0; path < left.length; path++) {
    final aPath = left[path];
    final bPath = right[path];
    if (aPath.closed != bPath.closed ||
        aPath.points.length != bPath.points.length) {
      return false;
    }
    for (var i = 0; i < aPath.points.length; i++) {
      if (aPath.points[i] != bPath.points[i]) return false;
    }
  }
  return true;
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
  }) : super(repaint: controller) {
    viewBox.validate();
    if (!strokeWidth.isFinite || strokeWidth < 0) {
      throw MeldException('invalid-stroke-width',
          'Stroke width must be finite and non-negative.');
    }
    _strokePaint = _createPaint(ui.PaintingStyle.stroke);
    _fillPaint = _createPaint(ui.PaintingStyle.fill);
  }

  final MeldIconController controller;
  final MeldViewBox viewBox;
  final ui.Color color;
  final double strokeWidth;
  final ui.StrokeCap strokeCap;
  final ui.StrokeJoin strokeJoin;
  final bool antiAlias;
  final MeldPaintStyle paintStyle;
  late final ui.Paint _strokePaint;
  late final ui.Paint _fillPaint;
  final ui.Path _allPath = ui.Path();
  final ui.Path _closedPath = ui.Path()..fillType = ui.PathFillType.evenOdd;
  final ui.Path _openPath = ui.Path();
  final ui.Path _segmentPath = ui.Path();
  double _limitedControlX = 0;
  double _limitedControlY = 0;

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
    _strokePaint.color = color;
    _fillPaint.color = color;
    final progress = controller.progress;
    final atCanonicalEndpoint =
        !controller.isAnimating && (progress <= 1e-6 || progress >= 1 - 1e-6);
    final outputs = atCanonicalEndpoint ? null : controller.flightPaths;
    final closed = controller.closedPaths;
    _allPath.reset();
    _closedPath.reset();
    _closedPath.fillType = ui.PathFillType.evenOdd;
    _openPath.reset();
    var hasOpenContours = false;
    if (outputs != null && closed != null) {
      for (var i = 0; i < outputs.length; i++) {
        _segmentPath.reset();
        _appendFlightPath(_segmentPath, outputs[i], closed[i]);
        _allPath.addPath(_segmentPath, ui.Offset.zero);
        if (closed[i]) {
          _closedPath.addPath(_segmentPath, ui.Offset.zero);
        } else {
          _openPath.addPath(_segmentPath, ui.Offset.zero);
          hasOpenContours = true;
        }
      }
    } else {
      final paths = controller.canonicalPaths;
      if (paths != null) {
        for (final cubic in paths) {
          _segmentPath.reset();
          _appendCubicPath(_segmentPath, cubic);
          _allPath.addPath(_segmentPath, ui.Offset.zero);
          if (cubic.closed) {
            _closedPath.addPath(_segmentPath, ui.Offset.zero);
          } else {
            _openPath.addPath(_segmentPath, ui.Offset.zero);
            hasOpenContours = true;
          }
        }
      }
    }
    _draw(canvas, _allPath, _closedPath, _openPath, hasOpenContours);
    canvas.restore();
  }

  ui.Paint _createPaint(ui.PaintingStyle style) => ui.Paint()
    ..color = color
    ..style = style
    ..strokeWidth = strokeWidth
    ..strokeCap = strokeCap
    ..strokeJoin = strokeJoin
    ..isAntiAlias = antiAlias;

  void _draw(
    ui.Canvas canvas,
    ui.Path allPath,
    ui.Path closedPath,
    ui.Path openPath,
    bool hasOpenContours,
  ) {
    switch (paintStyle) {
      case MeldPaintStyle.outline:
        canvas.drawPath(allPath, _strokePaint);
      case MeldPaintStyle.original:
        _drawOriginal(
          canvas,
          allPath,
          closedPath,
          openPath,
          hasOpenContours,
        );
      case MeldPaintStyle.both:
        canvas.drawPath(closedPath, _fillPaint);
        canvas.drawPath(allPath, _strokePaint);
    }
  }

  void _drawOriginal(
    ui.Canvas canvas,
    ui.Path allPath,
    ui.Path closedPath,
    ui.Path openPath,
    bool hasOpenContours,
  ) {
    final progress = controller.progress.clamp(0, 1).toDouble();
    final current = controller._plan == null
        ? controller.currentPaintStyle
        : controller._planStartPaintStyle;
    final target = controller._plan == null
        ? controller.targetPaintStyle
        : controller._planTargetPaintStyle;
    final fillOpacity =
        _lerp(_fillWeight(current), _fillWeight(target), progress);
    final strokeOpacity =
        _lerp(_strokeWeight(current), _strokeWeight(target), progress);
    if (fillOpacity > 1e-6) {
      _fillPaint.color = _withOpacity(fillOpacity);
      canvas.drawPath(closedPath, _fillPaint);
    }
    if (strokeOpacity > 1e-6) {
      _strokePaint.color = _withOpacity(strokeOpacity);
      canvas.drawPath(allPath, _strokePaint);
    }
    if (hasOpenContours && strokeOpacity <= 1e-6 && fillOpacity > 1e-6) {
      _strokePaint.color = _withOpacity(fillOpacity);
      canvas.drawPath(openPath, _strokePaint);
    }
  }

  double _fillWeight(MeldSourcePaintStyle style) =>
      style == MeldSourcePaintStyle.outline ? 0 : 1;

  double _strokeWeight(MeldSourcePaintStyle style) =>
      style == MeldSourcePaintStyle.fill ? 0 : 1;

  double _lerp(double start, double end, double value) =>
      start + (end - start) * value;

  ui.Color _withOpacity(double opacity) => ui.Color.fromARGB(
        // ignore: deprecated_member_use
        (color.alpha * opacity).round().clamp(0, 255),
        // ignore: deprecated_member_use
        color.red,
        // ignore: deprecated_member_use
        color.green,
        // ignore: deprecated_member_use
        color.blue,
      );

  void _appendFlightPath(ui.Path path, Float64List points, bool close) {
    final count = points.length ~/ 2;
    path.moveTo(points[0], points[1]);
    if (count < 2) return;

    final segmentCount = close ? count : count - 1;
    for (var segment = 0; segment < segmentCount; segment++) {
      final startX = _flightCoordinate(points, count, segment, 0, close);
      final startY = _flightCoordinate(points, count, segment, 1, close);
      final endX = _flightCoordinate(points, count, segment + 1, 0, close);
      final endY = _flightCoordinate(points, count, segment + 1, 1, close);
      final previousX = _flightCoordinate(points, count, segment - 1, 0, close);
      final previousY = _flightCoordinate(points, count, segment - 1, 1, close);
      final nextNextX = _flightCoordinate(points, count, segment + 2, 0, close);
      final nextNextY = _flightCoordinate(points, count, segment + 2, 1, close);
      final startWeight = _cornerWeight(points, count, segment, close);
      final endWeight = _cornerWeight(points, count, segment + 1, close);
      final startHandleX = startX + (endX - previousX) * startWeight / 6;
      final startHandleY = startY + (endY - previousY) * startWeight / 6;
      final endHandleX = endX - (nextNextX - startX) * endWeight / 6;
      final endHandleY = endY - (nextNextY - startY) * endWeight / 6;
      final chordX = endX - startX;
      final chordY = endY - startY;
      final chord = math.sqrt(chordX * chordX + chordY * chordY);
      final maxHandle = chord * 0.5;
      _setLimitedControl(startX, startY, startHandleX, startHandleY, maxHandle);
      final limitedStartX = _limitedControlX;
      final limitedStartY = _limitedControlY;
      _setLimitedControl(endX, endY, endHandleX, endHandleY, maxHandle);
      final limitedEndX = _limitedControlX;
      final limitedEndY = _limitedControlY;
      path.cubicTo(
        limitedStartX,
        limitedStartY,
        limitedEndX,
        limitedEndY,
        endX,
        endY,
      );
    }
    if (close) path.close();
  }

  double _flightCoordinate(
      Float64List points, int count, int index, int axis, bool close) {
    if (close) {
      index %= count;
      if (index < 0) index += count;
    } else {
      index = index.clamp(0, count - 1);
    }
    return points[index * 2 + axis];
  }

  double _cornerWeight(Float64List points, int count, int index, bool close) {
    if (!close && (index <= 0 || index >= count - 1)) return 1;
    final previousX = _flightCoordinate(points, count, index - 1, 0, close);
    final previousY = _flightCoordinate(points, count, index - 1, 1, close);
    final currentX = _flightCoordinate(points, count, index, 0, close);
    final currentY = _flightCoordinate(points, count, index, 1, close);
    final nextX = _flightCoordinate(points, count, index + 1, 0, close);
    final nextY = _flightCoordinate(points, count, index + 1, 1, close);
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

  void _setLimitedControl(double baseX, double baseY, double controlX,
      double controlY, double maxDistance) {
    final deltaX = controlX - baseX;
    final deltaY = controlY - baseY;
    final distance = math.sqrt(deltaX * deltaX + deltaY * deltaY);
    if (distance <= maxDistance || distance < 1e-9) {
      _limitedControlX = controlX;
      _limitedControlY = controlY;
      return;
    }
    final scale = maxDistance / distance;
    _limitedControlX = baseX + deltaX * scale;
    _limitedControlY = baseY + deltaY * scale;
  }

  void _appendCubicPath(ui.Path path, CubicPath source) {
    final points = source.points;
    path.moveTo(points[0], points[1]);
    for (var i = 2; i < points.length; i += 6) {
      path.cubicTo(points[i], points[i + 1], points[i + 2], points[i + 3],
          points[i + 4], points[i + 5]);
    }
    if (source.closed) path.close();
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
                  Text('cache bytes: ${stats.bytes}'),
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.attach(this);
    _applyOptions();
    // `TickerMode.of` keeps the package compatible with the declared Flutter
    // minimum; the newer valuesOf API is not available on all supported SDKs.
    // ignore: deprecated_member_use
    controller.tickerEnabled = TickerMode.of(context);
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
    // ignore: deprecated_member_use
    controller.tickerEnabled = TickerMode.of(context);
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
    if (ownsController) {
      controller.motionMode = widget.motionMode ?? theme.motionMode;
      controller.interpolation = widget.interpolation ?? theme.interpolation;
    } else {
      // An external controller owns its motion policy. Widget-level values
      // remain explicit overrides, while a theme's defaults must not reset
      // controller configuration during the first attach or a rebuild.
      if (widget.motionMode != null) controller.motionMode = widget.motionMode!;
      if (widget.interpolation != null) {
        controller.interpolation = widget.interpolation!;
      }
    }
    controller.userAnimationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.size.isFinite || widget.size <= 0) {
      throw MeldException(
        'invalid-icon-size',
        'MeldIcon size must be finite and greater than zero.',
      );
    }
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
