import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart' show NodeStyle, ScalarStyle;
import 'package:test/test.dart';

const _comments = ['trailing', 'comments'];

void main() {
  late final YamlDumper dumper;

  // Only flow nodes can have trailing comments
  late final Iterable<DumpableView> flowNodes;

  late final StringBuffer buffer;

  setUpAll(() {
    buffer = StringBuffer();
    dumper = YamlDumper.toStringBuffer(
      config: Config.defaults(),
      buffer: buffer,
    );
    flowNodes = ScalarStyle.values
        .where((s) => s.nodeStyle.isFlow)
        .map(
          (style) => ScalarView(24)
            ..commentStyle = CommentStyle.trailing
            ..comments.addAll(_comments)
            ..scalarStyle = style,
        )
        .cast<DumpableView>()
        .followedBy([
          YamlIterable([])
            ..nodeStyle = NodeStyle.flow
            ..commentStyle = CommentStyle.trailing
            ..comments.addAll(_comments),

          DartMap({})
            ..nodeStyle = NodeStyle.flow
            ..commentStyle = CommentStyle.trailing
            ..comments.addAll(_comments),
        ]);
  });

  tearDown(() {
    buffer.clear();
  });

  test('Applies trailing comments correctly in block sequence', () {
    dumper
      ..reset(config: Config.defaults())
      ..dump(flowNodes);

    check(buffer.toString()).equals('''
- 24 # trailing
     # comments
- '24' # trailing
       # comments
- "24" # trailing
       # comments
- [] # trailing
     # comments
- {} # trailing
     # comments
''');
  });

  test('Applies trailing comments correctly in block map', () {
    dumper
      ..reset(config: Config.defaults())
      ..dump(flowNodes.toList().asMap());

    check(buffer.toString()).equals('''
0: 24 # trailing
      # comments
1: '24' # trailing
        # comments
2: "24" # trailing
        # comments
3: [] # trailing
      # comments
4: {} # trailing
      # comments
''');
  });

  test('Applies trailing comments correctly in flow list', () {
    dumper
      ..reset(config: Config.yaml(styling: TreeConfig.flow(forceInline: false)))
      ..dump(flowNodes);

    check(buffer.toString()).equals('''
[
  24 # trailing
     # comments
  ,
  '24' # trailing
       # comments
  ,
  "24" # trailing
       # comments
  ,
  [] # trailing
     # comments
  ,
  {} # trailing
     # comments
]''');
  });

  test('Applies trailing comments correctly in flow map', () {
    dumper
      ..reset(config: Config.yaml(styling: TreeConfig.flow(forceInline: false)))
      ..dump(flowNodes.toList().asMap());

    check(buffer.toString()).equals('''
{
  0: 24 # trailing
        # comments
  ,
  1: '24' # trailing
          # comments
  ,
  2: "24" # trailing
          # comments
  ,
  3: [] # trailing
        # comments
  ,
  4: {} # trailing
        # comments
}''');
  });

  test('Dumps keys as explicit if trailing comments are present', () {
    dumper.reset(config: Config.defaults());

    final orderedMap = flowNodes.fold(
      <Map<DumpableView, String>>[],
      (m, e) => m..add({e: 'value'}),
    );
    dumper.dump(orderedMap);

    check(buffer.toString()).equals('''
- ? 24 # trailing
       # comments
  : value
- ? '24' # trailing
         # comments
  : value
- ? "24" # trailing
         # comments
  : value
- ? [] # trailing
       # comments
  : value
- ? {} # trailing
       # comments
  : value
''');

    buffer.clear();
    dumper.dump(YamlIterable(orderedMap)..nodeStyle = NodeStyle.flow);

    check(buffer.toString()).equals('''
[
  {
    ? 24 # trailing
         # comments
    : value
  },
  {
    ? '24' # trailing
           # comments
    : value
  },
  {
    ? "24" # trailing
           # comments
    : value
  },
  {
    ? [] # trailing
         # comments
    : value
  },
  {
    ? {} # trailing
         # comments
    : value
  }
]''');
  });

  test('Ignores comments when a flow collection is inlined', () {
    dumper
      ..reset(config: Config.defaults())
      ..dump([
        YamlIterable(flowNodes)
          ..comments.addAll(_comments)
          ..commentStyle = CommentStyle.trailing
          ..nodeStyle = NodeStyle.flow
          ..forceInline = true,

        DartMap({0: flowNodes})
          ..comments.addAll(_comments)
          ..commentStyle = CommentStyle.trailing
          ..nodeStyle = NodeStyle.flow
          ..forceInline = true,
      ]);

    check(buffer.toString()).equals('''
- [24, '24', "24", [], {}] # trailing
                           # comments
- {0: [24, '24', "24", [], {}]} # trailing
                                # comments
''');
  });
}
