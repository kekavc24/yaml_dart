import 'dart:math';

import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/scalar_value.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Callback for creating a document with the current parser's information.
typedef DocumentBuilder<Doc, R> =
    Doc Function(
      ParsedDirectives directives,
      DocumentInfo documentInfo,
      RootNode<R> rootNode,
    );

typedef GreedyPlain = ({RuneOffset start, String greedChars});

typedef _OnDocStart = void Function(int document);

const rootIndentLevel = seamlessIndentMarker + 1;

/// Throws an exception if the prospective `YamlSourceNode`
/// (a child of the root node or the root node itself) in the document being
/// parsed did not have an explicit directives end marker (`---`) or the
/// directives end marker (`---`) is present but no directives were parsed.
///
/// This method is only works for [ScalarStyle.plain]. Any other style is safe.
void _throwIfBlockUnsafe(
  SourceIterator iterator, {
  required int indent,
  required bool hasDirectives,
  required bool inlineWithDirectiveMarker,
}) {
  if (iterator.current == directive && indent == 0 && !hasDirectives) {
    throwWithSingleOffset(
      iterator,
      message:
          '"%" cannot be used as the first non-whitespace character in a'
          ' non-empty content line',
      offset: iterator.currentLineInfo.current,
    );
  } else if (inlineWithDirectiveMarker &&
      inferBlockEvent(iterator) is BlockCollectionEvent) {
    throwForCurrentLine(
      iterator,
      message:
          'A block collection cannot be declared on the same line as a'
          ' directive end marker',
    );
  }
}

/// A `YamlDocument` parser.
///
/// [Doc] represents the type for all documents to be parsed and [R] represents
/// a type for all nodes that will be parsed.
final class DocumentParser<Doc, R> {
  /// Creates a forward-parsing document parser that emits a document of type
  /// [Doc] which has nodes of type [R] or a subtype of [R]. Calling
  /// `this.parseNext()` parses a single [Doc] from the [iterator].
  ///
  /// The document [builder] constructs a [Doc] from the information collected
  /// after parsing a full YAML document. The [collectionFunction] is used to
  /// construct a YAML list/map whereas the [scalarFunction] is reserved for
  /// scalars. Any aliases are constructed with the [aliasFunction].
  /// [onMapDuplicate] will always be called when a duplicate key is
  /// encountered and contains the key's start and end offset.
  ///
  /// [triggers] can be used to provide specialized callbacks to some parser
  /// actions that may be used to track the parser's state or provide resolvers
  /// for these actions.
  ///
  /// A custom logging function may be provided via the [logger].
  DocumentParser(
    SourceIterator iterator, {
    required AliasFunction<R> aliasFunction,
    required YamlCollectionBuilder<R> collectionFunction,
    required ScalarFunction<R> scalarFunction,
    required ParserLogger logger,
    required MapDuplicateHandler onMapDuplicate,
    required this.builder,
    CustomTriggers? triggers,
  }) : _state = ParserState<R>(
         iterator,
         aliasFunction: aliasFunction,
         collectionBuilder: collectionFunction,
         scalarFunction: scalarFunction,
         logger: logger,
         onMapDuplicate: onMapDuplicate,
         triggers: triggers,
       ),
       _onDocReset = triggers?.onDocumentStart ?? ((_) {});

  /// Constructs the document after the node has been parsed completely.
  final DocumentBuilder<Doc, R> builder;

  /// The internal parser's state.
  final ParserState<R> _state;

  /// Called when a new document's parsing begins.
  final _OnDocStart _onDocReset;

  /// Parses the next [Doc] if present in the YAML string.
  ///
  /// `NOTE:` This advances the parsing forward and holds no reference to a
  /// previously parsed [Doc].
  (bool didParse, Doc? parsed) parseNext() {
    if ((_state..reset()).isEOF()) return _emptyDoc();

    final ParserState(:iterator, :onParseComment, :logger) = _state;
    iterator.allowBOM(true);
    _onDocReset(_state.current);

    final docStartOffset = _state.docStart();

    YamlDirective? version;
    var tags = <TagHandle, GlobalTag>{};
    var reserved = <ReservedDirective>[];

    var rootIndent = skipToParsableChar(
      iterator,
      onParseComment: onParseComment,
      leadingAsIndent: !_state.docStartExplicit,
      isRoot: true,
    );

    iterator.skipBOM();
    var isInlineWithMarker = false; // In directive end '---' line

    final plain = _processDocDirectives(
      iterator,
      rootIndent: rootIndent,
      logger: logger,
      onComment: onParseComment,
      onDirectives: (yamlVersion, globalTags, unknown) {
        version = yamlVersion;
        tags = globalTags;
        reserved = unknown;
      },
      ifDocInDocStart: (rootInDirectiveLine) {
        rootIndent = null;
        isInlineWithMarker = rootInDirectiveLine;
      },
    );

    // Why block info? The doc end chars "..." and "---" exist in this format.
    BlockNode<R> rootBlockNode;

    // If we attempted to check for doc markers and found none
    if (plain != null) {
      rootBlockNode = parseBlockScalar(
        _state,
        event: ScalarEvent.startFlowPlain,
        blockParentIndent: null,
        minIndent: 0,
        indentLevel: rootIndentLevel,
        isImplicit: false,
        composeImplicitMap: true,
        composedMapIndent: 0,
        greedyOnPlain: plain.greedChars,
        start: plain.start,
        scalarProperty: null,
      );
    } else {
      rootIndent ??= skipToParsableChar(
        iterator,
        onParseComment: onParseComment,
        leadingAsIndent: !isInlineWithMarker,
        isRoot: true,
      );

      _throwIfBlockUnsafe(
        iterator,
        indent: rootIndent ?? 0,
        hasDirectives: _state.hasDirectives,
        inlineWithDirectiveMarker: isInlineWithMarker,
      );

      rootBlockNode = parseBlockNode(
        _state,
        blockParentIndent: null, // No parent
        inferredFromParent: rootIndent,
        indentLevel: rootIndentLevel,
        laxBlockIndent: 0,
        fixedInlineIndent: 0,
        forceInlined: false,
        composeImplicitMap: !isInlineWithMarker,
        canComposeMapIfMultiline: true,
      );
    }

    final (:blockInfo, :node) = rootBlockNode;

    _terminateDoc(
      iterator,
      docEnd: blockInfo.docMarker,
      onComment: onParseComment,
      onDocEnd: (end) => node.nodeSpan.parsingEnd = end,
    );

    return (
      true,
      builder(
        (version: version, tags: tags.values, unknown: reserved),
        (
          index: _state.current,
          start: docStartOffset,
          docType: YamlDocType.inferType(
            hasDirectives: _state.hasDirectives,
            isDocStartExplicit: _state.docStartExplicit,
          ),
          hasExplicitStart: _state.docStartExplicit,
          hasExplicitEnd: _state.docEndExplicit,
        ),
        (root: node.parsed(), anchors: _state.anchorNodes),
      ),
    );
  }
}

