import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map_entry.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Parses a flow sequence entry using the current parser [state].
NodeDelegate<Obj> _parseFlowSequenceEntry<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  final ParserState(:iterator) = state;
  final peekEvent = inferNextEvent(
    iterator,
    isBlockContext: false,
    lastKeyWasJsonLike: false,
  );

  if (peekEvent == FlowCollectionEvent.startExplicitKey) {
    return parseExplicitAsFlowMap(
      state,
      indentLevel: indentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    );
  }

  final keyOrElement = parseFlowNode(
    state,
    currentIndentLevel: indentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    collectionDelimiter: flowSequenceEnd,
  );

  // Track if we switched lines
  final lineIndex = iterator.currentLineInfo.current.lineIndex;
  final elementSpan = keyOrElement.nodeSpan;

  // Normally a list is a wildcard. We must assume that we parsed
  // an implicit key unless we never see ":". Encountering a
  // linebreak means the current flow node cannot be an implicit key.
  if (!nextSafeLineInFlow(
        iterator,
        minIndent: minIndent,
        forceInline: forceInline,
        onParseComment: state.onParseComment,
      ) ||
      (iterator.currentLineInfo.current.lineIndex != lineIndex) ||
      keyOrElement.encounteredLineBreak() ||
      inferNextEvent(
            iterator,
            isBlockContext: false,
            lastKeyWasJsonLike: keyIsJsonLike(keyOrElement),
          ) !=
          FlowCollectionEvent.startEntryValue) {
    elementSpan.parsingEnd = iterator.currentLineInfo.current;
    return keyOrElement;
  }

  elementSpan.parsingEnd = iterator.currentLineInfo.current;
  iterator.nextChar();
  state.onParseMapKey(keyOrElement.parsed());

  // We want this value inline. Override implicit and force inline param.
  final value = parseFlowNode(
    state,
    currentIndentLevel: indentLevel + 1,
    minIndent: minIndent,
    forceInline: true,
    collectionDelimiter: flowSequenceEnd,
  );

  return delegateWithOptimalEnd(
    state.defaultMapDelegate(
      mapStyle: NodeStyle.flow,
      indentLevel: indentLevel,
      indent: minIndent,
      keySpan: elementSpan,
    )..accept(keyOrElement.parsed(), value.parsed()),
    value.nodeSpan,
  );
}

/// Parses a flow sequence.
///
/// If [forceInline] is `true`, the sequence must be declared on the same line
/// with no line breaks and throws if otherwise.
NodeDelegate<Obj> parseFlowSequence<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
  NodeKind kind = YamlCollectionKind.sequence,
  ObjectFromIterable<Obj, Obj>? asCustomList,
}) {
  final ParserState(:iterator, :onParseComment, :onMapDuplicate) = state;

  bool goToNext(YamlSourceSpan entrySpan) => continueToNextEntry(
    iterator,
    lastEntrySpan: entrySpan,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  );

  final sequence = initFlowCollection(
    iterator,
    flowStartIndicator: flowSequenceStart,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
    flowEndIndicator: flowSequenceEnd,
    init: (start) {
      if (asCustomList != null) {
        return SequenceLikeDelegate<Obj, Obj>.boxed(
          asCustomList.onCustomIterable(),
          collectionStyle: NodeStyle.flow,
          indentLevel: indentLevel,
          indent: minIndent,
          start: start,
          afterSequence: asCustomList.afterObject<Obj>(),
        );
      }

      return state.defaultSequenceDelegate(
        style: NodeStyle.flow,
        indentLevel: indentLevel,
        indent: minIndent,
        start: start,
        kind: kind,
      );
    },
  );

  do {
    if (iterator.current case flowEntryEnd || flowSequenceEnd) {
      break;
    }

    final entry = _parseFlowSequenceEntry(
      state,
      indentLevel: indentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    );

    sequence.accept(entry.parsed());
    if (!goToNext(entry.nodeSpan)) break;
  } while (!iterator.isEOF);

  return terminateFlowCollection(iterator, sequence, flowSequenceEnd);
}
