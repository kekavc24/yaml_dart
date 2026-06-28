import 'package:checks/checks.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

extension Typed<T> on Subject<TreeNode<T>> {
  Subject<T> whoseNode() => has<T>((e) => e.node, 'Node');

  void hasTag(String? tag) => has((e) => e.localTag, 'Tag').equals(tag);

  void hasAnchor(String? anchor) =>
      has((e) => e.anchor, 'Anchor').equals(anchor);

  void hasStyle(NodeStyle style) =>
      has((e) => e.nodeStyle, 'Style').equals(style);

  void isNodeType(NodeType type) =>
      has((e) => e.nodeType, 'Node Type').equals(type);

  Subject<bool> multiline() => has((e) => e.isMultiline, 'Multiline');
}
