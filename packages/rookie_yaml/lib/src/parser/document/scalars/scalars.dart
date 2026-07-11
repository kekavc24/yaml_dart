import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/delegates/one_pass_scalars/efficient_scalar_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/custom_node.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Creates a `null` delegate.
NodeDelegate<Obj> nullBlockNode<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int indent,
  required RuneOffset start,
  RuneOffset? end,
}) => emptyBlockNode(
  state,
  property: null,
  indentLevel: indentLevel,
  indent: indent,
  start: start,
  end: end,
);

/// Creates a `null` delegate only if [property] is not an [Alias].
NodeDelegate<Obj> emptyBlockNode<Obj>(
  ParserState<Obj> state, {
  required ParsedProperty? property,
  required int indentLevel,
  required int indent,
  required RuneOffset start,
  RuneOffset? end,
}) {
  final node = switch (property) {
    Alias _ => state.referenceAlias(
      property,
      indentLevel: indentLevel,
      indent: indent,
    ),
    NodeProperty(kind: final CustomKind kind) => emptyBlockOfKind<Obj>(
      kind,
      property,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    ),
    _ => nullScalarDelegate(
      indentLevel: indentLevel,
      indent: indent,
      startOffset: start,
      resolver: state.scalarFunction,
    ),
  };

  return state.trackAnchor(node..nodeSpan.nodeEnd = end ?? start, property);
}

/// Parses a `Scalar`.
///
/// [greedyOnPlain] is only ever passed when the first two plain scalar
/// characters resemble the directive end markers `---` but the last char
/// is not a match.
T parseScalar<R, T>(
  ScalarEvent event, {
  required OnCustomScalar<R>? onDefault,
  required AfterScalar<R>? afterScalar,
  required SourceIterator iterator,
  required ScalarFunction<R> scalarFunction,
  required void Function(YamlComment comment) onParseComment,
  required bool isImplicit,
  required bool isInFlowContext,
  required int indentLevel,
  required int minIndent,
  required int? blockParentIndent,
  required OnScalar<T, R> onScalar,
  required bool defaultToString,
  DelegatedValue? delegateScalar,
  String greedyOnPlain = '',
  RuneOffset? start,
}) {
  return parseCustomScalar(
    event,
    iterator: iterator,
    resolver: () {
      if (onDefault != null) return onDefault();
      return EfficientScalarDelegate.ofScalar(
        delegateScalar != null
            ? delegateScalar()
            : AmbigousDelegate(defaultToString: defaultToString),
        style: switch (event) {
          ScalarEvent.startBlockFolded => ScalarStyle.folded,
          ScalarEvent.startBlockLiteral => ScalarStyle.literal,
          ScalarEvent.startFlowDoubleQuoted => ScalarStyle.doubleQuoted,
          ScalarEvent.startFlowSingleQuoted => ScalarStyle.singleQuoted,
          _ => ScalarStyle.plain,
        },
        indentLevel: indentLevel,
        indent: minIndent,
        start: start ?? iterator.currentLineInfo.current,
        resolver: scalarFunction,
      );
    },
    afterScalar: afterScalar,
    property: null,
    onParseComment: onParseComment,
    onScalar: onScalar,
    isImplicit: isImplicit,
    isInFlowContext: isInFlowContext,
    indentLevel: indentLevel,
    minIndent: minIndent,
    blockParentIndent: blockParentIndent,
    charsOnGreedy: greedyOnPlain,
  );
}
