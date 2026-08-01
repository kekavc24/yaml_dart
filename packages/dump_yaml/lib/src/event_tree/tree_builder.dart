import 'dart:collection';

import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/event_tree/hashing.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/scalar_content.dart';
import 'package:dump_yaml/src/event_tree/visitor.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

extension on String {
  String capFirst() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

final _missing = TagShorthand.primary('unresolved');

/// Callback for tracking the current path.
typedef PathLogger = void Function(String path);

/// Callback for lazily mapping an object to another.
typedef ExpandObject = Object? Function(Object? object);

typedef _TagInfo = ({String? qualifiedTag, String generic});

typedef _IfNotRecursive<T> =
    void Function(
      String recursiveAnchor,
      String? qualifiedTag,
      LazyHash hash,
      T object,
    );

void _noOp(String _) {}

mixin _Decomposer {
  /// Anchors in the document.
  final _anchors = <String, FreeHash?>{};

  /// Global tags.
  final _globalTags = <TagHandle, GlobalTag>{};

  String? _pushAnchor(String? anchor, FreeHash hash) {
    if (anchor != null) _anchors[anchor] = hash;
    return anchor;
  }

  /// Unpacks a resolved [nodeTag] and returns the verbatim/local tag associated
  /// with the node.
  ///
  /// If [includeGeneric] is `true`, generic YAML schema tags assigned by the
  /// parser will be included.
  String? _localTag(
    ResolvedTag? nodeTag, {
    required void Function(TagShorthand tag) validate,
  }) {
    if (nodeTag == null) return null;
    final (:verbatim, :globalTag, :tag) = resolvedTagInfo(nodeTag);

    // Cannot have verbatim and global/local tag.
    if (verbatim != null) return verbatim;

    var namedHasGlobal = false;

    if (globalTag != null) {
      final globalHandle = globalTag.tagHandle;

      // A global tag is like an anchor URI for a local tag's handle which acts
      // as the alias.
      if (globalHandle != tag?.tagHandle) {
        throw FormatException(
          '''
Global tag handle doesn't match local tag handle.
  Global tag handle: ${globalTag.tagHandle}
  Local tag handle: ${tag?.tagHandle}
''',
        );
      }

      final existing = _globalTags.putIfAbsent(globalHandle, () => globalTag);

      // Multiple global tags cannot alias the same handle multiple times in the
      // same document.
      if (existing != globalTag) {
        throw FormatException(
          '''
A global tag with the current tag handle already exists.
  Existing: $existing
  Update: $globalTag
''',
        );
      }

      namedHasGlobal = true;
    }

    if (tag == null) return null;
    validate(tag);

    // Ensure our named handle has a global tag.
    if (tag.tagHandle.handleVariant == TagHandleVariant.named &&
        !namedHasGlobal) {
      throw FormatException(
        'The named local tag "$tag" has no global tag for its named handle',
      );
    }

    return tag.toString();
  }

  TagShorthand _genericTag(Object? object) => switch (object) {
    Iterable() => /* object is Set ? setTag : */ sequenceTag,
    Map() => mappingTag,
    int() => integerTag,
    double() => floatTag,
    String() => stringTag,
    bool() => booleanTag,
    null => nullTag,
    _ => _missing,
  };

  /// Matches the [object] to its YAML Schema tag only if [includeGeneric] is
  /// `true`.
  _TagInfo _genericIfMissing({
    Object? object,
    bool includeGeneric = false,
    TagShorthand? qualified,
    TagShorthand? generic,
  }) {
    final genericTag = qualified ?? generic ?? _genericTag(object);
    return (
      qualifiedTag: (qualified ?? (includeGeneric ? genericTag : null))
          ?.toString(),
      generic: genericTag.toString(),
    );
  }
}

/// Maps object to itself.
Object? _identity(Object? object) => object;

/// A builder that recreates a YAML representation tree for a dumper to dump.
///
/// {@category rep_tree}
final class TreeBuilder with _Decomposer, DartTypeVisitor, ViewVisitor {
  /// Creates a [TreeBuilder] with the provided [treeConfig].
  ///
  /// If [logger] is provided, the tree pushes the paths visited to this
  /// callback. Collections are annotated as their `runtimeType`. For scalars,
  /// the [logger] is called after the node has been visited.
  ///
  /// ```yaml
  /// # Path with iterable
  /// [Iterable]/0/value
  /// ---
  /// # Path with map
  /// [Map]/key/value
  /// ```
  TreeBuilder([TreeConfig? treeConfig, PathLogger logger = _noOp])
    : _config = (treeConfig ?? TreeConfig.block()).config,
      _pathLogger = logger,
      _mapper = _identity;

