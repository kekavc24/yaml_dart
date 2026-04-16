# dump_yaml

[![codecov](https://codecov.io/gh/kekavc24/yaml_dart/graph/badge.svg?token=KEAB3HXYL2&flag=dump_yaml)](https://codecov.io/gh/kekavc24/yaml_dart)
![pub_version][dart_pub_version]
![pub_downloads][dart_pub_downloads]

A spec-compliant YAML dumper that prioritizes clean YAML documents as its default configuration. It supports all features implemented in most (if not all) YAML parsers.

> [!TIP]
> If you're migrating from `package:rookie_yaml` version 0.6.0 and below, see the [migration guide](https://github.com/kekavc24/yaml_dart/blob/main/packages/dump_yaml/migrations/from_rookie_yaml.md).

## Principles

1. **100% spec-compliant** - All supported features are included in the YAML spec and vice versa (all YAML features are supported).
2. **Simplicity** - No YAML-specific knowledge required. Just call `dumpAsYaml`.
3. **Configurability** - The dumper includes features you can use to accurately control the final output of your YAML files. (See next section).

## What's Included

Dumping YAML is tricky but incredibly satisfying when gotten right. The `YamlDumper` exposed is built for configurability and reusability. The dumper accepts a config with 2 options:

- `styling` - Controls the node styles used when dumping.
- `formatting` - Controls the final YAML output.

### Styling

The package also exposes additional utility classes:

- `TreeBuilder` - builds the YAML representation tree that is dumped.
- `DumpableView` - a mutable lightweight wrapper class that exposes all the YAML features you may require for a node.

> [!TIP]
> A `DumpableView` can be used to override the style of nested nodes or apply comments. It provides useful setters for such usecases. See docs.

### Formatting

Use this option to configure:

1. Starting indent.
2. Indentation step for nested nodes of a collection.
3. Line ending used for your files.

## Usage

### Dumper oneliner

```dart
print(dumpAsYaml(['hello', 'there']));
```

```yaml
- hello
- there
```

### Streaming support

Tweak the dumper to match your requirements. A simple example:

```dart
final chunks = <String>[];
final someLazyStream = StreamController<String>();
final bufferChunks = someLazyStream.stream
    .listen(chunks.add)
    .asFuture<void>();

final dumper = YamlDumper(
  config: Config.defaults(),
  buffer: YamlBuffer.toStream(someLazyStream),
);

dumper.dump([
  'I',
  'love',
  {'streaming': 'things'},
  'lazily',
]);

await someLazyStream.close();
await bufferChunks;

/*
  * Lazy chunks as the dumper walks your object.

[, -,  , I,
, , -,  , love,
, , -,  , streaming, :,  , things,
, , -,  , lazily,
]
  */
print(chunks);

/*
- I
- love
- streaming: things
- lazily
*/
print(chunks.join());
```

### Support for YAML features

- A bit sophisticated. A `DumpableView` provides granular control over the `TreeBuilder` but still relies on the same builder for housekeeping. For example, `ScalarStyle.literal` is not allowed in flow styles in YAML.

```dart
final configurable = [
  ScalarView('hello YAML, from world')
    ..anchor = 'scalar'
    ..scalarStyle = ScalarStyle.literal // Not allowed in YAML flow.
    ..commentStyle = CommentStyle.trailing
    ..comments.addAll(['trailing', 'comments']),

  YamlMapping({'key': 24, 'next': Alias('scalar')})
      ..forceInline = true
      ..commentStyle = CommentStyle.block
      ..comments.addAll(['block', 'comments'])
];

print(
  dumpAsYaml(
    configurable,
    config: Config.yaml(
      includeYamlDirective: true,
      styling: TreeConfig.flow(
        forceInline: false,
        scalarStyle: ScalarStyle.doubleQuoted,
        includeSchemaTag: true,
      ),
      formatting: Formatter.config(rootIndent: 3, indentationStep: 1),
    ),
  ),
);
```

```yaml
%YAML 1.2
---
   !!seq [
    &scalar "hello YAML, from world" # trailing
                                     # comments
    ,
    # block
    # comments
    {!!str "key": !!int "24", !!str "next": *scalar}
   ]
```

## Documentation & Examples (Still in progress 🏗️)

- The `docs` folder in the repository. Use the [table of contents](https://github.com/kekavc24/yaml_dart/blob/main/packages/dump_yaml/doc/_contents.md) as a guide.
- Visit pub [guide](https://pub.dev/documentation/dump_yaml/latest/) which provides an automatic guided order for the docs above.

## Contribution

All contributions are welcome.

- Create an issue if you need help or any features you'd like.
- See [guide](https://github.com/kekavc24/yaml_dart/blob/main/CONTRIBUTING.md) on how to make contributions to this repository.

[dart_pub_version]: https://img.shields.io/pub/v/dump_yaml.svg
[dart_pub_downloads]: https://img.shields.io/pub/dm/dump_yaml.svg