typedef _PushDirectives =
    void Function(
      YamlDirective? yamlVersion,
      Map<TagHandle, GlobalTag> globalTags,
      List<ReservedDirective> unknown,
    );

extension<Doc, R> on DocumentParser<Doc, R> {
  /// Processes the document [Directives] if any are present.
  GreedyPlain? _processDocDirectives(
    SourceIterator iterator, {
    required int? rootIndent,
    required ParserLogger logger,
    required void Function(YamlComment comment) onComment,
    required _PushDirectives onDirectives,
    required void Function(bool rootInDirectiveLine) ifDocInDocStart,
  }) {
    if (_state.docStartExplicit || (rootIndent != null && rootIndent > 0)) {
      return null;
    }

    final (
      :yamlDirective,
      :globalTags,
      :reservedDirectives,
      :hasDirectiveEnd,
    ) = parseDirectives(
      iterator,
      onParseComment: onComment,
      warningLogger: (message) => logger(false, message),
    );

    onDirectives(yamlDirective, globalTags, reservedDirectives);

    _state.hasDirectives =
        yamlDirective != null ||
        globalTags.isNotEmpty ||
        reservedDirectives.isNotEmpty;

    _state.globalTags.addAll(globalTags);

    // When directives are absent, we may see dangling "---". Just to be sure,
    // confirm this wasn't the case.
    if (!hasDirectiveEnd) {
      if (iterator.current != blockSequenceEntry ||
          iterator.peekNextChar() != blockSequenceEntry) {
        return null;
      }

      final startOnMissing = iterator.currentLineInfo.current;
      var greedy = 0;

      final marker = checkForDocumentMarkers(
        iterator,
        onMissing: null,
        writer: (_) => ++greedy,
      );

      if (marker != DocumentMarker.directiveEnd) {
        return (greedChars: '-' * greedy, start: startOnMissing);
      }
    }

    // Fast forward to the first ns-char (line break excluded)
    if (iterator.current.isWhiteSpace()) {
      skipWhitespace(iterator, skipTabs: true);
      iterator.nextChar();
    }

    final char = iterator.current;
    ifDocInDocStart(char != comment && !char.isLineBreak());
    _state.docStartExplicit = true;
    return null;
  }

  /// Terminates the current document.
  void _terminateDoc(
    SourceIterator iterator, {
    required DocumentMarker docEnd,
    required void Function(YamlComment comment) onComment,
    required void Function(RuneOffset end) onDocEnd,
  }) {
    if (iterator.isEOF || docEnd.stopIfParsingDoc) {
      _state.updateDocEndChars(docEnd);
      return;
    }

    // We must see document end chars and don't care how they are laid within
    // the document. At this point the document is or should be complete
    skipToParsableChar(iterator, onParseComment: onComment);

    if (iterator.isEOF) {
      onDocEnd(iterator.currentLineInfo.current);
      _state.lastDocEndChars = '';
      return;
    }

    final marker = checkForDocumentMarkers(
      iterator,
      onMissing: null,
      throwIfDocEndInvalid: true,
    );

    if (marker.stopIfParsingDoc) {
      onDocEnd(iterator.currentLineInfo.start);
      _state.updateDocEndChars(marker);
      return;
    }

    throwForCurrentLine(
      iterator,
      message:
          'Invalid node state. Expected to find document end "..."'
          ' or directive end chars "---" ',
    );
  }

  /// Infers the state of the empty document.
  (bool didParse, Doc? emptyDoc) _emptyDoc() {
    // No document if no directive end chars '---' were present.
    if (!_state.docStartExplicit) return (false, null);

    _state.updateDocEndChars(DocumentMarker.none);

    return (
      true,
      builder(
        (version: null, tags: Iterable.empty(), unknown: const []),
        (
          index: _state.current,
          start: _state.docStart(),
          docType: YamlDocType.explicit,
          hasExplicitStart: true,
          hasExplicitEnd: false,
        ),
        (
          root: _state.scalarFunction(
            NullView(''),
            ScalarStyle.plain,
            null,
            null,
            YamlSourceSpan(_state.iterator.currentLineInfo.current),
          ),
          anchors: {},
        ),
      ),
    );
  }
}
