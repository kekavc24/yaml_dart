import 'dart:math';

import 'package:rookie_yaml/src/parser/delegates/one_pass_scalars/efficient_scalar_delegate.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

part 'block_header.dart';
part 'block_utils.dart';

/// Parses a block scalar. Specifically, [ScalarStyle.literal] or
/// [ScalarStyle.folded].
///
/// [onParseComment] ensures comments in a block scalar's header are not
/// discarded but written to the top level parser.
///
/// [minimumIndent] is the minimum indent imposed by the nearest block parent.
/// It should be noted that this indent is a suggestion as the block scalar
/// determines its indent from the first non-empty line.
///
/// This is the parser's low level implementation for parsing a double quoted
/// scalar which returns a [PreScalar]. This is intentional. The delegate that
/// will be assigned to this function will contain more context on how this
/// scalar will be resolved.
///
/// Used for testing.
PreScalar parseBlockScalar(
  SourceIterator iterator, {
  required int minimumIndent,
  required int? blockParentIndent,
  required void Function(YamlComment comment) onParseComment,
}) {
  final buffer = StringDelegate();
  final info = blockScalarParser(
    iterator,
    charBuffer: buffer.onWriteRequest,
    minimumIndent: minimumIndent,
    blockParentIndent: blockParentIndent,
    onParseComment: onParseComment,
  );

  return (
    content: buffer.parsed().scalar.value,
    wroteLineBreak: buffer.bufferedLineBreak,
    scalarInfo: info,
  );
}

