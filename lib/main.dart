import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:testpos/models/transaction_log_model.dart';
import 'package:testpos/presentation/main_navigation.dart';
import 'package:testpos/presentation/transaction_detail_page.dart';
import 'package:testpos/presentation/transaction_history_page.dart';
import 'package:testpos/presentation/transaction_summary_page.dart';
import 'package:testpos/transaction_storage.dart';
import 'core/tlv_parser.dart';
import 'core/hex.dart';
import 'data/nfc/apdu_commands.dart';
import 'presentation/receipt_screen.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'presentation/nfc_waiting_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'SoftPOS',
      debugShowCheckedModeBanner: false,
      home:
          const MainNavigation(), // C'est ici qu'on charge le menu principal avec onglets
      routes: {
        '/nfcWaiting': (context) => const NfcWaitingPage(),
        '/transactionSummary': (context) => const TransactionSummaryPage(),
        '/transactionDetail': (context) => const TransactionDetailPage(),
        '/transactionHistory':
            (context) => const TransactionHistoryPage(), // si besoin séparément
      },
    ),
  );
}

class HomeScreen extends StatefulWidget {
  final String? initialAmount;

  const HomeScreen({super.key, this.initialAmount});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String pan = ''; // PAN (Primary Account Number)
  String expiration = ''; // Date d'expiration
  String name = ''; // Nom du titulaire
  String ac = ''; // Cryptogramme AC
  String atc = ''; // Application Transaction Counter
  String cid = ''; // CID (Cryptogram Information Data)
  String result = ''; // Résultat de l'opération
  String amount = ''; // Montant de la transaction
  String transactionReference = ''; // Référence de la transaction
  String authorizationCode = ''; // Code d'autorisation
  bool isLoading = false; // Indicateur de chargement
  TextEditingController amountController =
      TextEditingController(); // Contrôleur pour le montant
  final int floorLimit = 100000; // Montant en centimes : ici 1000.00 DA
  final RSAPublicKey capkTest = RSAPublicKey(
    BigInt.parse(
      //exemple de CAPK Visa 1024 bits (publique) utilisée pour vérifier la signature SDA.
      'A38BCE78947B3F8D4EF4F93AA76B1F6B6E6C1B25B2B9E9CFBDE3C1A0D198E2113A336875C2D16A1F42ADFC23A28196A731E8AAB1881E12E1851B03F3E9FC1045',
      radix: 16,
    ),
    BigInt.parse('03', radix: 16),
  );
  final encrypt.Key aesKey = encrypt.Key.fromSecureRandom(
    32,
  ); // Clé AES sécurisée
  final encrypt.IV aesIv = encrypt.IV.fromSecureRandom(16); // IV sécurisé
  List<TransactionLog> transactionLogs =
      []; // Historique local des transactions

  Future<void> _demanderPin() async {
    String? pin = await showDialog<String>(
      context: context,
      builder: (context) {
        String enteredPin = '';
        return AlertDialog(
          title: const Text('Entrer le PIN'),
          content: TextField(
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            onChanged: (value) => enteredPin = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, enteredPin),
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );

    if (!mounted) return; // ⛑ sécurité : le widget est-il toujours monté ?

    if (pin == null || pin.length < 4) {
      // Utilisation sûre de setState
      setState(() {
        result = '❌ PIN incorrect ou annulé';
      });
      throw Exception('CVM échoué');
    }

    print('✅ PIN saisi : $pin');
  }

  String _terminalActionAnalysis(String cid, bool canGoOffline) {
    if (cid == '40' && canGoOffline) {
      return 'APPROVED_OFFLINE'; // TC = Transaction Certificate
    } else if (cid == '80') {
      return 'DECLINED'; // AAC = Application Authentication Cryptogram
    } else if (cid == '00') {
      return 'ONLINE_REQUESTED'; // ARQC = Authorization Request
    } else {
      return 'UNKNOWN';
    }
  }

  bool _verifySDASignature(Uint8List signature, Uint8List staticData) {
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.RSA(publicKey: capkTest, encoding: encrypt.RSAEncoding.PKCS1),
      );

      final decrypted = encrypter.decryptBytes(encrypt.Encrypted(signature));

      return decrypted
              .sublist(decrypted.length - staticData.length)
              .toString() ==
          staticData.toString();
    } catch (e) {
      print('Erreur SDA : $e');
      return false;
    }
  }