  /// Node Styling information.
  NodeConfig _config;

  /// Callback used to track the current path of the tree.
  PathLogger _pathLogger;

  /// Callback for mapping an object.
  ExpandObject _mapper;

  /// Updates the lazy mapper.
  set mapper(ExpandObject? mapper) => _mapper = mapper ?? _mapper;

  /// Global stack for pushing any built nodes.
  final _nodes = ListQueue<TreeNode<Object>>();

  /// Number of nodes currently in the internal build queue.
  int get stackSize => _nodes.length;

  /// Global stack with the current collection's [NodeStyle].
  final _collectionStyles = ListQueue<NodeStyle>();

  /// Global stack with the current collection's inline enforcement rules.
  final _inlineRules = ListQueue<bool>();

  /// Path to the current node.
  final _typePath = ListQueue<String>();

  /// Whether to reset the global tags before building the tree.
  var _resetTags = false;

  /// Number of anonymous objects without an anchor. Used as a suffix.
  int? _recursiveCount;

  /// Tracks the current collection-like object being walked.
  final _recursiveTracker = HashMap<Object?, (String, FreeHash)>.identity();

  /// Links an [object] to an [anchor] just before the builder walks.
  String _trackRecursive(Object? object, FreeHash hash, String? anchor) {
    String fetchCount() {
      var out = '';

      if (_recursiveCount != null) {
        out = '-${_recursiveCount!.toString()}';
        _recursiveCount = _recursiveCount! + 1;
      } else {
        _recursiveCount = 0;
      }

      return out;
    }

    final tracker = anchor ?? 'recursive${fetchCount()}';
    _recursiveTracker[object] = (tracker, hash);
    return tracker;
  }

  /// Throws a [StateError] with the [message] and includes the [_currentPath].
  Never _stateErrorWithPath(String message) =>
      _stateError('$message\n\tPath: ${_typePath.join('->')}');

  /// Throws a [StateError] with the [message].
  Never _stateError(String message) => throw StateError(message);

  void _reset() {
    _anchors.clear();
    _collectionStyles.clear();
    _inlineRules.clear();
    _typePath.clear();
    _recursiveCount = null;
    _recursiveTracker.clear();
  }

  /// Adds the [node] to the LIFO queue.
  void _addNode(TreeNode<Object> node) => _nodes.add(node);

  /// Adds the current [path] being iterated by the tree.
  void _pushPath(String path) {
    _typePath.addLast(path);
    _pathLogger(path);
  }

  /// Pops the [count] of paths provided.
  void _popPaths([int count = 1]) {
    for (var i = 0; i < count; i++) {
      _typePath.removeLast();
    }
  }

  /// Nearest collection's [NodeStyle].
  NodeStyle _nearestCollection() => _collectionStyles.last;

  /// Whether the current [style] is compatible with the [parent]'s style.
  ///
  /// If [parent] is `null`, this method looks for the last collection's
  /// [NodeStyle] it encountered.
  bool _buildWithStyle(NodeStyle style, [NodeStyle? parent]) =>
      !((parent ?? _nearestCollection()).isIncompatible(style));

  _TagInfo _tagFromView(
    ResolvedTag? tag, {
    required TagShorthand generic,
    required void Function(TagShorthand tag) validate,
  }) {
    final qualified = _localTag(tag, validate: validate);
    return (qualifiedTag: qualified, generic: qualified ?? generic.toString());
  }

  /// Visits a recursive [object] and tracks the object's state.
  void _visitRecursiveCandidate<T>(
    T object, {
    required _IfNotRecursive<T> visit,
    required bool isMap,
    required _TagInfo tagInfo,
    String? anchorOnVisit,
    Iterable<String>? comments,
    CommentStyle? commentStyle,
  }) {
    if (_recursiveTracker[object] case (String anchored, FreeHash refHash)) {
      _addNode(
        ReferenceNode(
          anchored,
          nodeHash: refHash,
          comments: comments,
          commentStyle: commentStyle,
          recursive: true,
        ),
      );

      _typePath.addLast(anchored);
      return;
    }

    final hash = LazyHash(isMap: isMap, seedTag: tagInfo.generic);
    final anchor = _trackRecursive(object, hash, anchorOnVisit);
    visit(anchor, tagInfo.qualifiedTag, hash, object);
    _recursiveTracker.remove(object);
  }

