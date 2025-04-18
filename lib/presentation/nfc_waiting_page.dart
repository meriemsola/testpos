import 'package:flutter/material.dart';
import 'package:testpos/main.dart';

class NfcWaitingPage extends StatelessWidget {
  final String initialAmount;

  const NfcWaitingPage({super.key, required this.initialAmount});

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(initialAmount: initialAmount),
        ),
      );
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Image.asset(
              'assets/images/nfc_scan.png', // 📸 ton image depuis Google
              height: 250,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'Approchez votre carte',
            style: TextStyle(fontSize: 20, color: Colors.black87),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.black12,
            ),
            child: Text(
              '$initialAmount DA',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
