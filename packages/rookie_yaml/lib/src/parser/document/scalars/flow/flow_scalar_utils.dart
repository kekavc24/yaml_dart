import 'package:rookie_yaml/src/parser/document/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

typedef FoldFlowInfo = ({
  bool indentDidChange,
  int foldIndent,
  bool hasLineBreak,
});

/// Throws if document/directive end markers are encountered while parsing a
/// scalar that is [ScalarStyle.doubleQuoted] or [ScalarStyle.singleQuoted].
void throwIfDocEndInQuoted(
  SourceIterator iterator, {
  required void Function(List<int> chars) onDocMissing,
  required int quoteChar,
}) {
  final start = iterator.currentLineInfo.current;

  if (checkForDocumentMarkers(
        iterator,
        onMissing: onDocMissing,
        throwIfDocEndInvalid: true,
      )
      case DocumentMarker.directiveEnd || DocumentMarker.documentEnd) {
    throwWithRangedOffset(
      iterator,
      message:
          'Expected a (${quoteChar.asString()}) before the current document'
          ' was terminated',
      start: start,
      end: iterator.currentLineInfo.current,
    );
  }
}

/// Ignores an escaped line break and excludes it from content in
/// [ScalarStyle.doubleQuoted].
///
/// See [escaped linebreak](https://yaml.org/spec/1.2.2/#731-double-quoted-style:~:text=In%20a%20multi,at%20arbitrary%20positions.)
({bool indentDidChange, int indentOnExit, bool exit}) _ignoreEscapedLineBreak(
  SourceIterator iterator, {
  required CharWriter scalarBuffer,
  required List<int> bufferedWhitespace,
  required int minIndent,
}) {
  do {
    bufferHelper(bufferedWhitespace, scalarBuffer);
    bufferedWhitespace.clear();

    // Skip to linebreak.
    iterator.nextChar();
    skipCrIfPossible(iterator.current, iterator: iterator);

    if (!iterator.hasNext) break;

    // Determine indent
    final indent = skipWhitespace(iterator, max: minIndent).length;
    iterator.nextChar();

    if (indent < minIndent) {
      return (indentDidChange: true, indentOnExit: indent, exit: true);
    }

    // Capture whitespace incase the next char combination is "\" + linebreak.
    if (iterator.current case space || tab) {
      bufferedWhitespace.add(iterator.current);

      skipWhitespace(
        iterator,
        skipTabs: true,
        previouslyRead: bufferedWhitespace,
      );
      iterator.nextChar();
    }
  } while (iterator.current == slash &&
      iterator.peekNextChar().isNotNullAnd((c) => c.isLineBreak()));

  bufferedWhitespace.clear(); // Also escaped.

  return (
    indentDidChange: false,
    indentOnExit: seamlessIndentMarker,
    exit: !iterator.current.isWhiteSpace() || !iterator.current.isLineBreak(),
  );
}

/// Folds a [ScalarStyle.singleQuoted] or [ScalarStyle.doubleQuoted] flow
/// scalar.
bool foldQuotedFlowScalar(
  SourceIterator iterator, {
  required CharWriter scalarBuffer,
  required int minIndent,
  required bool isImplicit,
  bool resumeOnEscapedLineBreak = false,
}) {
  final (:indentDidChange, :foldIndent, :hasLineBreak) = foldFlowScalar(
    iterator,
    scalarBuffer: scalarBuffer,
    minIndent: minIndent,
    isImplicit: isImplicit,
    resumeOnEscapedLineBreak: resumeOnEscapedLineBreak,
  );

  // Quoted scalar never allow an indent change before seeing closing quote
  if (indentDidChange) {
    throwWithApproximateRange(
      iterator,
      message:
          'Invalid indent! Expected $minIndent space(s), found $foldIndent'
          ' space(s)',
      current: iterator.currentLineInfo.current,
      charCountBefore: foldIndent,
    );
  }

  return hasLineBreak;
}

