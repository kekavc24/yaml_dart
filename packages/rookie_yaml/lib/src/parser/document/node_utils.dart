import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// A parsed flow/block map entry.
typedef ParsedEntry<T> = (NodeDelegate<T> key, NodeDelegate<T>? value);

/// Represents the current state after a block node has been completely parsed.
typedef BlockInfo = ({int? exitIndent, DocumentMarker docMarker});

/// Indicates no nodes can be parsed after the current block node.
const BlockInfo emptyScanner = (
  exitIndent: null,
  docMarker: DocumentMarker.none,
);

/// Represents a generic block-like node and its state.
typedef BlockNodeBuilder<T> = ({BlockInfo blockInfo, T node});

/// A single block node.
typedef BlockNode<T> = BlockNodeBuilder<NodeDelegate<T>>;

/// An explicit/implicit block entry for a map.
typedef BlockEntry<Obj> =
    BlockNodeBuilder<(NodeDelegate<Obj>? key, NodeDelegate<Obj>? value)>;

/// Callback for a block map entry that has been fully parsed.
typedef OnBlockMapEntry<Obj> =
    void Function(NodeDelegate<Obj> key, NodeDelegate<Obj>? value);

/// Throws if a flow [ScalarStyle.plain] scalar has any document/directive end
/// characters or its exit indent is less than the minimum [flowIndent].
void throwIfInvalidFlow(
  ScalarStyle style, {
  required SourceIterator iterator,
  required bool isInline,
  required DocumentMarker marker,
  required int flowIndent,
  required bool indentDidChange,
  required int indentOnExit,
}) {
  if (style != ScalarStyle.plain || isInline) return;

  // Plain scalars can have document/directive end chars embedded in the
  // content. Additionally, if not implicit, it can be affected by indent
  // changes since it has a block-like structure. Neither should be allowed.
  if (marker.stopIfParsingDoc) {
    throwForCurrentLine(
      iterator,
      message:
          'Premature document termination after parsing a plain flow'
          ' scalar',
    );
  } else if (indentDidChange && indentOnExit < flowIndent) {
    throwWithApproximateRange(
      iterator,
      message:
          'Indent change detected when parsing plain scalar. Expected'
          ' $flowIndent space(s) but found $indentOnExit space(s)',
      current: iterator.currentLineInfo.current,
      charCountBefore: indentOnExit,
    );
  }
}

/// Skips to the next parsable flow indicator/character.
///
/// If declared on a new line and [forceInline] is `false`, the flow
/// indicator/character must be indented at least [minIndent] spaces. Throws
/// otherwise.
bool nextSafeLineInFlow(
  SourceIterator iterator, {
  required int minIndent,
  required bool forceInline,
  required void Function(YamlComment comment) onParseComment,
}) {
  final indent = skipToParsableChar(
    iterator,
    onParseComment: onParseComment,
    allowTabs: (currentIndent, _) =>
        currentIndent == null || currentIndent >= minIndent,
  );

  if (indent != null) {
    // Must not have line breaks
    if (forceInline) {
      throwWithApproximateRange(
        iterator,
        message: 'Found a line break when parsing an inline flow node',
        current: iterator.currentLineInfo.current,
        charCountBefore: indent + 2, // Highlight upto the previous line
      );
    }

    // If line breaks are allowed, it must at least be the same or greater than
    // the min indent. Indent serves no purpose in flow collections. The min
    // indent is used as markup indent enforced parent block collection.
    if (indent < minIndent) {
      throwWithApproximateRange(
        iterator,
        message: 'Expected at least ${minIndent - indent} additional spaces',
        current: iterator.currentLineInfo.current,
        charCountBefore: indent,
      );
    }
  } else if (iterator.isEOF) {
    return false;
  }

  return true;
}

/// Whether the next flow sequence entry or flow map entry can be parsed.
bool continueToNextEntry(
  SourceIterator iterator, {
  required YamlSourceSpan lastEntrySpan,
  required int minIndent,
  required bool forceInline,
  required void Function(YamlComment comment) onParseComment,
}) {
  nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  );

  lastEntrySpan.parsingEnd = iterator.currentLineInfo.current;

  if (iterator.current != flowEntryEnd) {
    return false;
  }

  iterator.nextChar();
  final goToNext = nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  );
  return goToNext;
}

/// Whether a flow key was "json-like", that is, a single/double plain scalar
/// or flow map/sequence.
bool keyIsJsonLike(NodeDelegate? delegate) => switch (delegate) {
  EfficientScalarDelegate(
    scalarStyle: ScalarStyle.singleQuoted || ScalarStyle.doubleQuoted,
  ) ||
  MapLikeDelegate(collectionStyle: NodeStyle.flow) ||
  SequenceLikeDelegate(collectionStyle: NodeStyle.flow) => true,
  _ => false,
};

/// Initializes a flow collection and validates that the [flowStartIndicator]
/// matches the corresponding flow collection's start delimiter. Returns the
/// collection by calling [init].
T initFlowCollection<R, T extends NodeDelegate<R>>(
  SourceIterator iterator, {
  required int flowStartIndicator,
  required int minIndent,
  required bool forceInline,
  required void Function(YamlComment comment) onParseComment,
  required int flowEndIndicator,
  required T Function(RuneOffset start) init,
}) {
  final current = iterator.currentLineInfo.current;

  if (iterator.current != flowStartIndicator) {
    throwWithSingleOffset(
      iterator,
      message:
          'Expected the flow delimiter: '
          '"${flowStartIndicator.asString()}"',
      offset: current,
    );
  }

  iterator.nextChar();

  if (!nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  )) {
    throwWithRangedOffset(
      iterator,
      message:
          'Invalid flow collection state. Expected to find: '
          '"${flowEndIndicator.asString()}"',
      start: current,
      end: iterator.currentLineInfo.current,
    );
  }

  return init(current);
}

