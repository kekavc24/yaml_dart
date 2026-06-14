import 'dart:math';

import 'package:rookie_yaml/src/parser/document/block_nodes/block_map.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_sequence.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/forced_block_map.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/custom_node.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/scalars/scalars.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Throws if an explicit key or block sequence are forced to be inline or their
/// properties are on the same line the "?" or "-" respectively.
///
/// A leading explicit key signifies the start of a block map.
void throwIfInlineInBlock(
  SourceIterator iterator, {
  required bool isInline,
  required ParsedProperty property,
  required RuneOffset currentOffset,
  required String identifier,
}) {
  if (isInline || (property.parsedAny && !property.isMultiline)) {
    throwWithRangedOffset(
      iterator,
      message:
          '$identifier cannot be forced to be implicit or have inline '
          'properties before its indicator',
      start: property.span.start,
      end: currentOffset,
    );
  }
}

void _throwIfInlineExplicitKey(
  SourceIterator iterator, {
  required bool isInline,
  required ParsedProperty property,
}) => throwIfInlineInBlock(
  iterator,
  isInline: isInline,
  property: property,
  currentOffset: iterator.currentLineInfo.current,
  identifier: 'An explicit key',
);

void _inlineIfInlineBlockSequence(
  SourceIterator iterator, {
  required bool isInline,
  required ParsedProperty property,
}) => throwIfInlineInBlock(
  iterator,
  isInline: isInline,
  property: property,
  currentOffset: iterator.currentLineInfo.current,
  identifier: 'A block sequence',
);

/// Adjusts the indent of a block node based on the [inferredIndentFromParent]
/// while considering the current step indent obtained from the
/// [propertyExitIndent].
({int adjustedLaxIndent, int adjustedInlineIndent}) _adjustBlockIndent(
  SourceIterator iterator, {
  required RuneOffset propertyStartOffset,
  required int? inferredIndentFromParent,
  required int? propertyExitIndent,
  required int laxBlockIndent,
  required int fixedInlineIndent,
}) {
  final (
    hasParentIndent,
    adjustedLax,
    adjustedFixedInline,
  ) = switch (inferredIndentFromParent) {
    int forced => (true, forced, forced),
    _ => (false, laxBlockIndent, fixedInlineIndent),
  };

  // Indent remains unchanged. The properties were inline.
  //
  // - &anchor node
  //
  // OR
  //
  // ? &anchor !tag node
  //
  if (propertyExitIndent == null) {
    return (
      adjustedLaxIndent: adjustedLax,
      adjustedInlineIndent: adjustedFixedInline,
    );
  }

  // Always called when indent is equal to or greater than the lax indent. Lax
  // indent is just the normal "parentIndent + 1" in most cases. In block
  // nodes, the properties must be indented more than the node if the node is
  // declared on a new line. Here we check the fixed inline indent for:
  //
  // # Okay
  // -   !!seq
  //   - node
  //
  // # Okay
  // - !!seq
  //   - node
  //
  // # Invalid. Cannot be more indented!
  // ?
  //   !!seq
  //      - node
  //
  // # Invalid
  // -
  //   !!seq
  //     - node
  //
  //
  // See Block Nodes: https://yaml.org/spec/1.2.2/#823-block-nodes
  //   - Example "8.20 Node Types"
  if (hasParentIndent && propertyExitIndent > adjustedFixedInline) {
    throwWithRangedOffset(
      iterator,
      message: 'A block node cannot be indented more that its properties',
      start: propertyStartOffset,
      end: iterator.currentLineInfo.current,
    );
  }

  // If [true] applies to:
  //
  // -
  //     !!seq
  //     - node
  //
  // OR
  //
  // key:
  //     !!map
  //     nested: value
  //
  // Otherwise, find minimum because the property was multiline but the parent
  // assumed it was inline!
  //
  // -               !i-am-here # Too indented
  //    - psych!
  //
  // OR
  //
  // key: !i-am-here
  //    - psych!
  //
  final defaultIndent = adjustedLax == adjustedFixedInline
      ? propertyExitIndent
      : min(adjustedFixedInline, propertyExitIndent);

  return (
    adjustedLaxIndent: defaultIndent,
    adjustedInlineIndent: defaultIndent,
  );
}

