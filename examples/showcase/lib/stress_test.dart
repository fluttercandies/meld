import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meld/meld.dart';

const _stressFrom = PathDataSource('M3 6H21M3 12H21M3 18H21');
const _stressTo = PathDataSource('M5 5L19 19M19 5L5 19');

/// A deliberately dense page for checking multi-instance animation cost.
///
/// Every cell is mounted so each controller participates in the shared ticker;
/// the page avoids listening to the controllers from its parent, keeping frame
/// updates inside each [MeldIcon]'s painter boundary.
final class StressTestPage extends StatefulWidget {
  const StressTestPage({super.key});

  @override
  State<StressTestPage> createState() => _StressTestPageState();
}

final class _StressTestPageState extends State<StressTestPage> {
  static const counts = <int>[25, 100, 250];

  late MeldEngine _engine;
  late List<MeldIconController> _controllers;
  var _count = 100;

  @override
  void initState() {
    super.initState();
    _createControllers();
  }

  void _createControllers() {
    _engine = MeldEngine(
      sampling: const SamplingConfig(pointCount: 32, maxPointCount: 64),
    );
    _controllers = List<MeldIconController>.generate(
      _count,
      (_) => MeldIconController(
        engine: _engine,
        initialSource: _stressFrom,
      )
        ..motionMode = MeldMotionMode.always
        ..interpolation = MeldInterpolationStrategy.tangentAware,
      growable: false,
    );
  }

  void _disposeControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
  }

  void _setCount(int count) {
    if (_count == count) return;
    _disposeControllers();
    setState(() {
      _count = count;
      _createControllers();
    });
  }

  void _playAll() {
    final moveTo = _controllers.every(
      (controller) => controller.currentSource == _stressTo,
    )
        ? _stressFrom
        : _stressTo;
    for (final controller in _controllers) {
      unawaited(controller.morphTo(moveTo));
    }
  }

  void _reverseAll() {
    for (final controller in _controllers) {
      // Reset clears the previous plan, so seed the opposite transition when
      // there is no in-flight geometry to reverse.
      if (controller.currentSource == _stressFrom &&
          controller.target == _stressFrom) {
        unawaited(controller.morphTo(_stressTo));
      } else {
        unawaited(controller.reverse());
      }
    }
  }

  void _resetAll() {
    for (final controller in _controllers) {
      controller.set(_stressFrom);
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stress test'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Many icons, one shared scheduler',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All $_count controllers stay mounted and animate the same cached pair. Use Flutter DevTools or the performance overlay to inspect frame time on the target device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      const Text('Instances'),
                      for (final count in counts)
                        ChoiceChip(
                          key: ValueKey<String>('stress-count-$count'),
                          label: Text('$count'),
                          selected: _count == count,
                          onSelected: (_) => _setCount(count),
                        ),
                      FilledButton.icon(
                        key: const ValueKey<String>('stress-play-all'),
                        onPressed: _playAll,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play all'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey<String>('stress-reverse-all'),
                        onPressed: _reverseAll,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Reverse all'),
                      ),
                      TextButton.icon(
                        key: const ValueKey<String>('stress-reset-all'),
                        onPressed: _resetAll,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All controllers share one bounded plan cache and one isolate ticker.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900
                        ? 12
                        : constraints.maxWidth >= 620
                            ? 8
                            : constraints.maxWidth >= 420
                                ? 6
                                : 4;
                    return GridView.builder(
                      key: const ValueKey<String>('stress-grid'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _controllers.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        return _StressCell(
                          key: ValueKey<String>('stress-cell-$index'),
                          controller: _controllers[index],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _StressCell extends StatelessWidget {
  const _StressCell({required this.controller, super.key});

  final MeldIconController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Center(
        child: MeldIcon(
          controller: controller,
          size: 34,
          color: scheme.onSurface,
          strokeWidth: 1.6,
          paintStyle: MeldPaintStyle.outline,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
