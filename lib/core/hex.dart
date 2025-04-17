class Hex {
  static List<int> decode(String hex) {
    hex = hex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    return [
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }

  static String encode(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }
}
