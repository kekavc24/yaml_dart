import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map_entry.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_sequence.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/custom_node.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/scalars/scalars.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

/// Parses a flow scalar based on the current scalar [event].
ScalarLikeDelegate<R> parseFlowScalar<R>(
  ScalarEvent event, {
  required SourceIterator iterator,
  required ObjectFromScalarBytes<R>? onDefault,
  required ScalarFunction<R> scalarFunction,
  required void Function(YamlComment comment) onParseComment,
  required bool isInline,
  required int indentLevel,
  required int minIndent,
  bool defaultToString = false,
  DelegatedValue? delegateScalar,
}) => parseScalar(
  event,
  iterator: iterator,
  onDefault: onDefault?.onCustomScalar,
  afterScalar: onDefault?.afterObject<R>(),
  scalarFunction: scalarFunction,
  onParseComment: onParseComment,
  isImplicit: isInline,
  isInFlowContext: true,
  indentLevel: indentLevel,
  minIndent: minIndent,
  blockParentIndent: null,
  delegateScalar: delegateScalar,
  defaultToString: defaultToString,
  onScalar: (style, indentOnExit, indentDidChange, marker, scalar) {
    throwIfInvalidFlow(
      style,
      iterator: iterator,
      isInline: isInline,
      marker: marker,
      flowIndent: minIndent,
      indentDidChange: indentDidChange,
      indentOnExit: indentOnExit,
    );

    return scalar;
  },
);

/// Parses a flow node using the current parser [state].
///
/// If [isImplicit] or [forceInline] is `true` then the flow node will be
/// forced to be inline.
///
/// [minIndent] represents the minimum indent the flow node needs to adhere to
/// when embedded in a block node. Indent, by default, is moot in flow nodes.
NodeDelegate<Obj> parseFlowNode<Obj>(
  ParserState<Obj> state, {
  required int currentIndentLevel,
  required int minIndent,
  required bool forceInline,
  required int collectionDelimiter,
  bool lastKeyWasJsonLike = false,
  RuneOffset? structuralOffset,
}) {
  final ParserState(:iterator) = state;

  final (:event, :property) = parseFlowProperties(
    iterator,
    minIndent: minIndent,
    resolver: state.resolveTag,
    onParseComment: state.onParseComment,
    lastKeyWasJsonLike: lastKeyWasJsonLike,
    structuralOffset: structuralOffset,
  );

  if (!event.isFlowContext) {
    throwWithSingleOffset(
      iterator,
      message: 'Block nodes are not allowed in flow collections',
      offset: iterator.currentLineInfo.current,
    );
  } else if (property.parsedAny) {
    if (property.isMultiline &&
        forceInline &&
        (!iterator.isEOF &&
            iterator.current != collectionDelimiter &&
            iterator.current != flowEntryEnd)) {
      throwWithRangedOffset(
        iterator,
        message: 'Flow node cannot span multiple lines when implicit',
        start: property.span.start,
        end: iterator.currentLineInfo.current,
      );
    }

    switch (property) {
      case Alias alias:
        {
          return state.referenceAlias(
            alias,
            indentLevel: currentIndentLevel,
            indent: minIndent,
          )..updateNodeProperties = alias;
        }

      default:
        return state.trackAnchor(
          _flowNodeOfKind(
            property.kind,
            parserState: state,
            property: property as NodeProperty,
            flowEvent: event,
            currentIndentLevel: currentIndentLevel,
            minIndent: minIndent,
            forceInline: forceInline,
          ),
          property,
        );
    }
  }

  return state.trackAnchor(
    _ambigousFlowNode(
      event,
      parserState: state,
      property: property,
      currentIndentLevel: currentIndentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    ),
    property,
  );
}

