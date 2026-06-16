# Changelog

## 0.7.0-pre.3

This release improves how the parser handles various YAML grammar edge cases in block and flow collections. This change also includes a variety of regression tests for these edge cases.

> PS: We hit.. 96.95% 🎉 .. after running the official YAML test suite. 🥳

`fix`:
  - Fixes how the parser handles indents when exiting a block collection`s parsing context.
  - Tightens the grammar evaluations when handling `?`, `-` and `:` when inferring events.
  - Tightens the comment grammar and requires whitespace before `#` indicator.
  - Ensures a block map retains the structural offset of `-`, `:`, and `?` in its `NodeSpan`.
  - Fixes an issue where tabs were treated as indent in certain block contexts.
  - Strictly requires whitespace as separation when parsing compact block collections.
  - Removes implicit key restrictions in flow maps which accepts generic flow nodes in its grammar.

## 0.7.0-pre.2

`BREAKING`:
  - `YamlDocument` has been made abstract. Prefer using `ImmutableDocument`.
  - `DocBuilder` callback no longer provides the buffered `YamlComment`s.
  - Renames the `ofBytes` constructor to `ofUnicode` in `UnicodeIterator`.

`feat`:
  - Adds `span` param to `RuneOffset` which tracks the number of code units a single offset represents.
  - Adds an `onParseComment` method to `CustomTriggers`.

## 0.7.0-pre.1

