import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// A non-existent indent level for block(-like) scalars (`plain`, `literal`,
/// `folded`) that are affected by indent changes. Indicates that the said
/// scalar was parsed successfully without an indent change.
const seamlessIndentMarker = -2;

/// Callback for writing utf code units from a [SourceIterator].
///
/// {@category bytes_to_scalar}
typedef CharWriter = void Function(int char);

/// Contains all parsed [Directive]s of a document.
typedef ParsedDirectives = ({
  YamlDirective? version,
  Iterable<GlobalTag> tags,
  List<ReservedDirective> unknown,
});

/// Contains information about a document's position in the YAML bytes/string
/// and its type.
typedef DocumentInfo = ({
  int index,
  RuneOffset start,
  YamlDocType docType,
  bool hasExplicitStart,
  bool hasExplicitEnd,
});

/// Contains information about the document's root yaml node and any comments
/// parsed within the document. YAML spec bluntly states that a comment should
/// not be associated with a node.
typedef RootNode<T> = ({T root, Map<String, T> anchors});

/// Emits all externally [buffered] utf code units to a [writer].
void bufferHelper(Iterable<int> buffered, CharWriter writer) {
  for (final char in buffered) {
    writer(char);
  }
}

/// Scalar info from a low level scalar parse function.
typedef ParsedScalarInfo = ({
  /// `Scalar`'s scalarstyle
  ScalarStyle scalarStyle,

  /// Fixed indent used to parse the scalar.
  ///
  /// It should be noted that the indent for a flow scalar
  /// ([ScalarStyle.doubleQuoted], [ScalarStyle.singleQuoted]
  /// and [ScalarStyle.plain]) may be an approximate indent since indent serves
  /// no purpose in a flow scalar. Ergo, this [scalarIndent] may refer to the
  /// minimum indent used to determine its structure if its parent flow
  /// collection (`Sequence` or `Mapping`) is nested within a collection
  ///
  /// If the scalar is a direct child of a block key or block list then its
  /// indent is fixed based on the parent. However, for [ScalarStyle.folded]
  /// and [ScalarStyle.literal], this indent may be greater than that suggested
  /// by the parent since YAML allows block scalars to define their own
  /// indentation using the indentation indicator (`+`) in the block header.
  /// Additionally, YAML recommends the parser to infer the indent based
  /// on the first non-empty line's indentatio. This indent can be end up being
  /// equal to or greater than the indent recommended by the parent.
  int scalarIndent,

  /// Document marker type encountered
  DocumentMarker docMarkerType,

  /// Indicates whether any linebreak was ever seen while parsing.
  ///
  /// `NOTE`: This is a helper to prevent a redundant scan on the
  /// [parsedContent] as the line break may have already been seen while parsing
  /// the content and folded
  bool hasLineBreak,

  /// Always `true` for block(-like) styles, that is, `plain`, `literal` and
  /// `folded` if an indent change triggered the end of its parsing
  bool indentDidChange,

  /// Indent after complete parsing of the scalar. This will usually
  /// default to `-2` for quoted styles.
  ///
  /// Block(-like) styles, that is, `plain`, `literal` and `folded`, that rely
  /// on indentation to convey content may provide a different value when
  /// [indentDidChange] is `true`.
  int indentOnExit,

  /// End offset of the scalar (exclusive)
  RuneOffset end,
});

/// Precursor of an actual scalar before the top level parser resolves it.
/// However, this object may never be instantiated if the scalar has a custom
/// resolver.
typedef PreScalar = ({
  /// Buffered content
  String content,

  /// Scalar's info
  ParsedScalarInfo scalarInfo,

  /// Indicates if the actual formatted content itself has a line break.
  ///
  /// Do not confuse this with `hasLineBreak`. Some scalars fold line breaks
  /// which are never written to the buffer. Specifically,
  /// [ScalarStyle.doubleQuoted] allow line breaks to be escaped. In this case,
  /// the string may be concantenated without ever folding the line break to a
  /// space. This information may be crucial to how we infer the kind
  /// (Dart type) since most (, if not all,) types are inline.
  bool wroteLineBreak,
});

/// Single char for document end marker, `...`
const docEndSingle = period;

/// Single char for directives end marker, `---`
const directiveEndSingle = blockSequenceEntry;

typedef _Writer = void Function(int char);
typedef _OnBuffered = void Function();

(_Writer writer, _OnBuffered onBuffered) _docMarkerHelper({
  required void Function(List<int> buffered) onMissing,
  required void Function(int char)? writer,
}) {
  if (writer != null) return (writer, () {});
  final buffer = <int>[];
  return (buffer.add, () => onMissing(buffer));
}

