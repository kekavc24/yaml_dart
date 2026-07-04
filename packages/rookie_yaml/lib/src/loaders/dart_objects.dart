part of 'loader.dart';

/// Recursively copies all elements of a [Map] or [List]
Object? deepCopyReference(Object? object) {
  switch (object) {
    case Map():
      {
        final copy = <Object?, Object?>{};
        _dereferenceMap(copy, object);
        return copy;
      }

    case List():
      {
        final copy = <Object?>[];
        _dereferenceIterable(object, copy.add);
        return copy;
      }

    case Set():
      {
        final copy = <Object?>{};
        _dereferenceIterable(object, copy.add);
        return copy;
      }

    default:
      return object;
  }
}

/// Copies all keys and values from [original] to the [copy].
void _dereferenceMap(
  Map<Object?, Object?> copy,
  Map<Object?, Object?> original,
) {
  for (final MapEntry(:key, :value) in original.entries) {
    copy[deepCopyReference(key)] = deepCopyReference(value);
  }
}

/// Copies all elements from the [original] to a copy via its [push] callback.
void _dereferenceIterable(
  Iterable<Object?> original,
  void Function(Object? object) push,
) {
  for (final object in original) {
    push(deepCopyReference(object));
  }
}

/// Dereferences a [List] or [Map] if [dereferenceAlias] is `true`. Callers of
/// built-in Dart type loaders such [loadObject] or [loadAllObjects]
/// may want aliases dereferenced since the parser does a zero-copy operation
/// and just passes the reference around.
Object? _dereferenceAliases(Object? object, {required bool dereferenceAlias}) =>
    dereferenceAlias ? deepCopyReference(object) : object;

/// Creates a [DocumentParser] for (generic) `Dart` objects that reads
/// code units from a source [iterator]. Prefer using the provided
/// [UnicodeIterator] and implementing an [Iterator] which emits [Unicode]
/// values or using any of the helper constructors exposed by the [YamlSource]
/// extension type.
///
/// If [dereferenceAliases] is `true`, every [Map] and [Iterable] anchor
/// reference will be deeply-copied everytime the parser needs it. Otherwise,
/// the parser will use the [Map] and [Iterable] reference "as-is".
///
/// If [throwOnMapDuplicate] is `false`, the parser skips entries whose keys
/// are already in the YAML [Map] constructed and calls the [logger] callback
/// provided **INFORMING** you of this action. Otherwise, always throws.
DocumentParser<Object?, Object?> dartObjectParser(
  SourceIterator iterator, {
  required bool dereferenceAliases,
  required bool throwOnMapDuplicate,
  required CustomTriggers? triggers,
  required DocumentBuilder<Object?, Object?>? docBuilder,
  required void Function(bool isInfo, String message)? logger,
}) {
  return DocumentParser(
    iterator,
    aliasFunction: (_, reference, _) =>
        _dereferenceAliases(reference, dereferenceAlias: dereferenceAliases),
    collectionFunction: (buffer, _, _, _, _) => buffer,
    scalarFunction: (inferred, _, _, _, _) => inferred.value,
    triggers: triggers,
    logger: logger ?? defaultLogger,
    onMapDuplicate: (keyStart, keyEnd, message) => onParsedDuplicateKey(
      iterator,
      start: keyStart,
      end: keyEnd,
      message: message,
      throwOnMapDuplicate: throwOnMapDuplicate,
    ),
    builder: docBuilder ?? (_, _, rootNode) => rootNode.root,
  );
}

/// Loads every document as a `Dart` object.
List<Object?> _loadAsDartObject(
  SourceIterator iterator, {
  required bool dereferenceAliases,
  required bool throwOnMapDuplicate,
  required CustomTriggers? triggers,
  required void Function(bool isInfo, String message)? logger,
}) => loadYamlDocuments<Object?, Object?>(
  dartObjectParser(
    iterator,
    dereferenceAliases: dereferenceAliases,
    throwOnMapDuplicate: throwOnMapDuplicate,
    triggers: triggers,
    docBuilder: null,
    logger: logger,
  ),
);

/// Loads every document's root node as a `Dart` object. This function
/// guarantees that every object returned will be a primitive Dart type or a
/// type inferred via the [triggers] provided.
///
/// If [dereferenceAliases] is `true`, any [List] or [Map] anchors are copied
/// instead of being passed to the alias by reference. This operation only
/// occurs when the parser actually needs the node.
///
/// [triggers] enable the parser to accept a collection of [ScalarResolver]s
/// to directly manipulate parsed content of a parsed scalar. Additionally,
/// a custom trigger also accepts [CustomResolver]s that allow you to configure
/// how the parser treats nodes annotated with specific [TagShorthand]s. Each
/// node can only be resolved by a specific tag since a node is restricted to
/// one kind when parsing.
///
/// If [throwOnMapDuplicate] is `false`, the parser logs the duplicate as a
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category dart_objects}
List<Object?> loadAllObjects(
  YamlSource source, {
  bool dereferenceAliases = false,
  bool throwOnMapDuplicate = true,
  CustomTriggers? triggers,
  void Function(bool isInfo, String message)? logger,
}) => _loadAsDartObject(
  UnicodeIterator.ofUnicode(source),
  dereferenceAliases: dereferenceAliases,
  throwOnMapDuplicate: throwOnMapDuplicate,
  triggers: triggers,
  logger: logger,
);

/// Loads the first node as a `Dart` object. This function guarantees that
/// every object returned will be a primitive Dart type or a type inferred via
/// the [triggers] provided. A nullable [T] is returned in case the object could
/// not be parsed.
///
/// If [dereferenceAliases] is `true`, any [List] or [Map] anchors are copied
/// instead of being passed to the alias by reference. This operation only
/// occurs when the parser actually needs the node.
///
/// [triggers] enable the parser to accept a collection of [ScalarResolver]s
/// to directly manipulate parsed content of a parsed scalar. Additionally,
/// a custom trigger also accepts [CustomResolver]s that allow you to configure
/// how the parser treats nodes annotated with specific [TagShorthand]s. Each
/// node can only be resolved by a specific tag since a node is restricted to
/// one kind when parsing.
///
/// If [throwOnMapDuplicate] is `false`, the parser logs the duplicate as a
/// warning and continues parsing the next entry. The existing value will
/// not be overwritten.
///
/// {@category dart_objects}
T? loadObject<T>(
  YamlSource source, {
  bool dereferenceAliases = false,
  bool throwOnMapDuplicate = true,
  CustomTriggers? triggers,
  void Function(bool isInfo, String message)? logger,
}) =>
    loadAllObjects(
          source,
          dereferenceAliases: dereferenceAliases,
          throwOnMapDuplicate: throwOnMapDuplicate,
          triggers: triggers,
          logger: logger,
        ).firstOrNull
        as T?;
