import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:testpos/models/transaction_log_model.dart';
import 'package:testpos/presentation/main_navigation.dart';
import 'package:testpos/presentation/pin_entry_page.dart';
import 'package:testpos/presentation/transaction_detail_page.dart';
import 'package:testpos/presentation/transaction_history_page.dart';
import 'package:testpos/presentation/transaction_summary_page.dart';
import 'package:testpos/secure_storage_helper.dart';
import 'package:testpos/transaction_storage.dart';
import 'core/tlv_parser.dart';
import 'core/hex.dart';
import 'data/nfc/apdu_commands.dart';
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
        '/nfcWaiting': (context) => const NfcWaitingPage(initialAmount: ''),
        '/transactionSummary': (context) => const TransactionSummaryPage(),
        '/transactionDetail': (context) => const TransactionDetailPage(),
        '/transactionHistory':
            (context) => const TransactionHistoryPage(), // si besoin séparément
      },
    ),
  );
}

class HomeScreen extends StatefulWidget {
  //un écran (une page) qui peut évoluer dans le temps (c’est un StatefulWidget, donc il a un State associé).
  final String?
  initialAmount; //un champ (attribut) de ta classe HomeScreen, appelé initialAmount.C’est une valeur facultative (String?) qui représente le montant à encaisser
  const HomeScreen({
    super.key,
    this.initialAmount,
  }); //le constructeur de la page :super.key est un paramètre utile pour Flutter (optimisations internes).this.initialAmount permet de passer directement une valeur à initialAmount
  @override
  State<HomeScreen> createState() => _HomeScreenState(); // Tu dis que le "state" (l'état) de cette page sera géré par une autre classe : _HomeScreenState
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
  String cardCountryCode = '000'; // Valeur par défaut si 9F1A n'est pas trouvé

  // 🗂️ Table CAPK (clé publique par RID et index)
  final Map<String, List<Map<String, String>>> capkTable = {
    'A000000003': [
      // Visa RID
      {
        'index': '92', // Valeur de 9F22 fournie par la carte
        'modulus': //la grande clé (clé RSA, nombre premier).
            'A38BCE78947B3F8D4EF4F93AA76B1F6B6E6C1B25B2B9E9CFBDE3C1A0D198E2113A336875C2D16A1F42ADFC23A28196A731E8AAB1881E12E1851B03F3E9FC1045',
        'exponent':
            '03', //petit nombre, souvent 03 ou 65537 (valeurs classiques pour RSA).
      },
      // ajouter d'autres clés ici (ex : Mastercard, Amex)
    ],
    'A000000004': [
      // Mastercard RID
      {
        'index': '92',
        'modulus':
            'A8D3B2C158BF557F6A65A7D54D6B595F1AA28F1BC18985D358B47855A6B6A545F4C9818DC8D2E1152A3B516D23A1F19D225D5B9E03A61D17ECA02F4AC2B45A465',
        'exponent': '03',
      },
    ],
  };
  /*Quand on utilises SDA (Static Data Authentication) ou DDA/CDA (Dynamic Data Authentication), il faut :

      Vérifier que la signature fournie par la carte est authentique.

      Pour ça, il faut une clé publique du Certificate Authority (CA).

      Ces clés sont stockées dans ton terminal (ici dans capkTable) et sont identifiées par :

      Le RID = Registered Application Provider Identifier (exemple : 'A000000003' = Visa).

      Le index = Index de la clé utilisée par la carte (ex. '92' dans 9F22). */

  late encrypt.Key
  aesKey; // Déclaration des variables pour la clé AES et l’IV (pas initialisées tout de suite).
  late encrypt.IV aesIv;

  List<TransactionLog> transactionLogs =
      []; // Historique local des transactions
  /*Chaque TransactionLog contient :

      pan, expiration, atc, ac, cid, etc.

      ➡️ Et certains champs (ac, atc, cid) sont chiffrés grâce à ta clé AES.

      */

