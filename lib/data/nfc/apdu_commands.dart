class ApduCommands {
  /// SELECT PPSE = select "2PAY.SYS.DDF01" en hexadécimal
  static List<int> selectPPSE = [
    0x00, 0xA4, 0x04, 0x00,
    0x0E, // longueur de l'AID (14 bytes)
    0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53,
    0x2E, 0x44, 0x44, 0x46, 0x30, 0x31,
    0x00, // fin de commande
  ];

  /// Construit une commande SELECT avec un AID hexadécimal donné
  static List<int> buildSelectAID(String aidHex) {
    final aid = _hexStringToBytes(aidHex);
    return [0x00, 0xA4, 0x04, 0x00, aid.length, ...aid, 0x00];
  }

  /// Construit une commande GPO vide (PDOL non envoyé)
  static List<int> gpoEmpty = [
    0x80, 0xA8, 0x00, 0x00,
    0x02, // longueur des données suivantes
    0x83, 0x00, // tag 83 (PDOL vide)
    0x00, // Le = 0 (on attend une réponse)
  ];

  /// Utilitaire interne pour convertir une string hex en bytes
  static List<int> _hexStringToBytes(String hex) {
    hex = hex.replaceAll(" ", "").toUpperCase();
    return [
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }
}
