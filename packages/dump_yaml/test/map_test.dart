import 'dart:math';

import 'package:checks/checks.dart';
import 'package:collection/collection.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart'
    show ScalarStyle, YamlSource, loadObject;
import 'package:test/test.dart';

const _funkyMap = {
  'key': 24,
  24: ['rookie', 'yaml'],
  ['is', 'dumper']: {true: 24.0},
  '24\n0': 'value',
};

String _randomImplicitKey([int size = 1025]) {
  final buffer = StringBuffer();

  var value = size;
  final rand = Random();

  for (; value > 0; value--) {
    buffer.writeCharCode(rand.nextInt(25) + 65);
  }

  return buffer.toString();
}

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

  group('Flow maps', () {
    test('Dumps map with double quoted scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: false,
              scalarStyle: ScalarStyle.doubleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
{
  "key": "24",
  "24": [
      "rookie",
      "yaml"
    ],
  ? [
      "is",
      "dumper"
    ]
  : {
      "true": "24.0"
    },
  ? "24

    0"
  : "value"
}''');
    });

    test('Dumps map with single quoted style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: false,
              scalarStyle: ScalarStyle.singleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
{
  'key': '24',
  '24': [
      'rookie',
      'yaml'
    ],
  ? [
      'is',
      'dumper'
    ]
  : {
      'true': '24.0'
    },
  ? '24

    0'
  : 'value'
}''');
    });

    test('Dumps map with plain style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(forceInline: false),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
{
  key: 24,
  24: [
      rookie,
      yaml
    ],
  ? [
      is,
      dumper
    ]
  : {
      true: 24.0
    },
  ? 24

    0
  : value
}''');
    });
  });

  group('Inline flow maps', () {
    test('Dumps inline map with plain style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: true,
              scalarStyle: ScalarStyle.plain,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals(
        r'{key: 24, 24: [rookie, yaml], [is, dumper]: {true: 24.0}, '
        r'"24\n0": value}',
      );
    });

    test('Dumps inline map with single quoted style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: true,
              scalarStyle: ScalarStyle.singleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals(
        "{'key': '24', '24': ['rookie', 'yaml'], "
        "['is', 'dumper']: {'true': '24.0'}, \"24\\n0\": 'value'}",
      );
    });

    test('Dumps inline map with double quoted style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: true,
              scalarStyle: ScalarStyle.doubleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals(
        '{"key": "24", "24": ["rookie", "yaml"], '
        r'["is", "dumper"]: {"true": "24.0"}, "24\n0": "value"}',
      );
    });
  });

  group('Block maps', () {
    test('Dumps map with literal scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
? |-
  key
: |-
  24
? |-
  24
: - |-
    rookie
  - |-
    yaml
? - |-
    is
  - |-
    dumper
: ? |-
    true
  : |-
    24.0
? |-
  24
  0
: |-
  value
''');
    });

    test('Dumps map with folded scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.folded),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
? >-
  key
: >-
  24
? >-
  24
: - >-
    rookie
  - >-
    yaml
? - >-
    is
  - >-
    dumper
: ? >-
    true
  : >-
    24.0
? >-
  24

  0
: >-
  value
''');
    });

    test('Dumps map with double quoted scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.doubleQuoted),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
"key": "24"
"24":
  - "rookie"
  - "yaml"
? - "is"
  - "dumper"
: "true": "24.0"
? "24

  0"
: "value"
''');
    });

    test('Dumps map with single quoted scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.singleQuoted),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
'key': '24'
'24':
  - 'rookie'
  - 'yaml'
? - 'is'
  - 'dumper'
: 'true': '24.0'
? '24

  0'
: 'value'
''');
    });

    test('Dumps map with plain scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.plain),
          ),
        )
        ..dump(_funkyMap);

      check(buffer.toString()).equals('''
key: 24
24:
  - rookie
  - yaml
? - is
  - dumper
: true: 24.0
? 24

  0
: value
''');
    });

    test('Preserves leading whitespace in nested block scalars', () {
      const scalar = ' sh-Kalar';

      const map = {scalar: scalar, 'nested': scalar};

      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
          ),
        )
        ..dump(map);

      final dumped = buffer.toString();

      check(dumped).equals('''
? |1-
 $scalar
: |1-
 $scalar
? |-
  nested
: |1-
 $scalar
''');

      check(
        DeepCollectionEquality.unordered().equals(
          loadObject(YamlSource.simpleString(dumped)),
          map,
        ),
      ).isTrue();
    });
  });

  group('Key tests', () {
    setUp(() => dumper.reset());

    test(
      'Converts implicit key if length is greater than 1024 unicode characters',
      () {
        final explicit = _randomImplicitKey(1025);
        final implicit = _randomImplicitKey(1024);
        dumper.dump({explicit: 'explicit', implicit: 'implicit'});

        check(buffer.toString()).equals(
          '? $explicit\n'
          ': explicit\n'
          '$implicit: implicit\n',
        );
      },
    );

    test(
      'Converst alias to explicit if length is greater than 1024 unicode '
      'characters',
      () {
        final anchor = _randomImplicitKey(1100);
        final key = ScalarView('implicit')..anchor = anchor;
        dumper.dump({key: 'hello', Alias(anchor): 'alias'});

        check(buffer.toString()).equals(
          '&$anchor implicit: hello\n'
          '? *$anchor\n'
          ': alias\n',
        );
      },
    );
  });
}
