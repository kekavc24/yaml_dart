import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';
import 'helpers/object_helper.dart';

void main() {
  group('Tag properties', () {
    test('Parses simple tags', () {
      final testTag = TagShorthand.fromTagUri(TagHandle.primary(), 'test-tag');
      final yaml =
          '''
$testTag plain-scalar
---
$testTag "double quoted"
---
$testTag 'single quoted'
---
$testTag {flow: map}
---
$testTag [flow, sequence]
---
$testTag
block: map
---
$testTag
- block sequence
''';

      check(loadDoc(yaml))
        ..length.equals(7)
        ..every((n) => n.hasNode().hasTag(testTag));
    });

    test('Parses tags nested in flow map', () {
      final entryTag = TagShorthand.primary('simple-kv');
      final mapTag = TagShorthand.primary('flow-map');

      final yaml =
          '''
$mapTag {
$entryTag key: $entryTag value,
$entryTag key0: $entryTag value
}
''';

      check(loadDoc(yaml).first).hasNode()
        ..hasTag(mapTag)
        ..hasObject<Map<TestNode, TestNode?>>('Map').which(
          (map) => map
            ..has((e) => e.keys, 'Keys').every((k) => k.hasTag(entryTag))
            ..has(
              (e) => e.values,
              'Value',
            ).every((v) => v.isNotNull().hasTag(entryTag)),
        );
    });

    test('Parses tags in flow sequence', () {
      final seqEntryTag = TagShorthand.primary('seq-entry');
      final seqTag = TagShorthand.primary('flow-seq');

      final yaml =
          '''
$seqTag [
$seqEntryTag "double quoted",
$seqEntryTag plain
  multiline, $seqEntryTag 'single quoted',

  $seqEntryTag {flow: map-string},

  $seqEntryTag compact-flow-map: 'tag goes to key'
]
''';

      // First 5 elements have tags.
      check(loadDoc(yaml).first).hasNode()
        ..hasTag(seqTag)
        ..hasObject<List<TestNode>>('List').which(
          (list) => list
            ..has(
              (e) => e.take(4),
              'First 4 entries',
            ).every((e) => e.hasTag(seqEntryTag))
            ..has((e) => e.last.object, 'Last entry')
                .isA<Map<TestNode, TestNode?>>()
                .has((e) => e.keys.firstOrNull, 'First key')
                .isNotNull()
                .hasTag(seqEntryTag),
        );
    });

    test('Parses tags in a block map', () {
      final kvTag = TagShorthand.primary('block-kv');

      final yaml =
          '''
$kvTag key: $kvTag value
$kvTag key0: $kvTag value
? $kvTag >
 key1
: $kvTag value
''';

      check(loadDoc(yaml).first).hasNode()
        ..hasTag(yamlGlobalTag, suffix: mappingTag)
        ..hasObject<Map<TestNode, TestNode?>>(
          'Map',
        ).which(
          (map) => map
            ..has((e) => e.keys, 'Block Keys').every((key) => key.hasTag(kvTag))
            ..has(
              (e) => e.values,
              'Value',
            ).every((value) => value.isNotNull().hasTag(kvTag)),
        );
    });

    test('Parses tags in block sequence', () {
      final blockSeqTag = TagShorthand.primary('block-seq');
      final seqTag = TagShorthand.primary('seq');

      final yaml =
          '''
$seqTag
- $blockSeqTag "double quoted"

- $blockSeqTag plain
  multiline

- $blockSeqTag 'single quoted'

- $blockSeqTag >
  folded

- $blockSeqTag |
  literal

- $blockSeqTag [flow, sequence]
- $blockSeqTag {flow: map}

- compact: map
  not: allowed-properties

- ? compact-key: also
    not: allowed-properties
''';

      check(loadDoc(yaml).first).hasNode()
        ..hasTag(seqTag)
        ..hasObject<List<TestNode>>('List').which(
          (list) => list
            ..has(
              (l) => l.take(7),
              'First 7 elements',
            ).every((e) => e.hasTag(blockSeqTag))
            ..has((l) => l.skip(7), 'Last 2 entries').which(
              (i) => i
                ..length.equals(2)
                ..every((e) => e.hasTag(yamlGlobalTag, suffix: mappingTag)),
            ),
        );
    });
  });

  group('Anchors & alias', () {
    test('Parses simple anchor and alias', () {
      const yaml = '''
&a key: &b [ &c value ]

*b : &d { *a : *b }

*c :
  &e
  - ? *a
    : *b
  - *c

*d : *e
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'key': ['value'],

          ['value']: {
            'key': ['value'],
          },

          'value': [
            {
              'key': ['value'],
            },
            'value',
          ],

          {
            'key': ['value'],
          }: [
            {
              'key': ['value'],
            },
            'value',
          ],
        }.toString(),
      );
    });

    test('References flow key before entire entry is parsed', () {
      const yaml = '''
{
  &flow-key key: *flow-key ,

  &seq-key another: [
    *flow-key ,

    &multi-line-entry
    {key: *seq-key} ,

    *multi-line-entry ,

    &for-key key: *for-key
  ],

  *multi-line-entry
}
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'key': 'key',
          'another': [
            'key',
            {'key': 'another'},
            {'key': 'another'},
            {'key': 'key'},
          ],
          {'key': 'another'}: null,
        }.toString(),
      );
    });

    test('References block key before entire entry is parsed', () {
      const yaml = '''
&key key: *key

? &another another
: *another
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {'key': 'key', 'another': 'another'}.toString(),
      );
    });

    test('Parses trailing flow sequence aliases', () {
      const yaml = '''
[
  &anchor value,

  [ *anchor ], # Single trailing
  [ *anchor , *anchor ],
  *anchor
]
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          'value',
          ['value'],
          ['value', 'value'],
          'value',
        ].toString(),
      );
    });

    test('Parses compact block map with alias as key in block sequence', () {
      const yaml = '''
- &anchor value
- *anchor
- *anchor : *anchor
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          'value',
          'value',
          {'value': 'value'},
        ].toString(),
      );
    });
  });

  group(
    'Uses the minimum indent if a node is less indented than '
    'its properties',
    () {
      test('Variant [1]', () {
        check(
          bootstrapDocParser('''
-     !too-indented
  - hello
''').nodeAsSimpleString(),
        ).equals(
          [
            ['hello'],
          ].toString(),
        );
      });

      test('Variant [2]', () {
        check(
          bootstrapDocParser('''
?     !too-indented
  - hello
:             !even-further-indented
  - hello
''').nodeAsSimpleString(),
        ).equals(
          {
            ['hello']: ['hello'],
          }.toString(),
        );
      });

      test('Variant [3]', () {
        check(
          bootstrapDocParser('''
implicit:     !even-in-implicit
  - hello
''').nodeAsSimpleString(),
        ).equals(
          {
            'implicit': ['hello'],
          }.toString(),
        );
      });
    },
  );

  group('Attempts to compose a block map if multiple multiline properties '
      'are seen', () {
    test('Variant [1]', () {
      check(
        bootstrapDocParser('''
&must-be-map
&definitely key: value
''').nodeAsSimpleString(),
      ).equals(
        {'key': 'value'}.toString(),
      );
    });

    test('Variant [2]', () {
      check(
        bootstrapDocParser('''
- &anchor key
- &map
  *anchor : value
''').nodeAsSimpleString(),
      ).equals(
        [
          'key',
          {'key': 'value'},
        ].toString(),
      );
    });

    test('Variant [3]: Throws if impossible', () {
      check(
            () => bootstrapDocParser('''
&throw
&not key
'''),
          )
          .throws<ArgumentError>()
          .has((e) => e.message, 'Message')
          .equals('Duplicate node properties provided to a node');
    });
  });

  group('Exceptions', () {
    test('Throws when an anchor or alias has no suffix', () {
      const error = 'Expected at 1 non-whitespace character';

      check(
        () => bootstrapDocParser('& {}').nodeAsSimpleString(),
      ).throwsParserException(error);

      check(
        () => bootstrapDocParser('{ &this value, * }').nodeAsSimpleString(),
      ).throwsParserException(error);

      check(
        () => bootstrapDocParser('- &this value\n- *').nodeAsSimpleString(),
      ).throwsParserException(error);
    });

    test('Throws when an unknown secondary tag is used', () {
      final tag = '!!unknown-tag';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException(
        'Invalid secondary tag. Expected any of: '
        '$mappingTag, $orderedMappingTag, '
        '$sequenceTag, $setTag, '
        '$stringTag, $nullTag, $booleanTag, $integerTag or $floatTag',
      );
    });

    test('Throws when a named tag has no global tag alias', () {
      final tag = '!unknown-alias!string';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException(
        'Named tags must have a corresponding global tag',
      );
    });

    test('Throws when a named tag has no suffix', () {
      final tag = '!no-suffix!';
      final yaml =
          '''
%TAG $tag !indeed
---
$tag ignored :)
''';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException('Named tags must have a non-empty suffix');
    });

    test('Throws when a tag is declared for a compact flow node', () {
      final yaml = '''
[
  !compact-tag
  key: value
]
''';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException('Invalid flow collection state. Expected "]"');
    });

    test(
      'Throws when tags are used before explicit keys in block and flow styles',
      () {
        check(
          () => bootstrapDocParser('&anchor ? explicit-key').parseNodeSingle(),
        ).throwsParserException(
          'An explicit key cannot be forced to be implicit or have inline '
          'properties before its indicator',
        );

        check(
          () => bootstrapDocParser(
            '''
? key
: okay

!error ? never-parsed
''',
          ).parseNodeSingle(),
        ).throwsParserException(
          'An explicit key cannot be forced to be implicit or have inline '
          'properties before its indicator',
        );

        check(
          () => bootstrapDocParser(
            '''
? key
: okay

!error
? even-when-on-a-new-line
''',
          ).parseNodeSingle(),
        ).throwsParserException(
          'Implicit block nodes cannot span multiple lines',
        );

        check(
          () => bootstrapDocParser(
            '''
{
? key
: okay,

!error
? also-applies-to-flow
}
''',
          ).parseNodeSingle(),
        ).throwsParserException(
          'Flow node cannot span multiple lines when implicit',
        );
      },
    );

    test('Throws when tags are multiline in implicit keys', () {
      check(
        () => bootstrapDocParser(
          '''
!tag-okay implicit-1: is-fine

!this-is-not-okay
implicit-2: is-an-error
''',
        ).parseNodeSingle(),
      ).throwsParserException(
        'Implicit block nodes cannot span multiple lines',
      );

      check(
        () => bootstrapDocParser(
          '''
{
!tag-okay implicit-1: is-fine,

!this-is-not-okay
implicit-2: is-an-error}
''',
        ).parseNodeSingle(),
      ).throwsParserException(
        'Flow node cannot span multiple lines when implicit',
      );
    });

    test('Throws when tags are declared before block sequence indicator', () {
      check(
        () => bootstrapDocParser(
          '!!seq - not-okay',
        ).parseNodeSingle(),
      ).throwsParserException(
        'A block sequence cannot be forced to be implicit or have inline '
        'properties before its indicator',
      );

      check(
        () => bootstrapDocParser('''
!experimental-okay-1st
- first

!not-and-unlikely-okay
- second
''').parseNodeSingle(),
      ).throwsParserException('Expected a "- " at the start of the next entry');
    });

    test('Throws when non-existent alias is used', () {
      const alias = 'value';

      check(
        () => bootstrapDocParser('key: *$alias').parseNodeSingle(),
      ).throwsParserException('Alias is not a valid anchor reference');
    });

    test('Throws when an anchor is declared for a compact flow node', () {
      final yaml = '''
[
  !compact-anchor
  key: value
]
''';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException('Invalid flow collection state. Expected "]"');
    });

    test('Throws when a multiline property is less indented than its '
        'block node', () {
      for (final parent in const ['?', '-']) {
        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    - value
'''),
        ).throws();

        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    ? value
'''),
        ).throws();

        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    >
     value
'''),
        ).throws();

        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    |
      value
'''),
        ).throws();
      }
    });

    test("Throws when block node has an anchor or tag after an alias", () {
      check(
        () => bootstrapDocParser('''
key:
  *alias
  &anchor
'''),
      ).throwsParserException(
        'Invalid block node state. Duplicate properties implied the'
        ' start of a block map but a block map cannot be composed in the'
        ' current state',
      );
    });
  });
}
