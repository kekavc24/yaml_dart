import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart'
    show
        ScalarStyle,
        TagShorthand,
        formFeed,
        unicodeNull,
        bell,
        backspace,
        verticalTab,
        nextLine,
        lineSeparator,
        paragraphSeparator,
        asciiEscape,
        nbsp,
        Flattened;
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

  group('General', () {
    test('Ignores style replaces empty strings with null', () {
      dumper.dump('');
      check(buffer.toString()).equals('null');
    });

    test(
      'Dumps empty strings as empty double quoted in plain if not empty is not'
      ' null',
      () {
        dumper
          ..reset(
            config: Config.yaml(
              styling: TreeConfig.block(emptyAsNull: false),
            ),
          )
          ..dump('');

        check(buffer.toString()).equals('');
      },
    );

    test('Applies properties correctly', () {
      final scalar = ScalarView(24)
        ..anchor = '24'
        ..withNodeTag(TagShorthand.primary('24'));

      void checkDump(String expected, [ScalarStyle? style]) {
        buffer.clear();

        dumper
          ..reset(
            config: Config.yaml(
              styling: TreeConfig.block(includeSchemaTag: true),
              formatting: Formatter.classic(indent: 1),
            ),
          )
          ..dump(scalar..scalarStyle = style ?? classicScalarStyle);

        check(buffer.toString()).equals(' &24 !24 $expected');
      }

      checkDump('24'); // No style

      checkDump('"24"', ScalarStyle.doubleQuoted);
      checkDump("'24'", ScalarStyle.singleQuoted);
      checkDump('24', ScalarStyle.plain);
      checkDump('>-\n 24', ScalarStyle.folded);
      checkDump('|-\n 24', ScalarStyle.literal);
    });

    test(
      'Defaults to double quoted and normalizes line breaks if forced inline',
      () {
        const value = 'hello \n\n here';
        const dumped = r'"hello \n\n here"';

        for (final style in ScalarStyle.values) {
          dumper
            ..reset(
              config: Config.yaml(
                styling: TreeConfig.flow(
                  scalarStyle: style,
                  forceInline: true,
                ),
              ),
            )
            ..dump(value);

          check(buffer.toString()).equals(dumped);
          buffer.clear();
        }
      },
    );
  });

  group('Dumps plain', () {
    setUpAll(() {
      dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.flow(
            scalarStyle: ScalarStyle.plain,
            forceInline: false,
          ),
        ),
      );
    });

    test('Dumps plain scalar', () {
      dumper.dump(24);
      check(buffer.toString()).equals('24');
    });

    test('Unfolds plain scalar', () {
      dumper.dump('my unfolded\n\nstring');
      check(buffer.toString()).equals('my unfolded\n\n\nstring');
    });

    test(
      'Normalizes all escaped characters excluding tabs and linebreaks',
      () {
        dumper.dump(
          'Normalized '
          '${unicodeNull.asString()}'
          '${bell.asString()}'
          '${backspace.asString()}'
          '${verticalTab.asString()}'
          '${formFeed.asString()}'
          '${nextLine.asString()}'
          '${lineSeparator.asString()}'
          '${paragraphSeparator.asString()}'
          '${asciiEscape.asString()}'
          '${nbsp.asString()}'
          ' sandwich',
        );

        check(
          buffer.toString(),
        ).equals(r'Normalized \0\a\b\v\f\N\L\P\e\_ sandwich');
      },
    );

    test('Defaults to double quoted if plain starts with # (comment)'
        ' or is comment-like', () {
      dumper.dump('# 24');
      check(buffer.toString()).equals('"# 24"');

      buffer.clear();

      dumper.dump('24 but # comment');
      check(buffer.toString()).equals('"24 but # comment"');

      buffer.clear();

      dumper.dump('24 but\t# comment');
      check(buffer.toString()).equals('"24 but\t# comment"');

      buffer.clear();

      dumper.dump('24 but\n# comment');
      check(buffer.toString()).equals('"24 but\n\n# comment"');

      buffer.clear();

      dumper.dump('24 but\r# comment');
      check(buffer.toString()).equals('"24 but\n\n# comment"');
    });

    test(
      'Defaults to double quoted if plain has characters not allowed at the'
      ' start',
      () {
        for (final char in ['?', ':', '-']) {
          dumper.dump('$char 24');
          check(buffer.toString()).equals('"$char 24"');
          buffer.clear();
        }
      },
    );

    test(
      'Defaults to double quoted if plain has flow indicators when in a flow'
      ' context',
      () {
        dumper.reset(config: Config.yaml(styling: TreeConfig.flow()));
        for (final char in ['{', '}', '[', ']', ',']) {
          dumper.dump('$char 24');
          check(buffer.toString()).equals('"$char 24"');
          buffer.clear();
        }
      },
    );
  });

  group('Dumps single quoted', () {
    setUpAll(() {
      dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.flow(
            scalarStyle: ScalarStyle.singleQuoted,
            forceInline: false,
          ),
        ),
      );
    });

    test('Dumps single quoted scalar', () {
      dumper.dump(24);
      check(buffer.toString()).equals("'24'");
    });

    test('Unfolds single quoted scalar', () {
      dumper.dump('my unfolded\n\nstring');
      check(buffer.toString()).equals("'my unfolded\n\n\nstring'");
    });

    test('Escapes all single quotes', () {
      dumper.dump("It's my quoted's scalar. Go brrrr''''");
      check(
        buffer.toString(),
      ).equals("'It''s my quoted''s scalar. Go brrrr'''''''''");
    });

    test(
      'Defaults to double quoted when a non-printable character is used',
      () {
        dumper.dump(bell.asString());
        check(buffer.toString()).equals(r'"\a"');
      },
    );
  });

  group('Dumps double quoted', () {
    setUpAll(
      () => dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.flow(
            scalarStyle: ScalarStyle.doubleQuoted,
            forceInline: false,
          ),
        ),
      ),
    );

    test('Dumps double quoted scalar', () {
      dumper.dump(24);
      check(buffer.toString()).equals('"24"');
    });

    test('Unfolds a simple double quoted scalar', () {
      dumper.dump('my unfolded\n\nstring');
      check(buffer.toString()).equals('"my unfolded\n\n\nstring"');
    });

    test('Unfolds a complex double quoted scalar', () {
      dumper.dump(
        'my folded \n'
        'string with spaces \n'
        ' \n'
        'weirdly placed',
      );

      check(buffer.toString()).equals(
        r'"my folded \'
        '\n\n\n'
        r'string with spaces \'
        '\n\n\n'
        r'\ '
        '\n\n'
        'weirdly placed"',
      );
    });

    test(
      'Normalizes all escaped characters excluding tabs and linebreaks'
      ' when not in json mode',
      () {
        dumper.dump(
          '${unicodeNull.asString()}'
          '${bell.asString()}'
          '${backspace.asString()}'
          '${verticalTab.asString()}'
          '${formFeed.asString()}'
          '${nextLine.asString()}'
          '${lineSeparator.asString()}'
          '${paragraphSeparator.asString()}'
          '${asciiEscape.asString()}'
          '${nbsp.asString()}'
          '"'
          r'\/',
        );

        check(buffer.toString()).equals(r'"\0\a\b\v\f\N\L\P\e\_\"\\\/"');
      },
    );
  });

  group('Dumps literal', () {
    setUpAll(
      () => dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
        ),
      ),
    );

    test('Dumps literal scalar', () {
      dumper.dump(24);
      check(buffer.toString()).equals('|-\n24');
    });

    test('Never unfolds literal scalar', () {
      dumper.dump('my unfoldable\n\nstring');
      check(buffer.toString()).equals('|-\nmy unfoldable\n\nstring');
    });

    test(
      'Preserves trailing linebreaks from being chomped in literal scalar',
      () {
        dumper.dump('my literal string\n\n');
        check(buffer.toString()).equals('|+\nmy literal string\n\n');
      },
    );

    test(
      'Preserves leading whitespace from being consumed as indent in first '
      'non-empty line in literal scalar',
      () {
        dumper.dump(' literal string');
        check(buffer.toString()).equals(
          '|1-\n'
          '  literal string', // Indented by additional space
        );
      },
    );

    test('Defaults to double quoted when non-printable character is used', () {
      dumper.dump(bell.asString());
      check(buffer.toString()).equals(r'"\a"');
    });
  });

  group('Dumps block folded', () {
    setUpAll(
      () => dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.block(scalarStyle: ScalarStyle.folded),
        ),
      ),
    );

    test('Dumps folded scalar', () {
      dumper.dump(24);
      check(buffer.toString()).equals('>-\n24');
    });

    test('Unfolds block folded scalar', () {
      dumper.dump('my unfolded\n\nstring');
      check(buffer.toString()).equals('>-\nmy unfolded\n\n\nstring');
    });

    test(
      'Preserves trailing linebreaks from being chomped in folded scalar'
      ' without unfolding them',
      () {
        dumper.dump('my block folded string\n\n');
        check(buffer.toString()).equals('>+\nmy block folded string\n\n');
      },
    );

    test(
      'Preserves leading whitespace from being consumed as indent in first '
      'non-empty line in block folded scalar',
      () {
        dumper.dump(' folded string');
        check(buffer.toString()).equals(
          '>1-\n'
          '  folded string', // Indented by additional space
        );
      },
    );

    test('Never unfolds line breaks joining indented line', () {
      dumper.dump(
        'folded string\n'
        ' with indented \n\n'
        'line',
      );

      check(buffer.toString()).equals(
        '>-\n'
        'folded string\n'
        ' with indented \n\n'
        'line',
      );
    });

    test('Defaults to double quoted when non-printable character is used', () {
      dumper.dump(bell.asString());
      check(buffer.toString()).equals(r'"\a"');
    });
  });
}
