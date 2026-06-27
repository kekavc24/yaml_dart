import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart' show NodeStyle, ScalarStyle;
import 'package:test/test.dart';

const _comments = ['yaml', 'comments'];

void main() {
  late final YamlDumper dumper;
  late final StringBuffer buffer;

  setUpAll(() {
    buffer = StringBuffer();
    dumper = YamlDumper.toStringBuffer(
      config: Config.defaults(),
      buffer: buffer,
    );
  });

  tearDown(() {
    buffer.clear();
  });

  group('Sequence', () {
    test('Applies block comments to scalars in block collection', () {
      dumper.reset(config: Config.yaml(styling: TreeConfig.block()));

      dumper.dump(
        ScalarStyle.values.map(
          (style) => ScalarView(24)
            ..commentStyle = CommentStyle.block
            ..comments.addAll(_comments)
            ..scalarStyle = style,
        ),
      );

      check(buffer.toString()).equals('''
# yaml
# comments
- |-
  24
# yaml
# comments
- >-
  24
# yaml
# comments
- 24
# yaml
# comments
- '24'
# yaml
# comments
- "24"
''');
    });

    test('Applies block comments to elements in flow collection', () {
      dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.flow(forceInline: false),
        ),
      );

      dumper.dump(
        ScalarStyle.values
            .where((s) => s.nodeStyle.isFlow)
            .map(
              (style) => ScalarView(24)
                ..commentStyle = CommentStyle.block
                ..comments.addAll(_comments)
                ..scalarStyle = style,
            ),
      );

      check(buffer.toString()).equals('''
[
  # yaml
  # comments
  24,
  # yaml
  # comments
  '24',
  # yaml
  # comments
  "24"
]''');
    });

    test('Applies comments to nested elements correctly', () {
      dumper.reset(config: Config.yaml(styling: TreeConfig.block()));

      final block = ScalarStyle.values.map(
        (style) => ScalarView(24)
          ..commentStyle = CommentStyle.block
          ..comments.addAll(_comments)
          ..scalarStyle = style,
      );

      final flow = YamlIterable(block.where((e) => e.nodeStyle.isFlow))
        ..nodeStyle = NodeStyle.flow;

      dumper.dump([block, flow]);

      check(buffer.toString()).equals('''
- # yaml
  # comments
  - |-
    24
  # yaml
  # comments
  - >-
    24
  # yaml
  # comments
  - 24
  # yaml
  # comments
  - '24'
  # yaml
  # comments
  - "24"
- [
    # yaml
    # comments
    24,
    # yaml
    # comments
    '24',
    # yaml
    # comments
    "24"
  ]
''');
    });
  });

  group('Map', () {
    test('Dumps keys "as-is" when comments use a block style', () {
      final implicit = ScalarView(24)
        ..commentStyle = CommentStyle.block
        ..comments.addAll(_comments);

      final explicit = YamlIterable([implicit])
        ..commentStyle = CommentStyle.block
        ..comments.addAll(_comments);

      dumper.dump({implicit: 'value', explicit: 'value'});

      check(buffer.toString()).equals('''
# yaml
# comments
24: value
# yaml
# comments
? # yaml
  # comments
  - 24
: value
''');
    });

    test(
      'Dumps scalars on the next line if comments are block in block map',
      () {
        dumper
          ..reset(config: Config.yaml(styling: TreeConfig.block()))
          ..dump(
            ScalarStyle.values
                .map(
                  (style) => ScalarView(24)
                    ..commentStyle = CommentStyle.block
                    ..comments.addAll(_comments)
                    ..scalarStyle = style,
                )
                .toList()
                .asMap(),
          );

        check(buffer.toString()).equals('''
0:
  # yaml
  # comments
  |-
  24
1:
  # yaml
  # comments
  >-
  24
2:
  # yaml
  # comments
  24
3:
  # yaml
  # comments
  '24'
4:
  # yaml
  # comments
  "24"
''');
      },
    );

    test(
      'Dumps entries on the next line if comments are block in flow map',
      () {
        dumper
          ..reset(
            config: Config.yaml(
              styling: TreeConfig.flow(forceInline: false),
            ),
          )
          ..dump(
            ScalarStyle.values
                .where((s) => s.nodeStyle.isFlow)
                .map(
                  (style) => ScalarView(24)
                    ..commentStyle = CommentStyle.block
                    ..comments.addAll(_comments)
                    ..scalarStyle = style,
                )
                .cast<DumpableView>()
                .followedBy([
                  YamlIterable([])
                    ..commentStyle = CommentStyle.block
                    ..comments.addAll(_comments),

                  DartMap({})
                    ..commentStyle = CommentStyle.block
                    ..comments.addAll(_comments),
                ])
                .toList()
                .asMap(),
          );

        check(buffer.toString()).equals('''
{
  0:
    # yaml
    # comments
    24,
  1:
    # yaml
    # comments
    '24',
  2:
    # yaml
    # comments
    "24",
  3:
    # yaml
    # comments
    [],
  4:
    # yaml
    # comments
    {}
}''');
      },
    );
  });
}