  // 📘 Étapes 1 à 13 : Processus EMV complet
  void _startEMVSession() async {
    // ✅ Étape 0 : Vérifie si le montant est valide
    if (!_isValidAmount(amount)) {
      setState(() {
        result = '❌ Montant invalide. Veuillez entrer un nombre valide.';
      });
      return;
    }

    // ✅ Étape 1 : Vérifie si le NFC est disponible
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      setState(() {
        result = '❌ NFC non disponible : $availability';
      });
      return;
    }

    try {
      resetFields();
      setState(() => isLoading = true);

      // 📡 Étape 2 : Attente d'une carte NFC
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
      );
      if (tag == null) {
        setState(() => result = '❌ Carte non détectée');
        return;
      }
      print('✅ Carte détectée : ${tag.type}');

      // ... le reste de ta logique EMV ici

      // 📤 Étape 2 : Envoi SELECT PPSE
      final apduHex =
          ApduCommands.selectPPSE
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join();
      final responseHex = await FlutterNfcKit.transceive(apduHex);

      // 📘 Gestion des erreurs APDU pour SELECT PPSE
      final decodedError = decodeApduError(responseHex);
      if (decodedError != 'Succès') {
        setState(() => result = decodedError); // Afficher l'erreur si échec
        return;
      }

      final responseBytes = _hexToBytes(responseHex);
      final tlvs = TLVParser.parse(responseBytes);

      // 🔍 Étape 2b : Extraction de l'AID (TAG 84)
      final aidTlv = tlvs.firstWhere(
        (tlv) => tlv.tag == '84',
        orElse: () => TLV('00', 0, []),
      );
      if (aidTlv.tag != '84') return;
      final aidHex =
          aidTlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // 📤 Étape 3 : Envoi SELECT AID
      final selectAid = ApduCommands.buildSelectAID(aidHex);
      final selectAidHex =
          selectAid.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      final aidResponseHex = await FlutterNfcKit.transceive(selectAidHex);

      // 📘 Gestion des erreurs APDU pour SELECT AID
      final decodedAidError = decodeApduError(aidResponseHex);
      if (decodedAidError != 'Succès') {
        setState(() => result = decodedAidError);
        return;
      }

      // 🔐 Étape 4 : Traitement du PDOL (tag 9F38) et construction GPO dynamique
      final aidResponseBytes = _hexToBytes(aidResponseHex);
      final aidResponseTlvs = TLVParser.parse(aidResponseBytes);
      String? pdolHex;
      for (var tlv in aidResponseTlvs) {
        if (tlv.tag == '9F38') {
          pdolHex = Hex.encode(tlv.value);
          break;
        }
      }
      List<int> gpoCommand;
      if (pdolHex != null && pdolHex.isNotEmpty) {
        final pdolBytes = _hexToBytes(pdolHex);
        List<int> pdolData = [];
        int idx = 0;
        while (idx < pdolBytes.length) {
          final tag =
              pdolBytes[idx].toRadixString(16).padLeft(2, '0') +
              pdolBytes[idx + 1].toRadixString(16).padLeft(2, '0');
          final length = pdolBytes[idx + 2];
          idx += 3;

          if (tag == '9F02') {
            // Montant de la transaction
            int transactionAmount = (double.parse(amount) * 100).toInt();
            String amountHex = transactionAmount
                .toRadixString(16)
                .padLeft(length * 2, '0');
            pdolData.addAll(_hexToBytes(amountHex));
          } else {
            pdolData.addAll(List.filled(length, 0x00));
          }
        }

        final dolWithTag = [0x83, pdolData.length] + pdolData;
        gpoCommand = [
          0x80,
          0xA8,
          0x00,
          0x00,
          dolWithTag.length,
          ...dolWithTag,
          0x00,
        ];
      } else {
        gpoCommand = [0x80, 0xA8, 0x00, 0x00, 0x02, 0x83, 0x00, 0x00];
      }
      final gpoHexStr =
          gpoCommand.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      final gpoResponseHex = await FlutterNfcKit.transceive(gpoHexStr);
      final gpoResponseBytes = _hexToBytes(gpoResponseHex);
      final gpoTlvs = TLVParser.parse(gpoResponseBytes);

