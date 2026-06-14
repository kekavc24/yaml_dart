import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/explicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/implicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Adds a [key]-[value] pair to a [map].
void _addMapEntry<Obj>(
  MapDuplicateHandler handler,
  MapLikeDelegate<Obj, Obj, Obj> map,
  NodeDelegate<Obj> key,
  NodeDelegate<Obj>? value,
) {
  if (!map.accept(key.parsed(), value?.parsed())) {
    handler(
      key.nodeSpan.nodeStart,
      value?.nodeSpan.nodeEnd ?? key.nodeSpan.nodeEnd,
      'A block map cannot contain duplicate entries by the same key',
    );
  }

  delegateWithOptimalEnd(map, key.nodeSpan, value?.nodeSpan);
}

/// Attempts to compose and parse a block map using the [keyOrNode] as the
/// first implicit key. [keyOrNode] is not restricted to a `Scalar` but may
/// also represent any flow collection that is implicit.
///
/// If a block map cannot be parsed then the [keyOrNode] is returned. A block
/// map is never parsed if:
///   - [composeImplicitMap] is `false`.
///   - [keyOrNode] spans multiple lines.
///   - [keyOrNode] is a block style node. Block scalars cannot be implicit
///     keys.
///   - [documentMarker] is [DocumentMarker.directiveEnd] or
///     [DocumentMarker.documentEnd] which both signify the end of the current
///     document.
BlockNode<Obj> composeBlockMapFromScalar<Obj>(
  ParserState<Obj> state, {
  required NodeDelegate<Obj> keyOrNode,
  required ParsedProperty? keyOrMapProperty,
  required int? indentOnExit,
  required DocumentMarker documentMarker,
  required bool keyIsBlock,
  required bool composeImplicitMap,
  required int composedMapIndent,
}) {
  final ParserState(:iterator, :onParseComment) = state;

  if (!composeImplicitMap ||
      documentMarker.stopIfParsingDoc ||
      iterator.isEOF ||
      keyIsBlock ||
      keyOrNode.encounteredLineBreak()) {
    state.trackAnchor(nodeParseEnd(keyOrNode, iterator), keyOrMapProperty);

    return (
      blockInfo: (docMarker: documentMarker, exitIndent: indentOnExit),
      node: keyOrNode,
    );
  } else if (iterator.current != mappingValue) {
    final indentOrSeparation = skipToParsableChar(
      iterator,
      onParseComment: onParseComment,
      allowTabs: (currentIndent, _) => currentIndent == null,
    );

    // Indent must be null. This must be an inlined key
    if (iterator.isEOF ||
        indentOrSeparation != null ||
        inferBlockEvent(iterator) != BlockCollectionEvent.startEntryValue) {
      state.trackAnchor(nodeParseEnd(keyOrNode, iterator), keyOrMapProperty);
      return (
        blockInfo: (exitIndent: indentOrSeparation, docMarker: documentMarker),
        node: keyOrNode,
      );
    }
  }

  // Prefer handing off properties to the map moreso when no properties are
  // present. The map should hold the structual offset at all times. Not the
  // key.
  final (keyProp, mapProp) =
      keyOrMapProperty != null &&
          (keyOrMapProperty.isMultiline || !keyOrMapProperty.parsedAny)
      ? (null, keyOrMapProperty)
      : (keyOrMapProperty, null);

  return composeAndParseBlockMap(
    state,
    key: state.trackAnchor(keyOrNode, keyProp),
    mapProperty: mapProp,
    fixedMapIndent: composedMapIndent,
  );
}

/// Parses the value of the provided [key] and uses the first entry to create a
/// [MapLikeDelegate] representing the block map with an indent of
/// [fixedMapIndent].
///
/// [parseBlockMap] is only called if more entries can be parsed after the
/// first [key]'s value has been parsed.
BlockNode<Obj> composeAndParseBlockMap<Obj>(
  ParserState<Obj> state, {
  required NodeDelegate<Obj> key,
  required ParsedProperty? mapProperty,
  required int fixedMapIndent,
}) {
  final iterator = state.iterator;

  final (onMapDuplicate, map) = (
    state.onMapDuplicate,
    state.defaultMapDelegate(
      mapStyle: NodeStyle.block,
      indentLevel: key.indentLevel,
      indent: fixedMapIndent,
      keySpan: key.nodeSpan,
    ),
  );

  state.onParseMapKey(key.parsed());

  final blockInfo = parseImplicitValue(
    state,
    keyIndent: fixedMapIndent,
    keyIndentLevel: key.indentLevel,
    onValue: (implicitValue) => _addMapEntry(
      onMapDuplicate,
      map,
      key,
      implicitValue,
    ),
    onEntryValue: (key, value) => _addMapEntry(onMapDuplicate, map, key, value),
  );

  // Exit if we can't parse more entries.
  if (exitBlockCollection(
    map,
    iterator: iterator,
    nodeIndent: fixedMapIndent,
    marker: blockInfo.docMarker,
    exitIndent: blockInfo.exitIndent,
  )) {
    return (
      blockInfo: blockInfo,
      node: state.trackAnchor(blockEnd(map), mapProperty),
    );
  }

  final (node: _, blockInfo: mapInfo) = parseBlockMap(map, state: state);

  // Intentional. Track anchor only after the whole map is parsed.
  return (
    node: state.trackAnchor(map, mapProperty) as NodeDelegate<Obj>,
    blockInfo: mapInfo,
  );
}

/// Parses the entries of a block [map].
BlockNode<Obj> parseBlockMap<Obj>(
  MapLikeDelegate<Obj, Obj, Obj> map, {
  required ParserState<Obj> state,
}) {
  final ParserState(:iterator, :onMapDuplicate) = state;
  final MapLikeDelegate(indent: mapIndent, :indentLevel) = map;

  void onParseEntry(NodeDelegate<Obj> key, NodeDelegate<Obj>? value) =>
      _addMapEntry(onMapDuplicate, map, key, value);

  while (!iterator.isEOF) {
    final blockInfo = switch (inferBlockEvent(iterator)) {
      BlockCollectionEvent.startExplicitKey => parseExplicitBlockEntry(
        state,
        entryIndent: mapIndent,
        entryIndentLevel: indentLevel,
        onExplicitEntry: onParseEntry,
      ),
      _ => parseImplicitBlockEntry(
        state,
        keyIndent: mapIndent,
        keyIndentLevel: indentLevel,
        onImplicitEntry: onParseEntry,
      ),
    };

    // Exit if we can't parse more entries.
    if (exitBlockCollection(
      map,
      iterator: iterator,
      nodeIndent: mapIndent,
      marker: blockInfo.docMarker,
      exitIndent: blockInfo.exitIndent,
    )) {
      return (blockInfo: blockInfo, node: blockEnd(map));
    }
  }

  return (blockInfo: emptyScanner, node: blockEnd(map));
}
