import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/block_dumper.dart';
import 'package:dump_yaml/src/dumper/dumper.dart';
import 'package:dump_yaml/src/dumper/preamble.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/tree_builder.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

extension on Iterable<Directive> {
  /// Extracts the [GlobalTag]s from `this`.
  (List<Directive> nonGlobals, List<GlobalTag> globals) filter() {
    return fold((<Directive>[], <GlobalTag>[]), (previous, directive) {
      directive is GlobalTag
          ? (previous.$2.add(directive))
          : previous.$1.add(directive);

      return previous;
    });
  }
}

/// A YAML document dumper.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
final class YamlDumper extends Dumper<Object?> {
  /// Creates a [YamlDumper] that uses the specified [config]uration.
  YamlDumper({required Config config, required YamlBuffer buffer}) {
    _init(config.yamlConfig, buffer);
  }

  /// Initializes a [YamlDumper] that buffers to a string [buffer].
  YamlDumper.toStringBuffer({
    required Config config,
    required StringBuffer buffer,
  }) : this(config: config, buffer: YamlBuffer.withBuffer(buffer));

  /// Builds the YAML representation tree.
  late final TreeBuilder treeBuilder;

  /// Dumps the `TreeNode` emitted by the [treeBuilder].
  late final BlockDumper dumper;

  /// Persists config for the representation tree.
  ///
  /// Must remain `null` after [dump] has been called. Will always be `null` if
  /// [dump] is never called. This behaviour allows the [treeBuilder] to reuse
  /// its copy of the config and only rely on `this` to provide a fresh copy.
  TreeConfig? _treeConfig;

  /// Whether to include the parser version the dumper is pinned to.
  late bool _includeParserVersion;

  /// Document directives included everytime [dump] is called.
  Set<Directive>? _directives;

  /// Whether to include the directive end characters.
  late bool _addDirectiveEnd;

  /// Whether to include the document end characters.
  late bool _addDocEnd;

  /// Initializes `this` dumper and its members.
  void _init(YamlConfig config, YamlBuffer buffer) {
    final (:docConfig, :formatting, :styling) = config;
    treeBuilder = TreeBuilder(styling);

    final (:rootIndent, :indentationStep, :lineEnding) = formatting.config;
    dumper = BlockDumper(
      buffer
        ..indent = rootIndent
        ..step = indentationStep
        ..lineEnding = lineEnding,
    );

    _docInit(docConfig);
  }

  /// Initializes the document config specifically handled by `this` dumper.
  void _docInit(DocConfig config) {
    _includeParserVersion = config.includeParserVersion;
    _addDirectiveEnd = config.addDirectiveEnd;
    _addDocEnd = config.addDocEnd;

    _directives =
        (_directives
          ?..clear()
          ..addAll(config.directives)) ??
        {...config.directives};
  }

  /// Resets the dumper.
  ///
  /// If [config] is `null`, `Config.defaults()` is used.
  @override
  void reset({Config? config, Writer? writer}) {
    final (:docConfig, :formatting, :styling) =
        (config ?? Config.defaults()).yamlConfig;

    _treeConfig = styling;
    _docInit(docConfig);

    final (:rootIndent, :indentationStep, :lineEnding) = formatting.config;
    dumper.buffer
      ..writer = writer
      ..reset = rootIndent
      ..step = indentationStep
      ..lineEnding = lineEnding;

    dumper.reset();
    treeBuilder.withGlobalTags(Iterable.empty());
  }

  /// Dumps the [root] node.
  void _dumpObject(
    YamlBuffer buffer, {
    required TreeNode<Object> root,
    required int rootIndent,
  }) {
    final TreeNode(:commentStyle, :comments) = root;

    buffer.writeSpaceOrIndent(); // Leading indent.

    // Comments are dumped from a node level with more context. The document, in
    // this case, has the context.
    if (commentStyle.isPreamble) {
      blockEntryStart(buffer, CommentStyle.block, rootIndent, '', comments);
      dumper.dump(root);
      return;
    }

    dumper.dump(root);
    blockEntryEnd(buffer, CommentStyle.trailing, comments, rootIndent, false);
  }

  void _endOfDirectives(YamlBuffer buffer) => buffer
    ..writeInline(DocumentMarker.directiveEnd.indicator)
    ..moveToNextLine();

  /// Dumps the [node] as a valid YAML document based on the current
  /// configuration state.
  @override
  void dump(Object? node, {ExpandObject? expand}) {
    final buffer = dumper.buffer;
    final (otherDirectives, globals) = _directives!.filter();

    treeBuilder
      ..mapper = expand
      ..includeGlobalTags(globals)
      ..buildFor(node, config: _treeConfig);

    final (:root, :tags) = treeBuilder.builtDocument();

    // Use tags from the tree. [dumper.treeBuilder.*] may have been called.
    final docDirectives = <Directive>[
      ?(_includeParserVersion ? parserVersion : null),
    ].followedBy(tags).followedBy(otherDirectives).map((e) => e.toString());

    if (docDirectives.isNotEmpty) {
      // Write each directive on a separate line.
      _endOfDirectives(
        buffer..writeContent(
          docDirectives,
          cursorNextLine: true,
          preferredIndent: 0,
        ),
      );
    } else if (_addDirectiveEnd) {
      _endOfDirectives(buffer);
    }

    final rootIndent = buffer.indent;
    _dumpObject(buffer, root: root, rootIndent: rootIndent);

    if (_addDocEnd) {
      if (!buffer.lastWasLineEnding) buffer.moveToNextLine();
      buffer.writeInline(DocumentMarker.documentEnd.indicator);
    }

    _treeConfig = null; // [TreeBuilder] persists its copy.
    buffer.indent = rootIndent;
  }
}

/// Dumps an [object] to YAML using the [config] provided.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
String dumpAsYaml(Object? object, {Config? config, ExpandObject? expand}) {
  final buffer = StringBuffer();
  YamlDumper.toStringBuffer(
    config: config ?? Config.defaults(),
    buffer: buffer,
  ).dump(object, expand: expand);
  return buffer.toString();
}
