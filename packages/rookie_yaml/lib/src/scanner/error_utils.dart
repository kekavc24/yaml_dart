part of 'source_iterator.dart';

extension on int {
  /// Normalizes all character that can be escaped.
  ///
  /// If [includeTab] is `true`, then `\t` is also normalized. If
  /// [includeLineBreaks] is `true`, both `\n` and `\r` are normalized. If
  /// [includeSlashes] is `true`, backslash `\` and slash `/` are escaped. If
  /// [includeDoubleQuote] is `true`, the double quote is escaped.
  Iterable<int> normalizeEscapedChars({
    required bool includeTab,
    required bool includeLineBreaks,
    bool includeSlashes = true,
    bool includeDoubleQuote = true,
  }) sync* {
    int? leader = backSlash;
    var trailer = this;

    switch (this) {
      case unicodeNull:
        trailer = 0x30;

      case bell:
        trailer = 0x61;

      case asciiEscape:
        trailer = 0x65;

      case nextLine:
        trailer = 0x4E;

      case nbsp:
        trailer = 0x5F;

      case lineSeparator:
        trailer = 0x4C;

      case paragraphSeparator:
        trailer = 0x50;

      case backspace:
        trailer = 0x62;

      case tab when includeTab:
        trailer = 0x74;

      case lineFeed when includeLineBreaks:
        trailer = 0x6E;

      case verticalTab:
        trailer = 0x76;

      case formFeed:
        trailer = 0x66;

      case carriageReturn when includeLineBreaks:
        trailer = 0x66;

      case backSlash || slash:
        {
          if (includeSlashes) break;
          leader = null;
        }

      case doubleQuote:
        {
          if (includeDoubleQuote) break;
          leader = null;
        }

      default:
        leader = null; // Remove nerf by default
    }

    if (leader != null) yield leader;
    yield trailer;
  }
}

/// Represents an exception throw when parsing of a YAML source string fails.
final class YamlParseException implements Exception {
  YamlParseException(
    this.message, {
    required this.anchorOffset,
    required this.offsetOnError,
    required this.highlight,
  });

  /// A possible start offset of the error.
  final RuneOffset anchorOffset;

  /// Last offset before this error was thrown. Typically the offset closely
  /// associated with the error.
  final RuneOffset offsetOnError;

  /// Error message.
  final String message;

  /// Highlighted line(s) associated with the error.
  final String highlight;

  @override
  String toString() {
    final RuneOffset(:lineIndex, :columnIndex, :offset) = offsetOnError;
    return 'ParserException'
        '[Line ${lineIndex + 1}, Column $columnIndex, Offset $offset]: '
        '$message'
        '${highlight.isEmpty ? '' : '\n\n$highlight'}';
  }
}

/// Ensures the current line at the provided [index] is read until a line
/// terminator is found or no more characters are present (whichever comes
/// first).
///
/// If [index] is `null`, then the most recent line is buffered until a line
/// terminator is found.
void _makeLineAvailable(SourceIterator iterator, [int? index]) {
  final lineIndex = index ?? iterator.currentLine;

  while (iterator.hasNext && lineIndex >= iterator.currentLine) {
    iterator.nextChar();
  }
}

const _caret = '^';
const _space = ' ';

/// Normalizes all escapes characters and applies [_caret]s to all [indices]
/// speified.
String _applyCarets(Iterable<int> chars, {required Set<int> indices}) {
  // We never throw when we plan to throw!
  if (indices.isEmpty) {
    return String.fromCharCodes(chars);
  }

  final content = <String>[];
  final highlight = <String>[];

  void maybePushHighlight(int index, int count) {
    final str = indices.remove(index) ? _caret : _space;

    // Keep it simple :)
    for (var i = 0; i < count; i++) {
      highlight.add(str);
    }
  }

  for (final (index, char) in chars.indexed) {
    final normalized = char
        .normalizeEscapedChars(
          includeTab: true,
          includeLineBreaks: true,
          includeDoubleQuote: false,
          includeSlashes: false,
        )
        .map((i) => i.asString())
        .toList();

    content.addAll(normalized);

    // Icky (spacially inefficient) implementation. Will circle back.
    //
    // Some lines with errors may have an end offset nearer to the start which
    // clears any offsets that need to be highlighted quite early. At that
    // point, we are just trying to provide the current line's state as if the
    // parser has read it but was never parsed.
    //
    //   "Oh lexer, my lexer,
    //    Where art thou?"
    if (indices.isEmpty) continue;
    maybePushHighlight(index, normalized.length);
  }

  return '${content.join()}\n${highlight.join()}';
}

/// Returns an iterable that is not empty and can be highlighted.
///
/// This is important for empty lines. The iterable, if empty, is replaced with
/// a list which has a single space.
Iterable<int> _nonEmpty(Iterable<int> chars) => chars.isEmpty ? [space] : chars;

/// Highlights all [chars] from the [startIndex].
String _spannedHighlight(Iterable<int> chars, int startIndex) {
  final target = _nonEmpty(chars);
  return _applyCarets(
    target,
    indices: Iterable<int>.generate(
      target.length - startIndex,
      (index) => startIndex + index,
    ).toSet(),
  );
}

