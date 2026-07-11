import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_sequence.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/implicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Information after a special block sequence has been parsed.
///
/// See [composeSpecialBlockSequence] and [parseSpecialBlockSequence].
typedef SpecialBlockSequenceInfo = ({
  bool parsedNextImplicitKey,
  BlockInfo blockInfo,
});

typedef _CheckedSpecial<Obj> = (
  SequenceLikeDelegate<Obj, Obj>? node,
  ParsedProperty? propery,
);

_CheckedSpecial<Obj>? _checkIfSpecial<Obj>(NodeDelegate<Obj> node) {
  return switch (node) {
    EfficientScalarDelegate(isNullDelegate: true) => (null, node.property),
    SequenceLikeDelegate<Obj, Obj>() => (node, null),
    _ => null,
  };
}

/// Attempts to parse a block sequence on the same indent level as its implicit
/// key or explicit key/value.
///
/// ```yaml
/// ?
/// - explicit key
/// :
/// - explicit value
/// ```
///
/// OR
///
/// ```yaml
/// implicit key:
/// - value
/// ```
///
/// If the sequence is parsed, [onSequenceOrBlockNode] will be called.
/// [onNextImplicitEntry] will be called after the next implicit entry has been
/// parsed. In this case, the block sequence must have exited after encountering
/// "directive end"-ish characters.
///
/// ```yaml
/// key:
/// - sequence
///
/// # These are implicit keys
/// -- key: value
/// ---another: key
/// ```
SpecialBlockSequenceInfo composeSpecialBlockSequence<Obj>(
  ParserState<Obj> state, {
  required BlockNode<Obj> blockNode,
  required int keyIndent,
  required int keyIndentLevel,
  required void Function(NodeDelegate<Obj> sequence) onSequenceOrBlockNode,
  required OnBlockMapEntry<Obj> onNextImplicitEntry,
}) {
  final (:blockInfo, :node) = blockNode;

  if (_checkIfSpecial<Obj>(node) case final checked?
      when !state.iterator.isEOF &&
          !blockInfo.docMarker.stopIfParsingDoc &&
          blockInfo.exitIndent == keyIndent &&
          inferBlockEvent(state.iterator) ==
              BlockCollectionEvent.startBlockListEntry) {
    return parseSpecialBlockSequence(
      state,
      keyIndent: keyIndent,
      keyIndentLevel: keyIndentLevel,
      delegate: checked.$1
        ?..indent = keyIndent
        ..indentLevel = keyIndentLevel,
      property: checked.$2,
      onSequence: onSequenceOrBlockNode,
      onNextImplicitEntry: onNextImplicitEntry,
    );
  }

  onSequenceOrBlockNode(node);
  return (parsedNextImplicitKey: false, blockInfo: blockInfo);
}

/// Parses a block sequence on the same indent level as its implicit key or
/// explicit key/value.
///
/// ```yaml
/// ?
/// - explicit key
/// :
/// - explicit value
/// ```
///
/// OR
///
/// ```yaml
/// implicit key:
/// - value
/// ```
///
/// If the sequence is parsed, [onSequence] will be called.
/// [onNextImplicitEntry] will be called after the next implicit entry has been
/// parsed. In this case, the block sequence must have exited after encountering
/// "directive end"-ish characters.
///
/// ```yaml
/// key:
/// - sequence
///
/// # These are implicit keys
/// -- key: value
/// ---another: key
/// ```
SpecialBlockSequenceInfo parseSpecialBlockSequence<Obj>(
  ParserState<Obj> state, {
  required int keyIndent,
  required int keyIndentLevel,
  required void Function(NodeDelegate<Obj> sequence) onSequence,
  required OnBlockMapEntry<Obj> onNextImplicitEntry,
  RuneOffset? structuralStart,
  SequenceLikeDelegate<Obj, Obj>? delegate,
  ParsedProperty? property,
}) {
  final (:greedyOnPlain, :sequence) = parseBlockSequence(
    delegate ??
        state.defaultSequenceDelegate(
          style: NodeStyle.block,
          indent: keyIndent,
          indentLevel: keyIndentLevel,
          start: state.iterator.currentLineInfo.current,
          kind: property?.kind ?? YamlCollectionKind.sequence,
        ),
    state: state,
    levelWithBlockMap: true,
  );

  onSequence(sequence.node);

  // We are not eating into the next implicit plain key with "--"
  if (greedyOnPlain == null || greedyOnPlain.isEmpty) {
    return (parsedNextImplicitKey: false, blockInfo: sequence.blockInfo);
  }

  // Recover the next key we consumed.
  final (blockInfo: keyInfo, node: implicitKey) = parseBlockScalar(
    state,
    event: ScalarEvent.startFlowPlain,
    blockParentIndent: null,
    minIndent: keyIndent,
    indentLevel: keyIndentLevel,
    isImplicit: true,
    scalarProperty: null,
    composeImplicitMap: false,
    composedMapIndent: -1,
    greedyOnPlain: greedyOnPlain,
  );

  return (
    parsedNextImplicitKey: true,
    blockInfo: parseImplicitValue(
      state,
      keyIndentLevel: keyIndentLevel,
      keyIndent: keyIndent,
      onValue: (implicitValue) =>
          onNextImplicitEntry(implicitKey, implicitValue),
      onEntryValue: onNextImplicitEntry,
    ),
  );
}
