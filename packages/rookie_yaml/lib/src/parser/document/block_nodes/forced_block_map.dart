import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_map.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Composes a block node but expects it to be a block map. A block map may
/// begin with an implicit key rather than an explicit one.
BlockNode<Obj> composeBlockMapStrict<Obj>(
  ParserState<Obj> state, {
  required ParserEvent event,
  required int indentLevel,
  required int laxIndent,
  required int inlineFixedIndent,
  required NodeProperty property,
  required bool isInline,
  required bool composeImplicitMap,
}) {
  BlockNode<Obj> nodeInfo;

  if (property.kind case CustomKind kind) {
    if (kind != CustomKind.map) {
      throwWithRangedOffset(
        state.iterator,
        message: 'Expected the implied start of a custom block map',
        start: property.span.start,
        end: state.iterator.currentLineInfo.current,
      );
    }

    final resolver = property.customResolver as ObjectFromMap<Obj, Obj, Obj>;

    nodeInfo = parseBlockMap(
      MapLikeDelegate.boxed(
        resolver.onCustomMap(),
        collectionStyle: NodeStyle.block,
        indentLevel: indentLevel,
        indent: inlineFixedIndent,
        start: property.span.start,
        afterMapping: resolver.afterObject<Obj>(),
      ),
      state: state,
    );
  } else {
    switch (event) {
      case FlowCollectionEvent():
        {
          nodeInfo = parseFlowNodeInBlock(
            state,
            event: event,
            indentLevel: indentLevel,
            indent: laxIndent,
            isInline: isInline,
            composeImplicitMap: composeImplicitMap,
            composedMapIndent: inlineFixedIndent,
            flowProperty: property,
          );
        }
      case NodePropertyEvent propertyEvent
          when propertyEvent != NodePropertyEvent.startAlias:
        {
          nodeInfo = parseBlockNode(
            state,
            indentLevel: indentLevel,

            // Won't matter. The lax and inline indent are predetermined.
            inferredFromParent: null,

            // It must degenerate to a block map! A block scalar cannot or
            // should not be here (unless via an explicit key) since we expect
            // a block map after this call.
            blockParentIndent: null,
            laxBlockIndent: laxIndent,
            fixedInlineIndent: inlineFixedIndent,
            forceInlined: isInline,
            composeImplicitMap: composeImplicitMap,
          );

          state.trackAnchor(nodeInfo.node, property);
        }
      default:
        {
          nodeInfo = parseBlockMap(
            state.defaultMapDelegate(
              mapStyle: NodeStyle.block,
              indentLevel: indentLevel,
              indent: inlineFixedIndent,
              start: state.iterator.currentLineInfo.current,
            ),
            state: state,
          );

          state.trackAnchor(nodeInfo.node, property);
        }
    }

    if (nodeInfo.node is! MapLikeDelegate) {
      throwWithRangedOffset(
        state.iterator,
        message:
            'Expected an (implied) block map with property '
            '"${property.tag ?? property.anchor}"',

        start: property.span.start,
        end: nodeInfo.node.nodeSpan.nodeEnd,
      );
    }
  }

  return nodeInfo;
}