      // 🧠 Étape 5 : Lire l'AFL (TAG 94)
      final aflTlv = gpoTlvs.firstWhere(
        (tlv) => tlv.tag == '94',
        orElse: () => TLV('00', 0, []),
      );
      if (aflTlv.tag != '94') return;
      final afl = aflTlv.value;

      // 📖 Lecture des enregistrements
      for (int i = 0; i < afl.length; i += 4) {
        final sfi = afl[i] >> 3;
        final recordStart = afl[i + 1];
        final recordEnd = afl[i + 2];

        for (int record = recordStart; record <= recordEnd; record++) {
          final p1 = record;
          final p2 = (sfi << 3) | 4;
          final readRecord = [0x00, 0xB2, p1, p2, 0x00];
          final apduHex =
              readRecord.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

          try {
            final recordHex = await FlutterNfcKit.transceive(apduHex);
            final recordBytes = _hexToBytes(recordHex);
            final recordTlvs = TLVParser.parse(recordBytes);

            // ✅ Étape 6 : Extraction des données
            final sdaTlv = recordTlvs.firstWhere(
              (tlv) => tlv.tag == '93',
              orElse: () => TLV('00', 0, []),
            );
            if (sdaTlv.tag == '93') {
              final signature = Uint8List.fromList(sdaTlv.value);
              final staticData = <int>[];
              final panTlv = recordTlvs.firstWhere(
                (tlv) => tlv.tag == '5A',
                orElse: () => TLV('00', 0, []),
              );
              if (panTlv.tag == '5A') staticData.addAll(panTlv.value);
              final expTlv = recordTlvs.firstWhere(
                (tlv) => tlv.tag == '5F24',
                orElse: () => TLV('00', 0, []),
              );
              if (expTlv.tag == '5F24') staticData.addAll(expTlv.value);
              if (staticData.isNotEmpty) {
                final isValid = _verifySDASignature(
                  signature,
                  Uint8List.fromList(staticData),
                );
                if (!isValid) {
                  setState(
                    () =>
                        result =
                            '❌ Signature SDA invalide : transaction refusée',
                  );
                  return;
                }
              }
            }
            // 📘 Étape 7 : Traitement de la CVM List (tag 8E)
            final cvmTlv = gpoTlvs.firstWhere(
              (tlv) => tlv.tag == '8E',
              orElse: () => TLV('00', 0, []),
            );

            if (cvmTlv.tag == '8E') {
              final cvmList = cvmTlv.value;
              final cvmCode = cvmList[0]; // Premier code CVM (1er byte)

              if (cvmCode == 0x00) {
                // Code 0x00 = "Fail CVM processing" (refuser)
                setState(() => result = '❌ CVM échoué : transaction refusée');
                return;
              } else if (cvmCode == 0x01 || cvmCode == 0x02) {
                // Code 0x01/0x02 = "Plaintext PIN"
                await _demanderPin();
              } else if (cvmCode == 0x1E) {
                // Code 0x1E = "No CVM required"
                print('✅ Pas de CVM requis pour cette carte.');
              } else {
                print(
                  'ℹ️ Méthode CVM non implémentée : 0x${cvmCode.toRadixString(16)}',
                );
              }
            }

            var extractedCardData = extractCardData(recordTlvs);
            var extractedAuthData = extractAuthData(recordTlvs);

            // Vérification si les données sensibles sont présentes et non vides avant de les crypter
            if ((extractedAuthData.containsKey('ac') &&
                    extractedAuthData['ac']!.isNotEmpty) &&
                (extractedAuthData.containsKey('atc') &&
                    extractedAuthData['atc']!.isNotEmpty) &&
                (extractedAuthData.containsKey('cid') &&
                    extractedAuthData['cid']!.isNotEmpty)) {
              setState(() {
                pan = extractedCardData['pan'] ?? '';
                // Masquage du PAN
                pan = 'XXXX-XXXX-XXXX-${pan.substring(pan.length - 4)}';
                expiration = extractedCardData['expiration'] ?? '';
                name = extractedCardData['name'] ?? '';
                ac = encryptData(extractedAuthData['ac'] ?? '');
                atc = encryptData(extractedAuthData['atc'] ?? '');
                cid = encryptData(extractedAuthData['cid'] ?? '');
              });
            } else {
              setState(() => result = '⚠️ Données sensibles manquantes');
              return; // Sortir de la fonction si les données sensibles sont manquantes
            }
          } catch (_) {
            setState(() => result = '⚠️ Erreur lors de la lecture du record');
            return;
          }
        }
      }

