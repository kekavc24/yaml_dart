import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:test/test.dart';

ScalarResolver<int> _helper(TagShorthand tag, int radix) {
  return ScalarResolver.onMatch(
    tag,
    contentResolver: (i) => int.parse(i, radix: radix),
    toYamlSafe: (i) => i.toRadixString(radix),
  );
}

void main() {
  // TODO: More tests
  group('Scalars', () {
    test('Builder weeds out duplicate entries using their generic type', () {
      check(
        dumpAsYaml(
          CustomMap({
            ScalarView(24),
            ScalarView(24),
            ScalarView('hello'),
            ScalarView('hello'),
          })..getKeys = ((object) => object as Set),
        ),
      ).equals('''
24: null
hello: null
''');
    });

    test(
      'Integers with the same string content but different tags are not equal',
      () {
        // A tag in `package:rookie_yaml` forces a scalar to be resolved
        // differently.
        final intString = '12345670';

        final base8 = TagShorthand.primary('base8');
        final base10 = TagShorthand.primary('base10');
        final base16 = TagShorthand.primary('base16');

        final dumped = dumpAsYaml(
          CustomMap({
              ScalarView(intString)..withNodeTag(base16),
              ScalarView(intString)..withNodeTag(base10),
              ScalarView(intString)..withNodeTag(base8),
            })
            ..getKeys = ((object) => object as Set)
            ..readValue = (_, _) => '',
          config: Config.yaml(
            styling: TreeConfig.flow(
              emptyAsNull: false,
              scalarStyle: ScalarStyle.plain,
              forceInline: true,
            ),
          ),
        );

        check(
          dumped,
        ).equals('{$base16 $intString, $base10 $intString, $base8 $intString}');

        check(
          loadObject(
            YamlSource.simpleString(dumped),
            triggers: CustomTriggers(
              resolvers: [
                _helper(base8, 8),
                _helper(base10, 10),
                _helper(base16, 16),
              ],
            ),
          ),
        ).isA<Map>().deepEquals({
          int.parse(intString, radix: 16): null,
          int.parse(intString, radix: 10): null,
          int.parse(intString, radix: 8): null,
        });
      },
    );
  });
}
