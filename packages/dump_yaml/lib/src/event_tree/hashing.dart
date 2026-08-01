import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// A SHA-256 hash that uniquely identifies a type.
sealed class FreeHash {
  /// SHA-256 hex.
  String get hexHash;

  static String _combinedHashOnDemand(List<List<int>> toHash) =>
      sha256.convert(CombinedListView(toHash)).toString();

  @override
  int get hashCode => hexHash.hashCode;

  @override
  bool operator ==(Object other) =>
      other is FreeHash && hexHash == other.hexHash;
}

/// A SHA-256 hash that is available on demand.
final class QualifiedHash extends FreeHash {
  QualifiedHash._(this.hexHash);

  QualifiedHash.scalar(String seedTag, String content)
    : this._(
        FreeHash._combinedHashOnDemand([
          'SCALAR'.codeUnits,
          seedTag.codeUnits,
          content.codeUnits,
        ]),
      );

  QualifiedHash.danglingReference(String anchor)
    : this._(
        FreeHash._combinedHashOnDemand(['ALIAS'.codeUnits, anchor.codeUnits]),
      );

  @override
  final String hexHash;
}

const _emptyMap = ('MAPPING', {});

const _emptyList = ('SEQUENCE', []);

/// A SHA-256 hash computed on demand for every entry of a collection.
final class LazyHash extends FreeHash {
  LazyHash({required bool isMap, required String seedTag}) {
    hexHash = _initSeed(seedTag, isMap ? _emptyMap : _emptyList);
  }

  /// Uniquely identifies a type bound to this
  late final String id;

  @override
  late String hexHash;

  /// Initializes a collection's SHA-256 hash.
  String _initSeed(String seedTag, (String, Object) seed) {
    final (type, collection) = seed;
    id = type;

    // YAML-TYPE, TAG-TYPE, EMPTY-STATE-AS-SEED
    return FreeHash._combinedHashOnDemand([
      type.codeUnits,
      seedTag.codeUnits,
      identityHashCode(collection).toRadixString(16).codeUnits,
    ]);
  }

  /// Hashes the [keyOrElementHash] (and [valueHashIfMap] if present) with
  /// the existing hash as the seed.
  void incrementalOnDemand(String keyOrElementHash, [String? valueHashIfMap]) {
    hexHash = FreeHash._combinedHashOnDemand([
      hexHash.codeUnits,
      id.codeUnits,
      keyOrElementHash.codeUnits,
      ?valueHashIfMap?.codeUnits,
    ]);
  }
}