/// Parses the block scalar.
///
/// Calls [charBuffer] for every byte/utf code unit that it reads as valid content
/// from the [iterator]..
ParsedScalarInfo blockScalarParser(
  SourceIterator iterator, {
  required CharWriter charBuffer,
  required int minimumIndent,
  required int? blockParentIndent,
  required void Function(YamlComment comment) onParseComment,
}) {
  var wroteToBuffer = false;

  // TODO: Use a call exactly once util class? Meh for now
  void blockBuffer(int char) {
    wroteToBuffer = true;
    charBuffer(char);
  }

  var indentOnExit = seamlessIndentMarker;
  final (:isLiteral, :chomping, :indentIndicator) = _parseBlockHeader(
    iterator,
    onParseComment: onParseComment,
  );

  int? trueIndent;

  // If not null, we know the indent. Otherwise we have to infer from the first
  // non-empty line.
  if (indentIndicator != null) {
    trueIndent = (blockParentIndent ?? 0) + indentIndicator;
  }

  final lineBreaks = <int>[
    if (!isLiteral && iterator.current.isLineBreak())
      skipCrIfPossible(iterator.current, iterator: iterator),
  ];

  var lastWasIndented = false;
  var didRun = false;

  // Block scalar have no set indent. They infer indent using the first
  // non-empty line.
  int? previousMaxIndent;

  var docMarkerType = DocumentMarker.none;
  var end = iterator.currentLineInfo.current;

  // Buffers characters until the end of the current line.
  bool chunkAndExit(int current) {
    blockBuffer(current);

    final OnChunk(:sourceEnded) = iterateAndChunk(
      iterator,
      onChar: blockBuffer,
      exitIf: (_, curr) => curr.isLineBreak(),
    );

    end = iterator.currentLineInfo.current;
    return sourceEnded;
  }

  void markRun() {
    if (didRun) return;
    didRun = true;
  }

  blockParser:
  while (!iterator.isEOF) {
    final indent = trueIndent ?? minimumIndent;
    var char = iterator.current;

    switch (char) {
      checkIndent:
      case carriageReturn || lineFeed:
        {
          char = skipCrIfPossible(char, iterator: iterator);

          if (didRun) {
            lineBreaks.add(char);
          }

          final scannedIndent = skipWhitespace(iterator, max: indent).length;
          final charAfter = iterator.peekNextChar();
          final hasCharAfter = charAfter != null;

          if (charAfter != carriageReturn && charAfter != lineFeed) {
            // While `YAML` suggested we parse the comment thereafter, it is
            // better to exit and allow the `root` parser to determine how to
            // parse it.
            //
            // Also check if we need to exit incase a document/directives end
            // marker is found in a top level scalar
            if (!hasCharAfter || scannedIndent < indent) {
              indentOnExit = scannedIndent;
              iterator.nextChar();

              // If we have more characters, our actual scalar starts where the
              // current line starts since the indent change caused the exit.
              end = hasCharAfter
                  ? iterator.currentLineInfo.start
                  : iterator.currentLineInfo.current;
              break blockParser;
            }

            // Attempt to infer indent if null
            if (trueIndent == null) {
              final (
                :inferredIndent,
                :isEmptyLine,
                :startsWithTab,
              ) = _inferIndent(
                iterator,
                buffer: blockBuffer,
                scannedIndent: scannedIndent,
                callBeforeTabWrite: () => _maybeFoldLF(
                  blockBuffer,
                  isLiteral: isLiteral,
                  wroteToBuffer: wroteToBuffer,
                  lastNonEmptyWasIndented: false, // Not possible with no indent
                  lineBreaks: lineBreaks,
                ),
              );

              if (isEmptyLine) {
                previousMaxIndent = max(previousMaxIndent ?? 0, inferredIndent);
              } else if (previousMaxIndent != null &&
                  previousMaxIndent > inferredIndent) {
                throwWithApproximateRange(
                  iterator,
                  message:
                      'A previous empty line was more indented with '
                      '$previousMaxIndent space(s). Indent must be at least'
                      ' equal to or greater than this indent.',
                  current: iterator.currentLineInfo.current,
                  charCountBefore: inferredIndent,
                );
              } else {
                trueIndent = inferredIndent;
              }

              lastWasIndented = startsWithTab || lastWasIndented;
            }
          } else {
            // Avoid calling [iterator.currentLineInfo] multiple times for
            // sequential line breaks (inefficient). Repeatedly skip all.
            char = charAfter!;
            iterator.nextChar();
            markRun();
            continue checkIndent;
          }

          iterator.nextChar();
          markRun();
          end = iterator.currentLineInfo.start;
        }

      case blockSequenceEntry || period
          when trueIndent == 0 &&
              iterator.before.isNotNullAnd((c) => c.isLineBreak()):
        {
          // Ends when we see first "-" of "---" or "." of "..."
          final maybeEnd = iterator.currentLineInfo.current;

          docMarkerType = checkForDocumentMarkers(
            iterator,
            onMissing: (chars) => bufferHelper(chars, blockBuffer),
            throwIfDocEndInvalid: true,
          );

          if (docMarkerType.stopIfParsingDoc) {
            end = maybeEnd;
            break blockParser;
          }
        }

      case space || tab:
        {
          final canFold = lineBreaks.length > 1;

          // Only empty lines separating folded lines and indented line are
          // ignored. See folded section productions [180] & [181].
          if (!isLiteral && !wroteToBuffer && canFold) {
            _maybeFoldLF(
              blockBuffer,
              isLiteral: false,
              wroteToBuffer: true,
              lastNonEmptyWasIndented: false,
              lineBreaks: lineBreaks,
            );
          } else if (canFold || wroteToBuffer) {
            bufferHelper(lineBreaks, blockBuffer);
          }

          lastWasIndented = true;
          lineBreaks.clear();

          if (chunkAndExit(char)) break blockParser;
        }

      default:
        {
          // All block scalar styles only accept printable characters.
          if (!char.isPrintable()) {
            throwWithSingleOffset(
              iterator,
              message:
                  'Block scalar styles are restricted to the printable '
                  'character set',
              offset: iterator.currentLineInfo.current,
            );
          }

          if (lastWasIndented) {
            bufferHelper(lineBreaks, blockBuffer);
            lineBreaks.clear();
            lastWasIndented = false;
          } else {
            _maybeFoldLF(
              blockBuffer,
              isLiteral: isLiteral,
              wroteToBuffer: wroteToBuffer,
              lastNonEmptyWasIndented: lastWasIndented,
              lineBreaks: lineBreaks,
            );
          }

          if (chunkAndExit(char)) break blockParser;
        }
    }
  }

  _chompLineBreaks(
    chomping,
    buffer: blockBuffer,
    wroteToBuffer: wroteToBuffer,

    // Treat the only line break as a trailing one if no content was ever
    // present or we completely drained the source.
    lineBreaks:
        (didRun && lineBreaks.isEmpty && (!wroteToBuffer || iterator.isEOF))
        ? (lineBreaks..add(lineFeed))
        : lineBreaks,
  );

  return (
    scalarStyle: isLiteral ? ScalarStyle.literal : ScalarStyle.folded,
    scalarIndent: trueIndent ?? minimumIndent,
    indentOnExit: indentOnExit,
    indentDidChange: indentOnExit != seamlessIndentMarker,
    docMarkerType: docMarkerType,
    hasLineBreak: indentOnExit != seamlessIndentMarker || wroteToBuffer,
    end: end,
  );
}