  @override
  void visitObject(Object? object) => switch (_mapper(object)) {
    DumpableView view => visitView(view),
    TreeNode<Object> node => _addNode(node),
    Object? mapped => super.visitObject(mapped),
  };

  @override
  void visitAlias(Alias alias) {
    final ref = alias.alias;

    if (_anchors.containsKey(ref)) {
      var hash = _anchors[ref];

      // Assume that these anchors injected into the builder.
      if (hash == null) {
        hash = QualifiedHash.danglingReference(ref);
        _anchors[ref] = hash;
      }

      _addNode(
        ReferenceNode(
          ref,
          nodeHash: hash,
          comments: alias.comments,
          commentStyle: alias.commentStyle,
        ),
      );

      _typePath.addLast(ref);
      return;
    }

    _stateErrorWithPath('Unknown alias "$ref"');
  }

  @override
  void visitIterable(Iterable<Object?> iterable) => _visitRecursiveCandidate(
    iterable,
    isMap: false,
    tagInfo: _genericIfMissing(
      includeGeneric: _config.includeSchemaTag,
      generic: sequenceTag,
    ),
    visit: (anchor, tag, hash, object) => _buildIterable(
      object,
      style: _config.iterableStyle,
      hash: hash,
      localTag: tag,
      forceInline: _inlineRules.last,
      recursiveAnchor: anchor,
    ),
  );

  @override
  void visitIterableView(YamlIterable iterable) {
    final YamlIterable(:node, :anchor, :comments, :commentStyle) = iterable;

    _visitRecursiveCandidate(
      iterable.node,
      isMap: false,
      tagInfo: _tagFromView(
        iterable.tag,
        generic: sequenceTag,
        validate: throwIfNotListTag,
      ),
      comments: comments,
      commentStyle: commentStyle,
      anchorOnVisit: anchor,
      visit: (recursive, tag, hash, object) => _buildIterable(
        iterable.toFormat(object),
        style: iterable.nodeStyle,
        hash: hash,
        forceInline: iterable.forceInline || _inlineRules.last,
        comments: comments,
        anchor: anchor,
        recursiveAnchor: recursive,
        commentStyle: commentStyle,
        localTag: tag,
      ),
    );
  }

  @override
  void visitMap(Map<Object?, Object?> map) => _visitRecursiveCandidate(
    map,
    isMap: true,
    tagInfo: _genericIfMissing(
      includeGeneric: _config.includeSchemaTag,
      generic: mappingTag,
    ),
    visit: (anchor, tag, hash, object) => _buildMap(
      object.entries,
      style: _config.mapStyle,
      hash: hash,
      localTag: tag,
      forceInline: _inlineRules.last,
      recursiveAnchor: anchor,
    ),
  );

  @override
  void visitMappingView(YamlMapping mapping) {
    final YamlMapping(:node, :anchor, :comments, :commentStyle) = mapping;

    _visitRecursiveCandidate(
      mapping.node,
      isMap: true,
      tagInfo: _tagFromView(
        mapping.tag,
        validate: throwIfNotMapTag,
        generic: mappingTag,
      ),
      anchorOnVisit: anchor,
      comments: comments,
      commentStyle: commentStyle,
      visit: (recursive, tag, hash, object) => _buildMap(
        mapping.toFormat(object),
        style: mapping.nodeStyle,
        hash: hash,
        forceInline: mapping.forceInline || _inlineRules.last,
        comments: comments,
        anchor: anchor,
        recursiveAnchor: recursive,
        commentStyle: commentStyle,
        localTag: tag,
      ),
    );
  }

  @override
  void visitScalar(Object? scalar) => _buildScalar(
    scalar?.toString() ?? '',
    scalarStyle: _config.scalarStyle,
    tagInfo: _genericIfMissing(
      object: scalar,
      includeGeneric: _config.includeSchemaTag,
    ),
    forceInline: _inlineRules.last,
  );

  @override
  void visitScalarView(ScalarView scalar) {
    final ScalarView(:node) = scalar;

    _buildScalar(
      scalar.toFormat(node),
      scalarStyle: scalar.scalarStyle,
      emptyAsNull: scalar.emptyAsNull,
      forceInline: scalar.forceInline || _inlineRules.last,
      comments: scalar.comments,
      anchor: scalar.anchor,
      commentStyle: scalar.commentStyle,
      tagInfo: _tagFromView(
        scalar.tag,
        validate: throwIfNotScalarTag,
        generic: _genericTag(node),
      ),
    );
  }

