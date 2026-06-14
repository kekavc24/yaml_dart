import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

/// A node's parsed property.
///
/// {@category custom_resolvers_intro}
sealed class ParsedProperty {
  ParsedProperty(
    RuneOffset start,
    RuneOffset end,
    this.indentOnExit, {
    required bool spanMultipleLines,
    required this.kind,
    this.structuralOffset,
  }) : assert(
         end.offset >= start.offset,
         'Invalid start and end offset to a [ParsedProperty]',
       ),
       span = (start: start, end: end),
       isMultiline = spanMultipleLines || end.lineIndex > start.lineIndex;

  factory ParsedProperty.empty(
    RuneOffset start,
    RuneOffset end,
    int? indentOnExit, {
    required bool spanMultipleLines,
    required RuneOffset? structuralOffset,
  }) = _Empty;

  /// Creates a wrapper that indicates the node's properties parsing call
  /// was just empty lines.
  factory ParsedProperty.of(
    RuneOffset? structuralOffset,
    RuneOffset start,
    RuneOffset end, {
    required bool spanMultipleLines,
    required int? indentOnExit,
    required String? anchor,
    required ResolvedTag? tag,
    required NodeKind kind,
    required CustomResolver<Object, Object?>? customResolver,
  }) {
    if (tag != null || anchor != null) {
      return NodeProperty(
        start,
        end,
        indentOnExit,
        spanMultipleLines: spanMultipleLines,
        anchor: anchor,
        tag: tag,
        kind: kind,
        customResolver: customResolver,
        structuralOffset: structuralOffset,
      );
    }

    return _Empty(
      start,
      end,
      indentOnExit,
      spanMultipleLines: spanMultipleLines,
      structuralOffset: structuralOffset,
    );
  }

  /// Actual offset of the node this property belongs to when it's preceded by a
  /// block sequence or explicit key/value indicator.
  final RuneOffset? structuralOffset;

  /// Start [RuneOffset] (inclusive) and an end [RuneOffset] (exclusive).
  final RuneSpan span;

  /// The current indent after all the properties have been parsed.
  ///
  /// Will always be `null` if [isMultiline] is `false` or no more characters
  /// can be parsed.
  final int? indentOnExit;

  /// Kind of node being parsed
  final NodeKind kind;

  /// Whether any `tag`, `anchor` or `alias` was parsed.
  bool get parsedAny;

  /// Whether this property is an alias.
  bool get isAlias => false;

  /// Whether the property spanned multiple lines.
  final bool isMultiline;
}

/// Empty node properties
final class _Empty extends ParsedProperty {
  _Empty(
    super.start,
    super.end,
    super.indentOnExit, {
    required super.spanMultipleLines,
    required super.structuralOffset,
  }) : super(kind: NodeKind.unknown());

  @override
  bool get parsedAny => false;
}

/// Node `anchor` and/or `tag`.
///
/// {@category custom_resolvers_intro}
final class NodeProperty extends ParsedProperty {
  NodeProperty(
    super.start,
    super.end,
    super.indentOnExit, {
    required super.spanMultipleLines,
    required this.anchor,
    required this.tag,
    required super.kind,
    required this.customResolver,
    super.structuralOffset,
  });

  /// Node's anchor.
  final String? anchor;

  /// Node's resolved tag.
  final ResolvedTag? tag;

  /// A custom resolver for a node.
  final CustomResolver<Object, Object?>? customResolver;

  @override
  bool get parsedAny => anchor != null || tag != null;
}

/// Node alias
final class Alias extends ParsedProperty {
  Alias(
    super.start,
    super.end,
    super.indentOnExit, {
    required super.spanMultipleLines,
    required this.alias,
    super.structuralOffset,
  }) : super(kind: NodeKind.unknown());

  /// Node being aliased
  final String alias;

  @override
  bool get parsedAny => true;

  @override
  bool get isAlias => true;
}

/// Whether the node with the [property] should be parsed as a generic `!!map`
/// or `!!seq` or `!!str`.
///
/// {@category custom_resolvers_intro}
bool isGenericNode(ParsedProperty? property) {
  if (property == null) return false;
  final kind = property.kind;

  return kind.isGeneric ||
      (property is NodeProperty && property.tag != null && !kind.isKnown);
}

