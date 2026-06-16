import 'dart:async';

extension StringUtils on String {
  /// Applies the node's properties inline. This is usually all scalars and
  /// flow collections.
  String applyInline({String? tag, String? anchor, String? node}) {
    var dumped = node ?? this;

    void apply(String? prop, [String prefix = '']) {
      if (prop == null) return;
      dumped = '$prefix$prop $dumped';
    }

    apply(tag);
    apply(anchor, '&');
    return dumped;
  }
}

/// Input for the stream.
typedef Writer = void Function(String content);

/// A YAML buffer that buffers the inputs
final class YamlBuffer {
  /// Creates a [YamlBuffer] that calls your callback when the [Dumper] writes
  /// to it.
  YamlBuffer.ofWriter(this._writer);

  /// Creates a [YamlBuffer] that synchronously writes to a string [buffer].
  YamlBuffer.withBuffer(StringBuffer buffer) : this.ofWriter(buffer.write);

  /// Creates a [YamlBuffer] that writes to a [stream] sink.
  ///
  /// The output from this buffer is a valid YAML output that can be piped to
  /// your desired output. You must be careful when using this constructor. The
  /// buffer will not check if your [stream] sink is available for events.
  YamlBuffer.toStream(StreamSink<String> stream) : this.ofWriter(stream.add);

  /// Actual Buffer.
  Writer _writer;

  /// Current indentation.
  int indent = 0;

  /// Indentation step.
  int step = 0;

  /// Dumper's line ending.
  String lineEnding = '\n';

  /// Whether the last write operating included a trailing line break.
  var lastWasLineEnding = false;

  /// Current distance from margin.
  int distanceFromMargin = 0;
}

extension DumperHelpers on YamlBuffer {
  /// Resets `this` buffer with the [updated] indent and clears the internal
  /// string buffer.
  set reset(int updated) {
    indent = updated;
    lastWasLineEnding = false;
    distanceFromMargin = 0;
  }

  /// Updates the internal [writer] used by `this`.
  set writer(Writer? writer) {
    _writer = writer ?? _writer;
  }

  /// Moves the imaginary cursor to the next line by writing a [lineEnding].
  void moveToNextLine() {
    if (lastWasLineEnding) return;
    _writer(lineEnding);
    lastWasLineEnding = true;
    distanceFromMargin = 0;
  }

  /// Writes [content] inline.
  void writeInline(String content) {
    _writer(content);
    distanceFromMargin += content.length;
    lastWasLineEnding = false;
  }

  /// Writes the indent or the number of spaces if [count] is specified.
  void writeSpaceOrIndent([int? count]) => writeInline(' ' * (count ?? indent));

  /// Writes the [lines] to the underlying buffer.
  ///
  /// The [preferredIndent] or [indent] is not applied to the first line.
  ///
  /// If [cursorNextLine] is `true`, a [lineEnding] is written only if the
  /// [lines] didn't have a trailing line break.
  void writeContent(
    Iterable<String> lines, {
    bool cursorNextLine = false,
    int? preferredIndent,
  }) {
    final padding = ' ' * (preferredIndent ?? indent);
    final joined = lines
        .take(1)
        .followedBy(lines.skip(1).map((l) => l.isEmpty ? l : '$padding$l'))
        .join(lineEnding);

    _writer(joined);

    if (joined.endsWith(lineEnding)) {
      distanceFromMargin = 0;
      lastWasLineEnding = true;
      return;
    }

    lastWasLineEnding = false;

    if (!cursorNextLine) {
      distanceFromMargin += lines.lastOrNull?.length ?? 0;
      return;
    }

    moveToNextLine();
  }

  /// Writes the [comments] to the underlying buffer and moves the cursor to
  /// the next line.
  void writeComments(Iterable<String> comments, [int? indent]) {
    if (comments.isEmpty) {
      lastWasLineEnding = false;
      return;
    }

    writeContent(
      comments.map((e) => '#${e.isEmpty ? '' : ' '}$e'),
      cursorNextLine: true,
      preferredIndent: indent,
    );
  }
}

/// A generic YAML Dumper.
abstract class Dumper<T> {
  /// Dumps a [node].
  void dump(T node);

  /// Resets the dumper's internal state.
  void reset();
}
