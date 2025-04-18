import 'package:flutter/material.dart';

class PinEntryPage extends StatefulWidget {
  const PinEntryPage({super.key});

  @override
  State<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<PinEntryPage> {
  String pin = '';

  void _onKeyPressed(String value) {
    if (value == '⌫') {
      if (pin.isNotEmpty) {
        setState(() => pin = pin.substring(0, pin.length - 1));
      }
    } else if (pin.length < 6) {
      setState(() => pin += value);
    }
  }

  void _onValidate() {
    if (pin.length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PIN trop court')));
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrer le PIN')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Text(
              pin.replaceAll(RegExp(r'.'), '•'),
              style: const TextStyle(fontSize: 40, letterSpacing: 10),
            ),
            const SizedBox(height: 30),
            _buildKeypad(),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _onValidate,
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['⌫', '0', ''],
    ];

    return Column(
      children:
          keys.map((row) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children:
                  row.map((key) {
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: ElevatedButton(
                        onPressed:
                            key.isNotEmpty ? () => _onKeyPressed(key) : null,
                        style: ElevatedButton.styleFrom(
                          fixedSize: const Size(70, 70),
                          shape: const CircleBorder(),
                        ),
                        child: Text(key, style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  }).toList(),
            );
          }).toList(),
    );
  }
}
