import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:test/test.dart';

void main() {
  // `package:rookie_yaml` doesn't support recursive aliases yet but we can
  // simulate them with `DumpableView`s.
  // TODO: Add more tests.
  test('Detects and creates an alias for self-referential lists', () {
    final list = <Object?>['hello', 'there'];
    list.add(YamlIterable(list)); // cheat

    // Block lists
    check(
      dumpAsYaml(list, config: Config.defaults()),
    ).equals('''
&recursive
- hello
- there
- *recursive
''');
  });

  test('Detects and creates an alias for self-referential maps', () {
    final map = <String, Object>{'key': 'value'};
    map['self'] = YamlMapping(map);

    // Block maps
    check(dumpAsYaml(map, config: Config.defaults())).equals('''
&recursive
key: value
self: *recursive
''');
  });

  test("Detects and uses a view's anchor for self-referential objects", () {
    final map = <String, Object>{};
    map['self'] = YamlMapping(map);

    final list = <Object?>['hello'];

    list
      ..add(list)
      ..add(YamlMapping(map)..anchor = 'map');

    map['iter'] = list;

    check(dumpAsYaml(YamlIterable(list)..anchor = 'iter')).equals('''
&iter
- hello
- *iter
- &map
  self: *map
  iter: *iter
''');
  });

  test("Preserves a recursive object's view properties", () {
    final list = <Object?>[];

    list
      ..add(
        YamlIterable(list)
          ..comments.addAll(['block', 'comments'])
          ..commentStyle = CommentStyle.block,
      )
      ..add(
        YamlIterable(list)
          ..comments.addAll(['possessive', 'comments'])
          ..commentStyle = CommentStyle.possessive,
      )
      ..add(
        YamlIterable(list)
          ..comments.addAll(['trailing', 'comments'])
          ..commentStyle = CommentStyle.trailing,
      );

    check(dumpAsYaml(list)).equals('''
&recursive
# block
# comments
- *recursive
- # possessive
  # comments
  *recursive
- *recursive # trailing
             # comments
''');
  });

  test('ScalarView has no self reference', () {
    final view = ScalarView(24);
    check((view..node = view).node).equals(24);
    check((view..node = 0).node).equals(0);
  });
}