/// Parses a flow node that strictly matches the specified [kind].
///
/// Throws if [kind] is [NodeKind.unknown]. Prefer calling [_ambigousFlowNode]
/// instead.
NodeDelegate<Obj> _flowNodeOfKind<Obj>(
  NodeKind kind, {
  required ParserState<Obj> parserState,
  required NodeProperty property,
  required ParserEvent flowEvent,
  required int currentIndentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  final (:start, :end) = property.span; // Always use property offset

  if (kind is CustomKind) {
    return customFlowNode(
      kind,
      state: parserState,
      property: property,
      flowEvent: flowEvent,
      currentIndentLevel: currentIndentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    );
  }

  return parseNodeOfKind(
    kind,
    sequenceOnMatchSetOrOrderedMap: () =>
        flowEvent == FlowCollectionEvent.startFlowSequence,
    onMatchMapping: () => parseFlowMap(
      parserState,
      indentLevel: currentIndentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    ),
    onMatchSequence: () => parseFlowSequence(
      parserState,
      indentLevel: currentIndentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
      kind: kind,
    ),
    onMatchScalar: (scalarKind) {
      return switch (flowEvent) {
        ScalarEvent e => parseFlowScalar(
          e,
          iterator: parserState.iterator,
          onDefault: parserState.defaultScalar(),
          scalarFunction: parserState.scalarFunction,
          onParseComment: parserState.onParseComment,
          isInline: forceInline,
          indentLevel: currentIndentLevel,
          minIndent: minIndent,
          delegateScalar: scalarImpls(scalarKind),
        ),
        _ => nullScalarDelegate(
          indentLevel: currentIndentLevel,
          indent: minIndent,
          startOffset: start,
          resolver: parserState.scalarFunction,
        )..nodeSpan.nodeEnd = end,
      };
    },
    defaultFallback: () => _ambigousFlowNode(
      flowEvent,
      parserState: parserState,
      property: property,
      currentIndentLevel: currentIndentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    ),
  );
}

/// Parses a flow node using the current [parserState] and heavily relies on
/// the current [event] to determine the next course of action.
NodeDelegate<Obj> _ambigousFlowNode<Obj>(
  ParserEvent event, {
  required ParserState<Obj> parserState,
  required ParsedProperty property,
  required int currentIndentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  switch (event) {
    case FlowCollectionEvent.startExplicitKey:
      {
        // Explicit keys cannot have leading properties
        if (property.parsedAny) {
          final iterator = parserState.iterator;
          throwWithRangedOffset(
            iterator,
            message: 'An explicit compact flow entry cannot have properties',
            start: property.span.start,
            end: iterator.currentLineInfo.current,
          );
        }

        return parseExplicitAsFlowMap(
          parserState,
          indentLevel: currentIndentLevel,
          minIndent: minIndent,
          forceInline: forceInline,
        );
      }

    case FlowCollectionEvent.startFlowMap:
      {
        return parseFlowMap(
          parserState,
          indentLevel: currentIndentLevel,
          minIndent: minIndent,
          forceInline: forceInline,
        );
      }

    case ScalarEvent scalarEvent:
      {
        return parseFlowScalar(
          scalarEvent,
          iterator: parserState.iterator,
          onDefault: parserState.defaultScalar(),
          scalarFunction: parserState.scalarFunction,
          onParseComment: parserState.onParseComment,
          isInline: forceInline,
          indentLevel: currentIndentLevel,
          minIndent: minIndent,
          defaultToString: isGenericNode(property),
        );
      }

    case FlowCollectionEvent.startFlowSequence:
      {
        return parseFlowSequence(
          parserState,
          indentLevel: currentIndentLevel,
          minIndent: minIndent,
          forceInline: forceInline,
        );
      }

    default:
      {
        return nullScalarDelegate(
          indentLevel: currentIndentLevel,
          indent: minIndent,
          startOffset: property.span.start,
          resolver: parserState.scalarFunction,
        )..nodeSpan.nodeEnd = parserState.iterator.currentLineInfo.current;
      }
  }
}
