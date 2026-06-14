import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/special_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Parses an implicit key and its value if present.
BlockInfo parseImplicitBlockEntry<Obj>(
  ParserState<Obj> state, {
  required int keyIndent,
  required int keyIndentLevel,
  required OnBlockMapEntry<Obj> onImplicitEntry,
}) {
  final (:blockInfo, node: key) = parseBlockNode(
    state,
    blockParentIndent: null, // Cannot have block keys as implicit
    indentLevel: keyIndentLevel,
    inferredFromParent: keyIndent,
    laxBlockIndent: keyIndent,
    fixedInlineIndent: keyIndent,
    forceInlined: true,
    composeImplicitMap: false,
  );

  final iterator = state.iterator;

  // We parsed the directive end "---" or document end "..." chars. We have no
  // key. We reached the end of the doc and parsed the key as that char
  if (blockInfo.docMarker.stopIfParsingDoc) {
    return blockInfo;
  } else if (blockInfo.exitIndent case int? indent
      when indent != null && indent != seamlessIndentMarker) {
    // The exit indent *MUST* be null or be seamless (parsed completely with
    // no indent change if quoted). This is a key that should *NEVER*
    // spill into the next line.
    throwWithApproximateRange(
      iterator,
      message: 'Implicit block keys are restricted to a single line',
      current: iterator.currentLineInfo.current,
      charCountBefore: indent + 1,
    );
  } else if (iterator.current.isWhiteSpace()) {
    // Skip any separation space
    skipWhitespace(iterator, skipTabs: true);
    iterator.nextChar();
  }

  key.nodeSpan.nodeEnd = iterator.currentLineInfo.current;
  state.onParseMapKey(key.parsed());

  // Value's node info acts as this entire entry's info
  return parseImplicitValue(
    state,
    keyIndentLevel: keyIndentLevel,
    keyIndent: keyIndent,
    onValue: (implicitValue) => onImplicitEntry(key, implicitValue),
    onEntryValue: onImplicitEntry,
  );
}

/// Parses an implicit value.
///
/// This standalone function allows other functions that may parse block nodes
/// to parse the first entry without necessarily explicitly calling
/// [parseImplicitBlockEntry]. This allows a block map to be loosely composed
/// without relying on `parseBlockMap`.
BlockInfo parseImplicitValue<Obj>(
  ParserState<Obj> state, {
  required int keyIndentLevel,
  required int keyIndent,
  required void Function(NodeDelegate<Obj> implicitValue) onValue,
  required OnBlockMapEntry<Obj> onEntryValue,
}) {
  final ParserState(:iterator) = state;

  ParserEvent eventCallback() => inferBlockEvent(iterator);

  final indicatorOffset = iterator.currentLineInfo.current;

  if (eventCallback() != BlockCollectionEvent.startEntryValue) {
    throwWithSingleOffset(
      iterator,
      message: 'Expected to find ":" after the key and before its value',
      offset: indicatorOffset,
    );
  }

  iterator.nextChar();

  var composeBlockCollection = true;

  // It's better if we determine the actual state of the value here before
  // handing this off to [parseBlockNode]
  var indentOrSeparation = skipToParsableChar(
    iterator,
    onParseComment: state.onParseComment,
    allowTabs: (currentIndent, hasTabs) {
      // We only allow tabs in a context we can control, which is, this key's
      // value via the [composeBlockCollection] variable. We don't want the
      // previous parsing context handling a dirty state when Dart unrolls this
      // recursive context.
      if (hasTabs) {
        final isInline = currentIndent == null;
        composeBlockCollection = isInline;
        return isInline || currentIndent > keyIndent;
      }

      return true;
    },
  );

  final hasIndent = indentOrSeparation != null;
  final valueIndent = keyIndent + 1;
  final event = eventCallback();

  // Exit if we cannot parse an implicit value as a block node
  if (hasIndent && indentOrSeparation < valueIndent) {
    // Check if we should exit or recover and parse a block sequence.
    if (iterator.isEOF ||
        indentOrSeparation < keyIndent ||
        event != BlockCollectionEvent.startBlockListEntry) {
      onValue(
        nullScalarDelegate(
            indentLevel: keyIndentLevel,
            indent: keyIndent,
            startOffset: indicatorOffset,
            resolver: state.scalarFunction,
          )
          ..nodeSpan.nodeEnd = iterator.isEOF
              ? iterator.currentLineInfo.current
              : iterator.currentLineInfo.start,
      );
      return (docMarker: DocumentMarker.none, exitIndent: indentOrSeparation);
    }

    return parseSpecialBlockSequence(
      state,
      keyIndent: keyIndent,
      keyIndentLevel: keyIndentLevel,
      structuralStart: indicatorOffset,
      property: null,
      onSequence: onValue,
      onNextImplicitEntry: onEntryValue,
    ).blockInfo;
  } else if (event
      case BlockCollectionEvent.startBlockListEntry ||
          BlockCollectionEvent.startExplicitKey
      when !hasIndent || !composeBlockCollection) {
    throwWithRangedOffset(
      iterator,
      message:
          'The block collections must start on a new line when used as '
          'values of an implicit key',
      start: indicatorOffset,
      end: iterator.currentLineInfo.current,
    );
  }

  // Coin toss really.
  return composeSpecialBlockSequence(
    state,

    // We want to allow this value to degenerate to a block map itself if it
    // spans multiple lines. This cannot be determined here lest we duplicate
    // code. (PS: Duplication isn't an issue. [parseBlockNode] can handle this
    // effortlessly).
    //
    // A value can also degenerate to a block map if its property is multiline.
    // That's why we tell this function:
    //   - We don't expect it to (but it can) be inline -> [forceInline]
    //   - Compose if this value itself is multiline -> [composeImplicitMap]
    //   - Compose if *YOU* ("parseBlockNode") happen to note it is multiline
    //     -> [canComposeMapIfMultiline]
    blockNode: parseBlockNode(
      state,
      blockParentIndent: keyIndent,
      indentLevel: hasIndent ? keyIndentLevel + 1 : keyIndentLevel,
      inferredFromParent: indentOrSeparation,
      laxBlockIndent: valueIndent,
      fixedInlineIndent: valueIndent,
      forceInlined: false,
      composeImplicitMap: hasIndent && composeBlockCollection,
      canComposeMapIfMultiline: composeBlockCollection,
      structuralOffset: indicatorOffset,
    ),
    keyIndent: keyIndent,
    keyIndentLevel: keyIndentLevel,
    onSequenceOrBlockNode: onValue,
    onNextImplicitEntry: onEntryValue,
  ).blockInfo;
}
