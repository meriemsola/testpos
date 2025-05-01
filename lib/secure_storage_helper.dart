import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

// pour ne pas que les cle changes a chaque demmarage  permet de stocker tout ça dans un endroit sécurisé (Android Keystore ou iOS Keychain).
class SecureStorageHelper {
  // Utilisation de flutter_secure_storage pour stocker les clés de manière sécurisée (dans le keystore Android / keychain iOS).
  static const _storage = FlutterSecureStorage();
  static const _aesKeyName = 'aes_key'; // Nom sous lequel on stocke la clé AES.
  static const _aesIvName = 'aes_iv'; // Nom sous lequel on stocke l’IV.

  /// Récupère la clé AES depuis le stockage sécurisé.
  /// Si elle n’existe pas encore, en génère une nouvelle (256 bits) et la sauvegarde.
  static Future<encrypt.Key> getOrCreateKey() async {
    String? keyStr = await _storage.read(key: _aesKeyName);
    if (keyStr == null) {
      // Si pas de clé existante → génération aléatoire.
      final key = encrypt.Key.fromSecureRandom(32); // 32 octets = AES-256
      await _storage.write(
        key: _aesKeyName,
        value: key.base64,
      ); // Stockage en base64.
      return key;
    } else {
      return encrypt.Key.fromBase64(keyStr); // Récupère la clé déjà stockée.
    }
  }

  /// Récupère l’IV (Initialization Vector) depuis le stockage sécurisé.
  /// Si absent, génère un nouvel IV (128 bits) et le sauvegarde.
  static Future<encrypt.IV> getOrCreateIv() async {
    String? ivStr = await _storage.read(key: _aesIvName);
    if (ivStr == null) {
      final iv = encrypt.IV.fromSecureRandom(
        16,
      ); // 16 octets = 128 bits (standard IV pour AES).
      await _storage.write(key: _aesIvName, value: iv.base64);
      return iv;
    } else {
      return encrypt.IV.fromBase64(ivStr); // Récupère l’IV déjà stocké.
    }
  }
}
