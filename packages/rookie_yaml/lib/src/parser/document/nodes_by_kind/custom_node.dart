import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_map.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_sequence.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_sequence.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/document/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/document/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/document/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';

import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

part 'custom_block_node.dart';
part 'custom_flow_node.dart';

/// Parses a node annotated with a custom property. The resolver within the
/// [property] is extracted.
///
/// [onMatchScalar] receives the actual resolver.
///
/// [onMatchMap] and [onMatchIterable] receive their builder functions since a
/// map and iterable must be instantiated before they can accepts node being
/// parsed.
T _parseCustomKind<T, Obj>(
  CustomKind kind, {
  required NodeProperty property,
  required T Function(ObjectFromMap<Obj, Obj, Obj> mapBuilder) onMatchMap,
  required T Function(ObjectFromIterable<Obj, Obj> listBuilder) onMatchIterable,
  required T Function(ObjectFromScalarBytes<Obj> resolver) onMatchScalar,
}) {
  final resolver = property.customResolver!;

  return switch (kind) {
    CustomKind.map => onMatchMap(resolver as ObjectFromMap<Obj, Obj, Obj>),
    CustomKind.iterable => onMatchIterable(
      resolver as ObjectFromIterable<Obj, Obj>,
    ),
    _ => onMatchScalar(resolver as ObjectFromScalarBytes<Obj>),
  };
}

/// Creates an empty block node of the specified [kind] since the empty scalar
/// was captured by a tag present in the [property].
NodeDelegate<Obj> emptyBlockOfKind<Obj>(
  CustomKind kind,
  NodeProperty property, {
  required int indentLevel,
  required int indent,
  required RuneOffset start,
}) {
  return _parseCustomKind<NodeDelegate<Obj>, Obj>(
    kind,
    property: property,
    onMatchMap: (mapBuilder) => MapLikeDelegate.boxed(
      mapBuilder.onCustomMap(),
      collectionStyle: NodeStyle.block,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
      afterMapping: mapBuilder.afterObject<Obj>(),
    ),
    onMatchIterable: (listBuilder) => SequenceLikeDelegate.boxed(
      listBuilder.onCustomIterable(),
      collectionStyle: NodeStyle.block,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
      afterSequence: listBuilder.afterObject<Obj>(),
    ),
    onMatchScalar: (resolver) => BoxedScalar(
      resolver.onCustomScalar(),
      scalarStyle: ScalarStyle.plain,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
      afterScalar: resolver.afterObject<Obj>(),
    ),
  );
}

typedef OnScalar<R, T> =
    R Function(
      ScalarStyle style,
      int indentOnExit,
      bool indentDidChange,
      DocumentMarker marker,
      ScalarLikeDelegate<T> delegate,
    );

typedef _InternalScalar<Obj> = (
  CharWriter writer,
  void Function() onComplete,
  ScalarLikeDelegate<Obj> delegate,
);

/// Parses a scalar using a custom [resolver].
///
/// This function is quite similar to the default scalar implementation used
/// by the parser. However, this function prefers a more mechanical approach
/// and calls the low level parse functions that read directly from the
/// [iterator].
///
/// [onScalar] is only called after the `onComplete` callback provided in the
/// [resolver] has been called.
R parseCustomScalar<R, Obj>(
  ScalarEvent event, {
  required SourceIterator iterator,
  required OnCustomScalar<Obj> resolver,
  required AfterScalar<Obj>? afterScalar,
  required NodeProperty? property,
  required void Function(YamlComment comment) onParseComment,
  required OnScalar<R, Obj> onScalar,
  required bool isImplicit,
  required bool isInFlowContext,
  required int indentLevel,
  required int minIndent,
  required int? blockParentIndent,
  String charsOnGreedy = '',
}) {
  // Delegate helper.
  _InternalScalar<Obj> delegateOf(ScalarStyle style) {
    final delegate = resolver();
    final writer = delegate.onWriteRequest;
    final onComplete = delegate.onComplete;

    return delegate is EfficientScalarDelegate<Obj>
        ? (writer, onComplete, delegate)
        : (
            writer,
            onComplete,
            BoxedScalar(
              delegate,
              scalarStyle: style,
              indentLevel: indentLevel,
              indent: minIndent,
              start: property?.span.start ?? iterator.currentLineInfo.current,
              afterScalar: afterScalar!,
            ),
          );
  }

  // Updates the delegate and calls [onComplete]
  R completionHelper(
    ParsedScalarInfo info,
    ScalarLikeDelegate<Obj> delegate,
    void Function() onComplete,
  ) {
    final (
      :scalarStyle,
      :scalarIndent,
      :hasLineBreak,
      :docMarkerType,
      :indentOnExit,
      :indentDidChange,
      :end,
    ) = info;

    delegate
      ..indent = scalarIndent
      ..nodeSpan.nodeEnd = end;

    onComplete();

    return onScalar(
      scalarStyle,
      indentOnExit,
      indentDidChange,
      docMarkerType,
      delegate,
    );
  }

  // Handler for the parser.
  R parse(
    ScalarStyle style,
    ParsedScalarInfo Function(CharWriter writer) parser,
  ) {
    final (writer, onComplete, delegate) = delegateOf(style);
    return completionHelper(parser(writer), delegate, onComplete);
  }

  var isFolded = false;

  switch (event) {
    case ScalarEvent.startBlockFolded when !isImplicit && !isInFlowContext:
      {
        isFolded = true;
        continue block;
      }

    block:
    case ScalarEvent.startBlockLiteral when !isImplicit && !isInFlowContext:
      {
        return parse(
          isFolded ? ScalarStyle.folded : ScalarStyle.literal,
          (writer) => blockScalarParser(
            iterator,
            charBuffer: writer,
            minimumIndent: minIndent,
            blockParentIndent: blockParentIndent,
            onParseComment: onParseComment,
          ),
        );
      }

    case ScalarEvent.startFlowDoubleQuoted:
      {
        return parse(
          ScalarStyle.doubleQuoted,
          (writer) => doubleQuotedParser(
            iterator,
            buffer: writer,
            indent: minIndent,
            isImplicit: isImplicit,
          ),
        );
      }

    case ScalarEvent.startFlowSingleQuoted:
      {
        return parse(
          ScalarStyle.singleQuoted,
          (writer) => singleQuotedParser(
            iterator,
            buffer: writer,
            indent: minIndent,
            isImplicit: isImplicit,
          ),
        );
      }

    case _ when event == ScalarEvent.startFlowPlain:
      {
        // Plain scalars may return null
        final (writer, onComplete, delegate) = delegateOf(ScalarStyle.plain);

        final info = plainParser(
          iterator,
          buffer: writer,
          indent: minIndent,
          charsOnGreedy: charsOnGreedy,
          isImplicit: isImplicit,
          isInFlowContext: isInFlowContext,
        );

        if (info == null) {
          throwWithRangedOffset(
            iterator,
            message:
                'Dirty parser state. Failed to parse a custom plain scalar',
            start: delegate.nodeSpan.nodeStart,
            end: iterator.currentLineInfo.current,
          );
        }

        return completionHelper(info, delegate, onComplete);
      }

    default:
      throwWithRangedOffset(
        iterator,
        message: 'Dirty parser state. Failed to parse a scalar using $event.',
        start: property?.span.start ?? iterator.currentLineInfo.current,
        end: iterator.currentLineInfo.current,
      );
  }
}
