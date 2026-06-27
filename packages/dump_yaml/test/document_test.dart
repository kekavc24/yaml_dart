import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart'
    show GlobalTag, TagHandle, TagShorthand, VerbatimTag, parserVersion;
import 'package:test/test.dart';

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

  test('Includes schema tags', () {
    dumper
      ..reset(
        config: Config.yaml(
          styling: TreeConfig.block(includeSchemaTag: true),
        ),
      )
      ..dump([{}, 24, 24.0, "24", true, null]);

    check(buffer.toString()).equals('''
!!seq
- !!map {}
- !!int 24
- !!float 24.0
- !!str 24
- !!bool true
- !!null null
''');
  });

  test('Includes custom tags', () {
    dumper
      ..reset(
        config: Config.yaml(
          styling: TreeConfig.block(includeSchemaTag: false),
        ),
      )
      ..dump([
        ScalarView(24)..withVerbatimTag(
          VerbatimTag.fromTagShorthand(TagShorthand.primary('hello')),
        ),

        CustomMap('from')
          ..forceInline = true
          ..withNodeTag(TagShorthand.primary('world')),
      ]);

    check(buffer.toString()).equals('''
- !<!hello> 24
- !world {from: null}
''');
  });

  test('Includes custom global tags in document', () {
    dumper.reset(
      config: Config.yaml(
        styling: TreeConfig.block(includeSchemaTag: false),
      ),
    );

    final globalFromTag = GlobalTag.fromTagShorthand(
      TagHandle.primary(),
      TagShorthand.primary('global-shorthand'),
    );

    final globalFromUri = GlobalTag.fromTagUri(
      TagHandle.named('uri'),
      'uri:as.global',
    );

    dumper.dump([
      ScalarView(24)..withNodeTag(
        TagShorthand.primary('tag'),
        globalTag: globalFromTag,
      ),
      ScalarView('24')..withNodeTag(
        TagShorthand.named('uri', 'tag'),
        globalTag: globalFromUri,
      ),
      ScalarView(24.0)..withVerbatimTag(
        VerbatimTag.fromTagShorthand(TagShorthand.primary('verbatim')),
      ),
    ]);

    check(buffer.toString()).equals('''
$globalFromTag
$globalFromUri
---
- !tag 24
- !uri!tag 24
- !<!verbatim> 24.0
''');
  });

  test('Links aliases correctly', () {
    const ref = '24';

    dumper
      ..reset(config: Config.defaults())
      ..dump([
        ScalarView(24)..anchor = ref,
        Alias(ref),
        YamlIterable(['hello', 'there'])..anchor = ref,
      ]);

    check(buffer.toString()).equals('''
- &$ref 24
- *24
- &$ref
  - hello
  - there
''');
  });

  test('Dumps object as a full document', () {
    dumper
      ..reset(
        config: Config.yaml(
          includeYamlDirective: true,
          directives: {
            GlobalTag.fromTagUri(TagHandle.primary(), 'un:used.tag'),
          },
          includeDocEnd: true,
        ),
      )
      ..dump('Simple document');

    check(buffer.toString()).equals('''
$parserVersion
%TAG ! un:used.tag
---
Simple document
...''');

    buffer.clear();
    dumper
      ..reset(config: Config.yaml(includeDirectiveEnd: true))
      ..dump('Directive end but no directives');

    check(buffer.toString()).equals('''
---
Directive end but no directives''');
  });
}
