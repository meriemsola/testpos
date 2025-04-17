
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../data/emv_capk.dart';

class SDAValidator {
  static bool verifySignedData(Uint8List signature, Uint8List expectedData) {
    final signer = RSASigner(SHA1Digest(), '06052b0e03021a');
    signer.init(false, PublicKeyParameter<RSAPublicKey>(capkVisaTest));

    try {
      return signer.verifySignature(expectedData, RSASignature(signature));
    } catch (_) {
      return false;
    }
  }
}