      await FlutterNfcKit.finish();

      // 📘 Étape 8 : Analyse du CID avec déchiffrement
      final rawCid = decryptData(cid);
      final canGoOffline = _terminalRiskManagement();
      final taaDecision = _terminalActionAnalysis(rawCid, canGoOffline);

      if (ac.isNotEmpty && rawCid.isNotEmpty) {
        if (taaDecision == 'APPROVED_OFFLINE') {
          setState(() => result = '✅ Transaction approuvée offline');
        } else if (taaDecision == 'DECLINED') {
          setState(() => result = '❌ Transaction refusée par la carte');
        } else if (taaDecision == 'ONLINE_REQUESTED') {
          setState(() => result = '🔄 Autorisation en ligne en cours...');
          await Future.delayed(const Duration(seconds: 2));
          transactionReference = 'TRN${DateTime.now().millisecondsSinceEpoch}';
          authorizationCode = 'AUTH1234';
          setState(
            () =>
                result =
                    '✅ Autorisation acceptée pour $amount (simulation en ligne)',
          );
          transactionLogs.add(
            TransactionLog(
              pan: pan,
              expiration: expiration,
              atc: atc,
              result: result,
              timestamp: DateTime.now(),
              amount: amount,
              dateTime: DateTime.now().toString(),
              status: result,
            ),
          );
          await TransactionStorage.saveTransactions(transactionLogs);
        } else {
          setState(() => result = '⚠️ CID inconnu : $rawCid');
        }
      } else {
        setState(() => result = '⚠️ Données cryptographiques incomplètes');
      }