  /// Builds a [scalar].
  void _buildScalar(
    String scalar, {
    required ScalarStyle scalarStyle,
    required bool forceInline,
    required _TagInfo tagInfo,
    bool emptyAsNull = false,
    List<String>? comments,
    String? anchor,
    CommentStyle? commentStyle,
  }) {
    final collectionStyle = _nearestCollection();
    final dumpingStyle = _buildWithStyle(scalarStyle.nodeStyle, collectionStyle)
        ? scalarStyle
        : classicScalarStyle;

    final (:isMultiline, :lines, :useParentIndent) = splitScalar(
      scalar,
      style: dumpingStyle,
      emptyAsNull: emptyAsNull || _config.emptyAsNull,
      forceInline: forceInline,

      // It's okay if this is the top level node. By YAML standards, it is.
      parentIsBlock: collectionStyle.isBlock,
    );

    final hash = QualifiedHash.scalar(tagInfo.generic, scalar);

    _addNode(
      ContentNode(
        lines,
        dumpingStyle.nodeStyle,
        nodeHash: hash,
        inheritParentIndent: useParentIndent,
        isMultiline: isMultiline,
        comments: comments,
        anchor: _pushAnchor(anchor, hash),
        localTag: tagInfo.qualifiedTag,
        commentStyle: commentStyle?.ofQualified(dumpingStyle.nodeStyle),
      ),
    );

    _typePath.addLast(scalar);
  }

  /// Builds an [iterable] of objects.
  void _buildIterable(
    YamlIterableEntry iterable, {
    required NodeStyle style,
    required bool forceInline,
    required String recursiveAnchor,
    required LazyHash hash,
    List<String>? comments,
    String? anchor,
    String? localTag,
    CommentStyle? commentStyle,
  }) => _buildCollection(
    iterable,
    style: style,
    nodeType: NodeType.list,
    hash: hash,
    iterate: (index, element) {
      _pushPath(index.toString());
      visitObject(element);
      return true;
    },
    compose: (hash) {
      // One in, one out
      final element = _nodes.removeLast();
      _popPaths(2);
      hash.incrementalOnDemand(element.nodeHash.hexHash);
      return (element.isMultiline, element);
    },
    forceInline: forceInline,
    comments: comments,
    commentStyle: commentStyle,
    anchor: anchor,
    recursiveAnchor: recursiveAnchor,
    localTag: localTag,
    type: NodeType.list,
  );

  /// Builds a map using its [iterable] of entries.
  void _buildMap(
    YamlMappingEntry iterable, {
    required NodeStyle style,
    required String recursiveAnchor,
    required LazyHash hash,
    bool forceInline = false,
    List<String>? comments,
    String? anchor,
    String? localTag,
    CommentStyle? commentStyle,
  }) {
    final keysSeen = HashMap<NodeType, Iterable<FreeHash>>();

    // DartMap is just a helpful wrapper for a map.
    bool pushKey(TreeNode<Object> node) {
      final TreeNode(:nodeType, :nodeHash) = node;

      switch (keysSeen[nodeType]) {
        case Set<FreeHash> set:
          return set.add(nodeHash);

        case ListQueue<FreeHash> queue:
          {
            final set = queue.toSet();
            final seen = set.add(nodeHash);

            // Some collection nodes were finalized.
            if (set.length != queue.length) {
              keysSeen[nodeType] = ListQueue.of(set);
            }

            return seen;
          }

        default:
          {
            keysSeen[nodeType] = nodeType == NodeType.alias
                ? (ListQueue()..add(nodeHash))
                : {nodeHash};

            return true;
          }
      }
    }

    _buildCollection(
      iterable,
      style: style,
      nodeType: NodeType.map,
      hash: hash,
      iterate: (_, element) {
        visitObject(element.key);

        // Quickly determine if this is a duplicate.
        if (!pushKey(_nodes.last)) {
          _nodes.removeLast();
          return false;
        }

        visitObject(element.value);
        return true;
      },
      compose: (hash) {
        // Two in, two out
        final value = _nodes.removeLast();
        final key = _nodes.removeLast();
        hash.incrementalOnDemand(key.nodeHash.hexHash, value.nodeHash.hexHash);
        _popPaths(2);
        return (key.isMultiline || value.isMultiline, (key, value));
      },
      forceInline: forceInline,
      comments: comments,
      commentStyle: commentStyle,
      anchor: anchor,
      recursiveAnchor: recursiveAnchor,
      localTag: localTag,
      type: NodeType.map,
    );
  }

