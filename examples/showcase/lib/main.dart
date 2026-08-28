import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meld/meld.dart' hide Alignment;

abstract final class _MeldColors {
  static const canvas = Color(0xFF090A0F);
  static const surface = Color(0xFF11131B);
  static const surfaceRaised = Color(0xFF171A24);
  static const ink = Color(0xFFF5F7FF);
  static const inkMuted = Color(0xFFA7ACBD);
  static const accent = Color(0xFF6D5EF7);
  static const accentBright = Color(0xFF8B7FFF);
  static const grid = Color(0x0DFFFFFF);
  static const outline = Color(0x1FFFFFFF);
}

Color _withOpacity(Color color, double opacity) => Color.fromARGB(
      // ignore: deprecated_member_use
      (color.alpha * opacity).round().clamp(0, 255),
      // ignore: deprecated_member_use
      color.red,
      // ignore: deprecated_member_use
      color.green,
      // ignore: deprecated_member_use
      color.blue,
    );

void main() => runApp(const MeldShowcaseApp());

class MeldShowcaseApp extends StatelessWidget {
  const MeldShowcaseApp(
      {super.key, this.navigatorObservers = const <NavigatorObserver>[]});

  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meld showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _MeldColors.canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _MeldColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _MeldColors.accentBright,
          onPrimary: _MeldColors.ink,
          surface: _MeldColors.surface,
          onSurface: _MeldColors.ink,
          outline: _MeldColors.outline,
        ),
        textTheme: const TextTheme(
          displaySmall: TextStyle(
            color: _MeldColors.ink,
            fontSize: 36,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
          ),
          headlineSmall: TextStyle(
            color: _MeldColors.ink,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: _MeldColors.ink,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(
            color: _MeldColors.inkMuted,
            fontSize: 14,
            height: 1.35,
          ),
          labelLarge: TextStyle(
            color: _MeldColors.ink,
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        sliderTheme: const SliderThemeData(
          showValueIndicator: ShowValueIndicator.onDrag,
          trackHeight: 3,
        ),
      ),
      navigatorObservers: navigatorObservers,
      home: const ShowcaseHome(),
    );
  }
}

enum _SourceFamily { path, svg, font }

enum _Endpoint { from, to }

class _IconOption {
  const _IconOption({
    required this.id,
    required this.name,
    required this.family,
    required this.source,
  });

  final String id;
  final String name;
  final _SourceFamily family;
  final MeldSource source;
}

class _IconPair {
  const _IconPair(this.name, this.fromId, this.toId);
  final String name;
  final String fromId;
  final String toId;
}

const _pairs = <_IconPair>[
  _IconPair('Menu ↔ close', 'path-menu', 'path-close'),
  _IconPair('Arrow turn', 'path-arrow-right', 'path-arrow-down'),
  _IconPair('Plus ↔ close', 'path-plus', 'path-close'),
  _IconPair('Check ↔ close', 'path-check', 'path-close'),
  _IconPair('Circle ↔ square', 'path-circle', 'path-square'),
  _IconPair('Diamond ↔ square', 'path-diamond', 'path-square'),
];

const _pathOptions = <_IconOption>[
  _IconOption(
    id: 'path-menu',
    name: 'Menu',
    family: _SourceFamily.path,
    source: PathDataSource('M3 6H21M3 12H21M3 18H21'),
  ),
  _IconOption(
    id: 'path-close',
    name: 'Close',
    family: _SourceFamily.path,
    source: PathDataSource('M5 5L19 19M19 5L5 19'),
  ),
  _IconOption(
    id: 'path-arrow-right',
    name: 'Arrow right',
    family: _SourceFamily.path,
    source: PathDataSource('M4 12H20M13 5L20 12L13 19'),
  ),
  _IconOption(
    id: 'path-arrow-down',
    name: 'Arrow down',
    family: _SourceFamily.path,
    source: PathDataSource('M12 4V20M5 13L12 20L19 13'),
  ),
  _IconOption(
    id: 'path-plus',
    name: 'Plus',
    family: _SourceFamily.path,
    source: PathDataSource('M12 4V20M4 12H20'),
  ),
  _IconOption(
    id: 'path-check',
    name: 'Check',
    family: _SourceFamily.path,
    source: PathDataSource('M4 12L9 17L20 6'),
  ),
  _IconOption(
    id: 'path-circle',
    name: 'Circle',
    family: _SourceFamily.path,
    source: PathDataSource('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3Z'),
  ),
  _IconOption(
    id: 'path-square',
    name: 'Square',
    family: _SourceFamily.path,
    source: PathDataSource('M4 4H20V20H4Z'),
  ),
  _IconOption(
    id: 'path-diamond',
    name: 'Diamond',
    family: _SourceFamily.path,
    source: PathDataSource('M12 3L21 12L12 21L3 12Z'),
  ),
];