/// Throws a [YamlParseException] pointing to a single char at the specified
/// [offset].
Never throwWithSingleOffset(
  SourceIterator iterator, {
  required String message,
  required RuneOffset offset,
}) {
  final RuneOffset(:lineIndex, :columnIndex) = offset;
  _makeLineAvailable(iterator, lineIndex);

  // Include previous line if present
  final lines = iterator.lines(startIndex: max(0, lineIndex - 1));

  var highlighted = lines.length > 1
      ? '${String.fromCharCodes(_nonEmpty(lines.first.chars))}\n'
      : '';

  highlighted += _applyCarets(
    _nonEmpty((lines.lastOrNull ?? SourceLine(0, 0, chars: [space])).chars),
    indices: {columnIndex},
  );

  throw YamlParseException(
    message,
    anchorOffset: offset,
    offsetOnError: offset,
    highlight: highlighted,
  );
}

/// Throws a [YamlParseException] for range of [lines] where the last line has
/// the specified [end] offset. The [startIndex] acts as the column index for
/// the first line if [lines] has more than 1 line. Otherwise, the column index
/// is treated as an column index to the last line.
Never _rangedThrow(
  String message, {
  required RuneOffset start,
  required RuneOffset end,
  required List<SourceLine> lines,
}) {
  var columnIndex = start.columnIndex;
  var length = lines.length - 1;
  final buffer = StringBuffer();

  if (length >= 1) {
    --length;
    buffer.writeln(
      // Starting index indicates the number of elements we have to skip. The
      // first line may have an offset that is ahead.
      _spannedHighlight(lines.first.chars.skip(columnIndex), 0),
    );

    columnIndex = 0; // Reset. First line captured this index.

    // Non-terminating lines are highlighted from start to the end
    for (final line in lines.skip(1).take(length)) {
      buffer.writeln(_spannedHighlight(line.chars, 0));
    }
  }

  // Avoid using [spannedHighlight]. We have the end index and we also want to
  // show the line to the end but with a ranged highlight
  buffer.write(
    _applyCarets(
      _nonEmpty(lines.last.chars),
      indices: Iterable<int>.generate(
        (end.columnIndex + 1) - columnIndex,
        (i) => columnIndex + i,
      ).toSet(),
    ),
  );

  throw YamlParseException(
    message,
    anchorOffset: start,
    offsetOnError: end,
    highlight: buffer.toString(),
  );
}

/// Throw a [YamlParseException] with the current active line whose characters
/// are being iterated. The line is highlighted from the start to the end.
Never throwForCurrentLine(
  SourceIterator iterator, {
  required String message,
  RuneOffset? end,
}) {
  final (:start, :current) = iterator.currentLineInfo;
  return throwWithRangedOffset(
    iterator,
    message: message,
    start: start,
    end: end ?? current,
  );
}

/// Throws a [YamlParseException] for a source string with the [start] and [end]
/// offset specified.
Never throwWithRangedOffset(
  SourceIterator iterator, {
  required String message,
  required RuneOffset start,
  required RuneOffset end,
}) {
  if (start.offset > end.offset) {
    return throwWithSingleOffset(
      iterator,
      message: message,
      offset: start,
    );
  }

  _makeLineAvailable(iterator, end.lineIndex);
  return _rangedThrow(
    message,
    start: start,
    end: end,
    lines: iterator.lines(startIndex: start.lineIndex),
  );
}

/// Throws a [YamlParseException] for a source string with an end offset at the
/// [current] offset and a start offset approximately at least [charCountBefore]
/// behind.
///
/// [charCountBefore] doesn't include the character at the [current] offset.
Never throwWithApproximateRange(
  SourceIterator iterator, {
  required String message,
  required RuneOffset current,
  required int charCountBefore,
}) {
  final RuneOffset(:columnIndex, :lineIndex) = current;
  _makeLineAvailable(iterator, lineIndex);
  final linesAvailable = iterator.lines();

  final lines = <SourceLine>[linesAvailable.last];
  var offsetDiff = columnIndex - charCountBefore;

  var iterIndex = lineIndex - 1;

  // Iterate in reverse as look for the starting point
  while (iterIndex >= 0 && offsetDiff < 0) {
    final line = linesAvailable[iterIndex];
    lines.add(line);

    // Unlike the last line which uses column index, just use the total number
    // of characters in the current line. We just need to compensate for the
    // transition of the line break from one line to the next
    offsetDiff = offsetDiff + line.chars.length + 1;
    --iterIndex;
  }

  final actualColumn = max(0, offsetDiff);

  return _rangedThrow(
    message,
    start: (
      lineIndex: iterIndex + 1,
      columnIndex: actualColumn,
      rawOffset: -1, // cannot be determined here
      offset: lines.first.startOffset + actualColumn,
      span: 0, // Unknown with approximation.
    ),
    end: current,
    lines: lines,
  );
}
