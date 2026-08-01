import 'package:rookie_yaml/rookie_yaml.dart';

/// Default YAML style that is widely used.
const classicScalarStyle = ScalarStyle.plain;

extension Styling on NodeStyle {
  /// Whether [NodeStyle.block].
  bool get isBlock => this == NodeStyle.block;

  /// Whether [NodeStyle.flow].
  bool get isFlow => !isBlock;

  /// Whether `this` style is compatible with the [other] style.
  ///
  /// Flow [NodeStyle]s cannot contain embedded [NodeStyle.block] nodes.
  bool isIncompatible(NodeStyle other) => isFlow && other.isBlock;
}

enum CommentStyle {
  /// Comments are dumped before the node and on the same indentation level.
  ///
  /// ```yaml
  /// # Block
  /// "quoted"
  /// ---
  /// # Block
  /// key: value
  /// # Block
  /// next: value
  /// ---
  /// block:
  ///   # Comments
  ///   block
  /// --- {
  /// # Block
  /// key,
  /// # Block
  /// }
  /// ```
  ///
  /// A comment style is interleaved into the [NodeStyle] of a node. It has no
  /// control over how the node is laid.
  block(true),

  /// Comments are dumped before start of the node's meaning content after all
  /// the structural indicators but before its node properties.
  ///
  ///```yaml
  /// - # Possessive
  ///   "quoted"
  /// - ? # Possessive
  ///     key
  ///   : # Possessive
  ///     value
  /// ```
  ///
  /// In a flow context (under special circumstances) or for a root node, this
  /// comment style defaults to [CommentStyle.block].
  ///
  /// ```yaml
  /// # Root is block
  /// [
  ///   # Block
  ///   value
  /// ]
  /// ```
  possessive(true),

  /// Comments are dumped after the node's content if possible.
  ///
  /// ```yaml
  /// {key: value} # comments
  /// ---
  /// [flow] # comments
  /// ---
  /// - plain scalar # with
  ///           # comments
  /// - "quoted" # can
  ///               # also
  ///                  # have
  ///                     # comments.
  /// ```
  ///
  /// Block scalars and block collections have no indicators that demarcate
  /// their start and end offsets.
  ///
  /// ```yaml
  /// - >-
  ///   hello there
  ///       # This comment is content now.
  /// ```
  trailing(false);

  const CommentStyle(this.isPreamble);

  /// Whether the comments are dumped before the node.
  final bool isPreamble;

  /// Obtains a valid [CommentStyle] associated with the [style]. Specifically,
  /// returns [CommentStyle.possessive] if [NodeStyle.block] has
  /// [CommentStyle.trailing].
  CommentStyle ofQualified(NodeStyle style) => style.isFlow
      ? this
      : this == CommentStyle.trailing
      ? CommentStyle.possessive
      : this;
}

/// An object that can be dumped to YAML.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
sealed class DumpableView implements CompactYamlNode {
  /// Comments associated with this view.
  final comments = <String>[];

  /// Whether to force the object inline.
  ///
  /// When `true`, any comments will be ignored if nested within a collection
  /// that was also forced inline.
  ///
  /// ```yaml
  /// # Inlined collection
  /// ["my node", {'or': 'this'}]
  /// ```
  var forceInline = false;

  /// View's comment style.
  var commentStyle = CommentStyle.possessive;
}

/// An alias.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
final class Alias extends DumpableView {
  Alias(this.alias);

  @override
  String alias;

  @override
  String? get anchor => null;

  @override
  NodeStyle get nodeStyle => NodeStyle.flow;

  @override
  ResolvedTag? get tag => null;

  @override
  bool operator ==(Object other) => other is Alias && alias == other.alias;

  @override
  int get hashCode => alias.hashCode;
}

/// A callback for mapping an [object] to the specified [To] type.
typedef ObjectFromView<To> = To Function(Object? object);

/// A node that is not an alias.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
abstract base class ConcreteNode<To> extends DumpableView {
  /// Object that can be dumped as a node
  Object? get node;

  @override
  String? get alias => null;

  @override
  ResolvedTag? tag;

  @override
  String? anchor;

  /// Converts an object to type [To].
  ObjectFromView<To> get toFormat;
}

/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
extension Sandboxed on ConcreteNode {
  /// Updates the object's [ResolvedTag] to a verbatim [tag].
  ConcreteNode withVerbatimTag(VerbatimTag tag) => this..tag = tag;

  /// Updates the object's [ResolvedTag] to a [localTag] resolved to the
  /// specified [globalTag]. If [globalTag] is `null`, the object only has a
  /// generic local tag.
  ConcreteNode withNodeTag(
    TagShorthand localTag, {
    GlobalTag? globalTag,
  }) => this
    ..tag = NodeTag(globalTag ?? localTag, suffix: localTag, isGeneric: false);
}
