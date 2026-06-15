part of 'custom_node.dart';

/// Parses a custom flow node based on its [kind].
NodeDelegate<Obj> customFlowNode<Obj>(
  CustomKind kind, {
  required ParserState<Obj> state,
  required NodeProperty property,
  required ParserEvent flowEvent,
  required int currentIndentLevel,
  required int minIndent,
  required bool forceInline,
}) => _parseCustomKind<NodeDelegate<Obj>, Obj>(
  kind,
  property: property,
  onMatchMap: (builder) => parseFlowMap(
    state,
    indentLevel: currentIndentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    asCustomMap: builder,
  ),
  onMatchIterable: (builder) => parseFlowSequence(
    state,
    indentLevel: currentIndentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    asCustomList: builder,
  ),
  onMatchScalar: (resolver) => parseCustomScalar(
    flowEvent is ScalarEvent ? flowEvent : ScalarEvent.startFlowPlain,
    iterator: state.iterator,
    resolver: resolver.onCustomScalar,
    afterScalar: resolver.afterObject<Obj>(),
    property: property,
    onParseComment: (_) {}, // Flow nodes cannot have comments
    onScalar: (style, indentOnExit, indentDidChange, marker, delegate) {
      throwIfInvalidFlow(
        style,
        iterator: state.iterator,
        isInline: forceInline,
        marker: marker,
        flowIndent: minIndent,
        indentDidChange: indentDidChange,
        indentOnExit: indentOnExit,
      );

      return delegate;
    },
    isImplicit: forceInline,
    isInFlowContext: true,
    indentLevel: currentIndentLevel,
    minIndent: minIndent,
    blockParentIndent: null,
  ),
);
