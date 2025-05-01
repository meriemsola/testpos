/*class TLV {
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
*/
import 'dart:typed_data';
import '../utils.dart';

/// Decoded tag
class DecodedTag {
  final int value;
  final int encodedLen;
  DecodedTag(this.value, this.encodedLen);
}

class DecodedLen {
  final int value;
  final int encodedLen;
  DecodedLen(this.value, this.encodedLen);
}

class DecodedTV {
  final DecodedTag tag;
  final Uint8List value;
  final int encodedLen;
  DecodedTV(this.tag, this.value, this.encodedLen);
}

class DecodedTL {
  final DecodedTag tag;
  final DecodedLen length;
  final int encodedLen;
  DecodedTL(this.tag, this.length, this.encodedLen);
}

class TLVError implements Exception {
  final String message;
  TLVError(this.message);
  @override
  String toString() => message;
}

class TLV {
  int tag;
  Uint8List value;

  TLV(this.tag, this.value);

  factory TLV.fromBytes(final Uint8List encodedTLV) {
    final tv = decode(encodedTLV);
    return TLV(tv.tag.value, tv.value);
  }

  factory TLV.fromIntValue(final int tag, int n) {
    return TLV(tag, Utils.intToBin(n));
  }

  Uint8List toBytes() {
    return encode(tag, value);
  }

  static Uint8List encode(final int tag, final Uint8List data) {
    final t = encodeTag(tag);
    final l = encodeLength(data.length);
    return Uint8List.fromList(t + l + data);
  }

  static Uint8List encodeIntValue(final int tag, final int n) {
    return TLV.fromIntValue(tag, n).toBytes();
  }

  static DecodedTV decode(final Uint8List encodedTLV) {
    final tl = decodeTagAndLength(encodedTLV);
    final data = encodedTLV.sublist(
      tl.encodedLen,
      tl.encodedLen + tl.length.value,
    );
    return DecodedTV(tl.tag, data, tl.encodedLen + data.length);
  }

  static DecodedTL decodeTagAndLength(final Uint8List encodedTagLength) {
    final tag = decodeTag(encodedTagLength);
    final len = decodeLength(encodedTagLength.sublist(tag.encodedLen));
    return DecodedTL(tag, len, tag.encodedLen + len.encodedLen);
  }

  static Uint8List encodeTag(final int tag) {
    final byteCount = Utils.byteCount(tag);
    var encodedTag = Uint8List(byteCount == 0 ? 1 : byteCount);
    for (int i = 0; i < byteCount; i++) {
      final pos = 8 * (byteCount - i - 1);
      encodedTag[i] = (tag & (0xFF << pos)) >> pos;
    }
    return encodedTag;
  }

  static DecodedTag decodeTag(final Uint8List encodedTag) {
    if (encodedTag.isEmpty) {
      throw TLVError("Can't decode empty encodedTag");
    }

    int tag = 0;
    int b = encodedTag[0];
    int offset = 1;
    switch (b & 0x1F) {
      case 0x1F:
        {
          if (offset >= encodedTag.length) {
            throw TLVError("Invalid encoded tag");
          }
          tag = b;
          b = encodedTag[offset];
          offset += 1;

          while ((b & 0x80) == 0x80) {
            if (offset >= encodedTag.length) {
              throw TLVError("Invalid encoded tag");
            }
            tag <<= 8;
            tag |= b & 0x7F;
            b = encodedTag[offset];
            offset += 1;
          }
          tag <<= 8;
          tag |= b & 0x7F;
        }
        break;
      default:
        tag = b;
    }

    return DecodedTag(tag, offset);
  }

  static Uint8List encodeLength(int length) {
    if (length < 0 || length > 0xFFFFFF) {
      throw TLVError("Can't encode negative or greater than 16 777 215 length");
    }

    var byteCount = Utils.byteCount(length);
    var encodedLength = Uint8List(
      byteCount + (byteCount == 0 || length >= 0x80 ? 1 : 0),
    );

    if (length < 0x80) {
      encodedLength[0] = length;
    } else {
      encodedLength[0] = byteCount | 0x80;
      for (int i = 0; i < byteCount; i++) {
        final pos = 8 * (byteCount - i - 1);
        encodedLength[i + 1] = (length & (0xFF << pos)) >> pos;
      }
    }
    return encodedLength;
  }

  static DecodedLen decodeLength(Uint8List encodedLength) {
    if (encodedLength.isEmpty) {
      throw TLVError("Can't decode empty encodedLength");
    }

    int length = encodedLength[0] & 0xff;
    int byteCount = 1;

    if ((length & 0x80) == 0x80) {
      byteCount = length & 0x7f;
      if (byteCount > 3) {
        throw TLVError("Encoded length is too big");
      }

      length = 0;
      byteCount = 1 + byteCount;
      if (byteCount > encodedLength.length) {
        throw TLVError("Invalid encoded length");
      }

      for (int i = 1; i < byteCount; i++) {
        length = length * 0x100 + (encodedLength[i] & 0xff);
      }
    }

    return DecodedLen(length, byteCount);
  }

  @override
  String toString() {
    final tagHex = tag.toRadixString(16).padLeft(2, '0').toUpperCase();
    final lengthHex =
        value.length.toRadixString(16).padLeft(2, '0').toUpperCase();
    final valueHex =
        value
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .toUpperCase();
    return 'Tag: $tagHex, Length: $lengthHex, Value: [$valueHex]';
  }
}

class TLVParser {
  static List<TLV> parse(Uint8List data) {
    final List<TLV> result = [];
    int index = 0;

    while (index < data.length) {
      final DecodedTV tv = TLV.decode(data.sublist(index));
      final tlv = TLV(tv.tag.value, tv.value);
      result.add(tlv);

      final firstByte = _getFirstByte(tlv.tag);
      if ((firstByte & 0x20) == 0x20) {
        result.addAll(parse(tlv.value));
      }

      index += tv.encodedLen;
    }

    return result;
  }

  static int _getFirstByte(int tag) {
    if (tag <= 0xFF) {
      return tag;
    } else if (tag <= 0xFFFF) {
      return (tag >> 8) & 0xFF;
    } else if (tag <= 0xFFFFFF) {
      return (tag >> 16) & 0xFF;
    } else {
      return (tag >> 24) & 0xFF;
    }
  }

  /// 🔥 Ajout : fonction de recherche récursive d'un TLV
  static TLV? findTlvRecursive(List<TLV> tlvs, int targetTag) {
    for (var tlv in tlvs) {
      if (tlv.tag == targetTag) {
        return tlv;
      }
      final firstByte = _getFirstByte(tlv.tag);
      if ((firstByte & 0x20) == 0x20) {
        final innerTlvs = parse(tlv.value);
        final found = findTlvRecursive(innerTlvs, targetTag);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }
}
