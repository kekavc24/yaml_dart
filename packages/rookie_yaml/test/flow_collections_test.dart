import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/loaders/loader.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';

void main() {
  group('Flow Maps', () {
    test('Parses simple flow map', () {
      const yaml =
          '{'
          'one: "double-quoted", '
          "two: 'single-quoted', "
          'three: plain value, '
          'four: [sequence], '
          'five: {flow: map}'
          '}';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'one': 'double-quoted',
          'two': 'single-quoted',
          'three': 'plain value',
          'four': ['sequence'],
          'five': {'flow': 'map'},
        }.toString(),
      );
    });

    test('Parses implicit and explicit keys', () {
      const yaml =
          '{ implicit key: value,'
          '? explicit key: value }';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals({'implicit key': 'value', 'explicit key': 'value'}.toString());
    });

    test('Parses empty entry node declared explicitly', () {
      const yaml = '{ ? ? }';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          {null: null}: null,
        }.toString(),
      );
    });

    test('Parses implicit entry with missing keys/values', () {
      const yaml =
          '{'
          'implicit: with value ,'
          'implicit-with-no-value: ,'
          'implicit-with-no-colon ,'
          ': value-with-no-key'
          '}';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'implicit': 'with value',
          'implicit-with-no-value': null,
          'implicit-with-no-colon': null,
          null: 'value-with-no-key',
        }.toString(),
      );
    });

    test('Parses json-like keys without restrictions', () {
      // JSON-like keys need not have space after ":"
      const yaml =
          '{'
          '{ JSON-like-map: as-key }:"value" ,'
          '[JSON, like, sequence, as-key]:"value" ,'
          '"JSON-like-double-quoted":"value" ,'
          "'JSON-like-single-quoted':'value'"
          '}';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          {'JSON-like-map': 'as-key'}: 'value',
          ['JSON', 'like', 'sequence', 'as-key']: 'value',
          'JSON-like-double-quoted': 'value',
          'JSON-like-single-quoted': 'value',
        }.toString(),
      );
    });
  });

  group('Flow Sequences', () {
    test('Parses simple flow sequence', () {
      const yaml = '[one, two, three, four]';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(['one', 'two', 'three', 'four'].toString());
    });

    test('Parses flow sequence with various flow node types', () {
      const yaml = '''
[
"double
 quoted", 'single
           quoted',
plain
 text, [ nested ],
implicit: pair,
? explicit
  key: pair
]
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          'double quoted',
          'single quoted',
          'plain text',
          ['nested'],
          {'implicit': 'pair'},
          {'explicit key': 'pair'},
        ].toString(),
      );
    });
  });

  group('Exceptions', () {
    test("Throws if flow map doesn't start/end with map delimiters", () {
      check(
        () => bootstrapDocParser('{ !key ? key }').nodeAsSimpleString(),
      ).throwsParserException(
        'An explicit compact flow entry cannot have properties',
      );
    });

    test("Throws if flow map doesn't start/end with map delimiters", () {
      check(
        () => bootstrapDocParser('}').nodeAsSimpleString(),
      ).throwsParserException(
        'Invalid flow node state. Expected "{" or "]"',
      );

      check(
        () => bootstrapDocParser('{').nodeAsSimpleString(),
      ).throwsParserException(
        'Invalid flow collection state. Expected to find: "}"',
      );
    });

    test('Throws if duplicate keys are found', () {
      check(
        () => bootstrapDocParser(
          '{key: value, key: value}',
        ).nodeAsSimpleString(),
      ).throwsParserException(
        'A flow map cannot contain duplicate entries by the same key',
      );
    });

    test('Throws if "," is declared before key', () {
      const err = 'Invalid flow collection state. Expected "}"';

      check(
        () => bootstrapDocParser('{,}').nodeAsSimpleString(),
      ).throwsParserException(err);

      check(
        () => bootstrapDocParser('{key,,}').nodeAsSimpleString(),
      ).throwsParserException(err);
    });

    test("Throws if implicit key spans multiple lines", () {
      check(
        () => bootstrapDocParser(
          '{'
          'implicit-key-not-inline'
          '\n splits-here'
          ': value'
          '}',
        ).nodeAsSimpleString(),
      ).throwsParserException(
        'Expected a next flow entry indicator "," or a map value indicator ":" '
        'or a terminating delimiter "}"',
      );
    });

    test(
      "Throws if flow sequence doesn't start/end with sequence delimiters",
      () {
        check(
          () => bootstrapDocParser(']').nodeAsSimpleString(),
        ).throwsParserException('Invalid flow node state. Expected "{" or "]"');

        check(
          () => bootstrapDocParser('[').nodeAsSimpleString(),
        ).throwsParserException(
          'Invalid flow collection state. Expected to find: "]"',
        );
      },
    );

    test('Throws if "," is declared before entry', () {
      const error = 'Invalid flow collection state. Expected "]"';

      check(
        () => bootstrapDocParser('[,]').nodeAsSimpleString(),
      ).throwsParserException(error);

      check(
        () => bootstrapDocParser('[value,,]').nodeAsSimpleString(),
      ).throwsParserException(error);
    });

    test(
      'Flow collection in block: Throws if indent is less than minimum'
      ' allowed',
      () {
        check(
          () => bootstrapDocParser('''
- - [
      plain
  scalar
   ]
          ''').parseNodeSingle(),
        ).throwsParserException(
          'Indent change detected when parsing plain scalar. Expected'
          ' 3 space(s) but found 2 space(s)',
        );
      },
    );

    test('Throws when document end chars are used in a flow collection', () {
      const error =
          'Premature document termination after parsing a plain flow scalar';

      check(
        () => bootstrapDocParser('''
{ ? plain
...
}
          ''').parseNodeSingle(),
      ).throwsParserException(error);

      check(
        () => bootstrapDocParser('''
[ plain
...
]
          ''').parseNodeSingle(),
      ).throwsParserException(error);
    });

    test(
      'Throws when block nodes are used in flow collections',
      () {
        for (final char in const ['>', '|', '-']) {
          check(
            () => bootstrapDocParser('''
[ $char
    block
]
          ''').parseNodeSingle(),
          ).throws();
        }
      },
    );

    test('Throws when tabs are used as indent', () {
      check(
        () => loadObject(
          YamlSource.string('''
key:
  {key:
  !!map
\tnext 
 }
'''),
        ),
      ).throws();
    });
  });
}
