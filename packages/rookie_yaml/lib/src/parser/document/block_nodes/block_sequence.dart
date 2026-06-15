import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/scalars/scalars.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

typedef _SequenceState = ({
  bool parentCanRecover,
  String? greedyPlain,
  DocumentMarker? marker,
});

/// Checks if the next block sequence entry is a valid entry or just a
/// directive end marker. Returns `null` if the next entry is a valid block
/// node. Otherwise, throws if the next node is not a
/// [DocumentMarker.directiveEnd].
_SequenceState _sequenceNodeOrMarker(
  SourceIterator iterator, {
  required int indent,
  required bool isLevelWithParent,
}) {
  Never notSequence() => throwForCurrentLine(
    iterator,
    message: 'Expected a "- " at the start of the next entry',
    end: iterator.currentLineInfo.current,
  );

  final current = iterator.current;
  final next = iterator.peekNextChar();

  switch (current) {
    // Be gracious and check if we have doc end chars here
    case blockSequenceEntry || period when indent == 0 && next == current:
      {
        final buffer = StringBuffer();
        final marker = checkForDocumentMarkers(
          iterator,
          onMissing: null,
          writer: buffer.writeCharCode,
        );

        if (marker.stopIfParsingDoc) {
          return (parentCanRecover: false, greedyPlain: null, marker: marker);
        } else if (isLevelWithParent) {
          return (
            parentCanRecover: true,
            greedyPlain: buffer.toString(),
            marker: null,
          );
        }

        notSequence();
      }

    case blockSequenceEntry
        when next.isNullOr((c) => c.isWhiteSpace() || c.isLineBreak()):
      return (parentCanRecover: false, greedyPlain: null, marker: null);

    default:
      {
        if (isLevelWithParent) {
          return (parentCanRecover: true, greedyPlain: null, marker: null);
        }

        notSequence();
      }
  }
}

/// Parses a block sequence.
///
/// If [levelWithBlockMap] is `true`, the block sequence will not throw but
/// allows the nearest block parent to recover from the current parser state.
/// This ensures a block sequence on the same indent level as an implicit key or
/// explicit key/value will be parsed correctly.
({String? greedyOnPlain, BlockNode<Obj> sequence}) parseBlockSequence<Obj>(
  SequenceLikeDelegate<Obj, Obj> sequence, {
  required ParserState<Obj> state,
  required bool levelWithBlockMap,
}) {
  final ParserState(:iterator, :onParseComment) = state;
  final SequenceLikeDelegate(indent: sequenceIndent, :indentLevel) = sequence;

  final entryIndent = sequenceIndent + 1;

  do {
    final indicatorOffset = iterator.currentLineInfo.current;
    iterator.nextChar();

    // Be mechanical. Call [parseBlockNode] only after we determine the correct
    // indent range for this node.
    final (:indentOrSeparation, :composeMap) = skipToElementStart(
      iterator,
      onParseComment: onParseComment,
      structuralOffset: indicatorOffset,
    );

    final isNextLevel = indentOrSeparation != null;

    if (isNextLevel && indentOrSeparation <= sequenceIndent) {
      final empty = nullBlockNode(
        state,
        indentLevel: indentLevel,
        indent: sequenceIndent + 1,
        start: iterator.isEOF
            ? iterator.currentLineInfo.current
            : iterator.currentLineInfo.start,
      );

      delegateWithOptimalEnd(sequence..accept(empty.parsed()), empty.nodeSpan);
      if (iterator.isEOF || indentOrSeparation < sequenceIndent) {
        return (
          greedyOnPlain: null,
          sequence: (
            blockInfo: (
              docMarker: DocumentMarker.none,
              exitIndent: indentOrSeparation,
            ),
            node: blockEnd(sequence),
          ),
        );
      }
    } else {
      final (:laxIndent, :inlineFixedIndent) = indentOfBlockChild(
        indentOrSeparation,
        blockParentIndent: sequenceIndent,
        yamlNodeStartOffset: indicatorOffset.offset,
        contentOffset: iterator.currentLineInfo.current.offset,
      );

      final (:blockInfo, :node) = parseBlockNode(
        state,
        blockParentIndent: sequenceIndent,
        indentLevel: isNextLevel ? indentLevel + 1 : indentLevel,
        inferredFromParent: indentOrSeparation,
        laxBlockIndent: entryIndent,
        fixedInlineIndent: inlineFixedIndent,
        forceInlined: false,
        composeImplicitMap: composeMap,
        canComposeMapIfMultiline: true,
        structuralOffset: indicatorOffset,
      );

      if (exitBlockCollection(
        delegateWithOptimalEnd(sequence..accept(node.parsed()), node.nodeSpan),
        iterator: iterator,
        nodeIndent: sequenceIndent,
        marker: blockInfo.docMarker,
        exitIndent: blockInfo.exitIndent,
      )) {
        return (
          greedyOnPlain: null,
          sequence: (blockInfo: blockInfo, node: blockEnd(sequence)),
        );
      }
    }

    // Check if the current state can parse a sequence further
    final (:parentCanRecover, :marker, :greedyPlain) = _sequenceNodeOrMarker(
      iterator,
      indent: sequenceIndent,
      isLevelWithParent: levelWithBlockMap,
    );

    if (parentCanRecover) {
      return (
        greedyOnPlain: greedyPlain,
        sequence: (
          blockInfo: (
            docMarker: DocumentMarker.none,
            exitIndent: sequenceIndent,
          ),
          node: blockEnd(sequence),
        ),
      );
    } else if (marker != null) {
      // In case we see "---" or "..." before the next node
      return (
        greedyOnPlain: null,
        sequence: (
          blockInfo: (docMarker: marker, exitIndent: null),
          node: blockEnd(sequence),
        ),
      );
    }
  } while (!iterator.isEOF);

  return (
    greedyOnPlain: null,
    sequence: (blockInfo: emptyScanner, node: blockEnd(sequence)),
  );
}