typedef ConcreteProperty = ({
  ParserEvent event,
  ParsedProperty property,
});

/// Parses node properties of flow node if [isBlockContext] is `false`.
///
/// When [isBlockContext] is `true`, the function gladly checks if a duplicate
/// node property was declared on a new line. In such a case, this means that
/// the property may belong to a node other than current one.
///
/// The function always exits when the first non-whitespace char declared on a
/// new line has a lesser indent than [minIndent]. [onParseComment] adds
/// comments encountered when skipping to the next parsable char declared on a
/// new line.
ParsedProperty _corePropertyParser(
  SourceIterator iterator, {
  required int minIndent,
  required TagResolver resolver,
  required void Function(YamlComment comment) onParseComment,
  required bool isBlockContext,
  required RuneOffset? structuralOffset,
}) {
  final startOffset = iterator.currentLineInfo.current;

  var nodeKind = NodeKind.unknown();

  String? nodeAnchor;
  ResolvedTag? nodeTag;
  CustomResolver<Object, Object?>? nodeResolver;

  String? nodeAlias;
  int? indentOnExit;

  var lfCount = 0;

  bool isMultiline() => lfCount > 0;

  void skipAndTrackLF() {
    indentOnExit = skipToParsableChar(
      iterator,
      onParseComment: onParseComment,
      allowTabs: (currentIndent, _) {
        final isSeparation = currentIndent == null;
        return isBlockContext
            ? isSeparation
            : isSeparation || currentIndent >= minIndent;
      },
    );
    if (indentOnExit != null) ++lfCount;
  }

  void resetIndent() => indentOnExit = null;

  NodeProperty exitIfBlock(String error) {
    // Block node can have a lifeline in cases where a node spans multiple
    // lines. The properties may belong to a
    if (isBlockContext && indentOnExit != null) {
      return NodeProperty(
        startOffset,
        iterator.currentLineInfo.start,
        indentOnExit,
        spanMultipleLines: true, // Obviously :)
        anchor: nodeAnchor,
        tag: nodeTag,
        kind: nodeKind,
        customResolver: nodeResolver,
      );
    }

    throwWithRangedOffset(
      iterator,
      message: error,
      start: startOffset,
      end: iterator.currentLineInfo.current,
    );
  }

  // A node can only have:
  //   - Either a tag or anchor or both
  //   - Alias only
  //
  // The two options above are mutually exclusive.
  while (!iterator.isEOF && (nodeTag == null || nodeAnchor == null)) {
    switch (iterator.current) {
      case space || tab:
        {
          skipWhitespace(iterator, skipTabs: true); // Separation space
          iterator.nextChar();
        }

      case lineFeed || carriageReturn || comment:
        {
          skipAndTrackLF();

          final hasNoIndent = indentOnExit == null;

          if (hasNoIndent || indentOnExit! < minIndent) {
            final (:start, :current) = iterator.currentLineInfo;

            return ParsedProperty.of(
              structuralOffset,
              start,
              hasNoIndent ? current : start,
              spanMultipleLines: isMultiline(),
              indentOnExit: indentOnExit,
              anchor: nodeAnchor,
              tag: nodeTag,
              kind: nodeKind,
              customResolver: nodeResolver,
            );
          }
        }

      case tag:
        {
          if (nodeTag != null) {
            return exitIfBlock(
              'A node can only have a single tag property',
            );
          } else if (iterator.peekNextChar() == verbatimStart) {
            nodeTag = parseVerbatimTag(iterator);
          } else {
            final tagStart = iterator.currentLineInfo.current;
            final shorthand = parseTagShorthand(iterator);
            final (:kind, :tag, :customResolver) = resolver(
              tagStart,
              iterator.currentLineInfo.current,
              shorthand,
            );
            nodeKind = kind;
            nodeTag = tag;
            nodeResolver = customResolver;
          }

          resetIndent();
        }

      case anchor:
        {
          if (nodeAnchor != null) {
            return exitIfBlock('A node can only have a single anchor property');
          }

          iterator.nextChar();
          nodeAnchor = parseAnchorOrAliasTrailer(iterator);

          resetIndent();
        }

      case alias:
        {
          if (nodeTag != null || nodeAnchor != null) {
            return exitIfBlock(
              'Alias nodes cannot have an anchor or tag property',
            );
          }

          iterator.nextChar();
          nodeAlias = parseAnchorOrAliasTrailer(iterator);
          skipAndTrackLF();

          // Parsing an alias ignores any tag and anchor
          return Alias(
            startOffset,
            iterator.currentLineInfo.current,
            indentOnExit,
            alias: nodeAlias,
            spanMultipleLines: isMultiline(),
          );
        }

      // Exit immediately since we reached char that isn't a node property
      default:
        return ParsedProperty.of(
          structuralOffset,
          startOffset,
          indentOnExit != null && indentOnExit! < minIndent
              ? iterator.currentLineInfo.start
              : iterator.currentLineInfo.current,
          spanMultipleLines: isMultiline(),
          indentOnExit: indentOnExit,
          anchor: nodeAnchor,
          tag: nodeTag,
          kind: nodeKind,
          customResolver: nodeResolver,
        );
    }
  }

  // Prefer having accurate indent info. Parsing only reaches here if we
  // managed to parse both the tag and anchor.
  skipAndTrackLF();

  return ParsedProperty.of(
    structuralOffset,
    startOffset,
    indentOnExit != null && indentOnExit! < minIndent
        ? iterator.currentLineInfo.start
        : iterator.currentLineInfo.current,
    spanMultipleLines: isMultiline(),
    indentOnExit: indentOnExit,
    anchor: nodeAnchor,
    tag: nodeTag,
    kind: nodeKind,
    customResolver: nodeResolver,
  );
}