  /// Demande à l'utilisateur de saisir son PIN via l'écran `PinEntryPage`.
  ///  C'est utilisé pour la vérification du porteur de la carte (CVM : Cardholder Verification Method).
  /// Si le PIN est correct (longueur ≥ 4), la fonction continue.
  /// Sinon, elle arrête la transaction avec une exception ("CVM échoué").
  /// Demande à l'utilisateur de saisir son PIN.
  /// Retourne le PIN si saisi correctement, sinon lance une exception.
  /// Demande à l'utilisateur de saisir son PIN.
  /// Retourne le PIN si saisi correctement, sinon lance une exception.
  Future<String> _demanderPin() async {
    final pin = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PinEntryPage()),
    );

    if (!mounted) return ''; // Sécurité : si la page a été démontée entre-temps

    if (pin == null || pin.length < 4) {
      setState(() => result = '❌ PIN incorrect ou annulé');
      throw Exception('CVM échoué'); // Arrête la transaction
    }

    print('✅ PIN saisi : $pin');
    return pin; // 🔥 Le PIN est maintenant bien retourné à l’appelant !
  }

  Future<void> sendOfflinePlaintextPin(String pin) async {
    if (pin.isEmpty) {
      throw Exception('PIN vide, impossible d’envoyer à la carte');
    }

    // Prépare le PIN Block (format 2)
    // Exemple : 2412 345F FFFF FFFF (24 = length 4 digits, 12 34 5F... = PIN + padding F)
    String pinBlock =
        '2${pin.length}$pin${'FFFFFFFFFFFF'.substring(0, 14 - pin.length * 2)}';

    // Envoie la commande VERIFY (0x20)
    final apdu = [
      0x00, // CLA
      0x20, // INS (VERIFY)
      0x00, // P1
      0x80, // P2 (plain text PIN)
      pinBlock.length ~/ 2, // Lc (length of PIN block)
      ..._hexToBytes(pinBlock),
    ];

    final apduHex = apdu.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    final response = await FlutterNfcKit.transceive(apduHex);

    if (!response.endsWith('9000')) {
      setState(
        () =>
            result = '❌ PIN refusé par la carte : ${decodeApduError(response)}',
      );
      throw Exception('PIN refusé');
    }

    print('✅ PIN accepté par la carte');
  }

  Future<void> sendOfflineEncryptedPin(
    String pin,
    String rid,
    String capkIndex,
  ) async {
    if (pin.isEmpty) {
      throw Exception('PIN vide, impossible de continuer');
    }

    final capk = findCapk(rid, capkIndex);
    if (capk == null) {
      throw Exception('CAPK non trouvée pour RID $rid et index $capkIndex');
    }

    // 👉 Formatage du PIN Block (exemple Format 0)
    String pinBlock =
        '2${pin.length}$pin${'FFFFFFFFFFFF'.substring(0, 14 - pin.length * 2)}';
    List<int> pinBlockBytes = _hexToBytes(pinBlock);

    // 👉 Chiffrement RSA avec la clé publique CAPK
    final encrypter = encrypt.Encrypter(
      encrypt.RSA(publicKey: capk, encoding: encrypt.RSAEncoding.PKCS1),
    );
    final encryptedPin = encrypter.encryptBytes(pinBlockBytes);

    final apdu = [
      0x00, // CLA
      0x20, // INS (VERIFY)
      0x00, // P1
      0x88, // P2 (encrypted PIN block)
      encryptedPin.bytes.length, // Lc
      ...encryptedPin.bytes,
    ];

    final apduHex = apdu.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    final response = await FlutterNfcKit.transceive(apduHex);

    if (!response.endsWith('9000')) {
      setState(
        () =>
            result =
                '❌ PIN chiffré refusé par la carte : ${decodeApduError(response)}',
      );
      throw Exception('PIN chiffré refusé');
    }

    print('✅ PIN chiffré accepté par la carte');
  }

  /*Cette fonction décide quelle action prendre selon le CID (Cryptogram Information Data) que la carte a généré et si la transaction peut se faire offline.
    C’est ce qu’on appelle le Terminal Action Analysis (TAA) dans le standard EMV. */
  String _terminalActionAnalysis(String cid, bool canGoOffline) {
    // cid : c’est le code que la carte envoie pour dire ce qu’elle veut (approbation, refus, demande online). / canGoOffline : une valeur true ou false qui indique si le terminal accepte de faire des transactions offline (en fonction de la politique de gestion du risque).
    if (cid == '40' && canGoOffline) {
      return 'APPROVED_OFFLINE'; // TC = Transaction Certificate
    } else if (cid == '80') {
      return 'DECLINED'; // AAC = Application Authentication Cryptogram
    } else if (cid == '00') {
      return 'ONLINE_REQUESTED'; // ARQC = Authorization Request
    } else {
      return 'UNKNOWN';
    }
  } //Même si la carte propose, c’est le terminal qui tranche selon ses règles de sécurité.

  // 🔄 Partie ONLINE → à remplacer la simulation plus tard par un vrai appel HTTP ou HSM
  /*Quand la carte demande une autorisation online (ARQC), cette fonction est censée envoyer une requête HTTP à ton serveur bancaire (ou HSM) pour savoir si la transaction est acceptée ou refusée.
  on utilises une simulation (pas de vrai backend encore),  prêt pour être remplacé par un vrai appel. */
  Future<bool> sendArqcToBackend({
    required String
    arqc, // ARQC généré par la carte (Authorization Request Cryptogram)
    required String pan, // PAN complet (numéro de carte)
    required String
    atc, // ATC = Application Transaction Counter (compteur de transactions)
    required int amount, // Montant de la transaction
    required String pinOnline,
  }) async {
    // EXEMPLE D’APPEL HTTP (POST) vers ton serveur d'autorisation Envoie un POST HTTP vers ton backend.Avec un JSON qui contient les infos nécessaires
    /*
  final response = await http.post(
    Uri.parse('https://your-backend.com/authorize'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'arqc': arqc,
      'pan': pan,
      'atc': atc,
      'amount': amount,
      'pin': pinOnline,
    }),
  );
   //Traitement de la réponse
  if (response.statusCode == 200) {Si le serveur répond avec 200 OK 
    final data = jsonDecode(response.body);
    return data['authorized'] == true; //Il regarde dans la réponse JSON si authorized == true
  } else {
    throw Exception('Erreur serveur ou réseau : ${response.statusCode}'); // il lance une exception → échec réseau ou serveur
  }
  */

    // ⚠️ TEMPORAIRE (simulation actuelle) : a Supprime
    await Future.delayed(const Duration(seconds: 2));
    print('✅ ARQC envoyé avec PIN online : $pinOnline');
    return true; // ← simulation tjrs accepter
  }
  /*C’est la fonction qui génère le Application Cryptogram (AC), étape essentielle dans le process EMV.

    L’AC peut être :

    TC (Transaction Certificate) si la transaction est approuvée offline,

    AAC (Application Authentication Cryptogram) si la carte refuse,

    ARQC (Authorization Request Cryptogram) si la carte demande l’autorisation en ligne (backend / HSM).

    */

  Future<void> _generateAc(
    String taaDecision,
    List<TLV> aidResponseTlvs,
    String fullPan,
  ) async {
    try {
      // 📌 Lire le CDOL1 (Tag 8C)
      final cdol1Tlv =
          TLVParser.findTlvRecursive(aidResponseTlvs, 0x8C) ??
          TLV(0x00, Uint8List(0));

      if (cdol1Tlv.tag != 0x8C) {
        print('❌ Pas de CDOL1 trouvé → Impossible de générer AC');
        return;
      }

      final cdol1 = cdol1Tlv.value;
      List<int> cdolData = [];
      int idx = 0;

      while (idx < cdol1.length) {
        final tag =
            cdol1[idx].toRadixString(16).padLeft(2, '0') +
            cdol1[idx + 1].toRadixString(16).padLeft(2, '0');
        final length = cdol1[idx + 2];
        idx += 3;

        if (tag == '9F02') {
          int transactionAmount =
              ((double.tryParse(amount) ?? 0) * 100).toInt();
          final amountHex = transactionAmount
              .toRadixString(16)
              .padLeft(length * 2, '0');
          cdolData.addAll(_hexToBytes(amountHex));
        } else if (tag == '9F1A') {
          const terminalCountryCode = '056';
          cdolData.addAll(
            _hexToBytes(terminalCountryCode.padLeft(length * 2, '0')),
          );
        } else if (tag == '9F37') {
          final random = List<int>.generate(
            length,
            (i) => (DateTime.now().millisecondsSinceEpoch >> (i * 8)) & 0xFF,
          );
          cdolData.addAll(random);
        } else {
          cdolData.addAll(List.filled(length, 0x00));
        }
      }

      final acType = (taaDecision == 'APPROVED_OFFLINE') ? 0x40 : 0x80;
      final lc = cdolData.length;
      final generateAcCommand = [
        0x80,
        0xAE,
        acType,
        0x00,
        lc,
        ...cdolData,
        0x00,
      ];

      final generateAcHex =
          generateAcCommand
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join();
      print('📤 GENERATE AC : $generateAcHex');

      final responseHex = await FlutterNfcKit.transceive(generateAcHex);
      print('📥 Réponse GENERATE AC : $responseHex');

      final responseBytesList = _hexToBytes(responseHex);
      final responseBytes = Uint8List.fromList(responseBytesList);
      final responseTlvs = TLVParser.parse(responseBytes);

      // 🔎 Extraction CID
      final cidTlv =
          TLVParser.findTlvRecursive(responseTlvs, 0x9F27) ??
          TLV(0x00, Uint8List(0));

      final cid =
          cidTlv.value.isNotEmpty
              ? cidTlv.value[0].toRadixString(16).padLeft(2, '0')
              : '00';
      print('🔎 CID : $cid');

      // 🔎 Extraction ATC
      final atcTlv =
          TLVParser.findTlvRecursive(responseTlvs, 0x9F36) ??
          TLV(0x00, Uint8List(0));

      if (atcTlv.tag == 0x9F36) {
        final atc =
            atcTlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        print('🔢 ATC : $atc');
      }

      // 🔥 Interprétation du CID
      if (cid == '40') {
        print('✅ Transaction approuvée offline (TC)');
      } else if (cid == '80') {
        print('❌ Transaction refusée par la carte (AAC)');
      } else if (cid == '00') {
        print('🔄 Autorisation online demandée (ARQC)');

        // 📥 Extraction de l’ARQC
        final acTlv =
            TLVParser.findTlvRecursive(responseTlvs, 0x9F26) ??
            TLV(0x00, Uint8List(0));

        final arqc =
            acTlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        final atcValue =
            atcTlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        final authorized = await sendArqcToBackend(
          arqc: arqc,
          pan: fullPan,
          atc: atcValue,
          amount: int.parse(amount),
          pinOnline: authorizationCode,
        );

        if (authorized) {
          print('💎 Banque OK → continuer avec le 2nd GENERATE AC');
          await secondGenerateAc(
            authorized: true,
            aidResponseTlvs: aidResponseTlvs,
          );
        } else {
          print('🚫 Banque refuse → stoppe la transaction');
          await secondGenerateAc(
            authorized: false,
            aidResponseTlvs: aidResponseTlvs,
          );
        }
      } else {
        print('❓ CID inconnu : $cid');
      }

      // 📜 Traitement des Issuer Scripts (71, 72)
      for (var scriptTag in [0x71, 0x72]) {
        final scriptTlv =
            TLVParser.findTlvRecursive(responseTlvs, scriptTag) ??
            TLV(0x00, Uint8List(0));

        if (scriptTlv.tag == scriptTag) {
          final scriptCommand =
              scriptTlv.value
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join();
          print(
            '▶️ Envoi Issuer Script ${scriptTag.toRadixString(16).toUpperCase()} : $scriptCommand',
          );

          try {
            final scriptResponse = await FlutterNfcKit.transceive(
              scriptCommand,
            );
            print('📥 Réponse du Issuer Script : $scriptResponse');
          } catch (e) {
            print('❌ Erreur lors de l’exécution du Issuer Script : $e');
          }
        }
      }
    } catch (e) {
      print('❌ Erreur lors de GENERATE AC : $e');
    }
  }

  /*La fonction secondGenerateAc envoie la deuxième commande GENERATE AC à la carte bancaire pour finaliser la transaction, après avoir reçu la réponse de la banque (autorisée ou refusée).

    Dans EMV :

    1er GENERATE AC : Demande l’ARQC (pour online) ou génère le TC (offline).

    2nd GENERATE AC : Confirme le résultat (accepté ou refusé) auprès de la carte. */

  Future<void> secondGenerateAc({
    required bool authorized,
    required List<TLV> aidResponseTlvs,
  }) async {
    try {
      // Choix du type d'AC (Application Cryptogram)
      final acType =
          authorized ? 0x00 : 0x80; // 0x00 = TC (approuvé), 0x80 = AAC (refusé)

      final generateAcCommand = [
        0x80, // CLA : Class of instruction
        0xAE, // INS : Instruction code (GENERATE AC)
        acType, // P1 : Type d'AC demandé
        0x00, // P2
        0x00, // Lc : 0 car pas de CDOL2
      ];

      final generateAcHex =
          generateAcCommand
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join(); // Transforme en string hexadécimal
      print('📤 Second GENERATE AC : $generateAcHex');

      // Envoi de la commande APDU
      final responseHex = await FlutterNfcKit.transceive(generateAcHex);
      print('📥 Réponse du second GENERATE AC : $responseHex');

      // Traitement de la réponse
      final responseBytesList = _hexToBytes(responseHex);
      final responseBytes = Uint8List.fromList(responseBytesList);
      final responseTlvs = TLVParser.parse(responseBytes);

      // ➡️ (Optionnel) Tu peux extraire ici ATC, CID, etc. en utilisant findTlvRecursive
      // Exemple d'extraction (pas obligatoire si tu ne l'utilises pas maintenant) :
      /*
    final atcTlv = TLVParser.findTlvRecursive(
      responseTlvs,
      0x9F36,
    ) ?? TLV(0x00, Uint8List(0));

    if (atcTlv.tag == 0x9F36) {
      final atc = atcTlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      print('🔢 ATC (second AC) : $atc');
    }
    */

      // ➡️ Mise à jour du résultat
      setState(() {
        result =
            authorized
                ? '✅ Transaction autorisée après second GENERATE AC'
                : '❌ Transaction refusée après second GENERATE AC';
      });

      await FlutterNfcKit.finish();

      // ➡️ Historisation de la transaction
      final log = TransactionLog(
        pan: pan,
        expiration: expiration,
        atc: atc,
        result: result,
        timestamp: DateTime.now(),
        amount: amount,
        dateTime: DateTime.now().toString(),
        status: result,
      );
      transactionLogs.add(log);
      await TransactionStorage.saveTransactions(transactionLogs);

      // ➡️ Affichage du reçu
      Navigator.pushReplacementNamed(
        context,
        '/transactionDetail',
        arguments: log,
      );
    } catch (e) {
      print('❌ Erreur lors du second GENERATE AC : $e');
    }
  }

  //rouver la clé publique du Certificate Authority (CA), qui est utilisée pour vérifier la signature RSA (Static Data Authentication).

  RSAPublicKey? findCapk(String rid, String index) {
    final capkList =
        capkTable[rid]; // Récupère la liste des clés pour le RID donné. dentifie le fournisseur (Visa, Mastercard, etc.)
    if (capkList == null) return null; // Si pas de clés → retourne null.

    final capk = capkList.firstWhere(
      (capk) =>
          capk['index'] ==
          index, // Cherche la clé avec l’index donné. Indique laquelle des clés du CA utiliser
      orElse: () => {},
    );

    if (capk.isEmpty) return null; // Si pas trouvé → retourne null.

    // Construit la clé RSA publique avec le modulus et l’exponent.
    return RSAPublicKey(
      BigInt.parse(capk['modulus']!, radix: 16), //Partie de la clé RSA
      BigInt.parse(capk['exponent']!, radix: 16), //Autre partie de la clé RSA
    );
  }

  bool _verifySDASignature(
    Uint8List signature, // Signature à vérifier (RSA sur données statiques)
    Uint8List staticData, // Données originales (PAN + Expiration…)
    String aidHex, // AID de l’application (pour trouver le RID)
    List<TLV> aidResponseTlvs, // TLVs de la réponse SELECT AID
  ) {
    try {
      final String rid = aidHex.substring(
        0,
        10,
      ); // Récupère le RID (5 octets hex)

      // 🔍 Récupère le CAPK Index (Tag 9F22) en utilisant findTlvRecursive
      final capkTlv =
          TLVParser.findTlvRecursive(aidResponseTlvs, 0x9F22) ??
          TLV(0x00, Uint8List(0));

      final capkIndex =
          capkTlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Recherche de la clé publique CAPK correspondante
      final capk = findCapk(rid, capkIndex);
      if (capk == null) {
        print('❌ CAPK introuvable pour RID $rid avec index $capkIndex');
        return false;
      }

      // Déchiffrement de la signature avec la clé publique
      final encrypter = encrypt.Encrypter(
        encrypt.RSA(publicKey: capk, encoding: encrypt.RSAEncoding.PKCS1),
      );

      final decrypted = encrypter.decryptBytes(encrypt.Encrypted(signature));

      // Vérification : on compare les dernières données déchiffrées aux staticData
      final decryptedStaticData = decrypted.sublist(
        decrypted.length - staticData.length,
      );

      return decryptedStaticData.toString() == staticData.toString();
    } catch (e) {
      print('❌ Erreur lors de la vérification SDA : $e');
      return false;
    }
  }

  // 📘 Étapes 1 à 13 : Processus EMV complet
  void _startEMVSession({required bool skipReset}) async {
    //Démarrage de la transaction
    // ✅ Étape 0 : Vérifie si le montant est valide
    if (!_isValidAmount(amount)) {
      //vérifies si l'utilisateur a bien entré un montant correct (pas vide, pas négatif)
      setState(() {
        result = ' Montant invalide. Veuillez entrer un nombre valide.';
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
      try {
        final tag = await FlutterNfcKit.poll(
          //Lance la détection de la carte
          timeout: const Duration(seconds: 20),
        );
        print('✅ Carte détectée : ${tag.type}'); //récupère le type de carte
        setState(() => result = '✅ Carte détectée : ${tag.type}');
      } catch (e) {
        print('❌ Erreur NFC : $e');
        setState(() => result = '❌ Aucune carte détectée (timeout)');
        return;
      }

      // 📤 Étape 2 : Envoi SELECT PPSE Sélection de l'application de paiement Cela veut dire "Sélectionne l'environnement de paiement".Proximity Payment System Environment 2PAY.SYS.DDF01
      final apduHex =
          ApduCommands
              .selectPPSE //Cela  renvoie l’AID (Application Identifier), qui identifie le type de carte (Visa, Mastercard…).
              .map(
                (e) => e.toRadixString(16).padLeft(2, '0'),
              ) //transforme chaque byte en sa version hexadécimale sur deux caractères.
              .join();
      final responseHex = await FlutterNfcKit.transceive(
        apduHex,
      ); //prend une string hexadécimale et Envoi de la commande via NFC et attend la reponse À la fin, 9000 = statut success (OK). Sinon, ça peut être 6A88 → AID not found, etc.

      // 📘 Gestion des erreurs APDU pour SELECT PPSE
      final decodedError = decodeApduError(
        responseHex,
      ); //va extraire les 4 derniers caractères (Status Word SW1 SW2). 9000 → "Succès" 6A88 → "Sélecteur d’application non trouvé" 6700 → "Paramètre incorrect

      if (decodedError != 'Succès') {
        setState(() => result = decodedError); // Afficher l'erreur si échec
        return;
      }
      // La réponse du SELECT PPSE est une structure TLV
      final responseBytesList = _hexToBytes(
        responseHex,
      ); // Transforme la string hex en liste de bytes (List<int>)
      final responseBytes = Uint8List.fromList(
        responseBytesList,
      ); // Convertit en Uint8List car TLVParser.parse attend Uint8List
      final tlvs = TLVParser.parse(
        responseBytes,
      ); // Utilise ton TLVParser pour extraire les champs Tag-Length-Value
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu :$tlvs');

      // 🔍 Étape 2b : Extraction de l'AID (TAG 4F)
      final aidTlv =
          TLVParser.findTlvRecursive(tlvs, 0x4F) ??
          TLV(0x00, Uint8List(0)); // Utilise la fonction récursive

      if (aidTlv.tag != 0x4F) {
        print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu 222222222');
        return; // Si aucun AID trouvé → on sort directement
      }
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu :$aidTlv');
      final aidHex =
          aidTlv.value
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(); // Transforme la valeur de l'AID en string hex lisible
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu :$aidHex');
      // 📤 Étape 3 : Envoi SELECT AID
      final selectAid = ApduCommands.buildSelectAID(
        // .buildSelectAID fonction qui construit l’APDU SELECT AID à partir de l’AID récupéré
        // Format de la commande CLA | INS | P1 | P2 | Lc | Data (AID) | Le (00)
        aidHex,
      ); // Cela sélectionne l’application de paiement sur la carte

      final selectAidHex =
          selectAid
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join(); // Transforme en hexadécimal

      final aidResponseHex = await FlutterNfcKit.transceive(
        selectAidHex,
      ); // Envoie la commande SELECT AID via NFC
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu :$aidResponseHex');
      // 📘 Gestion des erreurs APDU pour SELECT AID
      final decodedAidError = decodeApduError(aidResponseHex);
      if (decodedAidError != 'Succès') {
        // si la carte a répondu avec le code 9000 (succès).ça affiche l’erreur et arrête la transaction.
        setState(() => result = decodedAidError);
        return;
      }

      /*qu’est-ce que le PDOL et le GPO ?
          PDOL (Processing Options Data Object List) → C’est une liste de données que la carte attend du terminal avant de démarrer le traitement.

          Exemples d’éléments demandés dans le PDOL :

          Montant de la transaction (9F02)

          Code pays (9F1A)

          Devise (5F2A)

          Etc.

          GPO (Get Processing Options) → C’est la commande qui démarre officiellement la transaction EMV après avoir fourni les infos demandées par la carte dans le PDOL.*/

      // 🔐 Étape 4 : Traitement du PDOL (tag 9F38) et construction GPO dynamique

      // Décode la réponse de SELECT AID reçue juste avant
      final aidResponseBytesList = _hexToBytes(aidResponseHex);
      final aidResponseBytes = Uint8List.fromList(
        aidResponseBytesList,
      ); // Convertit en Uint8List pour TLVParser
      final aidResponseTlvs = TLVParser.parse(aidResponseBytes);
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu :$aidResponseTlvs');
      // Lecture du PDOL dans la réponse
      String? pdolHex;
      final pdolTlv = TLVParser.findTlvRecursive(
        aidResponseTlvs,
        0x9F38,
      ); // Recherche du tag 9F38 récursivement
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu PDOLE:$pdolTlv');
      if (pdolTlv != null) {
        pdolHex = Hex.encode(pdolTlv.value);
      }

      // Construction du GPO si le PDOL est présent
      List<int> gpoCommand;
      if (pdolHex != null && pdolHex.isNotEmpty) {
        final pdolBytes = _hexToBytes(pdolHex); // Transformation en bytes
        List<int> pdolData = [];
        int idx = 0;

        while (idx < pdolBytes.length) {
          // Ici, on parcourt les éléments du PDOL : Chaque entrée = Tag (2 octets) + Length (1 octet)
          final tag =
              pdolBytes[idx].toRadixString(16).padLeft(2, '0') +
              pdolBytes[idx + 1]
                  .toRadixString(16)
                  .padLeft(2, '0'); // Tag (2 octets)
          final length = pdolBytes[idx + 2]; // Length (1 octet)
          idx += 3;

          if (tag == '9F02') {
            // Montant de la transaction
            int transactionAmount =
                (double.tryParse(amount) ?? 0 * 100).toInt();
            final amountHex = transactionAmount
                .toRadixString(16)
                .padLeft(length * 2, '0');
            pdolData.addAll(
              _hexToBytes(amountHex),
            ); // Montant converti en hex et rempli
          } else {
            pdolData.addAll(
              List.filled(length, 0x00),
            ); // Si ce n’est pas le montant → on met des zéros (0x00)
          }
        }

        //Quand le PDOL est présent
        final dolWithTag =
            [0x83, pdolData.length] +
            pdolData; //83 = tag du GPO template.Le reste : la taille + les données.
        gpoCommand = [
          0x80, // CLA (class of instruction)
          0xA8, // INS (instruction) → GET PROCESSING OPTIONS
          0x00, // P1
          0x00, // P2
          dolWithTag
              .length, // Lc = longueur des données suivantes (PDOL rempli)
          ...dolWithTag, // Les données demandées par le PDOL (ex : montant)
          0x00, // Le (longueur de réponse attendue)
        ];
      } else {
        gpoCommand = [
          0x80,
          0xA8,
          0x00,
          0x00,
          0x02,
          0x83,
          0x00,
          0x00,
        ]; //Si PAS de PDOL (la carte n’a rien demandé)
      }

      /*⚠️ Ne pas envoyer les données attendues par la carte → la transaction peut être rejetée (non-respect du PDOL).

        Si on envoies une commande sans respecter le PDOL, certaines cartes (Visa, Mastercard) peuvent répondre avec une erreur comme 6A80 (data incorrecte).

        Si il n’y a pas de PDOL, la carte accepte la version courte sans souci.*/

      // Construction de la commande GPO en hexadécimal
      final gpoHexStr =
          gpoCommand
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join(); // Convertit la commande GPO en string hexadécimale

      // Envoi de la commande GPO via NFC
      final gpoResponseHex = await FlutterNfcKit.transceive(gpoHexStr);
      print(
        'coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu GPOOOOOOOOOREPONSE:$gpoResponseHex',
      );
      // Transformation de la réponse GPO en bytes
      final gpoResponseBytesList = _hexToBytes(gpoResponseHex);
      final gpoResponseBytes = Uint8List.fromList(
        gpoResponseBytesList,
      ); // Convertit en Uint8List car TLVParser.parse attend Uint8List

      // Utilise ton TLVParser pour extraire les champs Tag-Length-Value
      final gpoTlvs = TLVParser.parse(gpoResponseBytes);
      print(
        'coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu GPOOOOOOOOOOOTTLVVV :$gpoTlvs',
      );
      // 🧠 Étape 5 : Lire l'AFL (TAG 94)
      /*Juste avant, on a envoyé la commande GPO (Get Processing Options) à la carte.
       La réponse de la carte contient plusieurs informations importantes, notamment l’AFL (Application File Locator), qui est le plan de lecture des enregistrements. L’AFL décrit quels enregistrements il faut lire sur la carte, et où ils se trouvent.
      Parcours de l’AFL
      L’AFL (tag 94) te dit où aller lire dans la carte, avec :

      SFI : identifiant du fichier (Short File Identifier),

      Record Start / End : les lignes (records) à lire dans ce fichier.
      Il contient des groupes de 4 octets par enregistrement :


      Octet	Signification
      1er octet	SFI (Short File Identifier, 5 bits) + padding
      2ème octet	Premier record à lire
      3ème octet	Dernier record à lire
      4ème octet	Nombre d’occurrences (non utilisé dans ton cas simple)
      */

      // 🔍 Recherche de l'AFL (Tag 94) dans la réponse GPO
      final aflTlv =
          TLVParser.findTlvRecursive(gpoTlvs, 0x94) ??
          TLV(
            0x00,
            Uint8List(0),
          ); // ← Recherche récursive, retourne TLV vide si pas trouvé

      if (aflTlv.tag != 0x94) {
        return; // ← Si pas d’AFL, on sort (car on ne peut pas continuer)
      }
      print(
        'coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu  AFLLLLLLLLLLTTTTTTTLVVV:$aflTlv',
      );

      // Si trouvé, on récupère la valeur de l’AFL
      final afl = aflTlv.value;
      print('coucouuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu  AFLLLLLLLLLL:$afl');
      // On déclare ici pour pouvoir l'utiliser plus tard dans le generateAC
      String fullPan = '';

      // 📖 Lecture des enregistrements
      for (int i = 0; i < afl.length; i += 4) {
        final sfi = afl[i] >> 3; // Extraction du SFI (Short File Identifier)
        final recordStart = afl[i + 1]; // Premier record à lire
        final recordEnd = afl[i + 2]; // Dernier record à lire

        for (int record = recordStart; record <= recordEnd; record++) {
          final p1 = record; // Numéro du record
          final p2 =
              (sfi << 3) | 4; // Le SFI est placé dans les bits de poids fort
          final readRecord = [
            0x00,
            0xB2,
            p1,
            p2,
            0x00,
          ]; // Commande READ RECORD 0x00 : CLA (class byte),0xB2 : INS (instruction : READ RECORD),p1 = numéro du record (recordStart jusqu’à recordEnd),p2 = (SFI << 3) | 4 : placement du SFI dans les bits de poids fort, 4 = mode “readrecord by SFI”.

          final apduHex =
              readRecord
                  .map((e) => e.toRadixString(16).padLeft(2, '0'))
                  .join(); //hex

          try {
            // Envoi de la commande READ RECORD
            final recordHex = await FlutterNfcKit.transceive(
              apduHex,
            ); // Envoie et réception de la réponse

            // Transformation de la réponse en bytes
            final recordBytesList = _hexToBytes(recordHex);
            final recordBytes = Uint8List.fromList(
              recordBytesList,
            ); // Convertit en Uint8List pour TLVParser

            // Parsing TLV de la réponse
            final recordTlvs = TLVParser.parse(recordBytes);

            /* La réponse de la carte contient souvent :
     - PAN (tag 5A)
     - Expiration (tag 5F24)
     - Nom du titulaire (tag 5F20)
     - Signature SDA (tag 93)
     - Autres données utiles (CVM List, ATC, AC, etc.)
  */

            // ✅ Étape 6 : Extraction des données

            // Extraction du code pays (tag 9F1A)
            final countryCodeTlv =
                TLVParser.findTlvRecursive(recordTlvs, 0x9F1A) ??
                TLV(0x00, Uint8List(0)); // TLV vide si pas trouvé

            if (countryCodeTlv.tag == 0x9F1A) {
              cardCountryCode =
                  countryCodeTlv.value
                      .map((b) => b.toRadixString(16).padLeft(2, '0'))
                      .join(); // Convertit les bytes en string hex
            }

            // Extraction de la signature SDA (tag 93)
            final sdaTlv =
                TLVParser.findTlvRecursive(recordTlvs, 0x93) ??
                TLV(0x00, Uint8List(0));

            if (sdaTlv.tag == 0x93) {
              // Si signature trouvée
              final signature = Uint8List.fromList(
                sdaTlv.value,
              ); // Signature extraite
              final staticData = <int>[]; // Static Data vide

              // Extraction du PAN (tag 5A)
              final panTlv =
                  TLVParser.findTlvRecursive(recordTlvs, 0x5A) ??
                  TLV(0x00, Uint8List(0));
              if (panTlv.tag == 0x5A) {
                staticData.addAll(
                  panTlv.value,
                ); // Ajoute le PAN aux données statiques
              }

              // Extraction de la date d'expiration (tag 5F24)
              final expTlv =
                  TLVParser.findTlvRecursive(recordTlvs, 0x5F24) ??
                  TLV(0x00, Uint8List(0));
              if (expTlv.tag == 0x5F24) {
                staticData.addAll(
                  expTlv.value,
                ); // Ajoute la date d'expiration aux données statiques
              }

              // Vérification de la signature SDA si staticData n'est pas vide
              if (staticData.isNotEmpty) {
                final isValid = _verifySDASignature(
                  signature,
                  Uint8List.fromList(staticData),
                  aidHex,
                  aidResponseTlvs,
                );

                // Si la signature est invalide
                if (!isValid) {
                  setState(() {
                    result = '❌ Signature SDA invalide : transaction refusée';
                  });
                  return;
                }
              }
            }

            // 📘 Étape 7 : Traitement de la CVM List (tag 8E)
            /*Dans EMV, la CVM (Cardholder Verification Method) permet de vérifier que le porteur de la carte est bien l’utilisateur légitime.

                Exemples de CVM :

                PIN offline

                Signature

                Pas de CVM nécessaire (ex : petit montant)

                PIN online
                 La carte peut proposer plusieurs méthodes, classées par ordre de priorité. */

            Future<bool> checkCvmCondition(int conditionCode) async {
              // Chaque méthode CVM est associée à une condition.Cette fonction vérifie si la condition est remplie.

              final montant =
                  (double.tryParse(amount) ?? 0) * 100; // Montant en centimes

              switch (conditionCode) {
                case 0x00: // Always
                  return true;
                case 0x01: // If amount > floorLimit
                  return montant > floorLimit;
                case 0x02: // If amount <= floorLimit
                  return montant <= floorLimit;
                default:
                  print(
                    '⚠️ Condition CVM inconnue : 0x${conditionCode.toRadixString(16)}',
                  );
                  return false;
              }
            }

            final rid = aidHex.substring(
              0,
              10,
            ); // RID = les 10 premiers caractères de l'AID

            // 🔍 Extraction du CAPK Index (Tag 9F22)
            final capkTlv =
                TLVParser.findTlvRecursive(aidResponseTlvs, 0x9F22) ??
                TLV(0x00, Uint8List(0)); // TLV vide si pas trouvé

            final capkIndex =
                capkTlv.value
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(); // Convertit en string hexadécimale

            Future<bool> processCvmList(List<int> cvmList) async {
              int idx = 0;

              while (idx + 2 <= cvmList.length) {
                final cvmCode = cvmList[idx];
                final conditionCode = cvmList[idx + 1];
                idx += 2;

                final bool conditionOk = await checkCvmCondition(conditionCode);
                /*Que fait cette boucle ?
                  La liste cvmList vient du tag 8E (CVM List) sur la carte.

                  Chaque paire de deux octets représente :

                  cvmCode: méthode de vérification.

                  conditionCode: condition pour appliquer cette méthode.

                   La carte propose plusieurs méthodes, par exemple :


                  CVM Code	Méthode	Condition Code
                  0x01	PIN offline vérifié	0x01 (si > floorLimit)
                  0x1E	Aucune vérification	0x02 (si ≤ floorLimit) */

                if (conditionOk) {
                  //Si condition remplie
                  // Applique la méthode CVM trouvée
                  if (cvmCode == 0x00) {
                    //Fail CVM processing → Refuser
                    setState(
                      () => result = '❌ CVM échoué : transaction refusée',
                    );
                    return false;
                  } else if (cvmCode == 0x01) {
                    //PIN offline plaintext
                    final pin = await _demanderPin();
                    await sendOfflinePlaintextPin(pin);
                    return true;
                  } else if (cvmCode == 0x02) {
                    //PIN offline ciphertext
                    final pin = await _demanderPin();
                    await sendOfflineEncryptedPin(
                      pin,
                      rid,
                      capkIndex,
                    ); // À développer si tu veux supporter encrypted
                    return true;
                  } else if (cvmCode == 0x1E) {
                    //No CVM required
                    print('✅ Pas de CVM requis pour cette carte.');
                    return true;
                  } else if (cvmCode == 0x03) {
                    // 0x03 = PIN Online
                    final pin =
                        await _demanderPin(); // Tu as déjà cette fonction

                    // Stocke ce PIN pour l'envoyer à la banque
                    setState(() => authorizationCode = pin);
                    print('✅ PIN Online saisi : $pin');
                    return true;
                  } else if (cvmCode == 0x1F) {
                    //Signature
                    print('⚠️ Signature requise (non implémentée).');
                    return true;
                  }
                }
              }

              // Si aucune condition remplie → refuser
              setState(
                () =>
                    result =
                        '❌ Aucune méthode CVM applicable : transaction refusée',
              );
              return false;
            }
            /*
            Étape	But
            Récupérer la CVM List (Tag 8E)	Liste des méthodes proposées par la carte
            Vérifier la condition	Montant > / ≤ floorLimit, Always…
            Appliquer la méthode correspondante	PIN, Signature, Aucune CVM, ou refuser
            Arrêter la transaction si aucune méthode ne fonctionne	 Sécurité respectée selon EMV */

            //Récupération de la CVM List (tag 8E) dans les TLVs

            // 🔍 Recherche de la CVM List (Tag 8E) dans la réponse GPO
            final cvmTlv =
                TLVParser.findTlvRecursive(gpoTlvs, 0x8E) ??
                TLV(0x00, Uint8List(0)); // TLV vide si pas trouvé

            if (cvmTlv.tag == 0x8E) {
              final cvmList = cvmTlv.value;

              // Appelle la fonction pour traiter la CVM List
              final success = await processCvmList(cvmList);

              if (!success) {
                return; // Si CVM échouée, on arrête ici la transaction
              }
            }

            /*Après avoir lu les enregistrements (records) via l’AFL (Application File Locator), on obtiens un ensemble de TLVs (Tag-Length-Value). Ces TLVs contiennent :

              Les données de la carte (PAN, expiration, nom…).

              Les informations d’authentification (AC, ATC, CID…). */
            var extractedCardData = extractCardData(
              recordTlvs,
            ); //extractCardData : va chercher les tags :5A : PAN (Primary Account Number).5F24 : Date d’expiration.5F20 : Nom du titulaire de la carte.
            var extractedAuthData = extractAuthData(
              recordTlvs,
            ); //extractAuthData : va chercher les tags :9F26 : AC (Application Cryptogram).9F36 : ATC (Application Transaction Counter).9F27 : CID (Cryptogram Information Data).

            // Vérification si les données sensibles sont présentes et non vides avant de les crypter
            /*Si une de ces trois valeurs (AC, ATC, CID) est absente, la transaction ne peut pas continuer.
              📌 Ces données sont indispensables pour :

              Authentifier la transaction.

              Vérifier l’intégrité des calculs.

              Faire les calculs cryptographiques dans le protocole EMV. */
            if ((extractedAuthData.containsKey('ac') &&
                    extractedAuthData['ac']!.isNotEmpty) &&
                (extractedAuthData.containsKey('atc') &&
                    extractedAuthData['atc']!.isNotEmpty) &&
                (extractedAuthData.containsKey('cid') &&
                    extractedAuthData['cid']!.isNotEmpty)) {
              //Traitement des données (si OK)
              final fullPan =
                  extractedCardData['pan'] ??
                  ''; // 🟢 On garde le vrai PAN complet

              setState(() {
                pan =
                    'XXXX-XXXX-XXXX-${fullPan.substring(fullPan.length - 4)}'; // 🔒 Masquage pour l’affichage  (bonnes pratiques de sécurité) :
                expiration =
                    extractedCardData['expiration'] ??
                    ''; // Récupération de l’expiration et du nom (si présents)
                name = extractedCardData['name'] ?? '';
                // Les données sensibles AC, ATC, CID sont chiffrées avant de les stocker (fonction encryptData).
                ac = encryptData(extractedAuthData['ac'] ?? '');
                atc = encryptData(extractedAuthData['atc'] ?? '');
                cid = encryptData(extractedAuthData['cid'] ?? '');
              });
            } else {
              //Si une donnée manque
              setState(() => result = '⚠️ Données sensibles manquantes');
              return; // Sortir de la fonction si les données sensibles sont manquantes
            }
          } catch (_) {
            // En cas d’erreur pendant la lecture
            setState(() => result = '⚠️ Erreur lors de la lecture du record');
            return;
          }
        }
      }

      await FlutterNfcKit.finish(); //Libération propre de la session NFC → on termines la communication avec la carte.

      // 📘 Étape 8 : Analyse du CID avec déchiffrement
      final rawCid = decryptData(
        cid,
      ); // Le cid a été stocké chiffré juste avant (pour sécuriser les données). on  le déchiffres pour pouvoir l’utiliser Le CID détermine ce que veut faire la carte :'40' → Transaction approuvée offline (TC - Transaction Certificate). '80' → Transaction refusée par la carte (AAC - Application Authentication Cryptogram).'00' → La carte demande une autorisation en ligne (ARQC - Authorization Request Cryptogram).

      final canGoOffline = _terminalRiskManagement(
        cardCountryCode,
      ); //Cette fonction décide si la transaction a le droit d’être offline : Si le montant est faible.Si la carte n’est pas étrangère.Si le compteur de transactions offline n’a pas dépassé le seuil.Si les conditions ne sont pas réunies → forcé à passer en online.

      final taaDecision = _terminalActionAnalysis(rawCid, canGoOffline);

      /*Cette fonction croise :

      Ce que la carte demande (CID).

      Ce que le terminal autorise (via canGoOffline).


      CID	Peut offline ?	Résultat (TAA)
      40	Oui	            APPROVED_OFFLINE
      80	 -	             DECLINED
      00	Non            	ONLINE_REQUESTED
      Autre	-             	UNKNOWN */

      await _generateAc(taaDecision, aidResponseTlvs, fullPan);
      /*Cela envoie la commande GENERATE AC à la carte,
        pour confirmer la décision :

        Offline : produire un TC.

        Online : produire un ARQC.

        Refus : produire un AAC.

        */

      if (ac.isNotEmpty && rawCid.isNotEmpty) {
        // Si les données sont bien présentes (AC + CID)
        if (taaDecision == 'APPROVED_OFFLINE') {
          //Si APPROVED_OFFLINE Transaction terminée sans contacter la banque.
          setState(() => result = '✅ Transaction approuvée offline');
        } else if (taaDecision == 'DECLINED') {
          //Si DECLINED :On arrête : carte elle-même refuse.
          setState(() => result = '❌ Transaction refusée par la carte');
        } else if (taaDecision == 'ONLINE_REQUESTED') {
          //Si ONLINE_REQUESTED :Ici c’est une simulation de serveur d’autorisation.En vrai, il faudrait envoyer l’ARQC à la banque (HSM ou serveur) → retour OK ou NOK.

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
            //Sauvegarde de la transaction
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
          //Si CID inconnu
          setState(() => result = '⚠️ CID inconnu : $rawCid');
        }
      } else {
        //Si des données cryptographiques sont manquantes
        setState(() => result = '⚠️ Données cryptographiques incomplètes');
      }
    } catch (e) {
      //Gestion des erreurs libères l’état et arrêtes le chargement même en cas d’erreur.
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

  /*Cette fonction sert à interpréter le code retour des commandes APDU envoyées à la carte (réponse de la carte).
  En EMV, chaque réponse APDU se termine par un code status word (SW) de 2 octets (souvent 9000, 6A88, etc.). */
  String decodeApduError(String apduResponse) {
    final errorCode = apduResponse.substring(
      apduResponse.length - 4,
    ); //prends les 4 derniers caractères de la réponse hexadécimale, car le status word est toujours à la fin.
    final errorCodes = {
      //C’est une table de correspondance entre le code et son message explicatif.
      '6A88': 'Sélecteur d’application non trouvé',
      '6F': 'Erreur générique',
      '9000': 'Succès',
      '6700': 'Paramètre incorrect',
      '6982': 'Conditions d’utilisation non remplies',
      // Ajouter plus de codes d'erreurs EMV ici
    };

    return errorCodes[errorCode] ??
        'Erreur inconnue : $errorCode'; //Si le code existe dans ton dictionnaire : il retourne le message.Sinon : il affiche "Erreur inconnue : <le code>".
  }

  void resetFields() {
    //Réinitialiser tous les champs de ta transaction avant d’en démarrer une nouvelle
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
    //Convertir une chaîne hexadécimale en liste d’octets (List<int>).
    hex =
        hex
            .replaceAll(' ', '')
            .toUpperCase(); //Nettoie la chaîne (replaceAll(' ', ''), toUpperCase()).
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(
          hex.substring(i, i + 2),
          radix: 16,
        ), //Découpe par paires de caractères (2 par 2).Chaque paire est convertie en entier base 16.
    ];
  }

  Map<String, String> extractCardData(List<TLV> tlvs) {
    // Récupérer les données de la carte bancaire (PAN, expiration, nom)
    Map<String, String> cardData = {};

    for (final tlv in tlvs) {
      // Recherche des données intéressantes
      if (tlv.tag == 0x5A) {
        // PAN (numéro de la carte)
        cardData['pan'] =
            tlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } else if (tlv.tag == 0x5F24) {
        // Expiration (format YYMMDD)
        final date =
            tlv.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        cardData['expiration'] =
            '20${date.substring(0, 2)}/${date.substring(2, 4)}';
      } else if (tlv.tag == 0x5F20) {
        // Nom du titulaire
        cardData['name'] = String.fromCharCodes(tlv.value);
      }
    }

    return cardData;
  }

  Map<String, String> extractAuthData(List<TLV> tlvs) {
    // Extraire les informations d’authentification cryptographique de la carte
    // Ce sont les éléments cryptographiques utilisés pour la sécurité EMV
    Map<String, String> authData = {};

    for (final tlv in tlvs) {
      if (tlv.tag == 0x9F26) {
        // AC (Application Cryptogram)
        authData['ac'] = Hex.encode(tlv.value);
      } else if (tlv.tag == 0x9F36) {
        // ATC (Application Transaction Counter)
        authData['atc'] = Hex.encode(tlv.value);
      } else if (tlv.tag == 0x9F27) {
        // CID (Cryptogram Information Data)
        authData['cid'] = Hex.encode(tlv.value);
      }
    }

    return authData;
  }

  String encryptData(String data) {
    //Chiffre les données sensibles avec AES.
    final validatedData = validateData(data);
    if (validatedData == null) return '';
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey));
    final encrypted = encrypter.encrypt(validatedData, iv: aesIv);
    return encrypted.base64;
  }

  String decryptData(String encryptedData) {
    //Déchiffre les données pour pouvoir les relire.
    if (encryptedData.isEmpty) return '';
    final encryptedBytes = encrypt.Encrypted.fromBase64(encryptedData);
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey));
    final decrypted = encrypter.decrypt(encryptedBytes, iv: aesIv);
    return decrypted;
  }
  /*Utilise la librairie encrypt avec une clé AES (aesKey) et un vecteur d'initialisation (IV) (aesIv).
  Sécurise des infos comme ac, atc, cid stockées dans le téléphone. */

  bool _terminalRiskManagement(String cardCountryCode) {
    //Effectuer la gestion du risque côté terminal (TRM → Terminal Risk Management). Elle décide si la transaction peut rester offline ou doit passer online.
    try {
      final montant = (double.tryParse(amount) ?? 0) * 100; // en centimes

      if (montant <= 0) {
        //Refuser : montant invalide
        result = '❌ Montant invalide';
        return false;
      }

      // 💰 Vérification du montant
      if (montant > floorLimit) {
        //Forcer autorisation online
        result =
            'ℹ️ Montant dépasse le seuil offline → Forcer autorisation en ligne';
        return false; // online required
      }

      // 🗺️ Vérification du pays
      const terminalCountryCode = '056'; // Ex. 056 pour l’Algérie
      if (cardCountryCode != terminalCountryCode) {
        //Forcer online
        result = '🌍 Carte d’un autre pays → Autorisation en ligne requise';
        return false;
      }

      // 🚫 Vérification blacklist (exemple simple avec PAN bloqués)
      const blacklistedPans = [
        '4111111111111111',
        '5500000000000004',
      ]; //Refuser
      if (blacklistedPans.contains(
        pan.replaceAll('-', '').replaceAll(' ', ''),
      )) {
        result = '🚫 Carte sur blacklist → Transaction refusée';
        return false;
      }

      // 🕐 Exemple de velocity check (à améliorer selon ton besoin)
      const maxOfflineTransactions = 3;
      final offlineCount =
          transactionLogs.where((t) => t.status.contains('offline')).length;

      if (offlineCount >= maxOfflineTransactions) {
        //Forcer online
        result =
            '🔁 Trop de transactions offline → Autorisation en ligne requise';
        return false;
      }

      result = '✅ Transaction acceptée offline';
      return true; // OK offline
    } catch (e) {
      result = '❌ Erreur TRM : $e';
      return false;
    }
  }

  void _loadTransactions() async {
    //Charger l’historique des transactions stockées localement (sur le téléphone).
    final saved =
        await TransactionStorage.loadTransactions(); //Lit les transactions enregistrées cette fonction ce trouve dans transaction_storage.dart Elle appelle la méthode de chargement.C’est asynchrone → donc elle attend que la lecture soit finie.
    setState(() {
      // Une fois les données chargées, elle met à jour la variable transactionLogs avec la liste récupérée.
      transactionLogs = saved;
    });
  }

  Future<void> _initializeCrypto() async {
    aesKey = await SecureStorageHelper.getOrCreateKey();
    aesIv = await SecureStorageHelper.getOrCreateIv();
  }

  /// Initialise la clé AES et l’IV en les récupérant depuis le stockage sécurisé.
  /// Si jamais ils n’existent pas → les génère automatiquement.

  @override
  void initState() {
    super.initState();
    _initializeCrypto(); //Initialise la clé AES et l’IV sécurisés dès le démarrage.
    _loadTransactions(); //dès que ta page est ouverte, l’historique est automatiquement chargé.

    // Si un montant initial est fourni → pré-remplit le champ et lance la transaction automatiquement.
    if (widget.initialAmount != null && widget.initialAmount!.isNotEmpty) {
      amount = widget.initialAmount!;
      amountController.text = widget.initialAmount!;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).unfocus();
        _startEMVSession(skipReset: true);
      });
    }
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
            widget.initialAmount == null || widget.initialAmount!.isEmpty
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '💰 Montant à encaisser',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
                  ],
                )
                : Text(
                  '💰 Montant : \$$amount',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),

            const SizedBox(height: 24),
            Row(
              children: [
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MainNavigation()),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('Accueil'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.teal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
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