/// Checks and ensures the [parsed] block node leaves the parser in a state
/// where the next block node can be deduced or parsed easily.
BlockNode<Obj> _safeBlockState<Obj>(
  ParserState<Obj> state, {
  required BlockNode<Obj> parsed,
}) {
  final ParserState(:iterator) = state;
  final (:blockInfo, :node) = parsed;

  if (!iterator.isEOF &&
      !blockInfo.docMarker.stopIfParsingDoc &&
      (blockInfo.exitIndent == seamlessIndentMarker ||
          iterator.current.matches((i) => i.isWhiteSpace() || i == comment))) {
    final indent = skipToParsableChar(
      iterator,
      onParseComment: state.onParseComment,
      allowTabs: (currentIndent, hasTabs) => currentIndent == null && !hasTabs,
    );

    return (
      blockInfo: (docMarker: blockInfo.docMarker, exitIndent: indent),
      node: nodeParseEnd(node, iterator),
    );
  }

  return parsed;
}

/// Parses a block node using the current parser [state].
///
/// This function will attempt to compose block map from the current node
/// if [composeImplicitMap] is `true` or [canComposeMapIfMultiline] is `true`
/// and the node's properties were multiline.
///
/// [inferredFromParent] represents the indent suggested by the parent for
/// the current block node while [laxBlockIndent] represents the `(block
/// parent's indent + 1)`.
///
/// [fixedInlineIndent] is usually equal to [laxBlockIndent] unless the parent
/// is a block sequence or an explicit key/value. In this case, then, this
/// represents the indent for this inline block where:
///
/// [fixedInlineIndent] =  ([laxBlockIndent] - 1) +  `m`
///   where `m` is the number of characters after the "-", "?" or ":"
///   (inclusive).
BlockNode<Obj> parseBlockNode<Obj>(
  ParserState<Obj> state, {
  required int? blockParentIndent,
  required int indentLevel,
  required int? inferredFromParent,
  required int laxBlockIndent,
  required int fixedInlineIndent,
  required bool forceInlined,
  required bool composeImplicitMap,
  bool canComposeMapIfMultiline = false,
  RuneOffset? structuralOffset,
}) {
  final ParserState(:iterator) = state;

  final (:event, :property) = parseBlockProperties(
    iterator,
    minIndent: laxBlockIndent,
    resolver: state.resolveTag,
    onParseComment: state.onParseComment,
    structuralOffset: structuralOffset,
  );

  // Exit immediately if we see an indent less than than the min required
  if (property.indentOnExit case int indent when indent < laxBlockIndent) {
    return (
      blockInfo: (exitIndent: indent, docMarker: DocumentMarker.none),
      node: emptyBlockNode(
        state,
        property: property,
        indentLevel: indentLevel,
        indent: laxBlockIndent,
        start: iterator.currentLineInfo.start,
      ),
    );
  } else if (iterator.isEOF) {
    return (
      blockInfo: emptyScanner,
      node: emptyBlockNode(
        state,
        property: property,
        indentLevel: indentLevel,
        indent: laxBlockIndent,
        start: iterator.currentLineInfo.current,
      ),
    );
  } else if (forceInlined && property.isMultiline) {
    throwWithRangedOffset(
      iterator,
      message: 'Implicit block nodes cannot span multiple lines',
      start: property.span.start,
      end: iterator.currentLineInfo.current,
    );
  }

  final (:adjustedLaxIndent, :adjustedInlineIndent) = _adjustBlockIndent(
    iterator,
    inferredIndentFromParent: inferredFromParent,
    propertyStartOffset: property.span.start,
    propertyExitIndent: property.indentOnExit,
    laxBlockIndent: laxBlockIndent,
    fixedInlineIndent: fixedInlineIndent,
  );

  // Quirky? I know. However, since we are using a lexer-less parser, we may
  // inadventently punish multiline implicit values. An inline implicit value
  // to an implicit key cannot degenerate to a block map. However, a multiline
  // one can.
  //
  // [*] Cannot degenerate
  //
  // key: value
  //
  // [*] Can actually degenerate
  //
  // key: !!map
  //   value: degenerate
  //
  // See [parseImplicitValue]
  final definitelyComposeMap =
      composeImplicitMap || canComposeMapIfMultiline && property.isMultiline;

  if (property.parsedAny) {
    /// When parsing properties, block nodes exit immediately after a duplicate
    /// property is seen only if it was declared on a new line. Check if the
    /// node can degenerate to an implicit map.
    if (event is NodePropertyEvent) {
      if (!definitelyComposeMap || property.isAlias) {
        throwWithRangedOffset(
          iterator,
          message:
              'Invalid block node state. Duplicate properties implied the'
              ' start of a block map but a block map cannot be composed in the'
              ' current state',
          start: property.span.start,
          end: iterator.currentLineInfo.current,
        );
      }

      return _safeBlockState(
        state,
        parsed: composeBlockMapStrict(
          state,
          event: event,
          indentLevel: indentLevel,
          laxIndent: adjustedLaxIndent,
          inlineFixedIndent: adjustedInlineIndent,
          property: property as NodeProperty,
          isInline: forceInlined,
          composeImplicitMap: definitelyComposeMap,
        ),
      );
    }

    // Just parse by kind
    switch (property) {
      case Alias alias:
        {
          return _safeBlockState(
            state,
            parsed: composeBlockMapFromScalar(
              state,
              keyOrNode: emptyBlockNode(
                state,
                property: alias,
                indentLevel: indentLevel,
                indent: laxBlockIndent,
                start: alias.span.end,
              ),
              keyOrMapProperty: null,
              indentOnExit: alias.indentOnExit,
              documentMarker: DocumentMarker.none,
              keyIsBlock: property.isMultiline,
              composeImplicitMap: definitelyComposeMap,
              composedMapIndent: adjustedInlineIndent,
            ),
          );
        }

      default:
        {
          if ((property as NodeProperty).kind.isKnown) {
            return _safeBlockState(
              state,
              parsed: _blockNodeOfKind(
                property.kind,
                state: state,
                event: event,
                property: property,
                blockParentIndent: blockParentIndent,
                indentLevel: indentLevel,
                laxBlockIndent: adjustedLaxIndent,
                fixedInlineIndent: adjustedInlineIndent,
                forceInlined: forceInlined,
                composeImplicitMap: definitelyComposeMap,
              ),
            );
          }
        }
    }
  }

  return _safeBlockState(
    state,
    parsed: _ambigousBlockNode(
      event,
      parserState: state,
      property: property,
      blockParentIndent: blockParentIndent,
      indentLevel: indentLevel,
      laxBlockIndent: adjustedLaxIndent,
      fixedInlineIndent: adjustedInlineIndent,
      forceInlined: forceInlined,
      composeImplicitMap: definitelyComposeMap,
    ),
  );
}