/// Checks and returns if the next sequence of characters are valid
/// [DocumentMarker]. Defaults to [DocumentMarker.none] if not true.
/// May throw if non-whitespace characters are declared in the same line as
/// document end markers (`...`).
///
/// Various parse functions maintain a buffer that may (not) accept characters.
/// Each parse function can plug a callback to this check depending the
/// sensitivity of its buffer. [onMissing] and [writer] are mutually exclusive.
///
/// Parse functions that provide [onMissing] usually maintain a buffer that
/// contains meaningful content which cannot be tainted if we parse any
/// document markers but can accept these characters if no document markers
/// are seen. Under the hood, this function buffers these characters and hands
/// them back to the function if no document markers are seen.
///
/// If [writer] is provided, this function assumes that the caller will handle
/// the characters as they come and never buffers the character on their
/// behalf.
DocumentMarker checkForDocumentMarkers(
  SourceIterator iterator, {
  bool throwIfDocEndInvalid = false,
  required void Function(List<int> buffered)? onMissing,
  void Function(int char)? writer,
}) {
  final (writeOnChar, onBufferred) = _docMarkerHelper(
    onMissing: onMissing ?? (_) {},
    writer: writer,
  );

  // Document markers, that `...` and `---` have no indent. They must be
  // top level. Check before falling back to checking if it is a top level
  // scalar.
  //
  // We insist on it being top level because the markers have no indent
  // before. They have a -1 indent at this point or zero depending on how
  // far along the parsing this is called.
  if (iterator.current case docEndSingle || directiveEndSingle) {
    const expectedCount = 3;
    final match = iterator.current;

    final skipped = takeFromIteratorUntil(
      iterator,
      includeCharAtCursor: true,
      mapper: (v) => v,
      onMapped: writeOnChar,
      stopIf: (count, possibleNext) {
        return count == expectedCount || possibleNext != match;
      },
    );

    iterator.nextChar();

    if (skipped == expectedCount) {
      // YAML insists document markers should not have any characters
      // after unless its just whitespace or comments.
      if (match == docEndSingle) {
        if (!iterator.isEOF && iterator.current.isWhiteSpace()) {
          skipWhitespace(iterator, skipTabs: true);
          iterator.nextChar();
        }

        if (iterator.isEOF ||
            iterator.current == comment ||
            iterator.current.isLineBreak()) {
          return DocumentMarker.documentEnd;
        } else if (!throwIfDocEndInvalid) {
          onBufferred();
          return DocumentMarker.none;
        }

        final (:start, :current) = iterator.currentLineInfo;

        throwWithRangedOffset(
          iterator,
          message:
              'Document end markers "..." can only have whitespace/comments'
              ' after',
          start: start,
          end: current,
        );
      }

      if (iterator.isEOF ||
          iterator.current.isLineBreak() ||
          iterator.current.isWhiteSpace() ||
          iterator.current.isByteOrderMark()) {
        return DocumentMarker.directiveEnd;
      }
    }
  }

  onBufferred();
  return DocumentMarker.none;
}

/// Skips any comments and linebreaks until a character that can be parsed
/// is encountered. Returns `null` if no indent was found.
///
/// If [leadingAsIndent] is `true`, leading white spaces are treated as indent
/// as though the previous character.
///
/// You must provide either [comments] or an [onParseComment] [Function]
int? skipToParsableChar(
  SourceIterator iterator, {
  required void Function(YamlComment comment) onParseComment,
  bool leadingAsIndent = false,
}) {
  int? indent;

  var warmUp = true;

  void checkIndent() {
    indent = takeFromIteratorUntil(
      iterator,
      includeCharAtCursor: warmUp && iterator.current == space,
      mapper: (c) => c,
      onMapped: (_) {},
      stopIf: (_, possibleNext) => !possibleNext.isIndent(),
    );

    if (iterator.isEOF) return;

    iterator.nextChar();
    warmUp = false;

    if (leadingAsIndent) return;

    if (iterator.current == tab) {
      skipWhitespace(iterator, skipTabs: true);
    }
  }

  skipper:
  while (!iterator.isEOF) {
    switch (iterator.current) {
      case carriageReturn || lineFeed:
        {
          skipCrIfPossible(iterator.current, iterator: iterator);
          checkIndent();
        }

      // Check if leading whitespace can be indent
      case space when leadingAsIndent:
        checkIndent();

      case space || tab when !leadingAsIndent:
        skipWhitespace(iterator, skipTabs: true);
        iterator.nextChar();

      case comment
          when iterator.before.isNullOr(
            (c) => c.isWhiteSpace() || c.isLineBreak(),
          ):
        {
          final (:onExit, :comment) = parseComment(iterator);
          onParseComment(comment);

          if (onExit.sourceEnded) return null;
          indent = null; // Guarantees indent recheck
        }

      default:
        break skipper;
    }
  }

  return indent;
}
