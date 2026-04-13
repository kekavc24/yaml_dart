import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';

/// A event that controls the `DocumentParser`'s next parse action
abstract interface class ParserEvent {
  /// Returns `true` if the `DocumentParser` is parsing a `YamlSourceNode` with
  /// [NodeStyle.flow] styling.
  bool get isFlowContext;
}

/// An event that triggers parsing of a `Scalar`
enum ScalarEvent implements ParserEvent {
  /// Parse a scalar with [ScalarStyle.literal]
  startBlockLiteral(isFlowContext: false),

  /// Parse a scalar with [ScalarStyle.folded]
  startBlockFolded(isFlowContext: false),

  /// Parse a scalar with [ScalarStyle.plain]
  startFlowPlain(isFlowContext: true),

  /// Parse a scalar with [ScalarStyle.doubleQuoted]
  startFlowDoubleQuoted(isFlowContext: true),

  /// Parse a scalar with [ScalarStyle.singleQuoted]
  startFlowSingleQuoted(isFlowContext: true);

  const ScalarEvent({required this.isFlowContext});

  @override
  final bool isFlowContext;
}

/// An event that trigger the parsing of a `YamlSourceNode`'s properties
enum NodePropertyEvent implements ParserEvent {
  /// Parse a local tag
  startTag,

  /// Parse a verbatim tag
  startVerbatimTag,

  /// Parse an anchor
  startAnchor,

  /// Parse an alias
  startAlias;

  @override
  bool get isFlowContext => throw UnsupportedError(
    'A node property should not be detected when parsing nodes!',
  );
}

/// An event that triggers parsing of a `YamlSourceNode` with [NodeStyle.block]
/// styling.
enum BlockCollectionEvent implements ParserEvent {
  /// Parse a block list
  startBlockListEntry,

  /// Parse a block map beginning with an explicit key
  startExplicitKey,

  /// Parse a block map value
  startEntryValue;

  @override
  bool get isFlowContext => false;
}

/// An event that triggers parsing of a `YamlSourceNode` with [NodeStyle.flow]
/// styling
enum FlowCollectionEvent implements ParserEvent {
  /// Parse a flow map
  startFlowMap,

  /// Parse an explicit flow map (entry) key
  startExplicitKey,

  /// Parse a flow map (entry) value
  startEntryValue,

  /// End flow map parsing
  endFlowMap,

  /// Parse flow sequence
  startFlowSequence,

  /// End flow sequence parsing
  endFlowSequence,

  /// End of a flow collection entry parsing and beginning of a new one.
  nextFlowEntry;

  @override
  bool get isFlowContext => true;
}

ScalarEvent _expectNsCharAfter(SourceIterator iterator, int? charAfter) {
  if (charAfter.isNotNullAnd((e) => e.isNonSpaceChar())) {
    return ScalarEvent.startFlowPlain;
  }

  throwWithSingleOffset(
    iterator,
    message:
        '"${iterator.current.asString()}" must be followed by a non-space '
        'character when used as the first char of plain scalar.',
    offset: iterator.currentLineInfo.current,
  );
}

/// Infers a generalized [ParserEvent] that determines how the [DocumentParser]
/// should parse the next collection of characters.
ParserEvent inferNextEvent(
  SourceIterator iterator, {
  required bool isBlockContext,
  required bool lastKeyWasJsonLike,
}) {
  final charAfter = iterator.peekNextChar();

  // Can be allowed after map like indicator such as:
  //   - "?" -> an explicit key indicator
  //   - ":" -> indicates start of a value
  final canBeSeparation = charAfter.isNullOr(
    (c) => c.isWhiteSpace() || c.isLineBreak(),
  );

  switch (iterator.current) {
    case doubleQuote:
      return ScalarEvent.startFlowDoubleQuoted;

    case singleQuote:
      return ScalarEvent.startFlowSingleQuoted;

    // |
    case literal:
      return ScalarEvent.startBlockLiteral;

    // >
    case folded:
      return ScalarEvent.startBlockFolded;

    case flowSequenceStart:
      return FlowCollectionEvent.startFlowSequence;
    case flowSequenceEnd:
      return FlowCollectionEvent.endFlowSequence;
    case flowEntryEnd:
      return FlowCollectionEvent.nextFlowEntry;
    case mappingStart:
      return FlowCollectionEvent.startFlowMap;
    case mappingEnd:
      return FlowCollectionEvent.endFlowMap;

    case anchor:
      return NodePropertyEvent.startAnchor;
    case alias:
      return NodePropertyEvent.startAlias;
    case tag:
      return charAfter == verbatimStart
          ? NodePropertyEvent.startVerbatimTag
          : NodePropertyEvent.startTag;

    case mappingValue:
      {
        // key: value
        if (canBeSeparation) {
          return isBlockContext
              ? BlockCollectionEvent.startEntryValue
              : FlowCollectionEvent.startEntryValue;
        } else if (!isBlockContext &&
            (lastKeyWasJsonLike ||
                charAfter.isNotNullAnd((c) => c.isFlowDelimiter()))) {
          // JSON-like structures can omit the space.
          return FlowCollectionEvent.startEntryValue;
        }

        return _expectNsCharAfter(iterator, charAfter);
      }

    case blockSequenceEntry:
      {
        if (isBlockContext) {
          return canBeSeparation
              ? BlockCollectionEvent.startBlockListEntry
              : _expectNsCharAfter(iterator, charAfter);
        } else if (charAfter.isNotNullAnd(
          (e) => !e.isFlowDelimiter() && e.isNonSpaceChar(),
        )) {
          // ns-plain-safe-in
          return ScalarEvent.startFlowPlain;
        }

        // This character is not allow in a flow context.
        throwWithSingleOffset(
          iterator,
          message: '"-" cannot be used in a flow context.',
          offset: iterator.currentLineInfo.current,
        );
      }

    // ?
    case mappingKey:
      {
        if (canBeSeparation) {
          return isBlockContext
              ? BlockCollectionEvent.startExplicitKey
              : FlowCollectionEvent.startExplicitKey;
        } else if (!isBlockContext &&
            charAfter.isNotNullAnd((c) => c.isFlowDelimiter())) {
          return FlowCollectionEvent.startExplicitKey;
        }

        return _expectNsCharAfter(iterator, charAfter);
      }

    default:
      return ScalarEvent.startFlowPlain;
  }
}

/// Infers the next block event.
ParserEvent inferBlockEvent(SourceIterator iterator) => inferNextEvent(
  iterator,
  isBlockContext: true,
  lastKeyWasJsonLike: false,
);