/// Parses a block node that strictly matches the specified [kind] using the
/// current parser [state] and uses the current [event] to enforce this.
///
/// Throws if [kind] is [NodeKind.unknown]. Prefer calling [_ambigousBlockNode]
/// instead.
BlockNode<Obj> _blockNodeOfKind<Obj>(
  NodeKind kind, {
  required ParserState<Obj> state,
  required ParserEvent event,
  required NodeProperty property,
  required int? blockParentIndent,
  required int indentLevel,
  required int laxBlockIndent,
  required int fixedInlineIndent,
  required bool forceInlined,
  required bool composeImplicitMap,
}) {
  if (kind is CustomKind) {
    return customBlockNode(
      kind,
      state: state,
      event: event,
      property: property,
      blockParentIndent: blockParentIndent,
      indentLevel: indentLevel,
      laxBlockIndent: laxBlockIndent,
      fixedInlineIndent: fixedInlineIndent,
      forceInlined: forceInlined,
      composeImplicitMap: composeImplicitMap,
      expectBlockMap: false,
    );
  }

  return parseNodeOfKind(
    kind,
    sequenceOnMatchSetOrOrderedMap: () =>
        event == BlockCollectionEvent.startBlockListEntry ||
        event == FlowCollectionEvent.startFlowSequence,
    onMatchMapping: () {
      if (event == BlockCollectionEvent.startExplicitKey) {
        _throwIfInlineExplicitKey(
          state.iterator,
          isInline: forceInlined,
          property: property,
        );
      }

      // Parse wildcard but expect a map
      return composeBlockMapStrict(
        state,
        event: event,
        indentLevel: indentLevel,
        laxIndent: laxBlockIndent,
        inlineFixedIndent: fixedInlineIndent,
        property: property,
        isInline: forceInlined,
        composeImplicitMap: composeImplicitMap,
      );
    },
    onMatchSequence: () {
      BlockNode<Obj>? sequence;

      if (event == BlockCollectionEvent.startBlockListEntry) {
        _inlineIfInlineBlockSequence(
          state.iterator,
          isInline: forceInlined,
          property: property,
        );

        sequence = parseBlockSequence(
          state.defaultSequenceDelegate(
            kind: kind,
            style: NodeStyle.block,
            indent: fixedInlineIndent,
            indentLevel: indentLevel,
            start: state.iterator.currentLineInfo.current,
          ),
          state: state,
          levelWithBlockMap: false,
        ).sequence;

        state.trackAnchor(sequence.node, property);
      } else if (event == FlowCollectionEvent.startFlowSequence) {
        sequence = parseFlowNodeInBlock(
          state,
          event: event as FlowCollectionEvent,
          indentLevel: indentLevel,
          indent: laxBlockIndent,
          isInline: forceInlined,
          composeImplicitMap: composeImplicitMap,
          flowProperty: property,
          composedMapIndent: fixedInlineIndent,
        );
      }

      // We must have a block sequence
      if (sequence == null) {
        throwWithRangedOffset(
          state.iterator,
          message: 'Expected the start of a block/flow sequence',
          start: property.span.start,
          end: state.iterator.currentLineInfo.current,
        );
      }

      return sequence;
    },
    onMatchScalar: (scalarKind) {
      if (event case ScalarEvent() || BlockCollectionEvent.startEntryValue) {
        return parseBlockWildCard(
          state,
          event: event,
          blockParentIndent: blockParentIndent,
          indentLevel: indentLevel,
          laxIndent: laxBlockIndent,
          inlineFixedIndent: fixedInlineIndent,
          property: property,
          isInline: forceInlined,
          composeImplicitMap: composeImplicitMap,
          delegateScalar: scalarImpls(scalarKind),
        );
      }

      throwWithRangedOffset(
        state.iterator,
        message: 'Expected the start of a valid scalar',
        start: property.span.start,
        end: state.iterator.currentLineInfo.current,
      );
    },
    defaultFallback: () => _ambigousBlockNode(
      event,
      parserState: state,
      property: property,
      blockParentIndent: blockParentIndent,
      indentLevel: indentLevel,
      laxBlockIndent: laxBlockIndent,
      fixedInlineIndent: fixedInlineIndent,
      forceInlined: forceInlined,
      composeImplicitMap: composeImplicitMap,
    ),
  );
}

