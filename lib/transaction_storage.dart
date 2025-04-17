import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testpos/models/transaction_log_model.dart';

class TransactionStorage {
  static const String _key = 'transactions';

  /// Sauvegarde la liste des transactions en JSON
  static Future<void> saveTransactions(
    List<TransactionLog> transactions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(transactions.map((t) => t.toMap()).toList());
    await prefs.setString(_key, encoded);
  }

  /// Charge la liste sauvegardée, ou vide si rien
  static Future<List<TransactionLog>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null) return [];
    final decoded = jsonDecode(jsonString) as List;
    return decoded.map((e) => TransactionLog.fromMap(e)).toList();
  }

  /// Vide l’historique
  static Future<void> clearTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
