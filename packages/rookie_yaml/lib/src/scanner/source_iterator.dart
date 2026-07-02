import 'dart:math';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/encoding/utf_utils.dart';
import 'package:rookie_yaml/src/scanner/span.dart';

part 'error_utils.dart';

/// Number of lines from [start] to [end]. This assumes the [end] is exclusive
/// and its line is ignored.
///
/// ```dart
/// final node = loadYamlNode(
///     YamlSource.string(
///       '''
/// - hello
/// - next''',
///     ),
///   );
///
/// final hello = node!.children.first.nodeSpan;
///
/// print(hello.end); // (columnIndex: 0, lineIndex: 1, utfOffset: 8)
/// print(getLineCount(hello.start, hello.end)); // 1
int getLineCount(RuneOffset start, RuneOffset end) =>
    max(0, end.lineIndex - start.lineIndex);

/// Returns start [RuneOffset] position of a line.
RuneOffset _getLineStart({
  int lineIndex = 0,
  int span = 0,
  int rawOffset = 0,
  int currentOffset = 0,
}) => (
  lineIndex: lineIndex,
  columnIndex: 0,
  span: 0,
  rawOffset: rawOffset + span,
  offset: currentOffset,
);

/// Represents the active line's span information. This is intentionally
/// different from [RuneSpan] because we prefer to iterate the source string
/// lazily and only split it when we encounter a `\n` terminator.
typedef LineInfo = ({RuneOffset start, RuneOffset current});

/// Represents a single line's source information with an inclusive start index
/// and end index.
final class SourceLine {
  const SourceLine(this.startOffset, this.endOffset, {required this.chars});

  /// Start offset (inclusive)
  final int startOffset;

  /// End index (inclusive)
  final int endOffset;

  /// UTF-8/UTF-16 code points
  final List<int> chars;

  @override
  String toString() => String.fromCharCodes(chars);
}

/// An iterator that iterates over any parsable YAML source string.
///
/// `[NOTE]`: This class does not subclass [Iterator]. This is intentional.
abstract base class SourceIterator {
  /// Whether a char is present after the [current] char.
  bool get hasNext;

  /// Character before [current].
  int? get before;

  /// Current character. Always points to the first character when this
  /// iterator is instantianted.
  ///
  /// Typically, this is the current character that the iterator **WAS**
  /// pointing to at [peekNextChar] before [nextChar] was called for any char
  /// other than the first char.
  int get current;

  /// Whether the underlying byte source has been iterated to completion.
  bool get isEOF;

  /// Index of the current line
  int get currentLine;

  /// Moves the iterator forward.
  ///
  /// Eagerly throws an [Error] rather than an [Exception] if called without
  /// checking [hasNext]. Ideally, a subclass may implement a heuristic that
  /// allows [current] to be skipped if it is the last character allowing
  /// [isEOF] to provide fine grained information on the current state of the
  /// iterator.
  @mustCallSuper
  void nextChar() {
    _throwIfBOM();
  }

  /// Peeks ahead and returns the next character which may be `null` if no
  /// more characters are present.
  int? peekNextChar();

  /// Returns the current line information which includes the start position
  /// of the current line and the current position of this iterator within
  /// the line.
  LineInfo get currentLineInfo;

  /// Returns the lines that have been iterated so far.
  List<SourceLine> lines({int startIndex = 0});

  /// Whether to treat the BOM as a valid character.
  var _allowBOM = false;

  /// Skips the current unicode character if it is the unicode BOM character.
  void skipBOM() {
    if (current.isByteOrderMark()) {
      nextChar();
    }

    _allowBOM = false;
  }

  /// Toggles the [state] of the iterator to (not) accept the unicode BOM
  /// character.
  void allowBOM(bool state) => _allowBOM = state;

  /// Throws if the BOM is not allowed in the current iterator's state.
  void _throwIfBOM() {
    if (_allowBOM || !current.isByteOrderMark(checkLE: true)) return;

    // Byte order mark is never allowed in YAML content.
    throwWithSingleOffset(
      this,
      message:
          'The BOM (byte order mark) "0xFEFF" can only appear at the start of'
          ' a document',
      offset: currentLineInfo.current,
    );
  }
}

/// A [SourceIterator] that iterates the utf16/utf32 unicode points of a source
/// string/file.
final class UnicodeIterator extends SourceIterator {
  UnicodeIterator._(this._iterator) {
    // Always point to the first character
    if (_iterator.moveNext()) {
      final char = _iterator.current;
      _currentCharSpan = char.span;
      _currentChar = char.unicode;

      _lineStartOffset = _getLineStart(span: _currentCharSpan);

      if (!_iterator.moveNext()) {
        _bufferCurrent();
        _markLineAsComplete();
      } else {
        _hasMoreLines = true;
        _hasNext = true;
        _nextChar = _iterator.current;

        _skipCarriageReturn();
      }

      return;
    }

    _lines.add(const SourceLine(0, 0, chars: []));
    _lineStartOffset = _getLineStart();
    allowBOM(true);
  }