  /// Builds a collection using its entries in the current [iterable]. [iterate]
  /// and [compose] is called on every element.
  void _buildCollection<E, T>(
    Iterable<E> iterable, {
    required NodeStyle style,
    required NodeType nodeType,
    required LazyHash hash,
    required bool Function(int index, E element) iterate,
    required (bool isMultiline, T value) Function(LazyHash hash) compose,
    required bool forceInline,
    required List<String>? comments,
    required String? anchor,
    required String recursiveAnchor,
    required String? localTag,
    required CommentStyle? commentStyle,
    required NodeType type,
  }) {
    var buildStyle = forceInline ? NodeStyle.flow : style;
    final parent = _nearestCollection();
    buildStyle = _buildWithStyle(style, parent) ? style : parent;

    _collectionStyles.addLast(buildStyle);
    _inlineRules.add(forceInline);
    _typePath.add('[${type.toString().capFirst()}]');

    var spanMultipleLines = buildStyle.isBlock;
    var hasRecursiveRef = false;

    void update(bool isMultiline, T child) {
      hasRecursiveRef =
          hasRecursiveRef ||
          isRecursiveAnchorRef(child, anchor ?? recursiveAnchor);
      if (forceInline) return;
      spanMultipleLines = spanMultipleLines || isMultiline;
    }

    final queue = ListQueue<T>();

    for (final (index, element) in iterable.indexed) {
      if (!iterate(index, element)) continue;
      final (isMultiline, node) = compose(hash);
      update(isMultiline, node);
      queue.addLast(node);
    }

    _addNode(
      CollectionNode(
        queue,
        buildStyle,
        nodeHash: hash,
        nodeType: nodeType,
        forcedInline: forceInline,
        isMultiline: spanMultipleLines && queue.isNotEmpty,
        anchor: _pushAnchor(
          anchor ?? (hasRecursiveRef ? recursiveAnchor : null),
          hash,
        ),
        localTag: localTag,
        comments: comments,
        commentStyle: commentStyle?.ofQualified(buildStyle),
      ),
    );

    _collectionStyles.removeLast();
    _inlineRules.removeLast();
  }

  /// Document represent by the tree.
  ///
  /// This document is "light" and only provides the global tags obtained from
  /// the object called with [buildFor]. Always throws if [buildFor] was never
  /// called at least once.
  DocumentNode builtDocument() =>
      (tags: UnmodifiableListView(_globalTags.values), root: builtNode());

  /// Root node of the tree.
  ///
  /// Always throws if [buildFor] was never called at least once.
  TreeNode<Object> builtNode<T>() => _nodes.first;

  /// Builds an event tree for an [object].
  ///
  /// The builder expects the [object] to be a built-in Dart type or a
  /// [DumpableView] of any Dart object.
  void buildFor(Object? object, {TreeConfig? config, PathLogger? logger}) {
    _config = config?.config ?? _config;
    _pathLogger = logger ?? _pathLogger;
    _nodes.clear();

    if (_resetTags) _globalTags.clear();

    _collectionStyles.add(_config.rootNodeStyle);
    _inlineRules.add(_config.forceInline);

    visitObject(object);
    _reset();
    _resetTags = true;
  }
}

/// {@category rep_tree}
extension InjectState on TreeBuilder {
  /// Adds the global [tags] if their handles are absent.
  void includeGlobalTags(Iterable<GlobalTag> tags) {
    if (_resetTags) _globalTags.clear();

    for (final gTag in tags) {
      final handle = gTag.tagHandle;

      if (_globalTags.containsKey(handle)) continue;
      _globalTags[gTag.tagHandle] = gTag;
    }

    _resetTags = false;
  }

  /// Removes existing global tags and adds these global [tags].
  void withGlobalTags(Iterable<GlobalTag> tags) {
    _globalTags.clear();
    includeGlobalTags(tags);
  }

  /// Adds any [anchors] not tracked by this builder.
  ///
  /// This method should only be called if you are sure at least one object
  /// within the tree includes such an anchor in its properties.
  void includeAnchors(Iterable<String> anchors) {
    for (final anchor in anchors) {
      _anchors[anchor] = null;
    }
  }
}
