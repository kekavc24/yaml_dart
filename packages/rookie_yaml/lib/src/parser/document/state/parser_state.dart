import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/schema.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// A callback for handling map duplicates
typedef MapDuplicateHandler =
    void Function(RuneOffset keyStart, RuneOffset keyEnd, String message);

/// Logger callback
typedef ParserLogger = void Function(bool isInfo, String message);

/// [ResolvedTag] and the [NodeKind] represented by the tag.
typedef OnTagResolved = ({
  ResolvedTag tag,
  NodeKind kind,
  CustomResolver<Object, Object?>? customResolver,
});

/// A tag resolver callback
typedef TagResolver =
    OnTagResolved Function(RuneOffset start, RuneOffset end, TagShorthand tag);

typedef _OnCustomResolver =
    CustomResolver<Object, Object?>? Function(TagShorthand localTag);

typedef _OnScalarResolver<R> =
    ResolverCreator<R>? Function(TagShorthand localTag);

typedef OnMapKey = void Function(Object? key);

typedef _OnDefaultSeq<S> = ObjectFromIterable<S, S>? Function();

typedef _OnDefaultMap<M> = ObjectFromMap<M, M, M>? Function();

typedef OnDefaultScalar<S> = ObjectFromScalarBytes<S>? Function();

/// Just a null-ish helper.
R? _nullish<R>() => null;

/// Holds the document parser's top level state
final class ParserState<R> {
  ParserState(
    this.iterator, {
    required this.aliasFunction,
    required this.collectionBuilder,
    required this.scalarFunction,
    required this.logger,
    required this.onMapDuplicate,
    required CustomTriggers? triggers,
  }) : _onCustomResolver = triggers?.onCustomResolver ?? ((_) => null),
       _onScalarResolver = triggers?.onScalarResolver ?? ((_) => null),
       onParseComment = triggers?.onParseComment ?? ((_) {}),
       onParseMapKey = triggers?.onParsedKey ?? ((_) {}),
       _defaultMap = triggers?.onDefaultMapping ?? _nullish,
       _defaultSequence = triggers?.onDefaultSequence ?? _nullish,
       defaultScalar = triggers?.onDefaultScalar ?? _nullish;

  /// Byte iterator.
  final SourceIterator iterator;

  /// Alias builder
  final AliasFunction<R> aliasFunction;

  /// Sequence & Map builder
  final YamlCollectionBuilder<R> collectionBuilder;

  /// Scalar builder
  final ScalarFunction<R> scalarFunction;

  /// Callback for binding a local tag to a custom resolver.
  final _OnCustomResolver _onCustomResolver;

  /// Callback for binding a local tag to a custom scalar resolver.
  final _OnScalarResolver _onScalarResolver;

  /// Called when a [YamlComment] has been parsed.
  final void Function(YamlComment comment) onParseComment;

  /// Callback once a valid map key has been parsed completely
  final OnMapKey onParseMapKey;

  /// Callback for creating a default sequence delegate.
  final _OnDefaultSeq<R> _defaultSequence;

  /// Callback for creating a default mapping delegate.
  final _OnDefaultMap<R> _defaultMap;

  /// Callback for creating a default scalar delegate.
  final OnDefaultScalar<R> defaultScalar;

  /// Logging function for warnings and info
  final ParserLogger logger;

  /// Callback used to report keys that are duplicates in flow/block maps
  final MapDuplicateHandler onMapDuplicate;

  /// Global directives.
  ///
  /// Secondary tag always resolves
  var globalTags = {yamlGlobalTag.tagHandle: yamlGlobalTag};

  /// Index of document being parsed
  int _currentIndex = -1;

  /// Index of document being parsed
  int get current => _currentIndex;

  /// Char sequence that terminated the last document.
  ///
  /// If `...`, the parser looks for directives first before parsing can
  /// start until an explicit `---` is encountered. Throws an error otherwise.
  ///
  /// If `---`, the parser starts parsing nodes immediately. This also limits
  /// the use of `%` as the first character for plain style-like nodes, that is,
  /// [ScalarStyle.plain], [ScalarStyle.literal] and [ScalarStyle.folded]. The
  /// character cannot be used if the indent level is `0`.
  String lastDocEndChars = '';

