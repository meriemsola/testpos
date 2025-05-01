import 'package:pointycastle/asymmetric/api.dart';

/// CAPK Visa test publique — Extrait d’un exemple de test EMVCo
final RSAPublicKey capkVisaTest = RSAPublicKey(
  BigInt.parse(
    'A04D27B36FB4EBC5B73DF2ED2E0D88AE5C2DDE6B8B49E0EEC2A2D7D59F9326F39F3A1DB3A697AC8F2733D13215755BD9333DA0F79CB92AABBDDE2A8BC3E3B9E3',
    radix: 16,
  ),
  BigInt.parse('03', radix: 16),
);
