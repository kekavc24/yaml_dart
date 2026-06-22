import 'package:checks/checks.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';

void main() {
  group('Block maps', () {
    test('Parses simple block map', () {
      const yaml =
          'one: "double-quoted"\n'
          "two: 'single-quoted'\n"
          'three: plain value\n'
          'four: [flow sequence]\n'
          'five: {flow: map}\n'
          'six:\n'
          ' - block sequence';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'one': 'double-quoted',
          'two': 'single-quoted',
          'three': 'plain value',
          'four': ['flow sequence'],
          'five': {'flow': 'map'},
          'six': ['block sequence'],
        }.toString(),
      );
    });

    test('Parses explicit keys', () {
      const yaml = '''
? # Empty node

? plain-key-with-empty-value # No value

? |
  block-key
: - value
  - value

? >
  folded
  key
: [value, value]

? - block
  - sequence
  - key
: {flow: value}

? {flow:
  map, ? as: key}
: "double quoted value"

? block: map
  as: key
: 'single quoted value'

? ? nested explicit key
  : nested value
: value
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          null: null,
          'plain-key-with-empty-value': null,
          'block-key\n': ['value', 'value'],
          'folded key\n': ['value', 'value'],
          ['block', 'sequence', 'key']: {'flow': 'value'},
          {'flow': 'map', 'as': 'key'}: 'double quoted value',
          {'block': 'map', 'as': 'key'}: 'single quoted value',
          {'nested explicit key': 'nested value'}: 'value',
        }.toString(),
      );
    });

    test('Parses implicit keys', () {
      const yaml = '''
: # Empty node

'key': # Key with no value

"key0": value # Key with inline value

key1:
  nested: block map

key2:
  - block sequence

# TODO: Excluded. Implement if this is something people want
# key3:
# - block indicator as indent
''';

      check(bootstrapDocParser(yaml).nodeAsSimpleString()).equals(
        {
          null: null,
          'key': null,
          'key0': 'value',
          'key1': {'nested': 'block map'},
          'key2': ['block sequence'],
          //'key3': ['block indicator as indent'],
        }.toString(),
      );
    });

    test(
      'Uses a block map\'s fast path when an alias follows an anchor for map',
      () {
        const yaml = '''
&hello key: value
next: &other
    *hello : value

*other : here
''';

        check(bootstrapDocParser(yaml).nodeAsSimpleString()).equals(
          {
            'key': 'value',
            'next': {'key': 'value'},
            {'key': 'value'}: 'here',
          }.toString(),
        );
      },
    );

    test('Throws if duplicate keys are found', () {
      void checkDuplicate(String yaml) {
        check(
          () => loadObject(YamlSource.string(yaml)),
        ).throwsParserException(
          'A block map cannot contain duplicate entries by the same key',
        );
      }

      checkDuplicate('''
key: value
key: value
''');

      checkDuplicate('''
key: value
? key
''');

      checkDuplicate('''
[key]: value
? [key]
: value
''');

      checkDuplicate('''
{flow}: key
? ? flow
''');
    });

    test('Throws if dangling ":" is not inline with "?"', () {
      const yaml = '''
?   - extremely indented block list
  : dangling value
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException(
        'Dangling node found when parsing explicit entry',
      );
    });

    test('Throws if block sequence is used as an implicit key', () {
      const yaml = '''
implicit: map

- rogue block key:
    value
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException(
        'A block sequence cannot be forced to be implicit or have inline'
        ' properties before its indicator',
      );
    });

    test('Throws if implicit key spans multiple lines', () {
      const yaml = '''
implicit: map

rogue
 implicit key: value
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException(
        'Implicit block keys are restricted to a single line',
      );

      check(
        () => bootstrapDocParser('''
key: value
[ \n ]: value
'''),
      ).throwsParserException(
        'Found a line break when parsing an inline flow node',
      );

      check(
        () => bootstrapDocParser('''
key: value

# Block scalar cannot be implicit
|
  block
'''),
      ).throwsParserException(
        'Dirty parser state. Failed to parse a scalar using'
        ' ${ScalarEvent.startBlockLiteral}.',
      );
    });

    test('Throws if a block sequence is inline with block implicit key', () {
      const yaml =
          'implicit:'
          ' - block sequence value # Block lists start on new line';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException(
        'The block collections must start on a new line'
        ' when used as values of an implicit key',
      );
    });

    test('Throws if dangling map entry', () {
      const yaml = '''
implicit:
    nested: map
  dangling: map
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException(
        'Invalid block node indentation in block collection.'
        ' Expected 0 space(s)',
      );
    });
  });

  group('Block Sequences', () {
    test('Parses block sequence', () {
      const yaml = '''
- "double quoted"
- 'single quoted'
- plain
- |
 literal
- >
 folded
- [flow, sequence]
- {flow: map}
- block: map
  nested: well
- - nested
  - sequence''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          'double quoted',
          'single quoted',
          'plain',
          'literal\n',
          'folded\n',
          ['flow', 'sequence'],
          {'flow': 'map'},
          {'block': 'map', 'nested': 'well'},
          ['nested', 'sequence'],
        ].toString(),
      );
    });

    test('Parses a nested block map with properties correctly', () {
      final defaultSeq = [
        'value',
        {
          'value': null,
          ['flow', 'key']: 'value',
        },
        ['flow', 'key'],
      ];

      check(
        bootstrapDocParser(
          '''
- &scalar value
- *scalar : &anchor-to-null
  &flow-list [flow, key]: *scalar
- *flow-list
''',
        ).nodeAsSimpleString(),
      ).equals(defaultSeq.toString());

      check(
        bootstrapDocParser(
          '''
- &scalar value
-
  *scalar : &anchor-to-null
  &flow-list [flow, key]: *scalar
- *flow-list
''',
        ).nodeAsSimpleString(),
      ).equals(defaultSeq.toString());
    });

    test('Parses block sequence with compact block nodes', () {
      const yaml = '''
- ? compact: explicit
  : - nested
    - sequence
  implicit: compact
- - compact
  - sequence:
     ? nested: block
     : as value
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          {
            {'compact': 'explicit'}: ['nested', 'sequence'],
            'implicit': 'compact',
          },
          [
            'compact',
            {
              'sequence': {
                {'nested': 'block'}: 'as value',
              },
            },
          ],
        ].toString(),
      );
    });

    test('Exits gracefully if doc markers are declared within sequence', () {
      const markers = ['---\n', '...\n'];

      const plain = 'block with doc markers';
      final sequenceStr = [plain].toString();

      const yaml = '- $plain\n';
      const trailing = '- ignored';

      for (final marker in markers) {
        check(
          bootstrapDocParser('$yaml$marker$trailing').nodeAsSimpleString(),
        ).equals(sequenceStr);
      }
    });

    test('Throws if a node has missing "- "', () {
      const yaml =
          '- value\n'
          '-error';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException('Expected a "- " at the start of the next entry');
    });

    test('Throws if dangling nested block entry is encountered', () {
      const yaml = '''
- first
-  - nested second
  - dangling third
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException(
        'Invalid block node indentation in block collection.'
        ' Expected 0 space(s)',
      );
    });

    test('Throws if a flow node is less indented than block parent', () {
      const yaml = '''
- - [not,
 okay]
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsParserException('Expected at least 2 additional spaces');
    });
  });

  group('Special Block Sequence', () {
    test('Variant [1]', () {
      check(
        bootstrapDocParser('''
?
- explicit key
- next
:
- explicit value
- next

--key: value
''').nodeAsSimpleString(),
      ).equals(
        {
          ['explicit key', 'next']: ['explicit value', 'next'],
          '--key': 'value',
        }.toString(),
      );
    });

    test('Variant [2]', () {
      check(
        bootstrapDocParser('''
?
- explicit key
- next
:
- explicit value
- next

---another: value
''').nodeAsSimpleString(),
      ).equals(
        {
          ['explicit key', 'next']: ['explicit value', 'next'],
          '---another': 'value',
        }.toString(),
      );
    });

    test('Variant [3]', () {
      check(
        bootstrapDocParser('''
?
- ?
  - key
:
- ?
  :
  - value
?
:
- value
''').nodeAsSimpleString(),
      ).equals(
        {
          [
            {
              ['key']: null,
            },
          ]: [
            {
              null: ['value'],
            },
          ],
          null: ['value'],
        }.toString(),
      );
    });

    test('Variant [4]', () {
      check(
        bootstrapDocParser('''
implicit key:
- value
- next
-key: value
''').nodeAsSimpleString(),
      ).equals(
        {
          'implicit key': ['value', 'next'],
          '-key': 'value',
        }.toString(),
      );
    });

    test('Variant [5]', () {
      check(
        bootstrapDocParser('''
:
- value
''').nodeAsSimpleString(),
      ).equals(
        {
          null: ['value'],
        }.toString(),
      );
    });

    test('Variant [6]', () {
      check(
        bootstrapDocParser('''
implicit key:
- value
- next
---variant: value
''').nodeAsSimpleString(),
      ).equals(
        {
          'implicit key': ['value', 'next'],
          '---variant': 'value',
        }.toString(),
      );
    });

    test('Variant [7]', () {
      check(
        bootstrapDocParser('''
implicit key: !!seq
- value
''').nodeAsSimpleString(),
      ).equals(
        {
          'implicit key': ['value'],
        }.toString(),
      );

      check(
        bootstrapDocParser('''
? !!seq
- value
: !!seq
- value
''').nodeAsSimpleString(),
      ).equals(
        {
          ['value']: ['value'],
        }.toString(),
      );
    });

    test('Variant [8]', () {
      check(
        () => bootstrapDocParser('''
key:
- value
---not sequence
'''),
      ).throwsParserException(
        'Expected to find ":" after the key and before its value',
      );
    });
  });

  group('Grammar adherence', () {
    test('Tabs as separation in compact collection throws', () {
      void compactThrows(String yaml) {
        check(() => loadObject(YamlSource.string(yaml))).throws();
      }

      compactThrows('-\t- compact');
      compactThrows('?\t? compact key');
      compactThrows('-\t? compact map');
      compactThrows('?\t- compact list');
      compactThrows('-\tkey: value');
      compactThrows('?\tkey: value');
      compactThrows('''
? okay: map
:\terr: map
''');
    });

    test('Tab separated value never degenerates to map', () {
      check(
        loadObject(
          YamlSource.string(
            'key:\n'
            ' \tvalid syntax',
          ),
        ),
      ).isA<Map>().deepEquals({'key': 'valid syntax'});

      check(
        () => loadObject(
          YamlSource.string(
            'key:\n'
            ' \tcannot: form-nested-map',
          ),
        ),
      ).throws();
    });

    test('Tabs separated degenerates to map if properties are multiline', () {
      const map = {'key': 'value'};

      void degenerates<T>(
        String yaml,
        void Function(Subject<T> object) checker,
      ) {
        checker(check(loadObject(YamlSource.string(yaml))));
      }

      degenerates(
        '?\t!!map\n'
        '  key: value',
        (obj) => obj.isA<Map>().deepEquals({map: null}),
      );

      degenerates(
        '-\t!!map\n'
        '  key: value',
        (obj) => obj.isA<List>().deepEquals([map]),
      );

      degenerates(
        'implicit:\n'
        '  \t!!map\n'
        ' key: value',
        (obj) => obj.isA<Map>().deepEquals({'implicit': map}),
      );
    });

    test(
      'Throws when dangling tabs results in an invalid block node state',
      () {
        check(
          () => loadObject(
            YamlSource.string('''
key:
  nested: value
 \ttab: key
'''),
          ),
        ).throws();
      },
    );
  });
}
