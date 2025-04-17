class TransactionLog {
  final String pan;
  final String expiration;
  final String atc;
  final String result;
  final DateTime timestamp;
  final String amount;
  final String dateTime;
  final String status;

  TransactionLog({
    required this.pan,
    required this.expiration,
    required this.atc,
    required this.result,
    required this.timestamp,
    required this.amount,
    required this.dateTime,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'pan': pan,
      'expiration': expiration,
      'atc': atc,
      'result': result,
      'timestamp': timestamp.toIso8601String(),
      'amount': amount,
      'dateTime': dateTime,
      'status': status,
    };
  }

  factory TransactionLog.fromMap(Map<String, dynamic> map) {
    return TransactionLog(
      pan: map['pan'] ?? '',
      expiration: map['expiration'] ?? '',
      atc: map['atc'] ?? '',
      result: map['result'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
      amount: map['amount'] ?? '',
      dateTime: map['dateTime'] ?? '',
      status: map['status'] ?? '',
    );
  }
}
