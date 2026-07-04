import 'package:rookie_yaml/src/loaders/loader.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/document_parser.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';

DocumentParser<Object?, Object?> bootStrapParser(
  String source, {
  bool deferenceAliases = false,
  CustomTriggers? triggers,
  DocumentBuilder<Object?, Object?>? docBuilder,
}) => dartObjectParser(
  UnicodeIterator.ofString(source),
  dereferenceAliases: deferenceAliases,
  throwOnMapDuplicate: true,
  triggers: null,
  docBuilder: docBuilder,
  logger: null,
);

void parseAllWithStubs(
  DocumentParser<Object?, Object?> parser, {
  Map<String, Object?>? anchors,
  Iterable<GlobalTag>? tags,
}) {
  do {
    parser.withIncrementalState(inheritedNodes: anchors, inheritedTags: tags);

    if (parser.parseNext() case (true, _)) continue;
    break;
  } while (true);
}

List<Object?> bootstrapDocParser(
  String yaml, {
  List<ScalarResolver<Object?>>? resolvers,
  void Function(bool isInfo, String message)? logger,
  void Function(String message)? onMapDuplicate,
}) => loadAllObjects(
  YamlSource.string(yaml),
  triggers: CustomTriggers(resolvers: resolvers),
  throwOnMapDuplicate: onMapDuplicate == null,
  logger: logger ?? (_, _) {},
);

extension YamlDocUtil on Iterable<Object?> {
  String nodeAsSimpleString() => parseNodeSingle().toString();

  Object? parseNodeSingle() => firstOrNull;

  Object? parseSingle() => first;

  Iterable<String> nodesAsSimpleString() => map((e) => e.toString());
}