  /// Creates a [UnicodeIterator] that uses the underlying code units to iterate
  /// the string [source].
  UnicodeIterator.ofString(String source)
    : this._(SpannedIterator.ofString(source));

  /// Creates a [UnicodeIterator] that iterates a sequence of utf bytes.
  UnicodeIterator.ofUnicode(Iterator<Unicode> source) : this._(source);

  /// Actual iterator being read.
  final Iterator<Unicode> _iterator;

  /// [SourceLine]s lazily buffered while iterating.
  final _lines = <SourceLine>[];

  /// UTF-16 unicode characters buffered for single [SourceLine]. Always handed
  /// off without an additional copy operation.
  var _bufferedRunes = <int>[];

  /// Whether the [_iterator] has a character when `_iterator.current` is
  /// called.
  bool _hasNext = false;

  bool _hasMoreLines = false;

  /// Start offset of the current [SourceLine]
  late RuneOffset _lineStartOffset;

  /// Index of the UTF-8/UTF-16 unicode character in a string.
  int _graphemeIndex = 0;

  /// True offset within the source.
  int _rawOffset = 0;

  /// Index of the current line
  int _lineIndex = 0;

  /// Column index of the current character
  int _columnIndex = 0;

  /// Preceding character.
  int? _charBefore;

  /// Number of code units represented by the current character.
  int _currentCharSpan = 0;

  /// Current character
  int _currentChar = -1;

  /// Next character
  Unicode _nextChar = empty;

  @override
  bool get hasNext => _hasNext;

  @override
  int? get before => _charBefore;

  @override
  int get current => _currentChar;

  @override
  bool get isEOF => _currentChar == -1;

  @override
  int get currentLine => _lineIndex;

  @override
  LineInfo get currentLineInfo => (
    start: _lineStartOffset,
    current: (
      lineIndex: _lineIndex,
      columnIndex: _columnIndex,
      span: _currentCharSpan,
      rawOffset: _rawOffset,
      offset: _graphemeIndex,
    ),
  );

  @override
  List<SourceLine> lines({int startIndex = 0}) =>
      UnmodifiableListView(_lines.skip(startIndex));

  /// Skips a `\r` if it's followed by a `\n`
  void _skipCarriageReturn() {
    // From our point of view, we treat \r\n as a complete line break. We don't
    // care if this isn't Windows. In our parsing context, we always fast
    // forward this combination.
    if (_currentChar == carriageReturn && _nextChar.unicode == lineFeed) {
      _moveNext();
      ++_rawOffset;
      ++_graphemeIndex;
      ++_columnIndex;
    }
  }

  /// Buffers the [_currentChar] if it is valid and not `\r` or `\n`
  void _bufferCurrent() {
    if (_currentChar == -1 || _currentChar.isLineBreak()) return;
    _bufferedRunes.add(_currentChar);
  }

  /// Buffers the current line's information to [_lines].
  void _markLineAsComplete() {
    _lines.add(
      SourceLine(
        _lineStartOffset.offset,
        _graphemeIndex,
        chars: UnmodifiableListView(_bufferedRunes),
      ),
    );

    _bufferedRunes = [];
    if (_hasMoreLines) _columnIndex = 0;
  }

  /// Moves the [_iterator] forward.
  void _moveNext() {
    final (:span, :unicode) = _nextChar;
    _currentCharSpan = span;
    _currentChar = unicode;
    _hasNext = _iterator.moveNext();
    _nextChar = _hasNext ? _iterator.current : empty;
  }

  @override
  void nextChar() {
    // Some defensive coding for the culture in case of refactors
    assert(
      _hasNext || _currentChar != -1,
      '[nextChar()] expects a non-empty char iterator',
    );

    var isNewLine = false;

    // We always treat \r\n as a single character. Seeing a \r forces us to
    // assume it is a line break. Keeping/tracking count serves no purpose since
    // both are considered line breaks by YAML.
    if (_currentChar.isLineBreak()) {
      _markLineAsComplete();
      isNewLine = true;
    } else {
      _bufferedRunes.add(_currentChar);
    }

    _charBefore = _currentChar;
    _moveNext();
    super.nextChar();

    final charSpan = max(1, _currentCharSpan);
    _rawOffset += charSpan;
    ++_graphemeIndex; // EOF included.

    // Update line index.
    if (isNewLine) {
      ++_lineIndex;
      _lineStartOffset = _getLineStart(
        lineIndex: _lineIndex,
        span: _currentCharSpan,
        rawOffset: _rawOffset,
        currentOffset: _graphemeIndex,
      );
    } else {
      _columnIndex += charSpan;
    }

    _skipCarriageReturn();

    if (_hasNext) return;

    // We will not get a chance to buffer this last line. Also this iterator has
    // no notion of trailing empty lines. A trailing line break will not trigger
    // an empty line to be added to [_lines]
    _hasMoreLines = false;
    _bufferCurrent();
    _markLineAsComplete();
  }

