import 'package:checks/checks.dart';
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

  group('ScalarView', () {
    test('Returns a content node for a scalar view', () {
      treeBuilder.buildFor(
        ScalarView({'ignores, type'})
          ..withNodeTag(stringTag)
          ..anchor = 'scalar',
      );

      check(treeBuilder.builtNode()).isA<ContentNode>()
        ..hasTag(stringTag.toString())
        ..hasAnchor('scalar');
    });
  });

  group('YamlIterable', () {
    test('Returns a collection view for an iterable', () {
      treeBuilder.buildFor(YamlIterable('converted to iterable'));

      check(treeBuilder.builtNode()).isA<CollectionNode>()
        ..whoseNode().any((e) => e.isA<ContentNode>())
        ..hasStyle(NodeStyle.block)
        ..hasAnchor(null)
        ..hasTag(null);
    });
  });

  group('YamlMapping', () {
    test('Returns a collection view for a map', () {
      treeBuilder.buildFor(CustomMap(['converted to key']));

      check(treeBuilder.builtNode()).isA<CollectionNode<MappingEntry>>()
        ..hasStyle(NodeStyle.block)
        ..hasTag(null)
        ..hasAnchor(null);
    });

    test('Removes duplicates from a custom YamlMapping', () {
      treeBuilder.buildFor(
        CustomMap([
            ('sneaky', 'entry'),
            ('sneaky', 'entry'),
            MapEntry(['key'], null),
            ['key'],
            {'key': 'value'},
            {'key': 'value'},
          ])
          ..getKeys = ((obj) =>
              (obj as Iterable).map((e) => e is MapEntry ? e.key : e).toSet())
          ..readValue = (map, current) =>
              current.index == 2 ? ((map as List)[2] as MapEntry).value : null,
      );

      check(
        treeBuilder.builtNode(),
      ).isA<MapNode>().whoseNode().length.equals(3);
    });

    test('Removes duplicates for Dart types hidden by wrapper', () {
      const list = ['value', 'next'];
      const map = {'key': list};

      treeBuilder.buildFor(
        CustomMap(
          {map, DartMap(map), list, YamlIterable(list)},
        )..getKeys = (object) => (object as Set),
      );

      check(
        treeBuilder.builtNode(),
      ).isA<MapNode>().whoseNode().length.equals(2);
    });
  });

  test('Throws if tags are mismatched', () {
    check(
      () => treeBuilder.buildFor(ScalarView('')..withNodeTag(mappingTag)),
    ).throws();

    check(
      () => treeBuilder.buildFor(YamlIterable('')..withNodeTag(stringTag)),
    ).throws();

    check(
      () => treeBuilder.buildFor(CustomMap([])..withNodeTag(sequenceTag)),
    ).throws();
  });
}
