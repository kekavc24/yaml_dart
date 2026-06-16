import 'dart:async';

import 'package:checks/checks.dart';
import 'package:dump_yaml/dump_yaml.dart';
import 'package:test/test.dart';

void main() {
  test('Buffers content to a stream', () {
    final controller = StreamController<String>();

    final dumper = YamlDumper(
      config: Config.defaults(),
      buffer: YamlBuffer.toStream(controller),
    );

    dumper.dump([
      'Hello',
      'World',
      'from',
      {'my': 'stream'},
    ]);

    final stream = controller.stream;
    controller.close();

    check(stream.join()).completes(
      (str) => str.equals('''
- Hello
- World
- from
- my: stream
'''),
    );
  });

  test('Buffers content to any writer', () {
    final writer = <String>[];

    final dumper = YamlDumper(
      config: Config.yaml(styling: TreeConfig.flow()),
      buffer: YamlBuffer.ofWriter(writer.add),
    );

    final mapSame = {'this': 'will', 'an': 'inline', 'flow': 'map'};

    dumper.dump(mapSame);
    check(writer.join()).equals(mapSame.toString());
  });

  test('Resets to any writer', () {
    const obj = {
      ['hello', 'world']: 'from',
      {'year'}: 24,
    };

    final chunks = <String>[];
    final other = StringBuffer();

    final dumper = YamlDumper.toStringBuffer(
      config: Config.defaults(),
      buffer: other,
    );

    dumper
      ..dump(obj)
      ..reset(writer: chunks.add)
      ..dump(obj);

    check(chunks.join()).equals(other.toString());
  });
}
