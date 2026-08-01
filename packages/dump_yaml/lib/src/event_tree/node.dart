import 'dart:collection';

import 'package:dump_yaml/src/event_tree/hashing.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:meta/meta.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

enum NodeType { scalar, map, list, alias }

const _noComments = Iterable<String>.empty();

/// A built document.
typedef DocumentNode = ({Iterable<GlobalTag> tags, TreeNode<Object> root});

extension Doc on DocumentNode {
  /// Whether this document has directives.
  bool get isDirectiveDoc => tags.isNotEmpty;
}

/// A node representing a small or the entire chunk of a finalized YAML tree
/// ready to be dumped.
///
/// {@category dump_map}
@sealed
abstract class TreeNode<T> extends CompactYamlNode {
  TreeNode(
    this.nodeStyle, {
    required this.nodeHash,
    Iterable<String>? comments,
    CommentStyle? commentStyle,
    this.anchor,
    this.localTag,
  }) : comments = comments ?? _noComments,
       commentStyle = commentStyle ?? CommentStyle.possessive;

  /// Any comments associated with the node.
  final Iterable<String> comments;

  /// Node's comment style
  final CommentStyle commentStyle;

  final FreeHash nodeHash;

  @override
  final NodeStyle nodeStyle;

  @override
  final String? anchor;

  /// A [ResolvedTag] reverted back to its [TagShorthand] form.
  ///
  /// When `this` is built, the underlying resolved [tag] is always (set to)
  /// `null`. This is because an [TreeNode] strips a node back to a
  /// "lexed" state but without the indent information.
  final String? localTag;

  /// Actual node representing the tree.
  T get node;

  /// Whether `this` spans multiple lines.
  bool get isMultiline;

  /// Whether `this` prefers using its parent's indent while being dumped
  /// rather than the indented calculated for parent's children.
  bool get inheritParentIndent => false;

  /// Type of node.
  NodeType get nodeType;
}

/// An alias.
final class ReferenceNode extends TreeNode<String> {
  ReferenceNode(
    this.alias, {
    required super.comments,
    required super.nodeHash,
    super.commentStyle,
    this.recursive = false,
  }) : super(NodeStyle.flow);

  /// Whether `this` is recursive.
  final bool recursive;

  @override
  final String alias;

  @override
  String get node => '*$alias';

  @override
  bool get inheritParentIndent => false;

  @override
  bool get isMultiline => false;

  @override
  NodeType get nodeType => NodeType.alias;
}

/// A finalized scalar's lines representing the string content of the node to be
/// dumped.
final class ContentNode extends TreeNode<Iterable<String>> {
  ContentNode(
    this.node,
    super.nodeStyle, {
    required super.nodeHash,
    required this.inheritParentIndent,
    required this.isMultiline,
    super.comments,
    super.anchor,
    super.localTag,
    super.commentStyle,
  });

  @override
  final Iterable<String> node;

  @override
  final bool inheritParentIndent;

  @override
  final bool isMultiline;

  @override
  NodeType get nodeType => NodeType.scalar;
}

/// Simple key and value for a map [CollectionNode].
typedef MappingEntry = (TreeNode<Object> key, TreeNode<Object> value);
typedef ListNode = CollectionNode<TreeNode<Object>>;
typedef MapNode = CollectionNode<MappingEntry>;

/// A finalized tree for an [Iterable] or [Map].
final class CollectionNode<T> extends TreeNode<ListQueue<T>> {
  CollectionNode(
    this.node,
    super.nodeStyle, {
    required super.nodeHash,
    required this.nodeType,
    required this.forcedInline,
    required this.isMultiline,
    super.anchor,
    super.localTag,
    super.comments,
    super.commentStyle,
  });

  @override
  final bool isMultiline;

  final bool forcedInline;

  @override
  final ListQueue<T> node;

  @override
  final NodeType nodeType;
}

extension on CommentStyle {
  bool get preferExplicit => switch (this) {
    CommentStyle.possessive || CommentStyle.trailing => true,
    _ => false,
  };
}

bool isRecursiveAnchorRef(Object? object, String? anchor) {
  bool isRef(Object? node) {
    if (node is! ReferenceNode || !node.recursive) return false;
    return anchor != null && anchor == node.alias;
  }

  if (object case MappingEntry(:final $1, :final $2)) {
    return isRef($1) || isRef($2);
  }

  return isRef(object);
}

extension KeyUtil on TreeNode<Object> {
  /// Whether `this` can be an explicit key in a map.
  bool isExplicitKey() {
    // Always enforce a very low threshold for an explicit key. Strive for
    // generalization over an "all-case-covered" strategy.
    if (this is CollectionNode ||
        isMultiline ||
        (commentStyle.preferExplicit && comments.isNotEmpty)) {
      return true;
    }

    bool byLength(int length) => length > 1024;

    // Check if the scalar is truly implicit.
    return switch (node) {
      Iterable<String> iterable => byLength(iterable.firstOrNull?.length ?? 0),
      _ => byLength(node.toString().length),
    };
  }

  /// Whether `this` is a block collection.
  bool isBlockCollection() => this is CollectionNode && nodeStyle.isBlock;
}
