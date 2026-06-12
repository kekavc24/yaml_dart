import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'utils.dart';

final _commentArgParser = ArgParser()
  ..addOption(
    'pr',
    help: 'Pull Request associated where this PR is being run',
    mandatory: true,
  )
  ..addOption(
    'tip-SHA',
    help: 'Commit SHA at the tip of PR branch',
    mandatory: true,
  )
  ..addOption(
    'working-directory',
    help: 'Root directory with repository',
    mandatory: true,
  );

extension on ArgResults {
  ({String pr, String headCommit, String directory}) unpack() => (
    pr: this['pr'],
    headCommit: this['tip-SHA'],
    directory: this['working-directory'],
  );
}

const _keyRan = 'Tests that ran:';
const _keyPass = 'Tests passing:';

/// Compares the current pass rate in the repo and the latest pass rate obtained
/// from the current PR.
({String currentPassRate, double prPassRate, String diff}) _passRateDiff(
  String rootDirectory,
  String summary,
) {
  int? testRan;
  int? testPass;

  for (final str in summary.split('\n')) {
    if (str.startsWith(_keyRan)) {
      testRan ??= int.tryParse(str.replaceFirst(_keyRan, '').trim());
    } else if (str.startsWith(_keyPass)) {
      testPass ??= int.tryParse(str.replaceFirst(_keyPass, '').trim());
    }
  }

  final rateOnPR = ((testPass ?? 0) / (testRan ?? 1)) * 100;
  final currentInRepo = getCurrentPassRate(rootDirectory);

  return (
    currentPassRate: currentInRepo,
    prPassRate: rateOnPR,
    diff: currentInRepo == rateOnPR.toStringAsFixed(2)
        ? 'No change ☑️'
        : (double.tryParse(currentInRepo) ?? 0) > rateOnPR
        ? 'Regression detected ‼️'
        : 'Possible fix ✅',
  );
}

void main(List<String> args) {
  final (:pr, :headCommit, :directory) = _commentArgParser.parse(args).unpack();

  final rookieDir = path.joinAll([directory, 'packages', 'rookie_yaml']);

  // Run test suite and get the summary
  final summary = runCommand<String>(
    'dart',
    args: ['runner.dart', '--mode', 'summary'],
    directory: path.joinAll([rookieDir, 'test', 'yaml_test_suite']),
  );

  final (:currentPassRate, :prPassRate, :diff) = _passRateDiff(
    rookieDir,
    summary,
  );

  addBotComment(pr, directory, '''
$diff
---
- Head SHA commit: $headCommit
- Base Repository Pass Rate: `$currentPassRate%`
- Pull Request Pass Rate: `${prPassRate.toStringAsFixed(2)}%`

```yaml
$summary
```
''');
}
