/// Offset information.
///
/// `lineIndex` - zero-based line index in the source string.<br>
/// `columnIndex` - zero-based column index within a line.<br>
/// `span` - number of UTF-? (8 OR 16) code units in this offset.<br>
/// `rawOffset` - zero-based offset within the actual source.<br>
/// `offset` - zero-based index in the source being read. (after all the
/// surrogates/code units have been combined).
///
/// Use `rawOffset` if you need to work with the actual source. Use `offset` if
/// you need to perform operations on complete unicode code unit chunks such
/// as UTF-16 strings.
typedef RuneOffset = ({
  int lineIndex,
  int columnIndex,
  int span,
  int rawOffset,
  int offset,
});

/// Range offset within a YAML input.
typedef RuneSpan = ({RuneOffset start, RuneOffset end});

/// Offset information for a parsed YAML node.
///
/// Always represents the start of the first parsable character of the node.
/// For top-level nodes, this doesn't include document level comments.
sealed class NodeSpan {
  /// Actual start offset when the current node is part of a node that allows
  /// arbitrary use of YAML indicators to demarcate it structure. For the
  /// parser, this is the node's first parsable content.
  ///
  /// This should not be confused with [nodeStart] and [nodeEnd] offsets which
  /// accurately describe the node's own structure independent of surrounding
  /// nodes. This will always be `null` for a top-level:
  ///   - Flow collection, quoted scalar and block scalar since their
  ///     indicators are part of the node's structure.
  ///   - Block collection and plain scalar.
  ///
  /// For a block sequence entry, this represents the offset of the `-`
  /// indicator.
  ///
  /// ```yaml
  /// - "hello"
  /// - 'world'
  /// - block: map
  /// - {flow: map}
  /// - [flow, sequence]
  /// ```
  ///
  /// In a block/flow map, this represents the offset of the `?` indicator when
  /// the node is an explicit key and `:` when the node is a value to an
  /// explicit/implicit key. For implicit keys, this will always be `null`.
  ///
  /// ```yaml
  /// - ? explicit
  ///   : entry
  ///   implicit: entry
  /// - {? this, : is, valid: }
  /// - [this: compact, ? notation, ? is : acceptable]
  /// ```
  RuneOffset? get structuralOffset;

  /// Span information for a node's property. This includes the `*` of an alias,
  /// `!!` of a tag and `&` of an anchor.
  ///
  /// ```yaml
  /// !!map {}
  /// ---
  /// - &hello !!str world
  /// - *hello
  /// ```
  RuneSpan? get propertySpan;

  /// Actual start offset of the node.
  ///
  /// For an alias, this represents the end offset of its alias name since it
  /// acts as a reference to another node. Thus, to an alias, the span
  /// information [nodeStart] to [nodeEnd] represents its layout in the YAML
  /// source. Prefer using [propertySpan] if you want its name's offset.
  RuneOffset get nodeStart;

  /// Exclusive end offset of the node's meaningful content.
  RuneOffset get nodeEnd;

  /// Exclusive end offset of the node.
  ///
  /// Unlike [nodeEnd], this may represent the offset past any trailing comments
  /// and empty lines that are not considered part of the node's meaningful
  /// content by the parser.
  ///
  /// In flow entries, this points to the character after `,` or `}`
  /// (when in map) or `]` (when in sequence).
  ///
  /// ```yaml
  /// # The scalar "hello" ends at `]` (exclusive).
  /// [hello]
  /// ---
  /// # This is valid yaml. Ends at `]` (exclusive).
  /// [hello,]
  /// ---
  /// # Ends at `,` (inclusive). So this offset points at the space " ".
  /// # The "," indicates the start of the next entry and acts as a marker for
  /// # the previous entry.
  /// [hello, next]
  /// ```
  RuneOffset end();

  @override
  String toString() {
    return '''
Structural Offset: $structuralOffset
Property Span: $propertySpan
Content Start: $nodeStart
Content End: $nodeEnd
Parsing End: ${end()}
''';
  }
}

/// Span information about a yaml node from a source string/bytes.
final class YamlSourceSpan extends NodeSpan {
  YamlSourceSpan(this.nodeStart) : nodeEnd = nodeStart;

  @override
  RuneOffset? structuralOffset;

  @override
  RuneSpan? propertySpan;

  @override
  RuneOffset nodeStart;

  @override
  RuneOffset nodeEnd;

  /// Exclusive end determined by a parsing function with more context than
  /// that which emitted [nodeEnd].
  RuneOffset? parsingEnd;

  @override
  RuneOffset end() => parsingEnd ?? nodeEnd;
}
