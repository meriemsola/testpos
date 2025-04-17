import 'package:flutter/material.dart';
import 'package:testpos/models/transaction_log_model.dart';
import '../transaction_storage.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  List<TransactionLog> transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final data = await TransactionStorage.loadTransactions();
    setState(() {
      transactions = data.reversed.toList();
    });
  }

  Future<void> _clearHistory() async {
    await TransactionStorage.clearTransactions();
    setState(() {
      transactions.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _clearHistory,
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Effacer l’historique',
          ),
        ],
      ),
      body:
          transactions.isEmpty
              ? const Center(
                child: Text(
                  'Aucune transaction disponible',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: transactions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  final isSuccess =
                      tx.status.contains('acceptée') ||
                      tx.status.contains('approuvée');

                  return Container(
                    decoration: BoxDecoration(
                      color: isSuccess ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade300,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isSuccess ? Colors.green : Colors.red,
                        child: Icon(
                          isSuccess ? Icons.check : Icons.close,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        '\$${tx.amount}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Carte : ${tx.pan}'),
                          Text('Date : ${tx.dateTime}'),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/transactionDetail',
                          arguments: tx,
                        );
                      },
                    ),
                  );
                },
              ),
    );
  }
}
