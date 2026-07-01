import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/scanner/encoding/utf_utils.dart';
import 'package:test/test.dart';

void main() {
  const yaml = '''
greet: 안녕하세요 👋🏾 # Hello in Hangul 😁
name: Same same, but different 👫 👫🏻 👩🏻‍🤝‍👨🏽 👩🏽‍🤝‍👨🏾 👩🏾‍🤝‍👨🏼
test: 𝓾𝓽𝓯
targets:
  - utf-8️⃣
  - utf-1️⃣6️⃣
  - utf-3️⃣2️⃣
  - dart-string 🎯-⸾
''';

  const map = {
    'greet': '안녕하세요 👋🏾',
    'name':
        'Same same, but different '
        '👫 👫🏻 👩🏻‍🤝‍👨🏽 👩🏽‍🤝‍👨🏾 👩🏾‍🤝‍👨🏼',
    'test': '𝓾𝓽𝓯',
    'targets': [
      'utf-8️⃣',
      'utf-1️⃣6️⃣',
      'utf-3️⃣2️⃣',
      'dart-string 🎯-⸾',
    ],
  };

  void checkInput(YamlSource input) =>
      check(loadObject(input)).isA<Map>().deepEquals(map);

  group('Passes', () {
    test('Same input, same output (no BOM)', () {
      checkInput(YamlSource.string(yaml));
      checkInput(YamlSource.strictUtf8(utf8.encode(yaml)));
      checkInput(YamlSource.fixedUtf16(Uint16List.fromList(yaml.codeUnits)));
      checkInput(YamlSource.strictUtf16Iterator(yaml.codeUnits.iterator));
      checkInput(
        YamlSource.fixedUtf32(Uint32List.fromList(yaml.runes.toList())),
      );

      checkInput(YamlSource.fixedUtf32Iterator(yaml.runes.iterator));
    });

    test('Input with U+FEFF BOM', () {
      const withBOM = '\uFEFF$yaml';

      checkInput(YamlSource.string(withBOM));
      checkInput(YamlSource.strictUtf8(utf8.encode(withBOM)));
      checkInput(YamlSource.fixedUtf16(Uint16List.fromList(withBOM.codeUnits)));
      checkInput(
        YamlSource.fixedUtf32(Uint32List.fromList(withBOM.runes.toList())),
      );
    });

    test('Converts to code unit\'s endianess when U+FFFE BOM is present', () {
      const out = 'Hello world 👋🏾';
      const bom = 0xFFFE;

      void twiddles(YamlSource source) => check(loadObject(source)).equals(out);

      twiddles(
        YamlSource.strictUtf16(
          [bom].followedBy(out.codeUnits.map(utf16Converter)),
        ),
      );
      twiddles(
        YamlSource.fixedUtf32(
          [bom].followedBy(out.runes.map(utf32Converter)),
        ),
      );
    });
  });

  group('Exceptions', () {
    void throwsOnDecode({
      required String error,
      required YamlSource source,
    }) => check(
      () => loadObject(source),
    ).throws<StateError>().has((e) => e.message, 'Message').contains(error);

    group('UTF-8', () {
      test('Throws when the first byte is invalid', () {
        const error = 'cannot be the first byte in a UTF-8 byte sequence.';
        const outOfRange = [
          0xc0,
          0xc1,
          0xf5,
          0xf6,
          0xf7,
          0xf8,
          0xf9,
          0xfa,
          0xfb,
          0xfc,
          0xfd,
          0xfe,
          0xff,
        ];

        for (final byte in outOfRange) {
          throwsOnDecode(
            error: '${byte.readableHex()} $error',
            source: YamlSource.strictUtf8(Uint8List.fromList([byte])),
          );
        }
      });

      test('Throws when a continuation byte is invalid/missing', () {
        const secondByteError =
            'Invalid continuation byte after the first byte';

        // Uses the format: (First, min - 1, max + 1)
        final sensitiveByteRange =
            [
              (0xE0, 0x9F, 0xC0),
              (0xED, 0x7F, 0xA0),
              (0xF0, 0x8F, 0xC0),
              (0xF4, 0x7F, 0x90),
            ].expand((e) sync* {
              final firstByte = e.$1;
              yield [firstByte, e.$2];
              yield [firstByte, e.$3];
            });

        for (final range in sensitiveByteRange) {
          throwsOnDecode(
            error: secondByteError,
            source: YamlSource.strictUtf8(Uint8List.fromList(range)),
          );
        }

        // Third byte is invalid.
        throwsOnDecode(
          error: 'Invalid continuation byte',
          source: YamlSource.strictUtf8(Uint8List.fromList([0xE1, 0x81, 0xC0])),
        );

        // Missing trailing bytes
        throwsOnDecode(
          error: 'Missing bytes in the byte sequence',
          source: YamlSource.strictUtf8(Uint8List.fromList([0xE1])),
        );
      });
    });

    group('UTF-16', () {
      test('Throws when out of range', () {
        throwsOnDecode(
          error:
              'Invalid code unit "0x10000" not in range of 0x00 - 0xFFFF'
              ' encountered',
          source: YamlSource.strictUtf16([0x10000]),
        );
      });

      test('Throws when a surrogate pair is missing', () {
        throwsOnDecode(
          error: 'Missing trailing low-surrogate code unit',
          source: YamlSource.strictUtf16('🎯'.codeUnits.take(1)),
        );
      });

      test('Throws when one of the surrogate pairs is invalid', () {
        final codeUnits = '🎯'.codeUnits;
        const message = 'Invalid surrogate pairs found in the byte source.';

        throwsOnDecode(
          error: message,
          source: YamlSource.strictUtf16(codeUnits.reversed),
        );

        throwsOnDecode(
          error: message,
          source: YamlSource.strictUtf16(codeUnits.take(1).followedBy([0x4D])),
        );
      });
    });

    group('UTF-32', () {
      test('Throws when code unit is out of range', () {
        throwsOnDecode(
          error:
              'Invalid code unit "0x110000" not in range of 0x00 - 0x10FFFF'
              ' encountered.',
          source: YamlSource.fixedUtf32(Uint32List.fromList([0x110000])),
        );
      });

      test('Throws when dangling surrogate code units are present', () {
        throwsOnDecode(
          error: 'Ill-formed surrogate code unit',
          source: YamlSource.fixedUtf32(
            Uint32List.fromList(['🎯'.codeUnits.first]),
          ),
        );
      });
    });
  });
}