  /// Tracks if the current document has an explicit start.
  ///
  /// End of directives. `---` at beginning.
  bool docStartExplicit = false;

  /// Tracks if last document had an explicit end.
  ///
  /// `...` at the end.
  bool docEndExplicit = false;

  /// Tracks whether any directives were declared
  bool hasDirectives = false;

  /// Tracks anchors that can be used as aliases
  var anchorNodes = <String, R>{};

  /// Start offset of the current document. Always updated after a document
  /// has been passed to completion.
  RuneOffset? _nextDocStart;

  /// Whether the next document has any bytes.
  bool isEOF() => iterator.isEOF;

  RuneOffset docStart() => _nextDocStart ??= iterator.currentLineInfo.current;

  /// Tracks the object [R] generated by the [object] if [property] is not null
  /// and its anchor is present.
  T trackAnchor<T extends NodeDelegate>(T object, ParsedProperty? property) {
    object.updateNodeProperties = property;

    if (property case NodeProperty(:final String anchor)) {
      anchorNodes[anchor] = object.parsed();
    }

    return object;
  }

  /// Returns an [AliasDelegate] if [alias] has a corresponding anchor.
  /// Otherwise, throws.
  AliasDelegate<R> referenceAlias(
    Alias property, {
    required int indentLevel,
    required int indent,
  }) {
    final Alias(:alias, :span) = property;

    if (anchorNodes.containsKey(alias)) {
      return AliasDelegate<R>(
        anchorNodes[alias] as R,
        refResolver: aliasFunction,
        indentLevel: indentLevel,
        indent: indent,
        start: span.end,
      );
    }

    throwWithRangedOffset(
      iterator,
      message: 'Alias is not a valid anchor reference',
      start: span.start,
      end: span.end,
    );
  }

  /// Resets the parser's internal state variables before a new [YamlDocument]
  /// is parsed.
  void reset() {
    ++_currentIndex; // Move to next document

    if (_currentIndex == 0) return;

    hasDirectives = false;
    docStartExplicit = lastDocEndChars == '---';
    docEndExplicit = false;

    globalTags = {yamlGlobalTag.tagHandle: yamlGlobalTag};
    anchorNodes = {};
  }

  /// Tracks the [marker] information after a [YamlDocument] has been
  /// completely parsed.
  void updateDocEndChars(DocumentMarker marker) {
    lastDocEndChars = marker.indicator;
    docEndExplicit = marker == DocumentMarker.documentEnd;

    final lineInfo = iterator.currentLineInfo;

    if (!docEndExplicit) {
      // Directive end chars are part of the next document.
      _nextDocStart = iterator.isEOF ? lineInfo.current : lineInfo.start;
      return;
    }

    _nextDocStart = lineInfo.current;
    final char = iterator.current;

    if (char == comment || char.isWhiteSpace() || char.isLineBreak()) {
      iterator.allowBOM(true);
      skipToParsableChar(iterator, onParseComment: onParseComment);
    }
  }