const _svgOptions = <_IconOption>[
  _IconOption(
    id: 'svg-ring',
    name: 'Ring',
    family: _SourceFamily.svg,
    source: SvgMarkupSource(
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="9"/></svg>',
    ),
  ),
  _IconOption(
    id: 'svg-rounded',
    name: 'Rounded square',
    family: _SourceFamily.svg,
    source: SvgMarkupSource(
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><rect x="4" y="4" width="16" height="16" rx="4"/></svg>',
    ),
  ),
  _IconOption(
    id: 'svg-chevron',
    name: 'Chevron',
    family: _SourceFamily.svg,
    source: SvgMarkupSource(
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><polyline points="8,4 16,12 8,20"/></svg>',
    ),
  ),
  _IconOption(
    id: 'svg-badge',
    name: 'Badge',
    family: _SourceFamily.svg,
    source: SvgMarkupSource(
      '<svg viewBox="0 0 24 24" fill="currentColor"><polygon points="12,3 21,12 12,21 3,12"/></svg>',
    ),
  ),
  _IconOption(
    id: 'svg-crosshair',
    name: 'Crosshair',
    family: _SourceFamily.svg,
    source: SvgMarkupSource(
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="6"/><line x1="12" y1="2" x2="12" y2="22"/><line x1="2" y1="12" x2="22" y2="12"/></svg>',
    ),
  ),
  _IconOption(
    id: 'svg-spark',
    name: 'Spark',
    family: _SourceFamily.svg,
    source: SvgMarkupSource(
      '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2L14.5 9.5L22 12L14.5 14.5L12 22L9.5 14.5L2 12L9.5 9.5Z"/></svg>',
    ),
  ),
];

String _familyLabel(_SourceFamily family) => switch (family) {
      _SourceFamily.path => 'Path data',
      _SourceFamily.svg => 'SVG markup',
      _SourceFamily.font => 'Font glyph',
    };

int _gridColumnCount(double width) {
  if (width >= 600) return 4;
  if (width >= 320) return 3;
  return 2;
}

class ShowcaseHome extends StatefulWidget {
  const ShowcaseHome({super.key});

  @override
  State<ShowcaseHome> createState() => _ShowcaseHomeState();
}

class _ShowcaseHomeState extends State<ShowcaseHome> {
  late MeldIconController _controller;
  var _activeFamily = _SourceFamily.path;
  var _activeEndpoint = _Endpoint.from;
  var _fromId = 'path-menu';
  var _toId = 'path-close';
  var _quality = 64;
  var _paintStyle = MeldPaintStyle.original;
  var _stiffness = 420.0;
  var _damping = 30.0;
  List<_IconOption> _fontOptions = const <_IconOption>[];
  String? _fontError;

  List<_IconOption> get _activeOptions => switch (_activeFamily) {
        _SourceFamily.path => _pathOptions,
        _SourceFamily.svg => _svgOptions,
        _SourceFamily.font => _fontOptions,
      };

  _IconOption? _findOption(String id) {
    for (final option in _pathOptions) {
      if (option.id == id) return option;
    }
    for (final option in _svgOptions) {
      if (option.id == id) return option;
    }
    for (final option in _fontOptions) {
      if (option.id == id) return option;
    }
    return null;
  }

  _IconOption get _fromOption => _findOption(_fromId) ?? _pathOptions.first;
  _IconOption get _toOption => _findOption(_toId) ?? _pathOptions[1];

  String get _transitionLabel => '${_fromOption.name} → ${_toOption.name}';

  bool get _hasShapeChange {
    if (canonicalPathData(_fromOption.source) !=
        canonicalPathData(_toOption.source)) {
      return true;
    }
    return _paintStyle == MeldPaintStyle.original &&
        _fromOption.source.paintStyle != _toOption.source.paintStyle;
  }

  int get _pairIndex => _pairs.indexWhere(
        (pair) => pair.fromId == _fromId && pair.toId == _toId,
      );

  @override
  void initState() {
    super.initState();
    _controller = _newController(_fromOption.source);
    _controller.seek(_toOption.source, 0);
    unawaited(_loadFontOptions());
  }