  @override
  int? peekNextChar() => switch (_nextChar.unicode) {
    -1 => null,
    int char => char,
  };

  /// Displays the current chunk within a line that is being iterated.
  @override
  String toString() => String.fromCharCodes(_bufferedRunes);
}

/// Whether a [char] from a [SourceIterator] is not a valid unicode character.
bool iteratedIsEOF(int? char) => char == null || char < 0;

/// Skips any whitespace and returns the whitespace characters skipped. If
/// [skipTabs] is `true`, then tabs `\t` will also be skipped.
///
/// [previouslyRead] must be mutable.
List<int> skipWhitespace(
  SourceIterator iterator, {
  bool skipTabs = false,
  int? max,
  List<int>? previouslyRead,
  void Function()? hasTabs,
}) {
  final buffer = previouslyRead ?? [];
  final hasMax = max != null;
  final callTabs = hasTabs ?? () {};

  var tabCount = 0;

  bool isMatch(int? char) {
    switch (char) {
      case tab:
        {
          if (skipTabs) {
            ++tabCount;
            return true;
          }

          return false;
        }

      case space:
        return true;

      default:
        return false;
    }
  }

  while (iterator.hasNext &&
      !(hasMax && buffer.length >= max) &&
      isMatch(iterator.peekNextChar())) {
    iterator.nextChar();
    buffer.add(iterator.current);
  }

  if (tabCount > 0) callTabs();
  return buffer;
}

/// Returns the number of characters taken until a character failed the
/// [stopIf] test, that is, evaluated to `false`.
///
/// [includeCharAtCursor] adds the current character present when
/// `iterator.current` is called on the cursor only if it is not `null`. The
/// [mapper] function is applied and value made available using [onMapped].
int takeFromIteratorUntil<T>(
  SourceIterator iterator, {
  required bool includeCharAtCursor,
  required T Function(int char) mapper,
  required void Function(T mapped) onMapped,
  required bool Function(int count, int possibleNext) stopIf,
}) {
  var taken = 0;

  if (includeCharAtCursor && iterator.current != -1) {
    onMapped(mapper(iterator.current));
    ++taken;
  }

  // Ensures we always leave the iterator in a safe state and prevents iterating
  // the same character multiple times.
  do {
    if (iterator.peekNextChar() case int char) {
      if (stopIf(taken, char)) {
        break;
      }

      onMapped(mapper(char));
      ++taken;
    }

    iterator.nextChar();
  } while (iterator.hasNext);

  return taken;
}

/// Represents information returned after a call to `bufferChunk` method
/// of the [SourceIterator]
///
/// `sourceEnded` - indicates if the entire string source was scanned.
///
/// `lineEnded` - indicates if an entire line was scanned, that is, until a
/// line feed was encountered.
///
/// `charOnExit` - indicates the character that triggered the `bufferChunk`
/// exit. Typically, the current character when `GraphemeScanner.charAtCursor`
/// is called.
typedef OnChunk = ({bool sourceEnded, int? charOnExit});

/// Reads and buffers all characters that fail the [exitIf] predicate or until
/// the end of the current line, that is, until the line's [lineFeed] is emitted
/// and no more characters are present in the line (whichever condition comes
/// first).
///
/// This function guarantees that it will leave the [iterator] in a safe state
/// if no more characters are present.
OnChunk iterateAndChunk(
  SourceIterator iterator, {
  required void Function(int char) onChar,
  required bool Function(int? previous, int current) exitIf,
}) {
  int? maybeCharOnExit;
  var evalChatArCursor = false;

  // Iterate as long as we can buffer characters
  while (iterator.hasNext) {
    iterator.nextChar();

    maybeCharOnExit = iterator.current;

    if (exitIf(iterator.before, maybeCharOnExit)) {
      evalChatArCursor = true;
      break;
    }

    onChar(maybeCharOnExit);
  }

  final sourceEnded = !evalChatArCursor && !iterator.hasNext;

  if (sourceEnded && !iterator.isEOF) {
    iterator.nextChar(); // Skip completely
  }

  return (
    sourceEnded: sourceEnded,
    charOnExit: maybeCharOnExit,
  );
}
