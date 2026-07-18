import 'package:checks/checks.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';
import 'helpers/test_resolvers.dart';

void main() {
  final listResolver = ObjectFromIterable<int, List<int>>(
    onCustomIterable: () => MySortedList(),
  );

  final mapResolver = ObjectFromMap<String, String?, Set<String>>(
    onCustomMap: () => MySetFromMap(),
  );

  final scalarResolver = ObjectFromScalarBytes<List<int>>(
    onCustomScalar: () => SimpleUtfBuffer(),
  );

  group('Generic triggers', () {
    test('Callback for document is always called', () {
      const yaml = '''
Bare doc
...
%TAG ! !with-directives
---
Document
---
Document with no directives
''';

      var count = 0;

      loadResolvedDartObject(yaml, onDoctStart: (_) => ++count);
      check(count).equals(3);
    });

    test('Callback for keys is always called', () {
      const yaml = '''
block: value

? blockExplicit
: {flow, ? flowExplicit}
''';

      final keyTracker = [];
      loadResolvedDartObject(yaml, onKeySeen: keyTracker.add);

      check(
        keyTracker,
      ).deepEquals(['block', 'blockExplicit', 'flow', 'flowExplicit']);
    });

    test('Loads default list', () {
      check(
        loadResolvedDartObject(
          '[30, 40, 10, 20]',
          customList: () => MySortedList(),
        ),
      ).isA<List<int>>().deepEquals([10, 20, 30, 40]);
    });

    test('Loads default map', () {
      check(
        loadResolvedDartObject(
          '{ hello, flow, flow, hello }',
          customMap: () => MySetFromMap(),
        ),
      ).isA<Set<String>>().deepEquals({'hello', 'flow'});
    });

    test('Loads default scalar', () {
      const value = '24';
      final codePoints = [...value.toString().codeUnits];
      final tracked = [...codePoints, -1];

      for (final style in ScalarStyle.values) {
        final yaml = switch (style) {
          ScalarStyle.doubleQuoted => '"$value"',
          ScalarStyle.singleQuoted => "'$value'",
          ScalarStyle.plain => value,
          ScalarStyle.folded => '>-\n $value',
          ScalarStyle.literal => '|-\n $value',
        };

        check(
          loadResolvedDartObject(yaml, customScalar: () => SimpleUtfBuffer()),
        ).isA<List<int>>().deepEquals(tracked);

        check(
          loadResolvedDartObject(
            yaml,
            customScalar: () => BytesToScalar.sliced(
              mapper: (slice) => slice,
            ),
          ),
        ).isA<List<int>>().deepEquals(codePoints);
      }
    });
  });

  group('Resolvers', () {
    test('Handles captured empty resolver tags correctly', () {
      final yaml =
          '''
- $setTag
- $mappingTag
- $integerTag
''';

      check(
        loadResolvedDartObject(
          yaml,
          nodeResolvers: {
            setTag: listResolver,
            mappingTag: mapResolver,
            integerTag: ObjectFromScalarBytes(
              onCustomScalar: () => BytesToScalar.sliced(mapper: (_) => 24),
            ),
          },
        ),
      ).isA<List>().containsMatchingInOrder([
        (seq) => seq.isA<List<int>>().isEmpty(),
        (map) => map.isA<Set<String>>().isEmpty(),
        (scalar) => scalar.isA<int>().equals(24),
      ]);
    });

    test('Loads a predictable strongly typed set from a map', () {
      // Flow map that has no values
      final sources = [
        '$setTag {  break, key, key, key, cycle }',
        '''
$setTag
? break
? key
key:
cycle:
''',
      ];

      const expected = {'break', 'key', 'cycle'};

      for (final source in sources) {
        check(
          loadResolvedDartObject(source, nodeResolvers: {setTag: mapResolver}),
        ).isA<Set<String>>().deepEquals(expected);
      }
    });

    test('Loads a predictable strongly typed sorted list', () {
      final sources = [
        '$sequenceTag [55, 2, 1000, 60, 89]',
        '''
$sequenceTag
- 55
- 2
- 1000
- 60
- 89
''',
      ];

      const expected = [2, 55, 60, 89, 1000];

      for (final source in sources) {
        check(
          loadResolvedDartObject(
            source,
            nodeResolvers: {sequenceTag: listResolver},
          ),
        ).isA<List<int>>().deepEquals(expected);
      }
    });

    test('Loads a strongly typed sorted list with special block sequences', () {
      check(
        loadResolvedDartObject(
          '''
key: $sequenceTag
- 25
- 2
- 0
- 18
''',
          nodeResolvers: {sequenceTag: listResolver},
        ),
      ).isA<Map>().which(
        (m) => m.values.first.isA<List<int>>().deepEquals([0, 2, 18, 25]),
      );
    });

    test('Loads strongly typed sorted list for nested flow', () {
      check(
            loadResolvedDartObject(
              ' [ $sequenceTag [ 1000, 623, 845, 0] ]',
              nodeResolvers: {sequenceTag: listResolver},
            ),
          )
          .isA<List>()
          .has((l) => l.firstOrNull, 'Single element')
          .which(
            (e) => e.isNotNull().isA<List<int>>().deepEquals(
              [0, 623, 845, 1000],
            ),
          );
    });

    test('Loads strongly typed set from nested flow map', () {
      check(
            loadResolvedDartObject(
              ' [ $setTag { is, is, a, a, set, set } ]',
              nodeResolvers: {setTag: mapResolver},
            ),
          )
          .isA<List>()
          .has((l) => l.firstOrNull, 'Single element')
          .which(
            (e) => e.isNotNull().isA<Set<String>>().deepEquals(
              {'is', 'a', 'set'},
            ),
          );
    });

    test(
      'Loads a strongly typed set from a block map when leading key has'
      ' properties',
      () {
        check(
          loadResolvedDartObject(
            '''
$setTag
!!str key:
''',
            nodeResolvers: {setTag: mapResolver},
          ),
        ).isA<Set<String>>().deepEquals({'key'});
      },
    );
  });

  group('Exceptions', () {
    test('Throws when a block node is inline with the custom properties', () {
      check(
        () => loadResolvedDartObject(
          '$setTag ? key',
          nodeResolvers: {setTag: mapResolver},
        ),
      ).throwsParserException(
        'A block sequence/map cannot be forced to be implicit or have inline '
        'properties before its indicator',
      );

      check(
        () => loadResolvedDartObject(
          '$sequenceTag - sequence',
          nodeResolvers: {sequenceTag: listResolver},
        ),
      ).throwsParserException(
        'A block sequence/map cannot be forced to be implicit or have inline '
        'properties before its indicator',
      );
    });

    test('Throws when a map can be constructed in the current state', () {
      check(
        () => loadResolvedDartObject(
          '''
$stringTag
!!int key: value
''',
          nodeResolvers: {stringTag: scalarResolver},
        ),
      ).throwsParserException(
        'Expected the implied start of a custom block map',
      );
    });

    test('Throws when a custom map cannot be parsed', () {
      check(
        () => loadResolvedDartObject(
          '$setTag [flow, sequence]',
          nodeResolvers: {setTag: mapResolver},
        ),
      ).throwsParserException('Expected a custom map');
    });

    test('Throws when a custom scalar cannot be parsed', () {
      check(
        () => loadResolvedDartObject(
          '$stringTag {key: value}',
          nodeResolvers: {stringTag: scalarResolver},
        ),
      ).throwsParserException(
        'Expected a scalar that can be parsed as a custom node',
      );
    });
  });
}