  Future<void> _loadFontOptions() async {
    try {
      final data = await rootBundle.load(
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final options = <_IconOption>[
        _fontOption('font-add', 'Add', CupertinoIcons.add, bytes),
        _fontOption('font-clear', 'Close', CupertinoIcons.clear, bytes),
        _fontOption('font-check', 'Check', CupertinoIcons.check_mark, bytes),
        _fontOption('font-circle', 'Circle', CupertinoIcons.circle, bytes),
        _fontOption('font-arrow-right', 'Arrow right',
            CupertinoIcons.arrow_right, bytes),
        _fontOption(
            'font-arrow-down', 'Arrow down', CupertinoIcons.arrow_down, bytes),
      ];
      if (!mounted) return;
      setState(() {
        _fontOptions = options;
        _fontError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _fontError = 'Font fixture unavailable: $error');
    }
  }

  _IconOption _fontOption(
      String id, String name, IconData icon, List<int> fontBytes) {
    return _IconOption(
      id: id,
      name: name,
      family: _SourceFamily.font,
      source: Meld.sourceFromIconData(icon, fontBytes: fontBytes),
    );
  }

  MeldIconController _newController(MeldSource source) {
    final controller = MeldIconController(
      engine: MeldEngine(
        sampling: SamplingConfig(pointCount: _quality, maxPointCount: 128),
      ),
      initialSource: source,
    )
      ..motionMode = MeldMotionMode.always
      ..interpolation = MeldInterpolationStrategy.tangentAware;
    return controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPair(int index) {
    final pair = _pairs[index];
    final from = _findOption(pair.fromId);
    final to = _findOption(pair.toId);
    if (from == null || to == null) return;
    _setEndpoints(from: from, to: to);
    setState(() => _activeFamily = _SourceFamily.path);
  }

  void _setEndpoints({required _IconOption from, required _IconOption to}) {
    _controller.set(from.source);
    _controller.seek(to.source, 0);
    setState(() {
      _fromId = from.id;
      _toId = to.id;
    });
  }

  void _selectEndpoint(_IconOption option) {
    final from = _activeEndpoint == _Endpoint.from ? option : _fromOption;
    final to = _activeEndpoint == _Endpoint.to ? option : _toOption;
    _setEndpoints(from: from, to: to);
  }

  void _selectFamily(_SourceFamily family) {
    final options = switch (family) {
      _SourceFamily.path => _pathOptions,
      _SourceFamily.svg => _svgOptions,
      _SourceFamily.font => _fontOptions,
    };
    if (options.isEmpty) return;
    setState(() => _activeFamily = family);
  }

  void _setActiveEndpoint(_Endpoint endpoint) {
    setState(() => _activeEndpoint = endpoint);
  }

  void _swapEndpoints() {
    final from = _fromOption;
    final to = _toOption;
    _setEndpoints(from: to, to: from);
  }

  void _changeQuality(int points) {
    final progress = _controller.progress.clamp(0, 1).toDouble();
    setState(() => _quality = points);
    final old = _controller;
    final next = _newController(_fromOption.source);
    next.seek(_toOption.source, progress);
    old.dispose();
    setState(() => _controller = next);
  }

  Future<void> _play() async {
    if (!_hasShapeChange) return;
    final spring = SpringConfig(stiffness: _stiffness, damping: _damping);
    if (_controller.status == MeldIconStatus.completed &&
        _controller.progress >= 1 - 1e-6) {
      final from = _fromOption;
      final to = _toOption;
      _setEndpoints(from: to, to: from);
      await _controller.morphTo(from.source, spring: spring);
      return;
    }
    if (_controller.status == MeldIconStatus.paused &&
        _controller.progress > 1e-6) {
      _controller.resume();
      return;
    }
    await _controller.morphTo(
      _toOption.source,
      spring: spring,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 880;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 40 : 16,
                vertical: wide ? 28 : 18,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Header(wide: wide),
                      SizedBox(height: wide ? 24 : 20),
                      wide ? _wideLayout() : _narrowLayout(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _wideLayout() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Expanded(
        flex: 5,
        child: _preview(iconSize: 178, minHeight: 390),
      ),
      const SizedBox(width: 20),
      Expanded(flex: 6, child: _controls()),
    ]);
  }

  Widget _narrowLayout() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _preview(iconSize: 152, minHeight: 340, showPlayButton: true),
          const SizedBox(height: 20),
          _controls(),
        ],
      );

  Widget _preview({
    required double iconSize,
    required double minHeight,
    bool showPlayButton = true,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: _MeldColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _MeldColors.outline),
      ),
      child: Stack(alignment: Alignment.center, children: <Widget>[
        const Positioned.fill(child: _GridBackdrop()),
        Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          MeldIconTheme(
            data: const MeldIconThemeData(
              color: _MeldColors.ink,
              strokeWidth: 1.8,
              strokeCap: StrokeCap.round,
            ),
            child: MeldIcon(
              key: const ValueKey<String>('preview-icon'),
              controller: _controller,
              size: iconSize,
              label: '$_transitionLabel morph preview',
              paintStyle: _paintStyle,
            ),
          ),
          const SizedBox(height: 16),
          Text(_transitionLabel,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${_familyLabel(_fromOption.family)} → ${_familyLabel(_toOption.family)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ]),
        Positioned(
          top: 12,
          right: 12,
          child: MeldDiagnosticsOverlay(controller: _controller),
        ),
        if (showPlayButton)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _primaryPlayButton(),
          ),
      ]),
    );
  }

  Widget _controls() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Explore the motion',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
              'Choose each endpoint, scrub the path, or play it with a physical spring.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          _renderControls(),
          const SizedBox(height: 14),
          Text('Quick pairs', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _gridColumnCount(constraints.maxWidth);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pairs.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 58,
                ),
                itemBuilder: (context, index) => _PairTile(
                  id: 'pair-$index',
                  pair: _pairs[index],
                  from: _findOption(_pairs[index].fromId)!,
                  to: _findOption(_pairs[index].toId)!,
                  paintStyle: _paintStyle,
                  selected: index == _pairIndex,
                  onTap: () => _selectPair(index),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Build a transition',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _endpointRail(),
          const SizedBox(height: 12),
          _sourceFamilies(),
          const SizedBox(height: 10),
          Text(
            'Choose ${_activeEndpoint == _Endpoint.from ? 'a start' : 'an end'} icon',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          _optionGrid(),
          if (_fontError != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _fontError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final progress = _controller.progress.clamp(0, 1).toDouble();
              final isNoOp = !_hasShapeChange;
              return Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'Progress',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      Text(
                        progress.toStringAsFixed(3),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Slider(
                    key: const ValueKey<String>('progress-slider'),
                    value: progress,
                    semanticFormatterCallback: (value) =>
                        'Progress ${(value * 100).round()} percent',
                    onChanged: (value) =>
                        _controller.seek(_toOption.source, value),
                  ),
                  if (isNoOp)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'These endpoints resolve to the same geometry.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _springControls(),
          const SizedBox(height: 12),
          const Text(
              'Reduced motion keeps the endpoint exact and removes the flight automatically.'),
        ]);
  }

  Widget _endpointRail() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: _EndpointCard(
            id: 'from-endpoint',
            eyebrow: 'Start',
            option: _fromOption,
            paintStyle: _paintStyle,
            selected: _activeEndpoint == _Endpoint.from,
            onTap: () => _setActiveEndpoint(_Endpoint.from),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: IconButton(
            key: const ValueKey<String>('swap-endpoints'),
            tooltip: 'Swap start and end icons',
            onPressed: _swapEndpoints,
            icon: const Icon(Icons.swap_horiz_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ),
        Expanded(
          child: _EndpointCard(
            id: 'to-endpoint',
            eyebrow: 'End',
            option: _toOption,
            paintStyle: _paintStyle,
            selected: _activeEndpoint == _Endpoint.to,
            onTap: () => _setActiveEndpoint(_Endpoint.to),
          ),
        ),
      ],
    );
  }

  Widget _sourceFamilies() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _FamilyChip(
          id: 'source-path',
          label: 'Path data',
          family: _SourceFamily.path,
          selected: _activeFamily == _SourceFamily.path,
          onTap: () => _selectFamily(_SourceFamily.path),
        ),
        _FamilyChip(
          id: 'source-svg',
          label: 'SVG markup',
          family: _SourceFamily.svg,
          selected: _activeFamily == _SourceFamily.svg,
          onTap: () => _selectFamily(_SourceFamily.svg),
        ),
        _FamilyChip(
          id: 'source-font',
          label: _fontOptions.isEmpty ? 'Font glyphs · loading' : 'Font glyphs',
          family: _SourceFamily.font,
          selected: _activeFamily == _SourceFamily.font,
          enabled: _fontOptions.isNotEmpty,
          onTap: () => _selectFamily(_SourceFamily.font),
        ),
      ],
    );
  }

  Widget _optionGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumnCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _activeOptions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 58,
          ),
          itemBuilder: (context, index) {
            final option = _activeOptions[index];
            return _OptionTile(
              id: '${_activeEndpoint == _Endpoint.from ? 'from' : 'to'}-${option.id}',
              option: option,
              paintStyle: _paintStyle,
              selected: option.id ==
                  (_activeEndpoint == _Endpoint.from ? _fromId : _toId),
              onTap: () => _selectEndpoint(option),
            );
          },
        );
      },
    );
  }

  Widget _primaryPlayButton() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final isRunning = _controller.status == MeldIconStatus.running;
        final isNoOp = !_hasShapeChange;
        final atEnd = _controller.progress >= 1 - 1e-6;
        final inFlight = _controller.progress > 1e-6 && !atEnd;
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey<String>('play-button'),
            onPressed: isRunning || isNoOp ? null : _play,
            icon: Icon(
              isRunning
                  ? Icons.motion_photos_on_rounded
                  : Icons.play_arrow_rounded,
            ),
            label: Text(
              isRunning
                  ? 'Playing transition…'
                  : isNoOp
                      ? 'Choose different endpoints'
                      : atEnd
                          ? 'Reverse to start'
                          : inFlight
                              ? 'Continue to end'
                              : 'Play spring transition',
            ),
          ),
        );
      },
    );
  }

  Widget _range(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Column(children: <Widget>[
      Row(
        children: <Widget>[
          Text(label),
          const Spacer(),
          Text(value.toStringAsFixed(0)),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        semanticFormatterCallback: (next) => '$label ${next.round()}',
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _springControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stiffness = _range('Stiffness', _stiffness, 80, 900,
            (value) => setState(() => _stiffness = value));
        final damping = _range('Damping', _damping, 4, 90,
            (value) => setState(() => _damping = value));
        if (constraints.maxWidth >= 500) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: stiffness),
              const SizedBox(width: 16),
              Expanded(child: damping),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[stiffness, damping],
        );
      },
    );
  }

  Widget _renderControls() {
    final paint = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Paint', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        const Text('Preview treatment'),
        const SizedBox(height: 8),
        SegmentedButton<MeldPaintStyle>(
          key: const ValueKey<String>('paint-style-selector'),
          showSelectedIcon: false,
          segments: const <ButtonSegment<MeldPaintStyle>>[
            ButtonSegment(
              value: MeldPaintStyle.outline,
              label: Text('Outline'),
            ),
            ButtonSegment(
              value: MeldPaintStyle.original,
              label: Text('Original'),
            ),
            ButtonSegment(
              value: MeldPaintStyle.both,
              label: Text('Both'),
            ),
          ],
          selected: <MeldPaintStyle>{_paintStyle},
          onSelectionChanged: (value) {
            setState(() => _paintStyle = value.first);
          },
        ),
      ],
    );
    final quality = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Quality', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Rendering detail',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text('$_quality samples'),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          key: const ValueKey<String>('quality-selector'),
          showSelectedIcon: false,
          segments: const <ButtonSegment<int>>[
            ButtonSegment(value: 32, label: Text('Fast')),
            ButtonSegment(value: 64, label: Text('Balanced')),
            ButtonSegment(value: 96, label: Text('Detailed')),
          ],
          selected: <int>{_quality},
          onSelectionChanged: (value) => _changeQuality(value.first),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: paint),
              const SizedBox(width: 12),
              Expanded(child: quality),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            paint,
            const SizedBox(height: 14),
            quality,
          ],
        );
      },
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({
    required this.id,
    required this.eyebrow,
    required this.option,
    required this.paintStyle,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String eyebrow;
  final _IconOption option;
  final MeldPaintStyle paintStyle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey<String>(id),
      button: true,
      selected: selected,
      label: 'Choose ${option.name} as $eyebrow icon',
      child: Material(
        color: selected
            ? _withOpacity(scheme.primary, 0.14)
            : _MeldColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : _MeldColors.outline,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                MeldIcon(
                  icon: option.source,
                  size: 30,
                  color: selected ? _MeldColors.ink : _MeldColors.inkMuted,
                  strokeWidth: 1.5,
                  paintStyle: paintStyle,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        eyebrow,
                        style: TextStyle(
                          color:
                              selected ? scheme.primary : _MeldColors.inkMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _MeldColors.ink,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FamilyChip extends StatelessWidget {
  const _FamilyChip({
    required this.id,
    required this.label,
    required this.family,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String id;
  final String label;
  final _SourceFamily family;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Use ${_familyLabel(family)} input',
      child: ChoiceChip(
        key: ValueKey<String>(id),
        label: Text(label),
        selected: selected,
        onSelected: enabled ? (_) => onTap() : null,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.id,
    required this.option,
    required this.paintStyle,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final _IconOption option;
  final MeldPaintStyle paintStyle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey<String>(id),
      button: true,
      selected: selected,
      label: 'Use ${option.name} as icon',
      child: Material(
        color: selected
            ? _withOpacity(scheme.primary, 0.16)
            : _MeldColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : _MeldColors.outline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                MeldIcon(
                  icon: option.source,
                  size: 25,
                  color: selected ? _MeldColors.ink : _MeldColors.inkMuted,
                  strokeWidth: 1.5,
                  paintStyle: paintStyle,
                  excludeFromSemantics: true,
                ),
                const SizedBox(height: 3),
                Text(
                  option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? _MeldColors.ink : _MeldColors.inkMuted,
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({
    required this.id,
    required this.pair,
    required this.from,
    required this.to,
    required this.paintStyle,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final _IconPair pair;
  final _IconOption from;
  final _IconOption to;
  final MeldPaintStyle paintStyle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey<String>(id),
      button: true,
      selected: selected,
      label: 'Select ${pair.name}',
      child: Material(
        color: selected
            ? _withOpacity(scheme.primary, 0.16)
            : _MeldColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : _MeldColors.outline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    MeldIcon(
                      icon: from.source,
                      size: 22,
                      color: selected ? _MeldColors.ink : _MeldColors.inkMuted,
                      strokeWidth: 1.8,
                      paintStyle: paintStyle,
                      excludeFromSemantics: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 13,
                        color: selected
                            ? _MeldColors.accentBright
                            : _MeldColors.inkMuted,
                      ),
                    ),
                    MeldIcon(
                      icon: to.source,
                      size: 22,
                      color: selected ? _MeldColors.ink : _MeldColors.inkMuted,
                      strokeWidth: 1.8,
                      paintStyle: paintStyle,
                      excludeFromSemantics: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pair.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? _MeldColors.ink : _MeldColors.inkMuted,
                    fontSize: 10.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
      _MeldMark(size: wide ? 52 : 44),
      SizedBox(width: wide ? 14 : 12),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Text(
              'Meld',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: wide ? 36 : 32,
                  ),
            ),
            Text(
              'Shape transitions with a point of view.',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: _MeldColors.inkMuted),
            ),
          ])),
      if (wide)
        const Text(
          'Dart · Flutter · deterministic',
          style: TextStyle(color: _MeldColors.inkMuted, fontSize: 13),
        ),
    ]);
  }
}

class _MeldMark extends StatelessWidget {
  const _MeldMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Meld mark',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MeldMarkPainter()),
      ),
    );
  }
}

class _MeldMarkPainter extends CustomPainter {
  const _MeldMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 64;
    canvas
      ..save()
      ..scale(scale);

    final mark = Path()
      ..moveTo(8, 16)
      ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(8))
      ..lineTo(24, 8)
      ..lineTo(24, 24)
      ..lineTo(32, 24)
      ..lineTo(32, 8)
      ..lineTo(40, 8)
      ..arcToPoint(const Offset(48, 16), radius: const Radius.circular(8))
      ..lineTo(48, 24)
      ..lineTo(32, 24)
      ..lineTo(32, 32)
      ..lineTo(48, 32)
      ..lineTo(48, 40)
      ..arcToPoint(const Offset(40, 48), radius: const Radius.circular(8))
      ..lineTo(32, 48)
      ..lineTo(32, 32)
      ..lineTo(24, 32)
      ..lineTo(24, 48)
      ..lineTo(16, 48)
      ..arcToPoint(const Offset(8, 40), radius: const Radius.circular(8))
      ..lineTo(8, 32)
      ..lineTo(24, 32)
      ..lineTo(24, 24)
      ..lineTo(8, 24)
      ..close();

    canvas.drawPath(mark, Paint()..color = _MeldColors.accent);
    canvas.drawRect(
      const Rect.fromLTWH(24, 24, 16, 16),
      Paint()..color = _MeldColors.canvas,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MeldMarkPainter oldDelegate) => false;
}

class _GridBackdrop extends StatelessWidget {
  const _GridBackdrop();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _MeldColors.grid
      ..strokeWidth = 1;
    const gap = 32.0;
    for (var x = gap; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = gap; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
