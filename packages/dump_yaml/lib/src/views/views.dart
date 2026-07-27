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
  YamlIterable(this.node, {this.toFormat = iterable});

  @override
  Object? node;

  @override
  NodeStyle nodeStyle = NodeStyle.block;

  @override
  IterableToYaml toFormat;

  @override
  bool operator ==(Object other) => yamlCollectionEquality.equals(node, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(node);
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
  ScalarView(this._scalar, {this.toFormat = string});

  Object? _scalar;

  @override
  Object? get node => _scalar;

  @override
  ScalarToString toFormat;

  set scalar(Object? value) {
    if (identical(value, this)) return;
    _scalar = value;
  }

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

/// A list of [MapEntry]s for a YAML map.
///
/// {@category dump_map}
typedef YamlMappingEntry = Iterable<MapEntry<Object?, Object?>>;

/// Maps a map to a yaml mapping.
///
/// {@category dump_map}
typedef MapToYaml = ObjectFromView<YamlMappingEntry>;

/// A mutable view for a [Map]-like object that can have YAML node properties.
/// Unlike [ScalarView] and [YamlIterable], its `toFormat` getter cannot be
/// overriden due to the sensitive nature of yaml [Map]s. See [DartMap] or
/// [CustomMap].
///
/// {@category dumpable_view}
/// {@category dump_map}
sealed class YamlMapping<T> extends ConcreteNode<YamlMappingEntry> {
  /// Creates a [YamlMapping] wrapping a [node].
  ///
  /// If the [node] is not an [Map], the default [toFormat] creates a single
  /// entry with a key and no value.  For a custom object, provide a [toFormat]
  /// callback that will be called when the map is being dumped.
  ///
  /// This view inherits the [node]'s hashcode and equality implementation.
  YamlMapping(this.node);

  @override
  covariant T node;

  @override
  NodeStyle nodeStyle = NodeStyle.block;

  @override
  MapToYaml get toFormat;
}

/// A wrapper for built-in `Dart` [Map]s.
///
/// {@category dumpable_view}
/// {@category dump_map}
final class DartMap extends YamlMapping<Map<Object?, Object?>> {
  DartMap(super.node);

  @override
  MapToYaml get toFormat =>
      (e) => (e as Map).entries;
}

/// Helper that returns the keys of an object.
///
/// {@category dump_map}
typedef GetKeys = Set<Object?> Function(Object? object);

/// Helper that reads the value of a key from a `map-like` object.
///
/// {@category dump_map}
typedef GetValue =
    Object? Function(Object? map, ({Object? key, int index}) current);

/// Lazily extracts the entries of an object [v] using predefined [getKeys] and
/// [readValue] helpers.
YamlMappingEntry _lazy(Object? v, GetKeys getKeys, GetValue readValue) sync* {
  var index = 0;

  for (final key in getKeys(v)) {
    yield MapEntry(key, readValue(v, (key: key, index: index)));
    ++index;
  }
}

/// A [YamlMapping] wrapper that allows you to wrap an object and provide
/// a custom [GetKeys] callback for extracting keys and a [GetValue] callback
/// for extracting the value associated with each key.
///
/// {@category dumpable_view}
/// {@category dump_map}
final class CustomMap extends YamlMapping<Object?> {
  CustomMap(super.node);

  /// Obtains the keys from a custom [node]. Duplicate keys will not have their
  /// entries visited by the `TreeBuilder`.
  GetKeys getKeys = (o) => {o};

  /// Obtains the values from the [node] via its keys.
  GetValue readValue = (_, _) => null;

  @override
  MapToYaml get toFormat =>
      (o) => _lazy(o, getKeys, readValue);
}
