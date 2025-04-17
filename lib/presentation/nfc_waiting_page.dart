import 'package:flutter/material.dart';

class NfcWaitingPage extends StatefulWidget {
  const NfcWaitingPage({super.key});

  @override
  State<NfcWaitingPage> createState() => _NfcWaitingPageState();
}

class _NfcWaitingPageState extends State<NfcWaitingPage> {
  late String amount;
  late String result;
  late String pan;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      amount = args['amount'] ?? '0.00';
      result = args['result'] ?? '';
      pan = args['pan'] ?? '';

      // ✅ Appeler automatiquement _startEMVSession si fourni
      Future.microtask(() {
        final Function()? startSession = args['startSession'];
        if (startSession != null) startSession();
      });
    } else {
      amount = '0.00';
      result = '';
      pan = '';
    }

    // ✅ Redirection vers résumé après succès
    if (result.contains('acceptée') || result.contains('approuvée')) {
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushNamed(
          context,
          '/transactionSummary',
          arguments: {
            'pan': pan,
            'amount': amount,
            'date': DateTime.now().toString(),
            'status': result,
          },
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String statusText;
    Color statusColor;

    if (result.contains('acceptée') || result.contains('approuvée')) {
      statusText = '✅ Success';
      statusColor = Colors.green;
    } else if (result.contains('refusée') ||
        result.contains('invalide') ||
        result.contains('Erreur') ||
        result.contains('❌') ||
        result.contains('⚠️')) {
      statusText = '❌ Échec';
      statusColor = Colors.red;
    } else {
      statusText = '⏳ Waiting...';
      statusColor = Colors.orange;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.nfc, size: 80, color: Colors.teal),
                const SizedBox(height: 20),
                const Text(
                  'Kindly put the card on the back of your phone, and wait for a few seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 30),
                Text(
                  'Amount: \$${amount}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