  /// Resolves a [localTag] to a [GlobalTag] uri if present.
  OnTagResolved resolveTag(
    RuneOffset start,
    RuneOffset end,
    TagShorthand localTag,
  ) {
    final TagShorthand(:tagHandle, :content) = localTag;

    SpecificTag prefix = localTag;
    TagShorthand? suffix; // Local tags have no suffixes

    // Check if alias to global tag
    final globalTag = globalTags[tagHandle];
    final hasGlobalTag = globalTag != null;

    switch (tagHandle.handleVariant) {
      // All named tags must have a corresponding global tag
      case TagHandleVariant.named:
        {
          if (!hasGlobalTag) {
            throwWithRangedOffset(
              iterator,
              start: start,
              end: end,
              message: 'Named tags must have a corresponding global tag',
            );
          } else if (content.isEmpty) {
            throwWithRangedOffset(
              iterator,
              start: start,
              end: end,
              message: 'Named tags must have a non-empty suffix',
            );
          }

          continue resolver;
        }

      // Secondary tags limited to tags only supported by YAML
      // TODO: Throw for yaml tag only
      case TagHandleVariant.secondary when !isYamlTag(localTag):
        throwWithRangedOffset(
          iterator,
          message:
              'Invalid secondary tag. Expected any of: '
              '$mappingTag, $orderedMappingTag, '
              '$sequenceTag, $setTag, '
              '$stringTag, $nullTag, $booleanTag, $integerTag or $floatTag',
          start: start,
          end: end,
        );

      resolver:
      default:
        {
          if (hasGlobalTag) {
            prefix = globalTag;
            suffix = localTag; // Local tag is prefixed with global tag uri
          }
        }
    }

    NodeKind? kind;
    CustomResolver<Object, Object?>? customResolver;
    ResolvedTag nodeTag = NodeTag(prefix, suffix: suffix, isGeneric: false);

    // A local tag cannot be treated as both a custom resolver and a scalar
    // resolver. Give preference to a custom resolver. This conveniently
    // allows non-specific tags to be captured for custom resolution before
    // they are dropped.
    if (_onCustomResolver(localTag)
        case CustomResolver<Object, Object?> resolver) {
      kind = resolver.kind;
      customResolver = resolver;
    } else if (_onScalarResolver(localTag)
        case ResolverCreator<Object?> function) {
      nodeTag = function(nodeTag as NodeTag);
      kind = YamlScalarKind.stringToType;
    }

    return (
      kind:
          kind ??
          switch (localTag.toString()) {
            '!!map' => YamlCollectionKind.mapping,
            '!!omap' => YamlCollectionKind.orderedMap,
            '!!seq' => YamlCollectionKind.sequence,
            '!!set' => YamlCollectionKind.set,
            '!!str' => YamlScalarKind.string,
            '!!null' => YamlScalarKind.nullString,
            '!!bool' => YamlScalarKind.booleanString,
            '!!int' => YamlScalarKind.integer,
            '!!float' => YamlScalarKind.float,
            _ when !hasGlobalTag && localTag.isNonSpecific =>
              NodeKind.generic(),
            _ => NodeKind.unknown(),
          },
      tag: nodeTag,
      customResolver: customResolver,
    );
  }

  /// Creates a generic map delegate.
  MapLikeDelegate<R, R, R> defaultMapDelegate({
    required NodeStyle mapStyle,
    required int indentLevel,
    required int indent,
    NodeSpan? keySpan,
    RuneOffset? start,
  }) {
    final mapStart =
        start ??
        keySpan!.structuralOffset ??
        keySpan!.propertySpan?.start ??
        keySpan!.nodeStart;

    return switch (_defaultMap()) {
      ObjectFromMap<R, R, R> customMap => MapLikeDelegate.boxed(
        customMap.onCustomMap(),
        collectionStyle: mapStyle,
        indentLevel: indentLevel,
        indent: indent,
        start: mapStart,
        afterMapping: customMap.afterObject<R>(),
      ),
      _ => GenericMap(
        collectionStyle: mapStyle,
        indentLevel: indentLevel,
        indent: indent,
        start: mapStart,
        mapResolver: collectionBuilder,
      ),
    };
  }

  /// Creates a generic sequence delegate.
  SequenceLikeDelegate<R, R> defaultSequenceDelegate({
    required NodeStyle style,
    required int indent,
    required int indentLevel,
    required RuneOffset start,
    NodeKind kind = YamlCollectionKind.sequence,
  }) => switch (_defaultSequence()) {
    ObjectFromIterable<R, R> customList => SequenceLikeDelegate.boxed(
      customList.onCustomIterable(),
      collectionStyle: style,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
      afterSequence: customList.afterObject<R>(),
    ),
    _ => GenericSequence.byKind(
      style: style,
      indent: indent,
      indentLevel: indentLevel,
      start: start,
      resolver: collectionBuilder,
      kind: kind,
    ),
  };
}
