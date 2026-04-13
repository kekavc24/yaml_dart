import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'utils.dart';

const _defaultBranch = 'main';

/// Test suite badge uri regex
final _regex = RegExp(r'(^!\[test_suite\].*$)', multiLine: true);

/// Argument parser to validate args for this script
final _argParser = ArgParser()
  ..addOption(
    'working-directory',
    abbr: 'w',
    mandatory: true,
    help: 'Repo directory',
  )
  ..addOption(
    'pr',
    abbr: 'p',
    mandatory: true,
    help: 'Github PR json event',
  )
  ..addOption(
    'head-SHA',
    abbr: 's',
    mandatory: true,
    help: 'Commit ID at the tip of the PR branch',
  )
  ..addOption(
    'is-package-rookie-yaml',
    mandatory: true,
    help: 'Whether rookie_yaml was updated',
  );

extension on ArgResults {
  /// Unpacks the arguments passed and returns:
  ///   - A directory where the current workflow is running
  ///   - PR number of PR that triggered the merging worflow
  ///   - SHA signature of the commit at the tip of the PR branch. This ensures
  ///     we merge branches in the state they were approved.
  ({String directory, int prNumber, String headSHA, bool isRookieYaml})
  unpack() => (
    //token: this['token'],
    directory: this['working-directory'],
    prNumber: int.parse(this['pr']),
    headSHA: this['head-SHA'].toString().trim(),
    isRookieYaml: bool.tryParse(this['is-package-rookie-yaml']) ?? false,
  );
}

/// Contributor information
typedef _ContributorInfo = ({
  String contributor,
  String repo,
  String branch,
  bool isExternalRepo,
});

extension on String {
  /// Parses the PR info of the branch to be merged
  _ContributorInfo parseContributorInfo() {
    final parsed = json.decode(this);

    if (parsed case {
      'headRepositoryOwner': {'login': final contributor},
      'headRepository': {'name': final repo},
      'headRefName': final branch,
      'isCrossRepository': bool isExternalRepo,
    }) {
      return (
        contributor: contributor.toString(),
        repo: repo.toString(),
        branch: branch.toString(),
        isExternalRepo: isExternalRepo,
      );
    }

    throw Exception('Incorrect API response: $parsed');
  }
}

/// Returns the colour matching the [passRate].
///
///   - "red" -> 0 - 49
///   - "yellow" -> 50 - 75
///   - "green" -> 76 - 100
String _colouredRate(String passRate) {
  final rate = double.tryParse(passRate);

  if (rate != null && rate > 50) {
    return switch (rate) {
      >= 50 && <= 75 => 'yellow',
      _ => 'green',
    };
  }

  return 'red';
}

/// Update the `YAML` test suite [passRate] in the README.
///
/// [directory] refers to path of the directory with the README.
void _updatePassRate(String directory, String passRate) {
  final file = File(path.join(directory, 'README.md'));

  final replacement =
      '$testSuiteLabel($testSuiteUrlPrefix'
      '-$passRate%25-${_colouredRate(passRate)})';

  final updated = file.readAsStringSync().replaceFirst(_regex, replacement);
  file.writeAsStringSync(updated);
}

/// Regenerate pass rate for YAML test suite.
void _maybeRegenerateTestSuite(String rootDir) {
  final rookieYamlDir = path.joinAll([rootDir, 'packages', 'rookie_yaml']);

  // Regenerate latest test suite pass rate before push
  final passRate = runCommand(
    'dart',
    args: ['runner.dart'],
    directory: path.joinAll([rookieYamlDir, 'test', 'yaml_test_suite']),
    mapper: (s) => s.trim(),
  );

  print('Pass rate: $passRate');

  // Update README
  _updatePassRate(rookieYamlDir, passRate);

  if (runCommand(
    'git',
    args: ['status', '--porcelain'],
    directory: rootDir,
    mapper: (s) => s.trim().isNotEmpty,
  )) {
    runCommand('git', args: ['add', 'README.md'], directory: rootDir);
    runCommand('git', args: ['status'], directory: rootDir);
    runCommand(
      'git',
      args: ['commit', '-m', 'Test Suite Update: $passRate\\%'],
      directory: rootDir,
    );
  }
}

void main(List<String> args) {
  final (:directory, :prNumber, :headSHA, :isRookieYaml) = _argParser
      .parse(args)
      .unpack();

  assert(
    directory.isNotEmpty && headSHA.isNotEmpty,
    'Expected a directory and SHA signature, found "$directory" && "$headSHA"',
  );

  /// Run command in the current directory and returns output
  T scopedProcRunner<T>(
    String command, {
    required List<String> args,
    String? messageOnFail,
    T Function(String stdout)? mapper,
    String? dirOverride,
  }) => runCommand(
    command,
    args: args,
    directory: dirOverride ?? directory,
    messageOnFail: messageOnFail,
    mapper: mapper,
  );

  // Fetch PR info
  final (:contributor, :repo, :branch, :isExternalRepo) = scopedProcRunner(
    'gh',
    args: [
      'pr',
      'view',
      '$prNumber',
      '--repo',
      rootRepository,
      '--json',
      'headRepository',
      '--json',
      'headRepositoryOwner',
      '--json',
      'headRefName',
      '--json',
      'isCrossRepository',
    ],
    mapper: (stdout) => stdout.parseContributorInfo(),
    messageOnFail: 'Failed to fetch pull request info',
  );

  var origin = 'origin';

  // Fetch the external repo to local
  if (isExternalRepo) {
    origin = 'forked';

    scopedProcRunner(
      'git',
      args: [
        'remote',
        'add',
        origin,
        'https://github.com/$contributor/$repo',
      ],
    );
  }

  scopedProcRunner('git', args: ['fetch', origin]);

  final actualMergeBranch = '$origin/$branch';

  print(actualMergeBranch);

  scopedProcRunner('git', args: ['remote', 'show', 'origin']);

  scopedProcRunner('git', args: ['checkout', _defaultBranch]); // Just be safe
  scopedProcRunner('git', args: ['pull']);
  scopedProcRunner('git', args: ['branch', '-vv']);

  // Most people may find this offputting.
  scopedProcRunner('git', args: ['merge', '--ff-only', actualMergeBranch]);

  // Check if the head commits match. Injector, no injecting
  if (scopedProcRunner('git', args: ['rev-parse', 'HEAD']) case final commitID
      when commitID != headSHA) {
    throw Exception('''
$actualMergeBranch found in a dirty state.
Expected tip SHA: $headSHA
Current tip SHA: $commitID
''');
  }

  // Leave bot approval once merge was successful
  scopedProcRunner(
    'gh',
    args: ['pr', 'review', '--approve', '$prNumber', '--repo', rootRepository],
  );

  if (isRookieYaml) {
    _maybeRegenerateTestSuite(directory);
  }

  scopedProcRunner(
    'git',
    args: ['push', '--force-with-lease', 'origin', _defaultBranch],
  );
}