/// Parses node properties of a block node.
ConcreteProperty parseBlockProperties(
  SourceIterator iterator, {
  required int minIndent,
  required TagResolver resolver,
  required void Function(YamlComment comment) onParseComment,
  required RuneOffset? structuralOffset,
}) {
  final property = _corePropertyParser(
    iterator,
    minIndent: minIndent,
    resolver: resolver,
    onParseComment: onParseComment,
    isBlockContext: true,
    structuralOffset: structuralOffset,
  );

  return (property: property, event: inferBlockEvent(iterator));
}

/// Parses properties of a flow node and returns the next possible event after
/// all the properties have been parsed.
ConcreteProperty parseFlowProperties(
  SourceIterator iterator, {
  required int minIndent,
  required TagResolver resolver,
  required void Function(YamlComment comment) onParseComment,
  required bool lastKeyWasJsonLike,
  required RuneOffset? structuralOffset,
}) {
  void throwIfLessIndent(int? currentIndent) {
    if (currentIndent != null && currentIndent < minIndent) {
      throwWithApproximateRange(
        iterator,
        message:
            'Expected at least $minIndent space(s). '
            'Found $currentIndent space(s)',
        current: iterator.currentLineInfo.current,
        charCountBefore: currentIndent,
      );
    }
  }

  // Move to the next parsable non-ws char.
  // TODO: 50/50 with [nextSafeLineInFlow]. Test this.
  throwIfLessIndent(
    skipToParsableChar(iterator, onParseComment: onParseComment),
  );

  // We can exit immediately if the next event is not a node property event
  if (inferNextEvent(
        iterator,
        isBlockContext: false,
        lastKeyWasJsonLike: lastKeyWasJsonLike,
      )
      case ParserEvent e when e is! NodePropertyEvent) {
    final offset = iterator.currentLineInfo.current;

    return (
      event: e,
      property: ParsedProperty.empty(
        offset,
        offset,
        null,
        spanMultipleLines: false,
        structuralOffset: structuralOffset,
      ),
    );
  }

  final property = _corePropertyParser(
    iterator,
    minIndent: minIndent,
    resolver: resolver,
    onParseComment: onParseComment,
    isBlockContext: false,
    structuralOffset: structuralOffset,
  );

  // Flow nodes are lax with indent. Never allow less than min indent.
  throwIfLessIndent(property.indentOnExit);

  return (
    event: inferNextEvent(
      iterator,
      isBlockContext: false,
      lastKeyWasJsonLike: lastKeyWasJsonLike,
    ),
    property: property,
  );
}
