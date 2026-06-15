import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// A flow map entry.
typedef FlowMapEntry<T> = ParsedEntry<T>;

/// Parses an explicit flow key and its value (if present) and composes a
/// compact flow map.
NodeDelegate<Obj> parseExplicitAsFlowMap<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) => _parseExplicitFlow(
  state,
  indentLevel: indentLevel,
  minIndent: minIndent,
  forceInline: forceInline,
  onExplicitKey: (_, key, value) {
    return delegateWithOptimalEnd(
      state.defaultMapDelegate(
        mapStyle: NodeStyle.flow,
        indentLevel: indentLevel,
        indent: minIndent,
        keySpan: key.nodeSpan,
      )..accept(key.parsed(), value?.parsed()),
      key.nodeSpan,
      value?.nodeSpan,
    );
  },
);

/// Parses an explicit flow key and its value (if present) using the current
/// parser [state].
FlowMapEntry<Obj> parseExplicitEntry<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) => _parseExplicitFlow(
  state,
  indentLevel: indentLevel,
  minIndent: minIndent,
  forceInline: forceInline,
  onExplicitKey: (_, key, value) => (key, value),
);

/// Parses an explicit flow key in arbitrary flow contexts and composes an
/// object [R] using the [onExplicitKey] callback.
R _parseExplicitFlow<R, Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
  required R Function(
    RuneOffset indicatorOffset,
    NodeDelegate<Obj> key,
    NodeDelegate<Obj>? value,
  )
  onExplicitKey,
}) {
  final ParserState(:iterator) = state;

  final keyStart = iterator.currentLineInfo.current;

  if (iterator.current != mappingKey) {
    throwWithSingleOffset(
      iterator,
      message: 'Expected an explicit key indicator "?"',
      offset: keyStart,
    );
  }

  iterator.nextChar();

  final key = parseFlowNode(
    state,
    currentIndentLevel: indentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    collectionDelimiter: mappingEnd,
    structuralOffset: keyStart,
  );

  // Value must be parsed in a safe state
  if (!nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: state.onParseComment,
  )) {
    throwWithSingleOffset(
      iterator,
      message:
          'Expected a next flow entry indicator "," or a map value indicator'
          ' ":" or a terminating delimiter "}"',
      offset: iterator.currentLineInfo.current,
    );
  }

  key.nodeSpan.parsingEnd = iterator.currentLineInfo.current;
  state.onParseMapKey(key.parsed());

  NodeDelegate<Obj>? value;

  if (inferNextEvent(
        iterator,
        isBlockContext: false,
        lastKeyWasJsonLike: keyIsJsonLike(key),
      ) ==
      FlowCollectionEvent.startEntryValue) {
    iterator.nextChar();
    value = parseFlowNode(
      state,
      currentIndentLevel: indentLevel + 1,
      minIndent: minIndent,
      forceInline: forceInline,
      collectionDelimiter: mappingEnd,
      structuralOffset: key.nodeSpan.parsingEnd,
    );
  }

  return onExplicitKey(keyStart, key, value);
}

/// Parses an implicit flow key and its value if present.
FlowMapEntry<Obj> parseImplicitEntry<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  final ParserState(:iterator) = state;

  if (iterator.current case flowEntryEnd || mappingEnd) {
    throwWithSingleOffset(
      iterator,
      message: 'Expected the start of an implicit flow key but found',
      offset: iterator.currentLineInfo.current,
    );
  }

  final parsedKey = parseFlowNode(
    state,
    currentIndentLevel: indentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    collectionDelimiter: mappingEnd,
  );

  final expectedCharErr =
      'Expected a next flow entry indicator "," or a map value indicator ":" '
      'or a terminating delimiter "}"';

  // Value must be parsed in a safe state
  if (!nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: state.onParseComment,
  )) {
    throwWithSingleOffset(
      iterator,
      message: expectedCharErr,
      offset: iterator.currentLineInfo.current,
    );
  }

  // Move end offset ahead for key
  parsedKey.nodeSpan.nodeEnd = iterator.currentLineInfo.current;
  state.onParseMapKey(parsedKey.parsed());

  if (iterator.current case flowEntryEnd || mappingEnd) {
    return (parsedKey, null);
  }

  // We must see ":"
  if (inferNextEvent(
        iterator,
        isBlockContext: false,
        lastKeyWasJsonLike: keyIsJsonLike(parsedKey),
      ) !=
      FlowCollectionEvent.startEntryValue) {
    throwWithSingleOffset(
      iterator,
      message: expectedCharErr,
      offset: iterator.currentLineInfo.current,
    );
  }

  iterator.nextChar();

  return (
    parsedKey,
    parseFlowNode(
      state,
      currentIndentLevel: indentLevel + 1,
      minIndent: minIndent,
      forceInline: forceInline,
      collectionDelimiter: mappingEnd,
      structuralOffset: parsedKey.nodeSpan.nodeEnd,
    ),
  );
}