This release focuses reducing the scope of `package:rookie_yaml` and migrating any non-parser functionality to external packages. It also includes minor QoL improvements. See progress [here](https://github.com/kekavc24/yaml_dart).

`BREAKING`:
  - Migrate `YamlSourceNode` and related classes to `package:editable_yaml` (unreleased).
  - Migrates the YAML dumper to [`package:dump_yaml`](https://pub.dev/packages/dump_yaml).
  - Renames YAML loaders.
    - `loadDartObject` renamed to `loadObject`.
    - `loadDartObjects` renamed to `loadAllObjects`.

## 0.6.0

This release revamps `YamlSourceNode` and adds a richer node span implementation.

`BREAKING`:
  - Removes `YamlNode` in favour of `CompactYamlNode`.
  - `Mapping` and `Sequence` can be iterated as built-in Dart types. Prefer calling the `children` getter if you need to iterate them as `YamlSourceNode`s.
  - `Mapping` and `Sequence` are now mutable out-of-the-box.

`experimental`:
  - Adds support for walking the entire YAML tree from a single node.
    - You'll have to write code to do this (for now) but its doable.
  - Adds a richer `NodeSpan` implementation.

`feat`:
  - Doc builder function now has the latest copy of the anchors used to parse the document.
  - Adds support for checking whether a tag is generic (provided by parser) or explicit (yours).
  - Adds support for accepting strongly typed objects when extending `MappingToObject` and `SequenceToObject`.

`fix`:
  - Prevents a map's property from being overwritten if the kind is unknown.
  - Sets the end offset of a plain correctly after an indent change.

## 0.5.1

- Fixes README and adds topic for pub.

## 0.5.0

This version focuses on adding support for parsing objects directly from raw UTF input.

`feat(parser)`:
  - Adds support for parsing a yaml document directly from a raw UTF input.
  - Exposes the internal `DocumentParser` API.

`feat(dumper)`:
  - Adds support for providing a mapper function when dumping objects.

`docs`
  - README and pub guide improvements.
  - Fixes typos in docs.

## 0.4.0

Happy (belated) new year! 🎉

This release overhauls the dumper and improves the developer experience for external resolvers.

`BREAKING`:
  - Drops support for `DartNode` and `DynamicMapping`. Use built-in Dart type loaders instead.
  - Drops support for `NodeResolver` and `TypeResolver` tags. Use built-in Dart type loaders instead.
  - Drops support for the `asCustomType` extension added for `YamlSourceNode`. Use built-in Dart type loaders instead.

`feat(parser)`:
  - Improves `ScalarResolver` dx.
  - Improves support for external resolvers.
    - Adds `CustomTriggers`. Acts as a top-level plugin to the underlying parser.
    - Adds `CustomResolver`. Replaces `NodeResolver`.
    - Adds support for custom objects via external delegates which interact with the parser.
  - Improves tags-as-code dx.
  - Improves how scalars are parsed. Parser can now parse scalars in a single-pass.

`feat(dumper)`:
  - Overhauls the dumper.
  - Adds support for intuitively adding properties to objects being dumped. See docs.
  - Adds support for adding comments to objects being dumped.

`fix`:
  - Ensures the end offset for plain scalars is set correctly.
  - Fixes an issue where all flow delimiters were treated as uri chars.
  - Calculates the indent correctly for block scalars with an indentation indicator.
    - Folds empty lines correctly when an indentation indicator is present in `ScalarStyle.folded`.

## 0.3.1

This release focuses on adding support for more YAML features and the internal test coverage making it a solid alternative to existing YAML parsers.

`BREAKING` (temporary):
  - Dart values can no longer be used as keys when a parsed `YamlSourceNode` is a `Mapping`.

`feat`:
  - Added a plausible start offset of the error to `YamlParserException`.
  - Improved support for block sequences declared on the same level as their block map key.

`fix`:
  - Ensures verbatim tags begin with the `tag:` uri prefix if they are not declared as local tags.
  - Fixes an issue where document end or directive end markers were parsed as a plain scalar when the document was empty.
  - Fixes an issue with leading unfoldable line break in `ScalarStyle.folded`.
  - Flow scalars can now recover when invalid document end/directive end markers are present.

## 0.3.0

This release brings extensive improvements to the recursive parsing strategy. The parser can now handle a wide variety of edge cases with regards to block nodes and their properties. The recursive parsing strategy has been modelled to match the official YAML grammar and syntax.

`BREAKING`:
  - Added a `YamlSource` extension type. All loaders no longer have the `source` and `byteSource` parameter. `YamlSource` provides named constructors for both with all loaders accepting a single `YamlSource` input.

`feat`:
  - Added backward compatibility support for `!!set` and `!!omap` secondary tags.
  - Added internal support for parsing a node based on its kind resulting in better performance and more contextual errors.

`refactor:`
  - `Mapping` and `Sequence` revert to extending `Dart` sdk's `UnmodifiableMapView` and `UnmodifiableListView` respectively.
  - The parser now bubbles up trivial errors to be caught at the correct recursive level. The errors are now more contextual with more accurate stack traces.

`fix(parser)`:
  - Uses the indentation level and not indent when calculating the indent of a block scalar (`ScalarStyle.folded` and `ScalarStyle.literal`) when the indentation indicator was specified.
  - Empty strings annotated with `!!str` are not inferred as `null`.
  - Fixes an issue where a document's root block collection with leading spaces was never parsed correctly.
  - Parser ensures the end offset of a `ScalarStyle.plain` node is set correctly.
  - Parses a flow node declared just before a terminating flow indicator (`,`, `}`, `]`) correctly instead of throwing.
  - Parser now handles block/flow nodes declared on the same line as the directives end marker (`---`) correctly.

`fix(dumper)`:
  - Forces a block style to be encoded as `ScalarStyle.doubleQuoted` if any leading whitespace (not tabs) is encountered.

## 0.2.2

`fix`:
  - Performs a deep copy when `dereferencesAliases` is `true` instead of a shallow copy.

## 0.2.1

This release fixes issues with the parser and built-in Dart type loaders.

`fix(parser)`:
  - Fixes an issue where a missing alias was treated as `null` when loading objects as built-in Dart types.
  - Fixes an issue where block nodes specified an incorrect node start that resulted in an invalid indent error when parsing block sequences and block maps.
  - Fixes an issue where a multi-line block node was mistakenly treated as a compact inline block node when parsing block sequences.
  - Allows `List` and `Map` aliases to be dereferenced when loading built-in Dart types. Pass in `dereferencesAliases` as `true` when calling `loadDartObject` or `loadAsDartObjects`.

`fix(dumper)`:
  - Fixes an issue where a nested block map value was dumped on the same line as implicit block map key which is invalid YAML.

`docs`:
  - Added information on dereferencing aliases to docs.

## 0.2.0

This release introduces the ability to load YAML directly as a built-in Dart type.

`BREAKING`:
  - Removed `YamlParser` in favour of loader functions.
  - `Mapping` now only accepts a `YamlSourceNode` as a key. Always cast to `DynamicMapping` if you want to use built-in Dart types as keys.

`feat`:
  - Added `loadDartObject` that loads a single document as a Dart built-in type.
  - Added `loadDartObjects` that loads multiple documents as Dart built-in types.
  - Added `loadYamlNode`. Migrated `YamlParser.parseNodes` and `YamlParser.parseDocuments` to `loadNodes` and `loadAllDocuments` respectively.

`fix`:
  - Fixes an issue where block maps with flow maps/sequences as the first key were ignored.
  - Throws better errors when a block/flow node cannot be parsed in the current parser state.

`docs`:
  - Added guides on loading YAML as a built-in Dart type.
  - Added a table of contents when accessing docs from the github repository.

## 0.1.1

`docs`:
  - Fix typo in package usage docs.
  - Update README.

## 0.1.0

This is the first minor release. It introduces a custom (experimental) error reporting style that focuses on providing a contextual and fairly accurate visual aid on the location of an error within the source string.

`BREAKING`:
  - Non-specific tags are resolved to `!!map`, `!!seq` or `!!str` based on its kind. No type inference for scalars.
  - `TagShorthand`s that are non-specific ( `!`) cannot be used to declare a custom type `Resolver`.
  - Drop support for `!!uri` tag.

`feat`:
  - Added a rich error reporting style.
  - `YamlParser` can now parse based on the source string location using the `ofString` and `ofFilePath` constructors.

`fix`:
  - Document and directive end marker are now checked even in quoted scalar styles, `ScalarStyle.doubleQuoted` and `ScalarStyle.singleQuoted`.
  - Fixes an issue where ` :` and `: ` combination was handled incorrectly when parsing plain scalars.
  - Fixes an issue where block sequence entries not declared using YAML's `compact-inline notation` were parsed incorrectly.
  - Always update the end offset of an explicit block key with no value before exiting.
  - Flow map nodes in flow sequence declared using YAML's `compact-inline notation` cannot have properties.
  - Alias/anchors are no longer restricted to URI characters. Any non-space character can be used.
  - Leading and trailing line breaks are now trimmed in plain scalars.
  - Parser exits gracefully when block scalar styles (`ScalarStyle.literal` and `ScalarStyle.folded`) only declare the header.
  - Parser exits gracefully when a block sequence entry is empty but present.
  - Parser exits gracefully when flow indicators are encountered while parsing tags/anchors/aliases.

## 0.0.6

This is a packed patch release. The main highlight of this release is the support for dumping objects back to YAML. Some of the changes introduced in this release were blocking the implementation of this functionality. A baseline was required. Our dumping strategy needed to be inline with parser functionality.

`BREAKING`:
  - Block scalar styles, `ScalarStyle.literal` and `ScalarStyle.folded`, are now restricted to the printable character set.
  - Renamed `PreResolver` to `Resolver`.
  - Removed `JsonNodeToYaml` and `DirectToYaml`. Prefer calling the dumping functions added in this release.

`feat`:
  - `YamlParser` can be configured to ignore duplicate map entries. This is a backwards-compatibility feature for YAML 1.1 and below. Explicitly pass in `throwOnMapDuplicates` as `true`. Duplicate entries are ignored and do not overwrite the existing entry.
  - `YamlParser` now accepts a logger callback. Register this callback if you have custom logging behaviour.
  - Added `dumpScalar`, `dumpSequence` and `dumpMapping` for dumping objects without properties back to YAML.
  - Added `CompactYamlNode` interface. External objects can provide custom properties by implementing this interface.
  - Added `dumpYamlNode`, `dumpCompactNode` and `dumpYamlDocuments` for dumping `CompactYamlNode` subtypes.

`fix`:
  - Tabs are treated as separation space in `ScalarStyle.plain` when checking if the plain scalar is a key to flow/block map.
  - Escaped slashes `\` are not ignored in `ScalarStyle.doubleQuoted`.
  - Comments in YAML directives are now skipped correctly and do not trigger a premature exit/error.
  - Escaped line breaks in `ScalarStyle.doubleQuoted` are handled correctly.
  - Prevent trailing aliases in flow sequences from being ignored.
  - Prevent key aliases for compact mappings in block sequences from being treated as a normal sequence.

`docs`:
  - Added guide for contributors who want to run the official YAML test suite to test the parser.
  - Added topic-like docs for pub.
  - Added examples.

## 0.0.5

`feat`:
  - Add `DynamicMapping` extension type that allow `Dart` values to be used as keys.
  - Allow `block` and `flow` key anchors to be used as aliases before the entire entry is parsed.

`fix`: Ensure the end offset in an alias used as a sequence entry is updated.

## 0.0.4

The parser is (fairly) stable and in a "black box" state (lexing and parsing are currently merged). You provide a source string and the parser just spits a `YamlDocument` or `YamlSourceNode` or `FormatException`. The parser cannot provide the event tree (or more contextual errors) at this time.

`refactor`: update API
  - Make `PreScalar` a record. Type inference is now done when instantiating a `Scalar`.
  - Rename `ParsedTag` to `NodeTag`. Some nodes get the default tags from the parser if they don't have any. The naming was confusing.
  - Rename `LocalTag` to `TagShorthand`. This change brings the API closer to the spec. [See here](https://yaml.org/spec/1.2.2/#69-node-properties:~:text=tag%20starting%0A%20%20with%20%27!%27.-,Tag%20Shorthands,-A%20tag%20shorthand)
  - Rename `ParsedYamlNode` to `YamlSourceNode`.
  - Rename `NativeResolverTag` to `TypeResolverTag`.
  - Expose the `TagShorthand` suffix present in the `NodeTag`. This allows a `TypeResolverTag` to bind itself to the suffix and resolve all `YamlSourceNode` that have the suffix.
  - Enable parser to associate a suffix with a `TypeResolverTag`
  - Rename `ChunkScanner` to `GraphemeScanner`

`feat`: Extended support for type inference
  - Add a `ScalarValue` object that infers a `Scalar`'s type only when it is instantiated.
  - Add a `uri` tag for `Dart` and infer `Uri` with schemes from the parsed content.
  - Add `ContentResolver` as a subtype of a `TypeResolverTag` that can infer a type on behalf of the `Scalar`. The type is embedded within the scalar as a `ScalarValue`
  - Add `NodeResolver` as a subtype of a `TypeResolverTag` that can resolve a parsed `YamlSourceNode` via its `asCustomType<T>` method.

`fix`:
  - Trim only whitespace for plain scalars. Intentionally avoid trimming line breaks.
  - Strip hex before parsing integers when using `int.tryParse` in Dart with a non-null radix
  - Flow nodes with explicit indicators now return indent information to the parent block node after they have been parsed completely. Block map nodes can now eagerly throw an error when parsing implicit keys.
  - Accurately track if a linebreak ended up in a scalar's content to ensure we can infer the type in one pass without scanning the source string once again.
  - Ensure verbatim tags are formatted correctly when instantiating them for `Dart`

## 0.0.3

`feat(experimental)`: Richer offset information that uses `SourceLocation` from `package:source_span`.

`breaking(experimental)`: Block styles (`ScalarStyle.literal` & `ScalarStyle.folded`) now have their non-printable characters "broken" up into a printable state
  - Escaped characters are broken up into `\` and whatever ascii character is escaped to elevate it into a control character.
  - Other non-printable characters are encoded as utf characters preceded by `\u`
  - This change is experimental and attempts to be inline with the spec where these non-printable characters cannot be escaped. Ideally, the parser could throw an error and restrict the block styles to only printable characters. [Reference here](https://yaml.org/spec/1.2.2/#chapter-8-block-style-productions:~:text=There%20is%20no%20way%20to%20escape%20characters%20inside%20literal%20scalars.%20This%20restricts%20them%20to%20printable%20characters.%20In%20addition%2C%20there%20is%20no%20way%20to%20break%20a%20long%20literal%20line.)

`fix`:
  - Document markers are now accurately bubbled up (tracked).
  - Characters consumed when checking for the directive end marker `---` are handed off correctly when parsing `ScalarStyle.plain`

> [!WARNING]
> This version is (somewhat stable and) usable but misses some core APIs that need to be implemented.

## 0.0.2

`refactor`: update API
  - Replaces `Node` with `YamlNode`. This class allow for external implementations to provide a custom `Dart` object to be dumped directly to YAML.
  - Introduces a `ParsedYamlNode`. Inherits from `YamlNode` but its implementation restricted to internal APIs. External objects cannot have resolved
    `tag`-s and/or `anchor`s / `alias`-es
  - Removes `NonSpecificTag` implementation which is now incorporated into the `LocalTag` implementation. A non-specific tag is just a local tag that has not yet been resolved to an existing YAML tag

`feat(experimental)`: add support for parsing node properties
  - The parser assigns `anchor`, `tag` and `alias` based on context and layout to the nearest `ParsableNode`. Currently, explicit keys in both `flow` and `block` nodes cannot have any node properties before the `?` indicator. Key properties must be declared after the `?` indicator before the actual key is parsed if present. Explicit block entries can have only node properties if all conditions below are met:
    1. At least one node property is declared on its own line before the `?` indicator is seen
    2. The explicit key is the first key of the map. This specific condition allows the node properties to be assigned to the entire block map.

  - This implementation is experimental and parsed properties are assigned on a "best effort" basis. Check docs once available for rationale.
  - Add tests

> [!WARNING]
> This version is (somewhat stable and) usable but misses some core APIs that need to be implemented.

## 0.0.1

`feat`:
  - Add support for parsing `YAML` documents and nodes

> [!WARNING]
> This version doesn't support `YAML` node properties. Anchors (`&`), local tags (`!`) and aliases (`*`) are not parsed.
