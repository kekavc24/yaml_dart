# Changelog

## 0.1.0-beta.6

`BREAKING`:
  - Ability to set a custom `toFormat` callback for `YamlMapping` has been removed.

`feat`:
  - The internal writer used by `YamlBuffer` can be swapped/reset to another writer target.

`fix`:
  - Fixes an bug where a `ScalarView` could reference itself which is impossible in YAML scalars.

## 0.1.0-beta.5

`feat`:
  - Adds support for detecting recursive aliases or object references.

`fix`:
  - Fixes an issue where duplicate keys from a `YamlMapping` were included.

## 0.1.0-beta.4

`BREAKING`:
  - Renames `YamlDumper.string` constructor to `YamlDumper.toStringBuffer`.
  - `YamlDumper` now accepts a `YamlBuffer` and not a closure to create it.

## 0.1.0-beta.3

`BREAKING`:
  - Renames `YamlStringBuffer` to `YamlBuffer`.
  - Removes the `dumped` method in `YamlDumper` and `BlockDumper`.
    - For one-off dumper runs, prefer calling `dumpAsYaml`.
    - For a reusable dumper, provide a:
      1. `StringBuffer` for chunked writes via the `YamlDumper.string` constructor.
      2. `StreamSink<String>` to the `buffer` param that instantiates the internal `YamlBuffer`.

`feat`:
  - Adds support for custom writer targets.

## 0.1.0-beta.2

- Bump `package:rookie_yaml` to the latest prerelease.
- Downgrade Dart SDK to `3.9.0`.

## 0.1.0-beta.1

Migrates and rewrites the YAML dumper from [`package:rookie_yaml`](https://pub.dev/packages/rookie_yaml).

- Adds support for building a [YAML Representantion Tree](https://yaml.org/spec/1.2.2/#31-processes) before it is dumped.
- Adds formatting support when dumping objects to YAML.
- Adds support for styling comments.
- Makes the `YamlDumper` reusable.
