import 'package:flutter/material.dart';

class AmountPage extends StatefulWidget {
  const AmountPage({Key? key}) : super(key: key);

  @override
  State<AmountPage> createState() => _AmountPageState();
}

class _AmountPageState extends State<AmountPage> {
  String amount = "0.00";
  final TextEditingController amountController = TextEditingController();

  void _onClear() {
    setState(() {
      amount = "0.00";
      amountController.clear();
    });
  }

  void _onConfirm() {
    Navigator.pushNamed(context, '/nfcWaiting', arguments: {'amount': amount});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Montant"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('💰 Entrez le montant', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Ex : 1500.00',
                prefixIcon: const Icon(Icons.payments),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) => setState(() => amount = value),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.nfc),
              onPressed:
                  amount.isEmpty ||
                          double.tryParse(amount) == null ||
                          double.parse(amount) <= 0
                      ? null
                      : _onConfirm,
              label: const Text('Lire carte EMV'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _onClear,
              child: const Text('Réinitialiser'),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/transactionHistory');
              },
              icon: const Icon(Icons.history),
              label: const Text('Voir l’historique'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.teal,
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
