import 'dart:io';

const thresholds = <String, double>{
  'packages/meld_flutter/coverage/lcov.info': 0.65,
  'examples/showcase/coverage/lcov.info': 0.70,
};

void main() {
  var failed = false;
  for (final entry in thresholds.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      stderr.writeln('Coverage file is missing: ${entry.key}');
      failed = true;
      continue;
    }
    var found = 0;
    var hit = 0;
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('LF:')) {
        found += int.parse(line.substring(3));
      } else if (line.startsWith('LH:')) {
        hit += int.parse(line.substring(3));
      }
    }
    final ratio = found == 0 ? 0.0 : hit / found;
    final percentage = (ratio * 100).toStringAsFixed(1);
    final minimum = (entry.value * 100).toStringAsFixed(1);
    stdout.writeln('${entry.key}: $percentage% (minimum $minimum%)');
    if (ratio < entry.value) failed = true;
  }
  if (failed) {
    stderr.writeln('Coverage regression: one or more thresholds failed.');
    exitCode = 1;
  }
}