/// Folds a flow scalar(`plain`, `double quoted` and `single quoted`) that
/// spans more than 1 line.
///
/// [resumeOnEscapedLineBreak] should only be provided when parsing a `Scalar`
/// with [ScalarStyle.doubleQuoted] which allows `\n` to be escaped.
FoldFlowInfo foldFlowScalar(
  SourceIterator iterator, {
  required CharWriter scalarBuffer,
  required int minIndent,
  required bool isImplicit,
  bool resumeOnEscapedLineBreak = false,
  bool Function(int? charAfter)? matcherOnPlain,
}) {
  final matchesPlain = matcherOnPlain ?? (_) => false;
  final bufferedWhitespace = <int>[];

  var didFold = false;

  folding:
  while (!iterator.isEOF) {
    var current = iterator.current;

    switch (current) {
      case carriageReturn || lineFeed when !isImplicit:
        {
          didFold = true;
          var lastWasLineBreak = false;

          void foldCurrent(int? current) {
            scalarBuffer(
              lastWasLineBreak || current != null ? lineFeed : space,
            );
            bufferedWhitespace.clear();
          }

          void cleanUpFolding() {
            // The linebreak is excluded from folding if it was escaped.
            if (!lastWasLineBreak) {
              foldCurrent(null);
            } else {
              // Never apply dangling whitespace if the new line was escaped.
              // Safe fallback
              bufferedWhitespace.clear();
            }
          }

          // Fold continuously until we encounter a char that is not a linebreak
          // or whitespace.
          while (current.isLineBreak()) {
            current = skipCrIfPossible(current, iterator: iterator);
            bufferedWhitespace.clear();

            // Ensure we fold cautiously. Skip indent first
            final indent = skipWhitespace(iterator, max: minIndent).length;
            iterator.nextChar();

            current = iterator.current;

            final isDifferentScalar = indent < minIndent;

            // We don't want to impede on the next scalar by consuming its
            // content
            if (!iteratedIsEOF(current) &&
                current.isWhiteSpace() &&
                !isDifferentScalar) {
              if (matchesPlain(iterator.peekNextChar())) {
                foldCurrent(null);
                iterator.nextChar();
                break folding;
              }

              bufferedWhitespace.add(current);

              skipWhitespace(
                iterator,
                skipTabs: true,
                previouslyRead: bufferedWhitespace,
              );

              iterator.nextChar();

              current = iterator.current;
            }

            // It could be consecutive line breaks with no indent that made us
            // think this is a different scalar. It was just an empty line.
            //
            // It doesn't matter if the line break was escaped. Resume the
            // folding.
            if (!iteratedIsEOF(current) && current.isLineBreak()) {
              current = skipCrIfPossible(current, iterator: iterator);
              foldCurrent(current);
              lastWasLineBreak = true;
              continue;
            }

            // Plain scalars can be used in block styles. This indent change
            // indicates we need to alert any block styles on the indent that
            // triggered this exit.
            //
            // This can also be used to restrict double/single quoted styles
            // nested in a block style.
            if (isDifferentScalar) {
              cleanUpFolding();
              return (
                foldIndent: indent,
                indentDidChange: true,
                hasLineBreak: true,
              );
            }

            break; // Always exit after finding a non space/line break char.
          }

          cleanUpFolding();
        }

      case space || tab:
        {
          iterator.nextChar();
          bufferedWhitespace.add(current);

          // Match " :" or " #". These assumes the plain scalar is a key.
          if (matchesPlain(iterator.current)) {
            bufferHelper(bufferedWhitespace, scalarBuffer);
            break folding;
          }
        }

      default:
        {
          // Reserved for double quoted scalar where the linebreak can be
          // escaped. All other flow styles should return false!
          if (resumeOnEscapedLineBreak &&
              current == backSlash &&
              iterator.peekNextChar().isNotNullAnd((c) => c.isLineBreak())) {
            final (
              :indentDidChange,
              :indentOnExit,
              :exit,
            ) = _ignoreEscapedLineBreak(
              iterator,
              scalarBuffer: scalarBuffer,
              bufferedWhitespace: bufferedWhitespace,
              minIndent: minIndent,
            );

            if (exit || indentDidChange) {
              return (
                indentDidChange: indentDidChange,
                foldIndent: indentOnExit,
                hasLineBreak: false, // Excluded from content
              );
            }

            break;
          }

          bufferHelper(bufferedWhitespace, scalarBuffer);
          break folding;
        }
    }
  }

  return (
    indentDidChange: false,
    foldIndent: seamlessIndentMarker,
    hasLineBreak: didFold,
  );
}
