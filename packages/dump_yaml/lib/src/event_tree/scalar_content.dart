import 'package:dump_yaml/src/strings.dart';
import 'package:dump_yaml/src/unfolding.dart';
import 'package:rookie_yaml/rookie_yaml.dart'
    show
        ScalarStyle,
        CharUtils,
        space,
        ChompingIndicator,
        SpacingUtils,
        tab,
        carriageReturn,
        lineFeed,
        comment,
        mappingKey,
        mappingValue,
        blockSequenceEntry;

/// Splits the [scalar] into separate lines and ensures that it conforms to the
/// [style] as required by the YAML spec. This is done in one-pass.
///
/// If the [scalar] cannot be dumped in the [style] specified, it defaults to
/// [ScalarStyle.doubleQuoted] in the same iteration sequence. This function
/// guarantees that your [style] will be the preferred style as long as your
/// [scalar] conforms to the restriction YAML imposes on such a [style].
({bool isMultiline, bool useParentIndent, Iterable<String> lines}) splitScalar(
  String scalar, {
  required ScalarStyle style,
  required bool emptyAsNull,
  required bool forceInline,
  required bool parentIsBlock,
}) {
  var multiline = false;
  var preferParentIndent = false;

  final lines = _toYamlScalar(
    scalar,
    scalarStyle: style,
    usePlainNull: emptyAsNull,
    forceInline: forceInline,
    parentIsBlock: parentIsBlock,
    isBlock: (useParentIndent) {
      multiline = true;
      preferParentIndent = useParentIndent;
    },
  );

  return (
    isMultiline: multiline || lines.length > 1,
    useParentIndent: preferParentIndent,
    lines: lines,
  );
}

Iterable<String> _toYamlScalar(
  String object, {
  required ScalarStyle scalarStyle,
  required bool usePlainNull,
  required bool forceInline,
  required bool parentIsBlock,
  required void Function(bool useParentIndent) isBlock,
}) sync* {
  if (object.isEmpty && usePlainNull) {
    yield 'null';
    return;
  }

  switch (scalarStyle) {
    case ScalarStyle.doubleQuoted:
      yield* asQuoted(splitUnfoldDoubleQuoted(object, forceInline));

    case ScalarStyle.singleQuoted:
      {
        final (isDoubleQuoted, lines) = splitUnfoldScanned(
          object,
          forceInline: forceInline,
          isSingleQuoted: true,

          // Single quoted style only accepts printable chars
          scan: (_, _, current) => current.isPrintable(),
          unfolding: unfoldNormal,
        );

        yield* asQuoted(lines, isDoubleQuoted ? '"' : "'");
      }

    case ScalarStyle.plain:
      {
        final (isDoubleQuoted, lines) = splitUnfoldScanned(
          object,
          forceInline: forceInline,
          isPlain: true,
          scan: (hasNext, previous, current) {
            if (!hasNext && (current.isLineBreak() || current.isWhiteSpace())) {
              return false;
            }

            return switch (previous) {
              // Cannot start plain with "#". That's just a comment.
              null ||
              space ||
              tab ||
              carriageReturn ||
              lineFeed when current == comment => false,

              // Not allowed by YAML.
              mappingKey ||
              mappingValue ||
              blockSequenceEntry when current.isWhiteSpace() => false,

              // Not safe in flow styles.
              _ when !parentIsBlock && current.isFlowDelimiter() => false,

              _ => true,
            };
          },
          unfolding: unfoldNormal,
        );

        yield* isDoubleQuoted ? asQuoted(lines) : lines;
      }

    // Block Styles
    default:
      {
        final isLiteral = scalarStyle == ScalarStyle.literal;

        final (isDoubleQuoted, lines) = splitUnfoldScanned(
          object,
          forceInline: forceInline,

          // Block styles only accept printable chars
          scan: (_, _, current) => current.isPrintable(),
          unfolding: (lines) {
            // Literal is canonically a restrictive WYSIWYG style.
            return isLiteral ? lines : unfoldBlockFolded(lines);
          },
        );

        if (isDoubleQuoted) {
          yield* asQuoted(lines);
          return;
        }

        var indentationIndicator = 0;

        String header(ChompingIndicator chomping, [String indent = '']) =>
            '${isLiteral ? '|' : '>'}'
            '${indent.isEmpty ? '' : '1'}${chomping.indicator}';

        final leading = lines.firstOrNull;

        if (leading == null || (leading.isEmpty && lines.length == 1)) {
          isBlock(false); // No indentation indicator
          yield header(ChompingIndicator.strip);
          yield '';
          return;
        } else if (leading.startsWith(' ')) {
          // Block styles infer indent from the first non-empty line and ignore
          // any indentation recommendations by the parser. Force the node
          // inwards and use an indentation indicator.
          indentationIndicator = 1;
        }

        final useParent = indentationIndicator > 0;
        isBlock(useParent); // Must use parent indent.

        yield header(
          lines.last.isEmpty ? ChompingIndicator.keep : ChompingIndicator.strip,
          ' ' * indentationIndicator,
        );

        // Under special circumstances, the line break in the ScalarStyle.folded
        // header is included while folding.
        final blockLines = isLiteral || leading.isNotEmpty
            ? lines
            : lines.skip(1);

        yield* useParent ? blockLines.map((e) => ' $e') : blockLines;
      }
  }
}
