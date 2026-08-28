import 'model.dart';

sealed class RawSegment {
  const RawSegment();
}

final class RawLine extends RawSegment {
  const RawLine(this.x, this.y);
  final double x;
  final double y;
}

final class RawCubic extends RawSegment {
  const RawCubic(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x;
  final double y;
}

final class RawQuadratic extends RawSegment {
  const RawQuadratic(this.x1, this.y1, this.x, this.y);
  final double x1;
  final double y1;
  final double x;
  final double y;
}

final class RawArc extends RawSegment {
  const RawArc(
    this.rx,
    this.ry,
    this.rotation,
    this.large,
    this.sweep,
    this.x,
    this.y,
  );
  final double rx;
  final double ry;
  final double rotation;
  final bool large;
  final bool sweep;
  final double x;
  final double y;
}

final class RawSubpath {
  RawSubpath(this.x0, this.y0);
  final double x0;
  final double y0;
  final List<RawSegment> segments = <RawSegment>[];
  bool closed = false;
}

bool _isCommand(int code) => 'MmLlHhVvCcSsQqTtAaZz'.codeUnits.contains(code);

/// Parses SVG path data into absolute raw segments with shorthand commands
/// expanded. The normalizer intentionally owns conversion to cubic paths.
List<RawSubpath> parsePath(String data) {
  final parser = _PathParser(data);
  return parser.parse();
}

final class _PathParser {
  _PathParser(this.data);

  final String data;
  int index = 0;
  double currentX = 0;
  double currentY = 0;
  double startX = 0;
  double startY = 0;
  double previousControlX = 0;
  double previousControlY = 0;
  String previous = '';
  String command = '';
  RawSubpath? current;
  bool started = false;
  final List<RawSubpath> output = <RawSubpath>[];

  Never fail(String message) {
    throw MeldException('invalid-path', message, offset: index, source: data);
  }

  List<RawSubpath> parse() {
    if (data.length > 1 << 20) {
      fail('Path data exceeds the 1 MiB safety limit.');
    }
    while (true) {
      skip();
      if (index >= data.length) break;
      final code = data.codeUnitAt(index);
      if (_isCommand(code)) {
        command = data[index++];
      } else if (command.isEmpty) {
        fail('Path must start with a move command.');
      } else if (command == 'M') {
        command = 'L';
      } else if (command == 'm') {
        command = 'l';
      } else if (command.toUpperCase() == 'Z') {
        fail('Unexpected data after close command.');
      }

      final upper = command.toUpperCase();
      final relative = command == command.toLowerCase();
      switch (upper) {
        case 'M':
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          started = true;
          currentX = x;
          currentY = y;
          startX = x;
          startY = y;
          current = RawSubpath(x, y);
          output.add(current!);
          previous = '';
          command = relative ? 'l' : 'L';
          break;
        case 'L':
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          open().segments.add(RawLine(x, y));
          currentX = x;
          currentY = y;
          previous = '';
          break;
        case 'H':
          final x = coordinate(relative, true);
          open().segments.add(RawLine(x, currentY));
          currentX = x;
          previous = '';
          break;
        case 'V':
          final y = coordinate(relative, false);
          open().segments.add(RawLine(currentX, y));
          currentY = y;
          previous = '';
          break;
        case 'C':
          final x1 = command.toUpperCase() == 'C'
              ? coordinate(relative, true)
              : reflectedX('C');
          final y1 = command.toUpperCase() == 'C'
              ? coordinate(relative, false)
              : reflectedY('C');
          final x2 = coordinate(relative, true);
          final y2 = coordinate(relative, false);
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          open().segments.add(RawCubic(x1, y1, x2, y2, x, y));
          previousControlX = x2;
          previousControlY = y2;
          currentX = x;
          currentY = y;
          previous = 'C';
          break;
        case 'S':
          final x1 = reflectedX('C');
          final y1 = reflectedY('C');
          final x2 = coordinate(relative, true);
          final y2 = coordinate(relative, false);
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          open().segments.add(RawCubic(x1, y1, x2, y2, x, y));
          previousControlX = x2;
          previousControlY = y2;
          currentX = x;
          currentY = y;
          previous = 'C';
          break;
        case 'Q':
          final x1 = command.toUpperCase() == 'Q'
              ? coordinate(relative, true)
              : reflectedX('Q');
          final y1 = command.toUpperCase() == 'Q'
              ? coordinate(relative, false)
              : reflectedY('Q');
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          open().segments.add(RawQuadratic(x1, y1, x, y));
          previousControlX = x1;
          previousControlY = y1;
          currentX = x;
          currentY = y;
          previous = 'Q';
          break;
        case 'T':
          final x1 = reflectedX('Q');
          final y1 = reflectedY('Q');
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          open().segments.add(RawQuadratic(x1, y1, x, y));
          previousControlX = x1;
          previousControlY = y1;
          currentX = x;
          currentY = y;
          previous = 'Q';
          break;
        case 'A':
          final rx = number();
          final ry = number();
          final rotation = number();
          final large = flag();
          final sweep = flag();
          final x = coordinate(relative, true);
          final y = coordinate(relative, false);
          open().segments.add(RawArc(rx, ry, rotation, large, sweep, x, y));
          currentX = x;
          currentY = y;
          previous = '';
          break;
        case 'Z':
          if (current != null) {
            current!.closed = true;
            current = null;
          }
          currentX = startX;
          currentY = startY;
          previous = '';
          command = '';
          break;
        default:
          fail('Unsupported path command "$command".');
      }
    }
    final segments = output.fold<int>(
        0, (count, subpath) => count + subpath.segments.length);
    if (segments > kMeldMaxCubicSegments) {
      fail('Path contains too many segments.');
    }
    return List<RawSubpath>.unmodifiable(
      output.where((subpath) => subpath.segments.isNotEmpty),
    );
  }

