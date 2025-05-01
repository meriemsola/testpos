import 'package:flutter/material.dart';
import 'package:testpos/models/transaction_log_model.dart';
import 'package:testpos/presentation/receipt_screen.dart';

class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tx = ModalRoute.of(context)?.settings.arguments as TransactionLog?;

    if (tx == null) {
      return const Scaffold(
        body: Center(child: Text('Aucune donnée disponible')),
      );
    }

    final bool isSuccess =
        tx.status.contains('acceptée') || tx.status.contains('approuvée');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la transaction'),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(
                isSuccess ? Icons.check_circle : Icons.cancel,
                size: 80,
                color: isSuccess ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 32),
            Text('💳 PAN : ${tx.pan}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            Text(
              '📅 Date : ${tx.dateTime}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              '💰 Montant : \$${tx.amount}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text('🔢 ATC : ${tx.atc}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            Text(
              '🧾 Statut : ${tx.status}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => ReceiptScreen(
                          pan: tx.pan,
                          expiration: tx.expiration,
                          name: '', // ✅ Ici on met une string vide
                          atc: tx.atc,
                          status: tx.status,
                          amount: tx.amount,
                          transactionReference:
                              'TRN${tx.timestamp.millisecondsSinceEpoch}',
                          authorizationCode: 'AUTH1234',
                          dateTime: tx.dateTime,
                        ),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text('Imprimer le reçu'),
            ),
          ],
        ),
      ),
    );
  }
}
