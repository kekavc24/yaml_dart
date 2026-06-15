import 'package:rookie_yaml/src/parser/delegates/one_pass_scalars/efficient_scalar_delegate.dart';
import 'package:rookie_yaml/src/parser/document/scalars/flow/flow_scalar_utils.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Characters that must not be parsed as the first character in a plain scalar.
final _mustNotBeFirst = <int>{
  mappingKey,
  mappingValue,
  blockSequenceEntry,
};

/// Characters that disrupt normal buffering of characters in a plain scalar.
final _delimiters = <int>{
  lineFeed,
  carriageReturn,
  space,
  tab,
  mappingValue,
  comment,
};

/// Parses a scalar with [ScalarStyle.plain].
///
/// This is the parser's low level implementation for parsing a double quoted
/// scalar which returns a [PreScalar]. This is intentional. The delegate that
/// will be assigned to this function will contain more context on how this
/// scalar will be resolved.
///
/// Used for testing.
PreScalar? parsePlain(
  SourceIterator iterator, {
  required int indent,
  required String charsOnGreedy,
  required bool isImplicit,
  required bool isInFlowContext,
}) {
  final buffer = StringDelegate();

  if (plainParser(
        iterator,
        buffer: buffer.onWriteRequest,
        indent: indent,
        charsOnGreedy: charsOnGreedy,
        isImplicit: isImplicit,
        isInFlowContext: isInFlowContext,
      )
      case ParsedScalarInfo info) {
    return (
      // Cannot have leading and trailing whitespace (line breaks included).
      content: buffer.parsed().scalar.value.trim(),
      wroteLineBreak: buffer.bufferedLineBreak,
      scalarInfo: info,
    );
  }

  return null;
}

/// Parses the plain scalar. [charsOnGreedy] may represent the leading
/// `--` of a directive end marker that were consumed by the top level parser as
/// it tried to parse a [DocumentMarker.directiveEnd] production. This is
/// because a plain scalar has no explicit markers that signifiy its start or
/// termination. It relies on indentation like a block scalar.
///
/// Unlike other parse functions for a scalar, this may return `null` if the
/// top level parser did not handle the leading `(? | -) + (s-whitespace)`
/// production correctly.
///
/// Calls [buffer] for every byte/utf code unit that it reads as valid content
/// from the [iterator].
ParsedScalarInfo? plainParser(
  SourceIterator iterator, {
  required CharWriter buffer,
  required int indent,
  required String charsOnGreedy,
  required bool isImplicit,
  required bool isInFlowContext,
}) {
  //  Ensure we don't have a `(? | - | : ) + (s-whitespace)` production.
  if (charsOnGreedy.isEmpty &&
      _mustNotBeFirst.contains(iterator.current) &&
      iterator.peekNextChar().isNotNullAnd((c) => c.isWhiteSpace())) {
    return iterator.current != mappingValue
        ? null
        : (
            scalarStyle: ScalarStyle.plain,
            scalarIndent: indent,
            docMarkerType: DocumentMarker.none,
            hasLineBreak: false,
            indentOnExit: seamlessIndentMarker,
            indentDidChange: false,
            end: iterator.currentLineInfo.current,
          );
  }

  // Will always be empty or '--' or '---' but not a directive end marker.
  bufferHelper(charsOnGreedy.codeUnits, buffer);

  var docMarkerType = DocumentMarker.none;
  var foundLineBreak = false;
  var end = iterator.currentLineInfo.current;
  var indentOnExit = seamlessIndentMarker;

  final foldingBuffer = <int>[];

  // Plain scalars cannot have trailing whitespaces.
  void flushFoldingBuffer() {
    if (foldingBuffer.isNotEmpty) {
      bufferHelper(foldingBuffer, buffer);
      foldingBuffer.clear();
    }
  }

  // Marks the current offset as the tentative end offset.
  void markEndNow() {
    end = iterator.currentLineInfo.current;
  }

  chunker:
  while (!iterator.isEOF) {
    final char = iterator.current;

    final charBefore = iterator.before;
    var charAfter = iterator.peekNextChar();

    switch (char) {
      // Check for the document end markers first always
      case blockSequenceEntry || period
          when indent == 0 &&
              charBefore.isNullOr((c) => c.isLineBreak()) &&
              charAfter == char:
        {
          markEndNow();

          docMarkerType = checkForDocumentMarkers(
            iterator,

            // Minimalistic closure. Assume we have whitespaces and linebreaks
            // present. Akin to a sequential write.
            onMissing: foldingBuffer.addAll,
            throwIfDocEndInvalid: true,
          );

          if (docMarkerType.stopIfParsingDoc) {
            break chunker;
          }

          flushFoldingBuffer(); // Non-space chars found
        }

      // A mapping key can never be followed by a whitespace. Exit regardless
      // of whether we folded this scalar before.
      case mappingValue
          when charAfter.isNullOr(
            (c) =>
                (isInFlowContext && c.isFlowDelimiter()) ||
                c.isWhiteSpace() ||
                c.isLineBreak(),
          ):
        markEndNow();
        break chunker;

      // A look behind condition if encountered while folding the scalar.
      case comment
          when charBefore.isNotNullAnd(
            (c) => c.isWhiteSpace() || c.isLineBreak(),
          ):
        markEndNow();
        break chunker;

      // A lookahead condition of the rule above before folding the scalar
      case space || tab when charAfter == comment:
        markEndNow();
        break chunker;

      // Restricted to a single line when implicit. Instead of throwing, exit
      // and allow parser to determine next course of action
      case carriageReturn || lineFeed when isImplicit:
        markEndNow();
        break chunker;

      // Attempt to fold by default anytime we see a line break or white space
      case space || tab || carriageReturn || lineFeed:
        {
          final (:indentDidChange, :foldIndent, :hasLineBreak) = foldFlowScalar(
            iterator,
            scalarBuffer: foldingBuffer.add,
            minIndent: indent,
            isImplicit: isImplicit,
            matcherOnPlain: (charAfter) =>
                charAfter == mappingValue || charAfter == comment,
          );

          if (indentDidChange) {
            final (:start, :current) = iterator.currentLineInfo;
            end = iterator.isEOF ? current : start;
            indentOnExit = foldIndent;
            break chunker;
          }

          foundLineBreak = foundLineBreak || hasLineBreak;
        }

      case _ when (isImplicit || isInFlowContext) && char.isFlowDelimiter():
        break chunker;

      default:
        {
          flushFoldingBuffer();
          buffer(char);

          final OnChunk(:sourceEnded) = iterateAndChunk(
            iterator,
            onChar: buffer,
            exitIf: (_, c) => _delimiters.contains(c) || c.isFlowDelimiter(),
          );

          if (sourceEnded) {
            markEndNow();
            break chunker;
          }
        }
    }
  }

  return (
    scalarStyle: ScalarStyle.plain,
    scalarIndent: indent,
    docMarkerType: docMarkerType,
    indentOnExit: indentOnExit,
    hasLineBreak: foundLineBreak,
    indentDidChange: indentOnExit != seamlessIndentMarker,
    end: end,
  );
}
