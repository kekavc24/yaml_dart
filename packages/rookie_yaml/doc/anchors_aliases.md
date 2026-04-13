An `alias` acts as a reference to an `anchor`. Think object references in `Dart` and any other language that is object oriented and `pointer`s in `C`.

You must declare an `anchor` before using it. The characters must also be valid [non-space printable characters][uri_char_url] that are not flow delimiters.

A node cannot have both an `anchor` and `alias`. `YAML` demands them to be mutually exclusive. This also disqualifies an `alias` from having a `tag` since it "borrows" its kind from the `anchor` node.

## Flow Nodes

Anchors and aliases for flow nodes since such nodes have explicit indicators.

```dart
const yaml = '''
# Indent is moot in flow styles
# It used for readability

{
  &ref-key "double quoted": &ref-seq [
    *ref-key ,
    &ref-single-quoted 'single quoted',
    &ref-plain plain,
    &ref-map {key: value}
  ],

  # Colon ":" is a valid uri char. Do not forget space
  *ref-plain : *ref-single-quoted ,

  # Use sequence as a key
  *ref-seq : *ref-map
}
''';

final expectedMap = {
  'double quoted': [
    'double quoted',
    'single quoted',
    'plain',
    {'key': 'value'},
  ],

  'plain': 'single quoted',

  [
    'double quoted',
    'single quoted',
    'plain',
    {'key': 'value'},
  ]: {'key': 'value'}
};

final node = loadObject(YamlSource.string(yaml));

/// Aliases are unpacked as the node they reference
print(node.toString() == expectedMap.toString()); // True

/// You need to use the Equality object exported by this package.
/// Prints true
print(yamlCollectionEquality.equals(node, expectedMap));
```

## Block Maps

Block map nodes are somewhat unique in this aspect. You need to declare the entire node on a new line for properties to be assigned to the node if it degenerates to a map.

```dart
  // This goes to the entire map
  const yaml = '''
- &map-anchor !!map
  key: value
- *map-anchor

--- # Next document!

&key-anchor !!str key: *key-anchor
''';

final docs = loadAllObjects(YamlSource.string(yaml));

// Objects are the same in the first document.
print((docs[0] as List).toSet().length == 1); // True

// Second document
final secondDoc = (docs[1] as Map).entries.first;

// Anchor in second document goes to the first key.
print(secondDoc.key == secondDoc.value); // True
```

## Block Explicit Keys & Block Sequences

Block explicit keys and block sequences cannot have properties before their `?` and `-` indicators respectively. Their node content begins after these indicators. You can only declare such properties if they are multiline and the block sequence entry or explicit key entry is the first entry in a block list and map respectively.

```dart
const yaml = '''
# This is okay

&map-anchor !!map
? key
: value
...

# This is also okay

&list-anchor !!seq
- entry
- next
''';

// [{key: value}, [entry, next]]
print(loadAllObjects(YamlSource.string(yaml)));
```

> [!WARNING]
> Currently, an `alias` cannot be recursive. The node must be parsed completely and resolved before an `anchor` can be used.

[uri_char_url]: https://yaml.org/spec/1.2.2/#692-node-anchors
