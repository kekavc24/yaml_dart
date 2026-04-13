import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

const rootRepository = 'kekavc24/rookie_yaml';
const testSuiteLabel = '![test_suite]';
const testSuiteUrlPrefix = 'https://img.shields.io/badge/YAML_Test_Suite';

extension Cmd on int {
  bool get isSuccess => this == 0;
}

/// Runs the [command] with its [args] and applies the [mapper] function to
/// the standard output obtained from the command.
T runCommand<T>(
  String command, {
  required List<String> args,
  required String directory,
  String? messageOnFail,
  T Function(String stdout)? mapper,
}) {
  final ProcessResult(:exitCode, :stdout, :stderr) = Process.runSync(
    command,
    args,
    workingDirectory: directory,
  );

  if (!exitCode.isSuccess) {
    throw Exception('Exit: $exitCode\n${messageOnFail ?? stderr}');
  }

  final mOrN = mapper ?? (s) => s.trim() as T;
  return mOrN(stdout);
}

const _defaultPassRate = 0.0;

/// Reads the current pass rate attached to the `README.md` file
double getCurrentPassRate(String rootDirectory) {
  final file = File(path.join(rootDirectory, 'README.md'));

  if (!file.existsSync()) return _defaultPassRate;

  final line = file.readAsLinesSync().firstWhereOrNull(
    (l) => l.startsWith(testSuiteLabel),
  );

  if (line != null) {
    // Remove "![test_suite](https://img.shields.io/badge/YAML_Test_Suite-"
    final trailing = line.replaceFirst(
      '$testSuiteLabel($testSuiteUrlPrefix-',
      '',
    );

    // Remove trailing color -> "%25-green)"
    return double.tryParse(trailing.substring(0, trailing.lastIndexOf('%'))) ??
        _defaultPassRate;
  }

  return _defaultPassRate;
}

/// Adds a [comment] to a [pr].
void addBotComment(String pr, String directory, String comment) {
  final temp = path.joinAll([directory, 'body']);

  // Avoid some "gh" quirks. Write the file and let "gh" read it whichever way
  // it sees fit.
  File(temp).writeAsStringSync(comment);

  runCommand(
    'gh',
    args: ['pr', 'comment', pr, '-R', rootRepository, '-F', temp],
    directory: directory,
  );
}