  RawSubpath open() {
    if (!started) fail('Path must start with a move command.');
    if (current == null) {
      current = RawSubpath(currentX, currentY);
      output.add(current!);
    }
    return current!;
  }

  double reflectedX(String type) =>
      previous == type ? 2 * currentX - previousControlX : currentX;

  double reflectedY(String type) =>
      previous == type ? 2 * currentY - previousControlY : currentY;

  double coordinate(bool relative, bool xAxis) {
    final value = number();
    if (!relative) return value;
    return value + (xAxis ? currentX : currentY);
  }

  bool flag() {
    skip();
    if (index >= data.length || (data[index] != '0' && data[index] != '1')) {
      fail('Arc flags must be a single 0 or 1.');
    }
    return data[index++] == '1';
  }

  double number() {
    skip();
    final start = index;
    if (index < data.length && (data[index] == '+' || data[index] == '-')) {
      index++;
    }
    var digits = false;
    while (index < data.length && _isDigit(data.codeUnitAt(index))) {
      digits = true;
      index++;
    }
    if (index < data.length && data[index] == '.') {
      index++;
      while (index < data.length && _isDigit(data.codeUnitAt(index))) {
        digits = true;
        index++;
      }
    }
    if (!digits) fail('Expected a number.');
    if (index < data.length && (data[index] == 'e' || data[index] == 'E')) {
      final exponentStart = index++;
      if (index < data.length && (data[index] == '+' || data[index] == '-')) {
        index++;
      }
      var exponentDigits = false;
      while (index < data.length && _isDigit(data.codeUnitAt(index))) {
        exponentDigits = true;
        index++;
      }
      if (!exponentDigits) index = exponentStart;
    }
    final value = double.tryParse(data.substring(start, index));
    if (value == null || !value.isFinite || value.abs() > kMeldMaxCoordinate) {
      fail(
        value == null || !value.isFinite
            ? 'Number is not finite.'
            : 'Number exceeds the supported coordinate range.',
      );
    }
    return value;
  }

  void skip() {
    while (index < data.length) {
      final code = data.codeUnitAt(index);
      if (code == 32 ||
          code == 9 ||
          code == 10 ||
          code == 13 ||
          code == 12 ||
          code == 44) {
        index++;
      } else {
        break;
      }
    }
  }
}

bool _isDigit(int code) => code >= 48 && code <= 57;
