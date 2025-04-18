import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:testpos/presentation/main_navigation.dart';
import 'package:testpos/presentation/receipt_pdf_generator.dart';

class ReceiptScreen extends StatelessWidget {
  final String pan;
  final String expiration;
  final String name;
  final String atc;
  final String status;
  final String amount;
  final String transactionReference;
  final String authorizationCode;
  final String dateTime;

  const ReceiptScreen({
    super.key,
    required this.pan,
    required this.expiration,
    required this.name,
    required this.atc,
    required this.status,
    required this.amount,
    required this.transactionReference,
    required this.authorizationCode,
    required this.dateTime,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess =
        status.contains('acceptée') || status.contains('approuvée');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu de paiement'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.cancel,
                  color: isSuccess ? Colors.green : Colors.red,
                  size: 60,
                ),
                const SizedBox(height: 12),
                Text(
                  isSuccess ? 'Transaction réussie' : 'Échec de la transaction',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isSuccess ? Colors.green : Colors.red,
                  ),
                ),
                const Divider(height: 30, thickness: 1),
                _buildRow('Nom', name),
                _buildRow('Carte', pan),
                _buildRow('Expiration', expiration),
                _buildRow('Montant', '\$$amount'),
                _buildRow('Date', dateTime),
                _buildRow('Référence', transactionReference),
                _buildRow('Code Autorisation', authorizationCode),
                _buildRow('ATC', atc),
                _buildRow('Statut', status),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    final pdfData = await generateReceiptPdf(
                      pan: pan,
                      expiration: expiration,
                      name: name,
                      atc: atc,
                      status: status,
                      amount: amount,
                      transactionReference: transactionReference,
                      authorizationCode: authorizationCode,
                      dateTime: dateTime,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📁 PDF enregistré avec succès'),
                      ),
                    );
                    await Printing.layoutPdf(onLayout: (format) => pdfData);
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exporter en PDF'),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed:
                      () => () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainNavigation(),
                          ),
                          (route) => false,
                        );
                      },

                  icon: const Icon(Icons.home),
                  label: const Text('Retour à l’accueil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label :',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
