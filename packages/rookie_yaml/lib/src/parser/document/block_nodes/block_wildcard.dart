import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_map.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_sequence.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/scalars/scalars.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Parses a valid block node matching the [event].
BlockNode<Obj> parseBlockWildCard<Obj>(
  ParserState<Obj> state, {
  required ParserEvent event,
  required int? blockParentIndent,
  required int indentLevel,
  required int laxIndent,
  required int inlineFixedIndent,
  required ParsedProperty property,
  required bool isInline,
  required bool composeImplicitMap,
  DelegatedValue? delegateScalar,
}) => switch (event) {
  BlockCollectionEvent.startEntryValue => composeBlockMapFromScalar(
    state,
    keyOrNode: nullScalarDelegate(
      indentLevel: indentLevel,
      indent: laxIndent,
      startOffset: state.iterator.currentLineInfo.current,
      resolver: state.scalarFunction,
    )..nodeSpan.nodeEnd = state.iterator.currentLineInfo.current,
    keyOrMapProperty: property,
    indentOnExit: property.indentOnExit,
    documentMarker: DocumentMarker.none,
    keyIsBlock: false,
    composeImplicitMap: composeImplicitMap,
    composedMapIndent: inlineFixedIndent,
  ),
  BlockCollectionEvent.startExplicitKey => parseBlockMap(
    state.defaultMapDelegate(
      mapStyle: NodeStyle.block,
      indentLevel: indentLevel,
      indent: inlineFixedIndent,
      start: state.iterator.currentLineInfo.current,
    ),
    state: state,
  ),
  FlowCollectionEvent event => parseFlowNodeInBlock(
    state,
    event: event,
    indentLevel: indentLevel,
    indent: laxIndent,
    isInline: isInline,
    composeImplicitMap: composeImplicitMap,
    flowProperty: property,
    composedMapIndent: inlineFixedIndent,
  ),
  ScalarEvent() => parseBlockScalar(
    state,
    event: event,
    blockParentIndent: blockParentIndent,
    minIndent: laxIndent,
    indentLevel: indentLevel,
    isImplicit: isInline,
    scalarProperty: property,
    composeImplicitMap: composeImplicitMap,
    composedMapIndent: inlineFixedIndent,
    delegateScalar: delegateScalar,
  ),
  _ => throwWithRangedOffset(
    state.iterator,
    message: 'Block node found in a unparsable state',
    start: property.span.start,
    end: state.iterator.currentLineInfo.current,
  ),
};

/// Parses a flow collection that is a top level block node or embedded in a
/// block node.
///
/// If [composeImplicitMap] is `true` and the flow collection was inline then
/// a block map may be composed.
BlockNode<Obj> parseFlowNodeInBlock<Obj>(
  ParserState<Obj> state, {
  required FlowCollectionEvent event,
  required int indentLevel,
  required int indent,
  required bool isInline,
  required bool composeImplicitMap,
  required int composedMapIndent,
  required ParsedProperty flowProperty,
  ObjectFromIterable<Obj, Obj>? asCustomList,
  ObjectFromMap<Obj, Obj, Obj>? asCustomMap,
}) {
  // All flow events must be start of flow map or sequence
  final flow = switch (event) {
    FlowCollectionEvent.startFlowMap => parseFlowMap(
      state,
      indentLevel: indentLevel,
      minIndent: indent,
      forceInline: isInline,
      asCustomMap: asCustomMap,
    ),
    FlowCollectionEvent.startFlowSequence => parseFlowSequence(
      state,
      indentLevel: indentLevel,
      minIndent: indent,
      forceInline: isInline,
      asCustomList: asCustomList,
    ),
    _ => throwWithRangedOffset(
      state.iterator,
      message: 'Invalid flow node state. Expected "{" or "]"',
      start: flowProperty.span.start,
      end: state.iterator.currentLineInfo.current,
    ),
  };

  // TODO: isRoot
  final indentOfNextNode = skipToParsableChar(
    state.iterator,
    onParseComment: state.onParseComment,
  );

  // Some flow collections can be used as keys like scalars.
  return composeBlockMapFromScalar(
    state,
    keyOrNode: flow,
    keyOrMapProperty: flowProperty,
    indentOnExit: indentOfNextNode,
    documentMarker: DocumentMarker.none,
    keyIsBlock: false,
    composeImplicitMap: composeImplicitMap && indentOfNextNode == null,
    composedMapIndent: composedMapIndent,
  );
}

/// Parses a block scalar based on the current scalar [event] and optionally
/// composes a block if [composeImplicitMap] is `true` and the `Scalar` is a
/// flow scalar.
BlockNode<Obj> parseBlockScalar<Obj>(
  ParserState<Obj> state, {
  required ScalarEvent event,
  required int minIndent,
  required int indentLevel,
  required int? blockParentIndent,
  required bool isImplicit,
  required ParsedProperty? scalarProperty,
  required bool composeImplicitMap,
  required int composedMapIndent,
  DelegatedValue? delegateScalar,
  String greedyOnPlain = '',
  RuneOffset? start,
}) {
  final defaultToString =
      delegateScalar == null &&
      (!composeImplicitMap || !(scalarProperty?.isMultiline ?? true)) &&
      isGenericNode(scalarProperty);

  final defaultScalar = state.defaultScalar();

  final (delegate, indentOnExit, docMarker, indentDidChange) = parseScalar(
    event,
    iterator: state.iterator,
    onDefault: defaultScalar?.onCustomScalar,
    afterScalar: defaultScalar?.afterObject<Obj>(),
    scalarFunction: state.scalarFunction,
    onParseComment: state.onParseComment,
    isImplicit: isImplicit,
    isInFlowContext: false,
    indentLevel: indentLevel,
    minIndent: minIndent,
    blockParentIndent: blockParentIndent,
    greedyOnPlain: greedyOnPlain,
    start: start,
    delegateScalar: delegateScalar,
    defaultToString: defaultToString,
    onScalar: (_, indentOnExit, indentDidChange, marker, scalar) =>
        (scalar, indentOnExit, marker, indentDidChange),
  );

  return composeBlockMapFromScalar(
    state,
    keyOrNode: delegate,
    keyOrMapProperty: scalarProperty,
    indentOnExit: indentOnExit,
    documentMarker: docMarker,

    // Plain scalar behaved like a block scalar if indent changed.
    keyIsBlock: !event.isFlowContext || indentDidChange,
    composeImplicitMap: composeImplicitMap,
    composedMapIndent: composedMapIndent,
  );
}
