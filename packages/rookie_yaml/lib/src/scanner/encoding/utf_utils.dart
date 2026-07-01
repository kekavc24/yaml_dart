/// Byte range for a UTF-8 byte sequence. (start and end inclusive)
typedef _MinMax = (int, int);

///
typedef Unicode = ({int span, int unicode});

extension UtfUtils on int {
  String readableHex() => '0x${toRadixString(16)}';
}

extension on _MinMax {
  /// Whether the [value] is within the range.
  bool hasValue(int value) => value >= $1 && value <= $2;

  /// Converts the range to "min..max".
  String toRange() => '${$1.toRadixString(16)}..${$2.toRadixString(16)}';
}

/// Default range for the third and fourth byte of a UTF-8 byte sequence. Also
/// applies to the second byte of a byte sequence which doesn't have `0xE0`,
/// `0xED`, `0xF0` and `0xF4` as its first byte.
const _uniformByteRange = (0x80, 0xBF);

/// Obtains the second byte range for the [firstByte] of a UTF-8 byte sequence.
@pragma('vm:prefer-inline')
_MinMax _unicodeSecondByteRange(int firstByte) => switch (firstByte) {
  0xE0 => (0xA0, 0xBF),
  0xED => (0x80, 0x9F),
  0xF0 => (0x90, 0xBF),
  0xF4 => (0x80, 0x8F),
  _ => _uniformByteRange,
};

/// Decodes a UTF-8 byte [source] and allows no malformed byte sequences. This
/// implementaton is based on The Unicode Standard, Version 17.0.
Iterable<Unicode> decodeUtf8Strict(Iterator<int> source) sync* {
  var canRead = source.moveNext();
  if (!canRead) return;

  const boundary = 7;
  var offset = 0;

  /// Moves the cursor forward and returns whether more characters can be read.
  bool move() {
    if (canRead) {
      ++offset;
      return canRead = source.moveNext();
    }

    return false;
  }

  /// Reads the next byte if possible. Otherwise, throws.
  int takeNext(int count, int remaining) {
    if (move()) return source.current;

    throw StateError(
      'Missing bytes in the byte sequence.\n'
      '\tCurrent offset: $offset\n'
      '\tRemaining unread bytes: $remaining',
    );
  }

  /// Obtains the bits stored in the leading byte of a "n"-byte-sequence where
  /// "n" >= 1. Also returns the number of bytes ahead that should be read.
  (int count, int highs) unpack(int byte) {
    final (mask, continuation) = switch (byte >> 4) {
      15 => (boundary, 3), // 1111 0uuu & 111 -> uuu
      14 => (0xF, 2), // 1110 zzzz & 1111 -> zzzz
      _ => (0x1F, 1), //  110y yyyy & 11111 -> yyyyy
    };

    return (continuation, (byte & mask));
  }

  /// Reads the trailing bytes of a UTF-8 byte sequence.
  int readTrailingBytes(int count, int highs, int firstByte) {
    const distributed = 0x3F;
    var taken = count;

    // The second byte is the most sensitive.
    var buffer = takeNext(count, taken);
    final secondByteRange = _unicodeSecondByteRange(firstByte);

    if (!secondByteRange.hasValue(buffer)) {
      throw StateError(
        'Invalid continuation byte after the first byte.\n'
        '\tFirst byte: ${firstByte.readableHex()}\n'
        '\tSecond byte: ${buffer.readableHex()}\n'
        '\tExpected byte range: ${secondByteRange.toRange()}',
      );
    }

    buffer = (highs << 6) | (buffer & distributed);
    --taken;

    while (taken > 0) {
      final value = takeNext(count, taken);
      if (_uniformByteRange.hasValue(value)) {
        buffer = (value & distributed) | (buffer << 6);
        --taken;
        continue;
      }

      throw StateError(
        'Invalid continuation byte:\n'
        '\tCurrent byte: ${value.readableHex()}\n'
        '\tExpected byte range: ${_uniformByteRange.toRange()}',
      );
    }

    return buffer;
  }

  do {
    final byte = source.current;

    // ASCII character.
    if (byte.bitLength <= boundary) {
      yield (span: 1, unicode: byte);
    } else if (byte < 0xC2 || byte > 0xF4) {
      // First byte must in the range of C2 - F4
      throw StateError(
        '${byte.readableHex()} cannot be the first byte in a UTF-8 byte'
        ' sequence.',
      );
    } else {
      final (count, highs) = unpack(byte);
      yield (span: count + 1, unicode: readTrailingBytes(count, highs, byte));
    }
  } while (move());
}

/// Allowed surrogate range.
const _surrogateRange = (0xD800, 0xDFFF);

typedef _Converter = int Function(int value);