/// Parses a block node using the current [parserState] and heavily relies on
/// the current [event] to determine the next course of action.
BlockNode<Obj> _ambigousBlockNode<Obj>(
  ParserEvent event, {
  required ParserState<Obj> parserState,
  required ParsedProperty property,
  required int? blockParentIndent,
  required int indentLevel,
  required int laxBlockIndent,
  required int fixedInlineIndent,
  required bool forceInlined,
  required bool composeImplicitMap,
}) {
  final ParserState(:iterator) = parserState;

  switch (event) {
    case BlockCollectionEvent.startExplicitKey:
      {
        _throwIfInlineExplicitKey(
          iterator,
          isInline: forceInlined,
          property: property,
        );

        final map = parseBlockMap(
          parserState.defaultMapDelegate(
            mapStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            start: iterator.currentLineInfo.current,
          ),
          state: parserState,
        );

        parserState.trackAnchor(map.node, property);
        return map;
      }

    case BlockCollectionEvent.startBlockListEntry:
      {
        _inlineIfInlineBlockSequence(
          iterator,
          isInline: forceInlined,
          property: property,
        );

        final sequence = parseBlockSequence(
          parserState.defaultSequenceDelegate(
            style: NodeStyle.block,
            indent: fixedInlineIndent,
            indentLevel: indentLevel,
            start: iterator.currentLineInfo.current,
          ),
          state: parserState,
          levelWithBlockMap: false,
        ).sequence;

        parserState.trackAnchor(sequence.node, property);
        return sequence;
      }

    default:
      {
        /// Just parse as a wildcard. Most block nodes always degenerate to
        /// block maps if they are not explicit keys/block lists if certain
        /// conditions are met.
        return parseBlockWildCard(
          parserState,
          event: event,
          blockParentIndent: blockParentIndent,
          indentLevel: indentLevel,
          laxIndent: laxBlockIndent,
          inlineFixedIndent: fixedInlineIndent,
          property: property,
          isInline: forceInlined,
          composeImplicitMap: composeImplicitMap,
        );
      }
  }
}
