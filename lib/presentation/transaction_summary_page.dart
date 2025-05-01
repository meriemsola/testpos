import 'package:flutter/material.dart';
import 'package:testpos/presentation/receipt_screen.dart';

class TransactionSummaryPage extends StatelessWidget {
  const TransactionSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    String pan = '';
    String amount = '';
    String date = '';
    String status = '';
    String expiration = '??/??';
    String name = 'Client';
    String atc = '0000';
    String transactionReference = 'TRX000000';
    String authorizationCode = 'AUTH000';

    if (args is Map<String, dynamic>) {
      pan = args['pan'] ?? '';
      amount = args['amount'] ?? '';
      date = args['date'] ?? '';
      status = args['status'] ?? '';
      expiration = args['expiration'] ?? '??/??';
      name = args['name'] ?? 'Client';
      atc = args['atc'] ?? '0000';
      transactionReference = args['transactionReference'] ?? 'TRX000000';
      authorizationCode = args['authorizationCode'] ?? 'AUTH000';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Summary'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(
                status.contains('acceptée') || status.contains('approuvée')
                    ? Icons.check_circle
                    : Icons.error,
                color:
                    status.contains('acceptée') || status.contains('approuvée')
                        ? Colors.green
                        : Colors.red,
                size: 80,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '💳 Carte : XXXX-XXXX-XXXX-$pan',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              '💰 Montant : \$$amount',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text('📅 Date : $date', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            Text('🧾 Statut : $status', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed:
                      () =>
                          Navigator.popUntil(context, ModalRoute.withName('/')),
                  icon: const Icon(Icons.home),
                  label: const Text('Accueil'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      () => Navigator.pushNamed(context, '/transactionHistory'),
                  icon: const Icon(Icons.history),
                  label: const Text('Historique'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => ReceiptScreen(
                            pan: pan,
                            expiration: expiration,
                            name: name,
                            atc: atc,
                            status: status,
                            amount: amount,
                            transactionReference: transactionReference,
                            authorizationCode: authorizationCode,
                            dateTime: date,
                          ),
                    ),
                  );
                },
                icon: const Icon(Icons.receipt),
                label: const Text('Voir le reçu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