/// Decodes a UTF-16 [source]. This implementaton is based on The Unicode
/// Standard, Version 17.0.
///
/// For UTF-16 code units, surrogate pairs are combined automatically. However,
/// this function throws if any unpaired high-surrogate or low-surrogate code
/// units are present.
///
/// In all other cases, the code units must be in the range of 0x00 - 0xFFFF
/// (inclusive on both ends).
@pragma('vm:prefer-inline')
Iterable<Unicode> _decodeUtf16Strict(Iterator<int> source) sync* {
  /// Checks if a code unit is a trailing surrogate pair.
  bool isTrailingSurrogate(int codeUnit) => (codeUnit & 0xFC00) == 0xDC00;

  /// Reads the surrogate pairs.
  int readSurrogatePair(int high) {
    if (!source.moveNext()) {
      throw StateError(
        'Missing trailing low-surrogate code unit after ${high.readableHex()}.',
      );
    }

    final low = source.current;

    if (isTrailingSurrogate(high) || !isTrailingSurrogate(low)) {
      throw StateError(
        'Invalid surrogate pairs found in the byte source.\n'
        '\tHigh-surrogate code unit: ${high.readableHex()}\n'
        '\tLow-surrogate code unit: ${low.readableHex()}',
      );
    }

    return 0x10000 + ((high & 0x3FF) << 10) + (low & 0x3FF);
  }

  while (source.moveNext()) {
    final codeUnit = source.current;

    if (_surrogateRange.hasValue(codeUnit)) {
      yield (span: 2, unicode: readSurrogatePair(codeUnit));
    } else if (codeUnit < 0 || codeUnit > 0xFFFF) {
      throw StateError(
        'Invalid code unit "${codeUnit.readableHex()}" not in range of '
        '0x00 - 0xFFFF encountered.',
      );
    } else {
      yield (span: 1, unicode: codeUnit);
    }
  }
}

/// Decodes a UTF-32 [source]. This implementaton is based on The Unicode
/// Standard, Version 17.0.
///
/// Any surrogate code units are considered ill-formed. In all other cases,
/// the code units must be in the range of 0x00 - 0x10FFFF.
@pragma('vm:prefer-inline')
Iterable<int> _decodeUtf32Strict(Iterator<int> source) sync* {
  bool notInRange(int value) => value < 0 || value > 0x10FFFF;

  while (source.moveNext()) {
    final codeUnit = source.current;

    if (notInRange(codeUnit)) {
      throw StateError(
        'Invalid code unit "${codeUnit.readableHex()}" not in range of '
        '0x00 - 0x10FFFF encountered.',
      );
    } else if (_surrogateRange.hasValue(codeUnit)) {
      throw StateError(
        'Ill-formed surrogate code unit "${codeUnit.readableHex()}" not allowed'
        'in UTF-32.',
      );
    }

    yield codeUnit;
  }
}

typedef _WideDecoder = Iterator<Unicode> Function(Iterator<int> source);

/// Converts the endianess of a `UTF-16` code unit.
@pragma('vm:prefer-inline')
int utf16Converter(int codeUnit) =>
    (((0x00FF & codeUnit) << 8) | (codeUnit >> 8));

/// Converts the endianess of a `UTF-32` code unit.
@pragma('vm:prefer-inline')
int utf32Converter(int codeUnit) =>
    ((0xFF & codeUnit) << 24) |
    ((0xFF00 & codeUnit) << 8) |
    ((codeUnit >> 8) & 0xFF00) |
    (codeUnit >> 24);

/// Helper function for obtaining the [_Converter] and [_WideDecoder] for
/// `UTF-16` if [isUtf16] is `true`. Otherwise, defaults to `UTF-32`.
@pragma('vm:prefer-inline')
(_Converter, _WideDecoder) _wideUtfHelper(bool isUtf16) => isUtf16
    ? (utf16Converter, (i) => _decodeUtf16Strict(i).iterator)
    : (
        utf32Converter,
        ((i) => SpannedIterator.fixed(1, _decodeUtf32Strict(i).iterator)),
      );

/// Decodes a `UTF-16` or `UTF-32` [input] whose source is an [Iterator].
Iterator<Unicode> iteratorDecodeUtfMin16(
  Iterator<int> input, {
  required bool isUtf16,
}) {
  if (!input.moveNext()) return Iterable<Unicode>.empty().iterator;
  final (converter, decoder) = _wideUtfHelper(isUtf16);
  final peeked = input.current;
  final unread = Iterable.withIterator(() => input);
  return decoder(
    (peeked == 0xFFFE ? unread.map(converter) : [peeked].followedBy(unread))
        .iterator,
  );
}

/// Empty stub.
const Unicode empty = (span: 0, unicode: -1);

/// A callback that obtains the span from its iterator.
typedef Spanned<Iter extends Iterator<int>> = int Function(Iter iterator);

/// A [Unicode] iterator.
final class SpannedIterator<Iter extends Iterator<int>>
    implements Iterator<Unicode> {
  /// Creates a [SpannedIterator] from the [iterator].
  SpannedIterator.iterator(this.iterator, {required this.spanned});

  /// Creates a [SpannedIterator] with a fixed [span] for each code unit.
  ///
  /// This constructor should be called for an [iterator] whose code units
  /// have no surrogate pairs or each code unit contains a constant fixed size
  /// of surrogate pairs.
  SpannedIterator.fixed(int span, Iter iterator)
    : this.iterator(iterator, spanned: (_) => span);

  /// Obtains the number of surrogate code units present in the current unicode.
  final Spanned<Iter> spanned;

  /// Underlying iterator with code units.
  final Iter iterator;

  /// Current code unit with its span information.
  Unicode? _current;

  @override
  Unicode get current => _current ?? empty;

  @override
  bool moveNext() {
    if (!iterator.moveNext()) {
      _current = null;
      return false;
    }

    _current = (span: spanned(iterator), unicode: iterator.current);
    return true;
  }
}

/// Creates a [SpannedIterator] using the [string]'s [RuneIterator].
SpannedIterator<RuneIterator> unicodeFromString(String string) =>
    SpannedIterator.iterator(
      string.runes.iterator,
      spanned: (iterator) => iterator.currentSize,
    );
