import 'dart:io';

const _forbidden = <String>['morphicons'];
const _ignoredDirectories = <String>{
  '.git',
  '.dart_tool',
  '.third',
  'build',
  'coverage',
  'doc',
  '.idea',
  'ephemeral',
};
const _ignoredFiles = <String>{
  'flutter_export_environment.sh',
  'Generated.xcconfig',
  'Flutter-Generated.xcconfig',
  'FlutterInputs.xcfilelist',
  'FlutterOutputs.xcfilelist',
  'flutter_native_integration.env',
  'check_brand.dart',
};

void main() {
  final violations = <String>[];
  for (final entity in Directory.current.listSync(recursive: true)) {
    if (entity is! File ||
        _isIgnored(entity.path) ||
        _ignoredFiles.contains(entity.uri.pathSegments.last)) continue;
    final bytes = entity.readAsBytesSync();
    if (bytes.contains(0)) continue;
    final text = String.fromCharCodes(bytes).toLowerCase();
    for (final term in _forbidden) {
      if (text.contains(term)) {
        violations.add('${entity.path}: contains forbidden brand "$term"');
      }
    }
  }
  if (violations.isNotEmpty) {
    stderr.write('${violations.join('\n')}\n');
    exitCode = 1;
    return;
  }
  stdout.writeln('Brand scan passed.');
}

bool _isIgnored(String path) {
  final parts = path.split(Platform.pathSeparator);
  return parts.any(_ignoredDirectories.contains);
}
