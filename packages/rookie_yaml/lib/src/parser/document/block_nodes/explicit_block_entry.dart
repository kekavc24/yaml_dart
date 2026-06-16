import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/special_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/scalars/scalars.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Parses an explicit key/value.
({bool ignoreValueIfKey, BlockInfo blockInfo}) _parseExplicit<R, Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int indent,
  required ParserEvent expectedEvent,
  required BlockInfo Function(SourceIterator iterator) fallback,
  required void Function(NodeDelegate<Obj> blockNode) onSequenceOrBlockNode,
  required OnBlockMapEntry<Obj> maybeOnEntry,
}) {
  final ParserState(:iterator) = state;

  if (inferBlockEvent(iterator) != expectedEvent) {
    return (ignoreValueIfKey: true, blockInfo: fallback(iterator));
  }

  final explicitCharOffset = iterator.currentLineInfo.current;

  iterator.nextChar();

  final (:indentOrSeparation, :composeMap) = skipToElementStart(
    iterator,
    onParseComment: state.onParseComment,
    structuralOffset: explicitCharOffset,
  );

  final isNextLevel = indentOrSeparation != null;
  final expectedLaxIndent = indent + 1;

  // The indent is on the same level as "?" or ":". This may also indicate
  // that we are now pointing to the next key that may be implicit or explicit
  if (isNextLevel && indentOrSeparation < expectedLaxIndent) {
    final ignoreValue = indentOrSeparation < indent;

    // Optionally check if we must exit or can recover and parse a block
    // sequence.
    if (iterator.isEOF ||
        ignoreValue ||
        inferBlockEvent(iterator) != BlockCollectionEvent.startBlockListEntry) {
      onSequenceOrBlockNode(
        nullBlockNode(
          state,
          indentLevel: indentLevel,
          indent: indent + 1,
          start: explicitCharOffset,
          end: iterator.isEOF
              ? iterator.currentLineInfo.current
              : iterator.currentLineInfo.start,
        ),
      );
      return (
        ignoreValueIfKey: ignoreValue,
        blockInfo: (
          docMarker: DocumentMarker.none,
          exitIndent: indentOrSeparation,
        ),
      );
    }

    final (:parsedNextImplicitKey, :blockInfo) = parseSpecialBlockSequence(
      state,
      keyIndent: indent,
      keyIndentLevel: indentLevel,
      property: null,
      structuralStart: explicitCharOffset,
      onSequence: onSequenceOrBlockNode,
      onNextImplicitEntry: maybeOnEntry,
    );

    return (ignoreValueIfKey: parsedNextImplicitKey, blockInfo: blockInfo);
  }

  final (laxIndent: _, :inlineFixedIndent) = indentOfBlockChild(
    indentOrSeparation,
    blockParentIndent: indent,
    yamlNodeStartOffset: explicitCharOffset.offset,
    contentOffset: iterator.currentLineInfo.current.offset,
  );

  final (:parsedNextImplicitKey, :blockInfo) = composeSpecialBlockSequence(
    state,
    blockNode: parseBlockNode(
      state,
      blockParentIndent: indent,
      indentLevel: isNextLevel ? indentLevel + 1 : indentLevel,
      inferredFromParent: indentOrSeparation,
      laxBlockIndent: indent + 1,
      fixedInlineIndent: inlineFixedIndent,
      forceInlined: false,
      composeImplicitMap: composeMap,
      canComposeMapIfMultiline: true,
      structuralOffset: explicitCharOffset,
    ),
    keyIndent: indent,
    keyIndentLevel: indentLevel,
    onSequenceOrBlockNode: onSequenceOrBlockNode,
    onNextImplicitEntry: maybeOnEntry,
  );

  return (ignoreValueIfKey: parsedNextImplicitKey, blockInfo: blockInfo);
}

/// Parses an explicit block key and its value (if present).
BlockInfo parseExplicitBlockEntry<Obj>(
  ParserState<Obj> state, {
  required int entryIndent,
  required int entryIndentLevel,
  required OnBlockMapEntry<Obj> onExplicitEntry,
}) {
  final ParserState(:iterator) = state;
  var marker = iterator.currentLineInfo.current;

  NodeDelegate<Obj>? key;
  final (:ignoreValueIfKey, blockInfo: keyInfo) = _parseExplicit(
    state,
    indentLevel: entryIndentLevel,
    indent: entryIndent,
    expectedEvent: BlockCollectionEvent.startExplicitKey,
    fallback: (iterator) => throwWithSingleOffset(
      iterator,
      message: 'Expected "?" followed by a whitespace',
      offset: iterator.currentLineInfo.current,
    ),
    onSequenceOrBlockNode: (blockNode) => key = blockNode,
    maybeOnEntry: onExplicitEntry,
  );

  if (key == null) {
    throwWithRangedOffset(
      iterator,
      message: 'Dirty explicit entry state! Key was never set!',
      start: marker,
      end: iterator.currentLineInfo.current,
    );
  } else if (ignoreValueIfKey || keyInfo.exitIndent == null) {
    state.onParseMapKey(key!.parsed());
    onExplicitEntry(key!, null);
    return keyInfo;
  } else {
    final exitIndent = keyInfo.exitIndent!;

    if (exitIndent > entryIndent) {
      final scanner = state.iterator;
      throwWithRangedOffset(
        scanner,
        message: 'Dangling node found when parsing explicit entry',
        start: key!.nodeSpan.nodeEnd,
        end: state.iterator.currentLineInfo.current,
      );
    } else if (exitIndent < entryIndent) {
      state.onParseMapKey(key!.parsed());
      onExplicitEntry(key!, null);
      return keyInfo;
    }
  }

  state.onParseMapKey(key!.parsed());

  // Parse value
  return _parseExplicit(
    state,
    indentLevel: entryIndentLevel,
    indent: entryIndent,
    expectedEvent: BlockCollectionEvent.startEntryValue,

    // We can fallback to null if we don't find ":".
    fallback: (_) {
      onExplicitEntry(key!, null);
      return keyInfo;
    },
    onSequenceOrBlockNode: (value) => onExplicitEntry(key!, value),
    maybeOnEntry: onExplicitEntry,
  ).blockInfo;
}
