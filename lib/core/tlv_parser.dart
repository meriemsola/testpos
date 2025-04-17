class TLV {
  final String tag;
  final int length;
  final List<int> value;

  TLV(this.tag, this.length, this.value);

  @override
  String toString() =>
      'TAG: $tag, LEN: $length, VAL: ${value.map((e) => e.toRadixString(16)).join(' ')}';
}

class TLVParser {
  /// Parse un tableau de bytes EMV TLV en une liste de TLV
  static List<TLV> parse(List<int> data) {
    final result = <TLV>[];
    int index = 0;

    while (index < data.length) {
      // Lire le tag (1 ou 2 octets)
      String tag = data[index].toRadixString(16).padLeft(2, '0');
      index++;

      // Support tag sur 2 octets
      if ((int.parse(tag, radix: 16) & 0x1F) == 0x1F) {
        tag += data[index].toRadixString(16).padLeft(2, '0');
        index++;
      }

      // Lire la longueur (format court uniquement ici)
      int length = data[index];
      index++;

      // Lire la valeur
      List<int> value = data.sublist(index, index + length);
      index += length;

      result.add(TLV(tag, length, value));
    }

    return result;
  }
}