/// Checks if the current char in the [iterator] matches the closing [delimiter]
/// of the flow collection. If valid, the [flowCollection]'s end offset is
/// updated and the [delimiter] is skipped.
D terminateFlowCollection<Obj, D extends NodeDelegate<Obj>>(
  SourceIterator iterator,
  D flowCollection,
  int delimiter,
) {
  if (iterator.current != delimiter) {
    throwWithSingleOffset(
      iterator,
      message:
          'Invalid flow collection state. Expected '
          '"${delimiter.asString()}"',
      offset: iterator.currentLineInfo.current,
    );
  }

  iterator.nextChar();
  flowCollection.nodeSpan.nodeEnd = iterator.currentLineInfo.current;
  return flowCollection;
}

/// Calculates the indent for a block node within a block collection
/// only if [inferred] indent is null.
({int laxIndent, int inlineFixedIndent}) indentOfBlockChild(
  int? inferred, {
  required int blockParentIndent,
  required int yamlNodeStartOffset,
  required int contentOffset,
}) {
  if (inferred != null) {
    return (laxIndent: inferred, inlineFixedIndent: inferred);
  }

  // Being null indicates the child is okay being indented at least "+1" if
  // the rest of its content spans multiple lines. This applies to
  // [ScalarStyle.literal] and [ScalarStyle.folded]. Flow collections also
  // benefit from this as the indent serves no purpose other than respecting
  // the current block parent's indentation. This is its [laxIndent].
  //
  // Its [inlineFixedIndent] is the character difference upto the current
  // parsable char. This indent is enforced on block sequences and maps used
  // as:
  //   1. a block sequence entry
  //   2. content of an explicit key
  //   3. content of an explicit key's value
  //
  // "?" is used as an example but applies to all block nodes that use an
  // indicator.
  //
  // (meh! No markdown hover)
  // ```yaml
  //
  // # With flow. Okay
  // ? [
  //  "blah", "blah",
  //  "blah"]
  //
  // # With literal. Applies to folded. Okay
  // ? |
  //  block
  //
  // # With literal. Applies to folded. We give "+1". Indent determined
  // # while parsing as recommended by YAML. See [parseBlockScalar]
  // ? |
  //     block
  //
  // # With block sequences. Must do this for okay
  // ? - blah
  //   - blah
  //
  // # With implicit or explict map
  // ? key: value
  //   keyB: value
  //   keyC: value # Explicit key ends here
  // : actual-value # Explicit key's value
  //
  // # With block sequence. If this is done. Still okay. Inferred.
  // ?
  //  - blah
  //  - blah
  //
  // ```
  return (
    laxIndent: blockParentIndent + 1,
    inlineFixedIndent:
        blockParentIndent + (contentOffset - yamlNodeStartOffset),
  );
}

/// Whether the parser can stop parsing a block [collection]. The end offset of
/// the collection is also updated.
bool exitBlockCollection<Obj, T extends NodeDelegate<Obj>>(
  T collection, {
  required SourceIterator iterator,
  required int nodeIndent,
  required DocumentMarker marker,
  required int? exitIndent,
}) {
  final lineInfo = iterator.currentLineInfo;

  void updateEnd(RuneOffset end) => collection.nodeSpan.parsingEnd = end;

  final parsedEnd = iterator.isEOF || exitIndent == null;

  if (parsedEnd) {
    updateEnd(lineInfo.current);
    return parsedEnd;
  } else if (marker.stopIfParsingDoc) {
    updateEnd(lineInfo.start);
    return true;
  } else if (exitIndent > nodeIndent) {
    throwWithSingleOffset(
      iterator,
      message:
          'Invalid block node indentation in block collection. '
          'Expected $nodeIndent space(s)',
      offset: iterator.currentLineInfo.current,
    );
  }

  updateEnd(lineInfo.start);
  return exitIndent != nodeIndent;
}

/// Terminates a block [node] that is a collection.
T blockEnd<Obj, T extends NodeDelegate<Obj>>(T node) {
  final span = node.nodeSpan;
  span.nodeEnd = span.parsingEnd ?? span.nodeStart;
  return node;
}

/// Updates the end offset of a block [node] that is a collection using the
/// [span] provided.
///
/// If the [node] is a block map, a value may override the key [span] with a
/// custom [spanOverride] that extends the span of the map further.
T delegateWithOptimalEnd<Obj, T extends NodeDelegate<Obj>>(
  T node,
  NodeSpan span, [
  NodeSpan? spanOverride,
]) => node..nodeSpan.parsingEnd = spanOverride?.end() ?? span.end();

/// Sets the end offset of a [node] whose end offset may have changed after
/// various parser actions.
T nodeParseEnd<Obj, T extends NodeDelegate<Obj>>(
  T node,
  SourceIterator iterator,
) {
  final lineInfo = iterator.currentLineInfo;
  return node
    ..nodeSpan.parsingEnd = iterator.isEOF ? lineInfo.current : lineInfo.start;
}