      // 📘 Étape 12 : Affichage du reçu avec toutes les informations nécessaires
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => ReceiptScreen(
                pan: pan,
                expiration: expiration,
                name: name,
                atc: atc,
                status: result,
                amount: amount, // Ajouter le montant ici
                transactionReference:
                    transactionReference, // Numéro de référence de la transaction
                authorizationCode:
                    authorizationCode, // Code d'autorisation simulé
                dateTime:
                    DateTime.now()
                        .toString(), // Date et heure de la transaction
              ),
        ),
      );
    } catch (e) {
      setState(() => result = '❌ Erreur : $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // 📘 Fonction pour valider le montant (doit être un nombre valide)
  bool _isValidAmount(String amount) {
    // Vérifie que le montant contient uniquement des chiffres et un séparateur décimal
    final regex = RegExp(r'^\d+(\.\d{1,2})?$');
    return regex.hasMatch(amount);
  }

  // 📘 Fonction pour valider les données avant de les crypter/déchiffrer
  String? validateData(String data) {
    if (data.isEmpty) {
      print(
        '❌ Données vides, impossible de procéder avec le chiffrement/déchiffrement',
      );
      return null; // Si les données sont vides, retourner null
    }
    return data; // Retourne les données si elles sont valides
  }

  // 📘 Fonction pour décoder les erreurs APDU
  String decodeApduError(String apduResponse) {
    final errorCode = apduResponse.substring(apduResponse.length - 4);
    final errorCodes = {
      '6A88': 'Sélecteur d’application non trouvé',
      '6F': 'Erreur générique',
      '9000': 'Succès',
      '6700': 'Paramètre incorrect',
      '6982': 'Conditions d’utilisation non remplies',
      // Ajouter plus de codes d'erreurs EMV ici
    };

    return errorCodes[errorCode] ?? 'Erreur inconnue : $errorCode';
  }

  void resetFields() {
    setState(() {
      pan = '';
      expiration = '';
      name = '';
      ac = '';
      atc = '';
      cid = '';
      result = '';
      isLoading = false;
      amount = ''; // Réinitialisation du montant
      amountController.clear(); // Réinitialisation du champ de saisie
    });
  }

  List<int> _hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '').toUpperCase();
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }

  Map<String, String> extractCardData(List<TLV> tlvs) {
    Map<String, String> cardData = {};
    for (final tlv in tlvs) {
      if (tlv.tag == '5A') {
        cardData['pan'] =
            tlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } else if (tlv.tag == '5F24') {
        final date =
            tlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        cardData['expiration'] =
            '20${date.substring(0, 2)}/${date.substring(2, 4)}';
      } else if (tlv.tag == '5F20') {
        cardData['name'] = String.fromCharCodes(tlv.value);
      }
    }
    return cardData;
  }

  Map<String, String> extractAuthData(List<TLV> tlvs) {
    Map<String, String> authData = {};
    for (final tlv in tlvs) {
      if (tlv.tag == '9F26') {
        authData['ac'] = Hex.encode(tlv.value);
      } else if (tlv.tag == '9F36') {
        authData['atc'] = Hex.encode(tlv.value);
      } else if (tlv.tag == '9F27') {
        authData['cid'] = Hex.encode(tlv.value);
      }
    }
    return authData;
  }

  String encryptData(String data) {
    final validatedData = validateData(data);
    if (validatedData == null) return '';
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey));
    final encrypted = encrypter.encrypt(validatedData, iv: aesIv);
    return encrypted.base64;
  }

  String decryptData(String encryptedData) {
    if (encryptedData.isEmpty) return '';
    final encryptedBytes = encrypt.Encrypted.fromBase64(encryptedData);
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey));
    final decrypted = encrypter.decrypt(encryptedBytes, iv: aesIv);
    return decrypted;
  }

  bool _terminalRiskManagement() {
    try {
      final montant = (double.parse(amount) * 100).toInt(); // en centimes

      if (montant <= 0) {
        result = '❌ Montant invalide';
        return false;
      }

      if (montant > floorLimit) {
        result =
            'ℹ️ Montant dépasse le seuil offline → Forcer autorisation en ligne';
        return false; // demande autorisation online
      }

      // ici, on pourrait vérifier d'autres critères : blacklist, pays, etc.

      result = '✅ Montant accepté offline';
      return true; // peut passer offline
    } catch (e) {
      result = '❌ Erreur TRM';
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTransactions();

    if (widget.initialAmount != null && widget.initialAmount!.isNotEmpty) {
      amount = widget.initialAmount!;
      print('🚀 _startEMVSession() déclenché automatiquement avec $amount');
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEMVSession());
    }
  }

  void _loadTransactions() async {
    final saved = await TransactionStorage.loadTransactions();
    setState(() {
      transactionLogs = saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SoftPOS - EMV NFC'),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Effacer l’historique',
            onPressed: () async {
              await TransactionStorage.clearTransactions();
              setState(() {
                transactionLogs.clear();
                result = '🗑️ Historique effacé';
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '💰 Montant à encaisser',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.nfc),
                    onPressed:
                        isLoading || amount.isEmpty || !_isValidAmount(amount)
                            ? null
                            : _startEMVSession,
                    label: const Text('Lire carte EMV'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: isLoading ? null : resetFields,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.teal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
            const SizedBox(height: 30),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text('💳 PAN : $pan', style: const TextStyle(fontSize: 16)),
              Text('📅 Expiration : $expiration'),
              Text('👤 Nom : $name'),
              const Divider(thickness: 1.2),
              Text('🔐 AC : ${decryptData(ac)}'),
              Text('🔢 ATC : ${decryptData(atc)}'),
              Text('📄 CID : ${decryptData(cid)}'),
              const SizedBox(height: 10),
              Text(result, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}
