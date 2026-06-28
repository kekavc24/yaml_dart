import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/tree_builder.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:test/test.dart';

import 'helpers/tree_node.dart';

void main() {
  late final TreeBuilder treeBuilder;

  setUpAll(() {
    treeBuilder = TreeBuilder();
  });

  group('Built-in Dart types', () {
    test('Returns a content node for a root scalar', () {
      treeBuilder.buildFor('hello world');
      check(treeBuilder.builtNode()).isA<ContentNode>();
    });

    test('Returns a collection node for an iterable', () {
      const iterable = ['dart', 'iterable'];
      final set = iterable.toSet();

      for (final iter in [iterable, set]) {
        treeBuilder.buildFor(iter);

        check(treeBuilder.builtNode()).isA<ListNode>().whoseNode().every(
          (node) => node.isA<ContentNode>(),
        );
      }
    });

    test('Returns a collection node for a map', () {
      treeBuilder.buildFor({
        'key': 'value',
        'next': [
          'value',
          {'nested': 'inner'},
        ],
      });

      check(treeBuilder.builtNode()).isA<MapNode>().whoseNode()
        ..has((f) => f.first, 'First Entry')
            .has((e) sync* {
              yield e.$1;
              yield e.$2;
            }, 'Both key and value')
            .every((e) => e.isA<ContentNode>())
        ..has((l) => l.last, 'Last Entry').which(
          (e) => e
            ..has((k) => k.$1, 'Key').isA<ContentNode>()
            ..has((k) => k.$2, 'Value').isA<ListNode>(),
        );
    });
  });

  group('Config', () {
    group('Styling', () {
      test('Block style allows all styles', () {
        treeBuilder.buildFor([
          'scalar',
          CustomMap('key')..nodeStyle = NodeStyle.flow,
        ], config: TreeConfig.block());

        check(treeBuilder.builtNode()).isA<ListNode>().whoseNode().any(
          (e) => e.isA<MapNode>().hasStyle(NodeStyle.flow),
        );
      });

      test("Flow only accepts flow", () {
        treeBuilder.buildFor(
          [
            ScalarView('hello')..scalarStyle = ScalarStyle.folded,
            YamlIterable({'key': 'map'})..nodeStyle = NodeStyle.block,
          ],
          config: TreeConfig.flow(),
        );

        check(treeBuilder.builtNode())
          ..hasStyle(NodeStyle.flow)
          ..isA<ListNode>().whoseNode().every(
            (e) => e.hasStyle(NodeStyle.flow),
          );
      });

      test('Forces nodes inline in flow style', () {
        treeBuilder.buildFor({
          'key\nwith\nlf': ['value\n'],
        }, config: TreeConfig.flow(forceInline: true));

        check(treeBuilder.builtNode()).isA<MapNode>()
          ..hasStyle(NodeStyle.flow)
          ..whoseNode()
              .has((e) => e.first, 'Entry')
              .which(
                (entry) => entry
                  ..has(
                    (ek) => ek.$1,
                    'Key',
                  ).isA<ContentNode>().multiline().isFalse()
                  ..has((ev) => ev.$2, 'value').which(
                    (c) => c
                      ..multiline().isFalse()
                      ..isA<ListNode>().whoseNode().every(
                        (e) => e.multiline().isFalse(),
                      ),
                  ),
              );
      });
    });

    group('Tags', () {
      test('Assigns schema tags correctly', () {
        treeBuilder.buildFor([
          'scalar',
          {},
          24,
          24.0,
          true,
          null,
          [],
        ], config: TreeConfig.block(includeSchemaTag: true));

        check(treeBuilder.builtNode())
            .isA<ListNode>()
            .whoseNode()
            .has((e) => e.map((f) => f.localTag), 'Tags')
            .deepEquals(
              [
                stringTag,
                mappingTag,
                integerTag,
                floatTag,
                booleanTag,
                nullTag,
                sequenceTag,
              ].map((e) => e.toString()),
            );
      });

      test('Assigns custom tags correctly', () {
        final spoof = TagShorthand.primary('spoof');

        treeBuilder.buildFor([
          ScalarView('hello')..withNodeTag(spoof),
          YamlIterable('world')..withNodeTag(spoof),
          CustomMap('custom')..withNodeTag(spoof),
        ]);

        check(
          treeBuilder.builtNode(),
        ).isA<ListNode>().whoseNode().every((e) => e.hasTag(spoof.toString()));
      });

      test(
        'Throws if the global tag handle is mismatched with a tag handle',
        () {
          final local = TagShorthand.primary('hello');
          final global = GlobalTag.fromTagShorthand(
            TagHandle.secondary(),
            TagShorthand.primary('spoof'),
          );

          check(
            () => treeBuilder.buildFor([
              ScalarView(24)..withNodeTag(local, globalTag: global),
            ]),
          ).throws();
        },
      );

      test('Throws if another global tag already defines the handle', () {
        final handle = TagHandle.named('handled');

        final core = GlobalTag.fromTagShorthand(
          handle,
          TagShorthand.primary('holder'),
        );

        final duplicate = GlobalTag.fromTagUri(handle, 'tag:another');

        check(
          () => treeBuilder.buildFor([
            ScalarView(24)..withNodeTag(
              TagShorthand.fromTagUri(handle, 'tag'),
              globalTag: core,
            ),

            YamlIterable([24])..withNodeTag(
              TagShorthand.fromTagUri(handle, 'multipl'),
              globalTag: duplicate,
            ),
          ]),
        ).throws();
      });

      test('Throws if a named tag has no global tag', () {
        check(
          () => treeBuilder.buildFor([
            ScalarView(24)..withNodeTag(TagShorthand.named('orphan', 'tag')),
          ]),
        ).throws();
      });
    });
  });

  group('Aliases', () {
    test('Constructs alias correctly', () {
      treeBuilder.buildFor([ScalarView(24)..anchor = '24', Alias('24')]);

      check(treeBuilder.builtNode())
          .isA<ListNode>()
          .whoseNode()
          .has((e) => e.lastOrNull, 'Last element')
          .isNotNull()
          .isA<ReferenceNode>()
          .which(
            (node) => node
              ..isNodeType(NodeType.alias)
              ..whoseNode().equals('*24'),
          );
    });

    test('Includes (invalid) anchors', () {
      const ref = 'invalid-yaml';

      check(
        (treeBuilder
              ..includeAnchors([ref])
              ..buildFor(Alias(ref)))
            .builtNode(),
      ).isA<ReferenceNode>().whoseNode().equals('*$ref');
    });

    test('Throws if no such anchor is present', () {
      check(() => treeBuilder.buildFor(Alias('24'))).throws();
      check(
        () => treeBuilder.buildFor([
          ScalarView(30)..anchor = 'this',
          Alias('that'),
        ]),
      ).throws();
    });
  });

  group('TreeNode', () {
    test('Ignores a top level tree node', () {
      final node = (treeBuilder..buildFor('Hello')).builtNode();

      treeBuilder.buildFor(node);
      check(identical(treeBuilder.builtNode(), node)).isTrue();
    });

    test('Ignores nested tree node', () {
      final node = (treeBuilder..buildFor(['Nested'])).builtNode();

      treeBuilder.buildFor(['this', 'is', node]);
      check(
        treeBuilder.builtNode(),
      ).isA<ListNode>().whoseNode().any((e) => e.identicalTo(node));
    });

    test('Maps object using the internal mapper', () {
      Object toString(Object? object) => switch (object) {
        List() => object,
        Map() || List() => object.toString(),
        _ => object.toString().split('').join('-'),
      };

      final builder = TreeBuilder()
        ..mapper = toString
        ..buildFor([
          {'hello': 'mapper'},
          '123',
        ]);

      check(builder.builtNode())
          .isA<ListNode>()
          .whoseNode()
          .has((e) => e.map((f) => f.node.toString()), 'Nodes')
          .deepEquals(['("{hello: mapper}")', '(1-2-3)']);
    });
  });
}
