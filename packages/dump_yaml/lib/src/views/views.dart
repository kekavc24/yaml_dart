import 'dart:collection';

import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

/// A YAML sequence with entries.
///
/// {@category dump_list}
typedef YamlIterableEntry = Iterable<Object?>;

/// Maps an object to yaml sequence.
///
/// {@category dump_list}
typedef IterableToYaml = ObjectFromView<YamlIterableEntry>;

/// Creates an iterable containing [object] only if [object] is not an
/// [Iterable].
YamlIterableEntry iterable(Object? object) =>
    object is Iterable ? object : [object];

/// A mutable view for an [Iterable]-like object that can have YAML node
/// properties.
///
/// {@category dumpable_view}
/// {@category dump_list}
final class YamlIterable extends ConcreteNode<YamlIterableEntry> {
  /// Creates a [YamlIterable] wrapping a [node].
  ///
  /// If the [node] is not an [Iterable], the default [toFormat] creates a
  /// [List] for it. For a custom object, provide a [toFormat] callback that
  /// will be called when the iterable is being dumped.
  ///
  /// This view inherits the [node]'s hashcode and equality implementation.
  YamlIterable(super.node, {this.toFormat = iterable});

  @override
  NodeStyle nodeStyle = NodeStyle.block;

  @override
  IterableToYaml toFormat;
}

/// A list of [MapEntry]s for a YAML map.
///
/// {@category dump_map}
typedef YamlMappingEntry = Iterable<MapEntry<Object?, Object?>>;

/// Maps a map to a yaml mapping.
///
/// {@category dump_map}
typedef MapToYaml = ObjectFromView<YamlMappingEntry>;

/// Obtains the entries of the [object]. If not a map, the [object] is treated
/// as a key with a null value.
YamlMappingEntry _mapping(Object? object) {
  MapEntry<Object?, Object?> wrap(Object? toWrap) =>
      toWrap is MapEntry ? toWrap : MapEntry(toWrap, null);

  return switch (object) {
    Map() => object.entries,
    Iterable() => object.fold(
      LinkedHashSet(
        equals: (k1, k2) => yamlCollectionEquality.equals(k1.key, k2.key),
        hashCode: (p0) => yamlCollectionEquality.hash(p0.key),
      ),
      (buff, next) {
        (buff as LinkedHashSet).add(wrap(next));
        return buff;
      },
    ),
    _ => [wrap(object)],
  };
}

/// A mutable view for a [Map]-like object that can have YAML node properties.
/// Unlike [ScalarView] and [YamlIterable], its `toFormat` getter cannot be
/// overriden due to the sensitive nature of yaml [Map]s.
///
/// {@category dumpable_view}
/// {@category dump_map}
final class YamlMapping extends ConcreteNode<YamlMappingEntry> {
  /// Creates a [YamlMapping] wrapping a [node].
  ///
  /// If the [node] is not an [Map], the default [toFormat] creates a single
  /// entry with a key and no value.  For a custom object, provide a [toFormat]
  /// callback that will be called when the map is being dumped.
  ///
  /// This view inherits the [node]'s hashcode and equality implementation.
  YamlMapping(super.node);

  @override
  NodeStyle nodeStyle = NodeStyle.block;

  @override
  MapToYaml get toFormat => _mapping;
}

/// Maps any object to a scalar.
///
/// {@category dump_scalar}
typedef ScalarToString = ObjectFromView<String>;

String string(Object? object) => object.toString();

/// Mutable view for any object that can be dumped as a `YAML` scalar.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
final class ScalarView extends ConcreteNode<String> {
  /// Creates a [ScalarView] wrapping a [node] that is always stringified. The
  /// view inherits the [node]'s hashcode and equality implementation.
  ScalarView(super.node, {this.toFormat = string});

  @override
  ScalarToString toFormat;

  /// Scalar style associated with this view.
  ScalarStyle scalarStyle = ScalarStyle.plain;

  /// Whether to treat an empty string as a physical `null` when [scalarStyle]
  /// is [ScalarStyle.plain].
  bool emptyAsNull = true;

  @override
  NodeStyle get nodeStyle => scalarStyle.nodeStyle;

  @override
  String toString() => toFormat(node);
}
