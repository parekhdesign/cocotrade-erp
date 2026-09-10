import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'services/local_sync_service.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
  }
  final prefs = await SharedPreferences.getInstance();
  final bool isFirstLoginDone = prefs.getBool('auth_first_login_completed_v2') ?? false;

  runApp(MaterialApp(
    title: 'COCOTRADE ERP',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF047857),
        primary: const Color(0xFF047857),
        surface: const Color(0xFFF8FAFC),
      ),
      useMaterial3: true,
    ),
    home: isFirstLoginDone ? const MainLayoutScreen() : const CloudRestoreSetupScreen(),
  ));
}
class SmsQueueItem {
  String id;
  String phone;
  String message;
  String status; // 'PENDING', 'SENT', 'FAILED'
  String createdAt;

  SmsQueueItem({
    required this.id,
    required this.phone,
    required this.message,
    this.status = 'PENDING',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'message': message,
    'status': status,
    'createdAt': createdAt,
  };

  factory SmsQueueItem.fromJson(Map<String, dynamic> json) => SmsQueueItem(
    id: json['id'] ?? '',
    phone: json['phone'] ?? '',
    message: json['message'] ?? '',
    status: json['status'] ?? 'PENDING',
    createdAt: json['createdAt'] ?? '',
  );
}
// ---------------- CLOUD RESTORE SETUP SCREEN ----------------
class CloudRestoreSetupScreen extends StatefulWidget {
  const CloudRestoreSetupScreen({super.key});

  @override
  State<CloudRestoreSetupScreen> createState() => _CloudRestoreSetupScreenState();
}

class _CloudRestoreSetupScreenState extends State<CloudRestoreSetupScreen> {
  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1914),
      body: Center(
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFA7F3D0))),
                child: const Icon(Icons.cloud_sync_rounded, size: 48, color: Color(0xFF047857)),
              ),
              const SizedBox(height: 20),
              const Text('Welcome to CocoTrade ERP', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              const Text(
                'Connect your Google Drive account to seamlessly restore business ledgers, profile, licensing, and access PIN.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF4B6354)),
              ),
              const SizedBox(height: 32),
              _isConnecting
                  ? const CircularProgressIndicator(color: Color(0xFF047857))
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Connect Google Drive & Restore', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () async {
  setState(() => _isConnecting = true);
  try {
    bool signedIn = await GoogleDriveService.signIn();
    if (!signedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.red, content: Text('Google Sign-In was canceled or failed.')),
        );
      }
      return;
    }

    Map<String, dynamic>? cloudData = await GoogleDriveService.downloadDatabase();
    if (cloudData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade800,
            content: Text('Connected as ${GoogleDriveService.currentUserEmail}, but cocotrade_backup.json was not found.'),
          ),
        );
      }
      return;
    }

    // Write database locally and proceed
    await LocalDriveManager.writeToDrive(cloudData);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auth_first_login_completed_v2', true);
    await prefs.setBool('is_profile_setup_done', true);
    await prefs.setBool('auth_is_licensed_v1', cloudData['isLicensed'] ?? true);
    if (cloudData.containsKey('savedPin')) await prefs.setString('auth_user_pin', cloudData['savedPin']);
    if (cloudData.containsKey('savedEmail')) await prefs.setString('auth_user_email', cloudData['savedEmail']);
    if (cloudData.containsKey('companyProfile') && cloudData['companyProfile'] is Map) {
      final comp = cloudData['companyProfile'];
      await prefs.setString('company_name', comp['name'] ?? 'CocoTrade ERP');
      await prefs.setString('company_phone', comp['phone'] ?? '');
      await prefs.setString('company_address', comp['address'] ?? '');
      await prefs.setString('company_invocation', comp['invocation'] ?? 'Om Sri Ganesaya Namaha');
    }
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayoutScreen()));
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Restore error: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isConnecting = false);
  }
},
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayoutScreen())),
                child: const Text('Skip / Start Fresh Setup', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- DIRECT AUTH CLIENT FOR ANDROID ----------------
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

// ---------------- GOOGLE DRIVE SERVICE ----------------
class GoogleDriveService {
 static final _clientId = ClientId(
    '1011382913553-qad37lf843tnj68r1cp720bel0scgkdm.apps.googleusercontent.com',
    'GOCSPX-' + 'wkDQSPfsxT_Nj7gUfS7PdMfOiaxR',
  );

  static const List<String> _scopes = <String>[drive.DriveApi.driveScope];
  static dynamic _client;
  static const String _prefsKey = 'google_drive_credentials_v1';
  static const String _emailPrefsKey = 'google_drive_active_email';
  static String? _cachedUserEmail;

  static dynamic get currentCredentials => _client;
  static String? get currentUserEmail => _cachedUserEmail;

  static const String _backupFolderName = 'CocoTrade Backups';
  static const String _fileName = 'cocotrade_backup.json';

  static Future<void> _fetchAndSaveUserEmail() async {
    try {
      if (_client != null) {
        final driveApi = drive.DriveApi(_client!);
        final about = await driveApi.about.get($fields: 'user(emailAddress)');
        if (about.user?.emailAddress != null) {
          _cachedUserEmail = about.user!.emailAddress;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_emailPrefsKey, _cachedUserEmail!);
        }
      }
    } catch (e) {
      debugPrint("Error fetching Drive user info: $e");
    }
  }

  static Future<bool> initSilentLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedUserEmail = prefs.getString(_emailPrefsKey);

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final GoogleSignIn googleSignIn = GoogleSignIn(scopes: _scopes);
        final account = await googleSignIn.signInSilently();
        if (account != null) {
          final authHeaders = await account.authHeaders;
          _client = GoogleAuthClient(authHeaders);
          _cachedUserEmail = account.email;
          await prefs.setString(_emailPrefsKey, account.email);
          return true;
        }
        return false;
      }

      final String? credString = prefs.getString(_prefsKey);
      if (credString != null) {
        final Map<String, dynamic> json = jsonDecode(credString);
        final credentials = AccessCredentials(
          AccessToken(
            json['tokenType'],
            json['accessToken'],
            DateTime.parse(json['expiry']).toUtc(),
          ),
          json['refreshToken'],
          List<String>.from(json['scopes']),
        );
        _client = autoRefreshingClient(_clientId, credentials, http.Client());
        if (_cachedUserEmail == null) {
          await _fetchAndSaveUserEmail();
        }
        return true;
      }
    } catch (e) {
      debugPrint("Silent Login Error: $e");
      await signOut();
    }
    return false;
  }

  static Future<bool> signIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final GoogleSignIn googleSignIn = GoogleSignIn(scopes: _scopes);
        try { await googleSignIn.signOut(); } catch (_) {}

        final account = await googleSignIn.signIn();
        if (account != null) {
          bool hasDriveScope = await googleSignIn.requestScopes(_scopes);
          if (!hasDriveScope) return false;

          final authHeaders = await account.authHeaders;
          _client = GoogleAuthClient(authHeaders);
          _cachedUserEmail = account.email;
          await prefs.setString(_emailPrefsKey, account.email);
          return true;
        }
        return false;
      } else {
        _client = await clientViaUserConsent(_clientId, _scopes, (String url) async {
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        });

        if (_client != null && _client.credentials.refreshToken != null) {
          final creds = _client.credentials;
          final jsonStr = jsonEncode({
            'tokenType': creds.accessToken.type,
            'accessToken': creds.accessToken.data,
            'expiry': creds.accessToken.expiry.toIso8601String(),
            'refreshToken': creds.refreshToken,
            'scopes': creds.scopes,
          });
          await prefs.setString(_prefsKey, jsonStr);
          await _fetchAndSaveUserEmail();
        }
        return _client != null;
      }
    } catch (e) {
      debugPrint("GOOGLE SIGN IN ERROR: $e");
      return false;
    }
  }

  static Future<void> signOut() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final GoogleSignIn googleSignIn = GoogleSignIn(scopes: _scopes);
        await googleSignIn.signOut();
      } else {
        _client?.close();
      }
    } catch (e) {
      debugPrint("Sign out error: $e");
    } finally {
      _client = null;
      _cachedUserEmail = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await prefs.remove(_emailPrefsKey);
    }
  }

  static Future<bool> uploadDatabase(String jsonContent) async {
    if (_client == null) throw Exception("Not signed in to Google Drive.");
    try {
      final driveApi = drive.DriveApi(_client!);
      String? folderId;

      final folderList = await driveApi.files.list(
        q: "mimeType = 'application/vnd.google-apps.folder' and name = '$_backupFolderName' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      ).timeout(const Duration(seconds: 10));

      if (folderList.files != null && folderList.files!.isNotEmpty) {
        folderId = folderList.files!.first.id;
      } else {
        final folderMeta = drive.File()
          ..name = _backupFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        final created = await driveApi.files.create(folderMeta, $fields: 'id');
        folderId = created.id;
      }

      if (folderId == null) throw Exception("Failed to resolve backup folder.");

      // ---------------------------------------------------------
      // FIX: BYPASS REDUNDANT ENCRYPTION FOR CLOUD SYNC
      // Upload raw JSON to guarantee cross-platform compatibility. 
      // ---------------------------------------------------------
      final List<int> bytes = utf8.encode(jsonContent);
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
      );

      final fileList = await driveApi.files.list(
        q: "name = '$_fileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      ).timeout(const Duration(seconds: 10));

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        await driveApi.files.update(
          drive.File(),
          fileList.files!.first.id!,
          uploadMedia: media,
        );
      } else {
        final driveFile = drive.File()
          ..name = _fileName
          ..parents = [folderId];
        await driveApi.files.create(driveFile, uploadMedia: media);
      }
      return true;
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  static Future<Map<String, dynamic>?> downloadDatabase() async {
    if (_client == null) throw Exception("Not signed in to Google Drive.");
    
    try {
      final driveApi = drive.DriveApi(_client!);
      String? targetFileId;

      final fileList = await driveApi.files.list(
        q: "name = '$_fileName' and trashed = false",
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        $fields: 'files(id, name)',
      ).timeout(const Duration(seconds: 10));

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        targetFileId = fileList.files!.first.id;
      }

      if (targetFileId == null) {
        final recentList = await driveApi.files.list(
          pageSize: 20,
          spaces: 'drive',
          orderBy: 'modifiedTime desc',
          $fields: 'files(id, name)',
        ).timeout(const Duration(seconds: 10));

        if (recentList.files != null) {
          for (var f in recentList.files!) {
            if (f.name != null && f.name!.contains('cocotrade') && f.name!.endsWith('.json')) {
              targetFileId = f.id;
              break;
            }
          }
        }
      }

      if (targetFileId == null) throw Exception("Backup file not found in Google Drive.");

      final drive.Media response = await driveApi.files.get(
        targetFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> dataStore = [];
      await for (var chunk in response.stream.timeout(const Duration(seconds: 20))) {
        dataStore.addAll(chunk);
      }
      
      String fileString = utf8.decode(dataStore).trim();

      // ---------------------------------------------------------
      // FIX: READ PURE JSON FILE
      // ---------------------------------------------------------
      if (fileString.startsWith('{') && fileString.endsWith('}')) {
        return jsonDecode(fileString) as Map<String, dynamic>;
      }

      // Fallback: If it encounters an old encrypted file during testing
      if (fileString.startsWith('"') && fileString.endsWith('"')) {
        fileString = fileString.substring(1, fileString.length - 1);
      }
      fileString = fileString.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');

      try {
        final decrypted = SecurityHelper.decrypt(fileString);
        return jsonDecode(decrypted) as Map<String, dynamic>;
      } catch (e) {
        // Truncate the error printout so it doesn't flood the UI
        String preview = fileString.length > 30 ? fileString.substring(0, 30) : fileString;
        throw Exception("Unreadable data format. (Preview: $preview...)");
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }
}
// ---------------- DATA MODELS ----------------
class CompanyProfile {
  String name; String tagline; String address; String phone; String invocation;
  CompanyProfile({this.name = 'SRI SAI COCONUTS', this.tagline = 'COCONUT EXPORTERS', this.address = 'Kakinada, Kakinada Dist.,\nAP-533001', this.phone = '09885551000, 09885552000', this.invocation = 'Om Sri Ganesaya Namaha'});
  Map<String, dynamic> toJson() => {'name': name, 'tagline': tagline, 'address': address, 'phone': phone, 'invocation': invocation};
  factory CompanyProfile.fromJson(Map<String, dynamic> json) => CompanyProfile(name: json['name'] ?? 'SRI SAI COCONUTS', tagline: json['tagline'] ?? 'COCONUT EXPORTERS', address: json['address'] ?? 'Kakinada, Kakinada Dist.,\nAP-533001', phone: json['phone'] ?? '09885551000', invocation: json['invocation'] ?? 'Om Sri Ganesaya Namaha');
}

class TradeConfirmation {
  String id, date, seller, buyer, coconutType, status; double rate;
  TradeConfirmation({required this.id, required this.date, required this.seller, required this.buyer, required this.coconutType, required this.rate, this.status = 'PENDING'});
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'seller': seller, 'buyer': buyer, 'coconutType': coconutType, 'rate': rate, 'status': status};
  factory TradeConfirmation.fromJson(Map<String, dynamic> json) => TradeConfirmation(id: json['id'] ?? '', date: json['date'] ?? '', seller: json['seller'] ?? '', buyer: json['buyer'] ?? '', coconutType: json['coconutType'] ?? 'TENDER', rate: (json['rate'] as num?)?.toDouble() ?? 0, status: json['status'] ?? 'PENDING');
}

class Party {
  String name, type, phone, address;
  Party({required this.name, required this.type, required this.phone, required this.address});
  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'phone': phone, 'address': address};
  factory Party.fromJson(Map<String, dynamic> json) => Party(name: json['name'] ?? '', type: json['type'] ?? 'BUYER', phone: json['phone'] ?? '', address: json['address'] ?? '');
}

class TruckEntry {
  String id, state, date, truck, supplier, buyer, transporter, type, remarks;
  double qty, supplierBill, buyerBill, commission, transportExp, freight, advance, rate, bags, bagRate, loadRate, insurance, amc, loadManualAmt;
  bool isInvoice, isLoadManual;

  TruckEntry({
    required this.id, required this.state, required this.date, required this.truck, required this.supplier, required this.buyer, required this.transporter, required this.type, required this.qty, required this.supplierBill, required this.buyerBill, required this.commission, required this.transportExp, required this.freight, required this.advance,
    this.isInvoice = false, this.rate = 0, this.bags = 0, this.bagRate = 0, this.loadRate = 0, this.insurance = 0, this.amc = 0, this.isLoadManual = false, this.loadManualAmt = 0, this.remarks = ''
  });

  double get balance => freight - advance;
  Map<String, dynamic> toJson() => {'id': id, 'state': state, 'date': date, 'truck': truck, 'supplier': supplier, 'buyer': buyer, 'transporter': transporter, 'type': type, 'qty': qty, 'supplierBill': supplierBill, 'buyerBill': buyerBill, 'commission': commission, 'transportExp': transportExp, 'freight': freight, 'advance': advance, 'isInvoice': isInvoice, 'rate': rate, 'bags': bags, 'bagRate': bagRate, 'loadRate': loadRate, 'insurance': insurance, 'amc': amc, 'isLoadManual': isLoadManual, 'loadManualAmt': loadManualAmt, 'remarks': remarks};
  factory TruckEntry.fromJson(Map<String, dynamic> json) => TruckEntry(id: json['id'] ?? '', state: json['state'] ?? 'Andhra Pradesh', date: json['date'] ?? '', truck: json['truck'] ?? '', supplier: json['supplier'] ?? '', buyer: json['buyer'] ?? '', transporter: json['transporter'] ?? '', type: json['type'] ?? 'TENDER', qty: (json['qty'] as num?)?.toDouble() ?? 0, supplierBill: (json['supplierBill'] as num?)?.toDouble() ?? 0, buyerBill: (json['buyerBill'] as num?)?.toDouble() ?? 0, commission: (json['commission'] as num?)?.toDouble() ?? 0, transportExp: (json['transportExp'] as num?)?.toDouble() ?? 0, freight: (json['freight'] as num?)?.toDouble() ?? 0, advance: (json['advance'] as num?)?.toDouble() ?? 0, isInvoice: json['isInvoice'] ?? false, rate: (json['rate'] as num?)?.toDouble() ?? 0, bags: (json['bags'] as num?)?.toDouble() ?? 0, bagRate: (json['bagRate'] as num?)?.toDouble() ?? 0, loadRate: (json['loadRate'] as num?)?.toDouble() ?? 0, insurance: (json['insurance'] as num?)?.toDouble() ?? 0, amc: (json['amc'] as num?)?.toDouble() ?? 0, isLoadManual: json['isLoadManual'] ?? false, loadManualAmt: (json['loadManualAmt'] as num?)?.toDouble() ?? 0, remarks: json['remarks'] ?? '');
}

class BankAccount {
  String id, name, account, ifsc, branch, note;
  BankAccount({required this.id, required this.name, required this.account, required this.ifsc, required this.branch, this.note = "Please Credit to our Account only"});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'account': account, 'ifsc': ifsc, 'branch': branch, 'note': note};
  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(id: json['id'] ?? '', name: json['name'] ?? '', account: json['account'] ?? '', ifsc: json['ifsc'] ?? '', branch: json['branch'] ?? '', note: json['note'] ?? "Please Credit to our Account only");
}

class PaymentEntry {
  String id, state, type, seller, buyer, mode, date;
  double amount, transportReceived, settlement, commissionAdjusted;

  PaymentEntry({
    required this.id, required this.state, required this.type, required this.seller, required this.buyer, required this.amount, required this.transportReceived, required this.settlement, this.commissionAdjusted = 0.0, required this.mode, required this.date,
  });

  String get party => type.contains("SELLER") ? seller : buyer;
  Map<String, dynamic> toJson() => {'id': id, 'state': state, 'type': type, 'seller': seller, 'buyer': buyer, 'amount': amount, 'transportReceived': transportReceived, 'settlement': settlement, 'commissionAdjusted': commissionAdjusted, 'mode': mode, 'date': date};
  factory PaymentEntry.fromJson(Map<String, dynamic> json) => PaymentEntry(id: json['id'] ?? '', state: json['state'] ?? 'Andhra Pradesh', type: json['type'] ?? 'PAYMENT TO SELLER', seller: json['seller'] ?? '', buyer: json['buyer'] ?? '', amount: (json['amount'] as num?)?.toDouble() ?? 0, transportReceived: (json['transportReceived'] as num?)?.toDouble() ?? 0, settlement: (json['settlement'] as num?)?.toDouble() ?? 0, commissionAdjusted: (json['commissionAdjusted'] as num?)?.toDouble() ?? 0, mode: json['mode'] ?? 'DIRECT', date: json['date'] ?? '');
}

class TransportPayment {
  String id, state, transporter, bank, date, billMonth;
  double amount;

  TransportPayment({
    required this.id,
    required this.state,
    required this.transporter,
    required this.bank,
    required this.amount,
    required this.date,
    this.billMonth = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'state': state,
    'transporter': transporter,
    'bank': bank,
    'amount': amount,
    'date': date,
    'billMonth': billMonth,
  };

  factory TransportPayment.fromJson(Map<String, dynamic> json) => TransportPayment(
    id: json['id'] ?? '',
    state: json['state'] ?? 'Andhra Pradesh',
    transporter: json['transporter'] ?? '',
    bank: json['bank'] ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    date: json['date'] ?? '',
    billMonth: json['billMonth'] ?? '',
  );
}

class GoodsItemController {
  final TextEditingController descCtrl, qtyCtrl, rateCtrl;
  GoodsItemController({String desc = 'COCONUT', String qty = '', String rate = ''})
      : descCtrl = TextEditingController(text: desc), qtyCtrl = TextEditingController(text: qty), rateCtrl = TextEditingController(text: rate);

  String get description => descCtrl.text.isEmpty ? 'COCONUT' : descCtrl.text.toUpperCase();
  double get qty => double.tryParse(qtyCtrl.text) ?? 0;
  double get rate => double.tryParse(rateCtrl.text) ?? 0;
  double calculateAmount(double divisor) {
    if (qty == 0 || rate == 0 || divisor == 0) return 0;
    return ((qty * rate) / divisor).ceilToDouble();
  }
  void dispose() { descCtrl.dispose(); qtyCtrl.dispose(); rateCtrl.dispose(); }
}

// ---------------- SECURITY & ENCRYPTION ----------------
class SecurityHelper {
  static final _key = enc.Key.fromUtf8('CocoTradeERP_SecureKey_2026_0907');
  static final _iv = enc.IV.fromLength(16);
  static final _encrypter = enc.Encrypter(enc.AES(_key));
  static String encrypt(String rawData) => _encrypter.encrypt(rawData, iv: _iv).base64;
  static String decrypt(String encryptedBase64) => _encrypter.decrypt(enc.Encrypted.fromBase64(encryptedBase64), iv: _iv);
}

// ---------------- LOCAL STORAGE MANAGER ----------------
class LocalDriveManager {
  static const String _prefCustomDirKey = 'cocotrade_custom_dir_path';
  static const String _folderName = 'CocoTradeData';
  static const String _fileName = 'cocotrade_master_db.json';

  static Future<File> getLocalDatabaseFile() async {
    final prefs = await SharedPreferences.getInstance();
    final customDir = prefs.getString(_prefCustomDirKey);
    if (customDir != null && customDir.isNotEmpty) {
      final customDirObj = Directory(customDir);
      if (!await customDirObj.exists()) await customDirObj.create(recursive: true);
      return File('${customDirObj.path}/$_fileName');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${docsDir.path}/$_folderName');
    if (!await dataDir.exists()) await dataDir.create(recursive: true);
    return File('${dataDir.path}/$_fileName');
  }

  static Future<void> writeToDrive(Map<String, dynamic> data) async {
    try {
      final file = await getLocalDatabaseFile();
      final jsonString = jsonEncode(data);
      // Write raw JSON directly to phone storage to guarantee cross-boot persistence
      await file.writeAsString(jsonString, flush: true);
    } catch (e) {
      debugPrint("Local database write failed: $e");
    }
  }

  static Future<Map<String, dynamic>?> readFromDrive() async {
    try {
      final file = await getLocalDatabaseFile();
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (content.isEmpty) return null;

        if (content.startsWith('{')) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
        // Fallback for older encrypted test files
        try {
          final decrypted = SecurityHelper.decrypt(content);
          return jsonDecode(decrypted) as Map<String, dynamic>;
        } catch (_) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint("Error reading from local drive: $e");
    }
    return null;
  }
}

// ---------------- MAIN SCREEN WITH NEO-SAAS ARCHITECTURE ----------------
class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});
  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> with WindowListener {

  static const String _prefFirstLoginKey = 'auth_first_login_completed_v2';
  static const String _prefEmailKey = 'auth_user_email';
  static const String _prefPassKey = 'auth_user_password';
  static const String _prefPinKey = 'auth_user_pin';
  static const String _prefIsLicensedKey = 'auth_is_licensed_v1';
  static const String _prefLicenseKeyString = 'auth_license_key_string';

  bool _isLoading = true;
  bool _isFirstLoginDone = false;
  bool _isLicensed = false;
  bool _isLocked = true;
  bool _forceEmailLogin = false;
  bool _isProfileSetupDone = false;
  int _trialDaysLeft = 2;
  bool _isTrialExpired = false;
  bool _autoSyncOnExit = true;
  bool _hasCustomBuyerBill = false;

  String _companyName = "CocoTrade ERP";
  String _companyPhone = "";
  String _companyAddress = "";
  String _savedEmail = "admin@cocotrade.com";
  String _savedPassword = "admin123";
  String _savedPin = "1234";
  String _savedLicenseKey = "";
  String _selectedFinancialYear = "2026-2027";
  final List<String> _financialYears = ["2024-2025", "2025-2026", "2026-2027", "2027-2028", "2028-2029"];
  String _selectedTransportMonth = "ALL MONTHS";
// SMS/WhatsApp Templates
  String _sellerMsgTemplate = "Trade Confirmed!\nDate: {date}\nBuyer: {buyer}\nCommodity: {type}\nRate: Rs. {rate}\n- {company}";
  String _buyerMsgTemplate = "Trade Confirmed!\nDate: {date}\nSeller: {seller}\nCommodity: {type}\nRate: Rs. {rate}\n- {company}";
  String _partyTypeFilter = 'ALL';
  final _partySearchCtrl = TextEditingController();
  final TextEditingController _sellerMsgCtrl = TextEditingController();
  final TextEditingController _buyerMsgCtrl = TextEditingController();
  final TextEditingController _loginEmailCtrl = TextEditingController();
  final TextEditingController _loginPassCtrl = TextEditingController();
  final TextEditingController _licenseKeyCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _settingsEmailCtrl = TextEditingController();
  final TextEditingController _settingsPassCtrl = TextEditingController();
  final TextEditingController _settingsPinCtrl = TextEditingController();
  final TextEditingController _cNameCtrl = TextEditingController();
  final TextEditingController _cTaglineCtrl = TextEditingController();
  final TextEditingController _cPhoneCtrl = TextEditingController();
  final TextEditingController _cAddressCtrl = TextEditingController();
  final _paySearchCtrl = TextEditingController();
  // Focus nodes for keyboard chaining
  final FocusNode _tSupplierFocus = FocusNode();
  final FocusNode _tBuyerFocus = FocusNode();
  final FocusNode _tTransporterFocus = FocusNode();
  final FocusNode _tQtyFocus = FocusNode();

  final FocusNode _confSellerFocus = FocusNode();
  final FocusNode _confBuyerFocus = FocusNode();
  final FocusNode _confRateFocus = FocusNode();

  String _selectedTab = 'dashboard';
  String _selectedState = "Andhra Pradesh";

  CompanyProfile _myCompany = CompanyProfile();
  
  List<dynamic> _parties = [];
  List<dynamic> _trucks = [];
  List<dynamic> _confirmations = [];
  List<dynamic> _transportPayments = [];
  List<dynamic> _payments = [];
  List<dynamic> _overdueBills = [];
  List<String> _coconutTypes = ["TENDER", "WATER & DRY", "HUSKED", "UNHUSKED", "MATURE", "GOTTA", "BOMBAY CHEEL"];
  List<BankAccount> _bankAccounts = [
    BankAccount(id: '1', name: "STATE BANK OF INDIA", account: "30554488991", ifsc: "SBIN0000054", branch: "MAIN BRANCH"),
    BankAccount(id: '2', name: "ICICI BANK", account: "0280005500946", ifsc: "ICIC0000280", branch: "KAKINADA"),
  ];
  List<SmsQueueItem> _smsQueue = [];
  late BankAccount _selectedBank;

  final _confDateCtrl = TextEditingController();
  final _confRateCtrl = TextEditingController();
  String _confBuyer = "", _confSeller = "", _confCocotype = "TENDER";
  String get _confType => _confCocotype;
  set _confType(String v) => _confCocotype = v;

  final _tTruckCtrl = TextEditingController();
  final _tDateCtrl = TextEditingController();
  final _tRemarksCtrl = TextEditingController();
  final _tCommCtrl = TextEditingController(text: "500");
  final _tFreightCtrl = TextEditingController(text: "0");
  final _tSearchCtrl = TextEditingController();
  final _tQtyCtrl = TextEditingController(text: "0");
  final _tSBillCtrl = TextEditingController(text: "0");
  final _tBBillCtrl = TextEditingController(text: "0");
  final _tExpCtrl = TextEditingController(text: "0");
  final _tAdvCtrl = TextEditingController(text: "0");
  String _tSupplier = "", _tBuyer = "", _tTransporter = "", _tCoconutType = "TENDER";

  final _invNCtrl = TextEditingController(text: "INV-00001");
  TextEditingController get _iNoCtrl => _invNCtrl;
  final _iDateCtrl = TextEditingController();
  final _iPhoneCtrl = TextEditingController();
  final _iAddressCtrl = TextEditingController();
  final _iLorryCtrl = TextEditingController();
  final _iDriverCtrl = TextEditingController();
  String _iBuyer = "", _iSeller = "", _iTransporter = "", _iTerms = "CASH";
  double _iDivisor = 1000;
  bool _iLoadingManual = false;
  final List<GoodsItemController> _invoiceGoods = [];
  final _iLoadManualAmountCtrl = TextEditingController(text: "0");
  final _iLoadRateCtrl = TextEditingController(text: "0");
  final _iAmcCtrl = TextEditingController(text: "0");
  final _iInsCtrl = TextEditingController(text: "0");
  final _iCommCtrl = TextEditingController(text: "0");
  final _iAdvCtrl = TextEditingController(text: "0");
  final _iFreightCtrl = TextEditingController(text: "0");
  final _iBagRateCtrl = TextEditingController(text: "0");
  final _iBagsCtrl = TextEditingController(text: "0");
  final _iSellerAmountCtrl = TextEditingController(text: "0");
  final _iTransportExpCtrl = TextEditingController(text: "0");

  double get _invTotalGoodsQty => _invoiceGoods.fold(0, (s, it) => s + it.qty);
  double get _invTotalGoodsAmount => _invoiceGoods.fold(0, (s, it) => s + it.calculateAmount(_iDivisor));
  double get _invGunniesAmount => (double.tryParse(_iBagsCtrl.text) ?? 0) * (double.tryParse(_iBagRateCtrl.text) ?? 0);
  double get _invLoadingAmount => _iLoadingManual ? (double.tryParse(_iLoadManualAmountCtrl.text) ?? 0) : (_invTotalGoodsQty * (double.tryParse(_iLoadRateCtrl.text) ?? 0)) / 1000;
  double get _invAmc => double.tryParse(_iAmcCtrl.text) ?? 0;
  double get _invInsurance => double.tryParse(_iInsCtrl.text) ?? 0;
  double get _invCommission => double.tryParse(_iCommCtrl.text) ?? 0;
  double get _invAdvance => double.tryParse(_iAdvCtrl.text) ?? 0;
  double get _invFreight => double.tryParse(_iFreightCtrl.text) ?? 0;
  double get _invTotalCharges => _invGunniesAmount + _invLoadingAmount + _invAmc + _invInsurance + _invCommission + _invAdvance;
  double get _invGrandTotal => _invTotalGoodsAmount + _invTotalCharges;
  double get _invTruckBalance => _invFreight - _invAdvance;

  String _payType = "PAYMENT TO SELLER", _paySeller = "", _payBuyer = "", _payMode = "DIRECT";
  final _payTransportReceivedCtrl = TextEditingController(text: "0");
  final _payDateCtrl = TextEditingController();
  final _payAmountCtrl = TextEditingController(text: "0");
  final _paySettlementCtrl = TextEditingController(text: "0");
  final _payCommAdjustedCtrl = TextEditingController(text: "0");

  String _tpTransporter = "";
  final _tpBankCtrl = TextEditingController(text: "STATE BANK OF INDIA");
  final _tpAmountCtrl = TextEditingController(text: "0");
  final _tpDateCtrl = TextEditingController();

  String _analysisTransporter = "", _repSeller = "", _repSellerBuyerFilter = "", _repBuyer = "", _repBuyerSellerFilter = "", _repStateSeller = "";
  final _analysisFromCtrl = TextEditingController(), _analysisToCtrl = TextEditingController();
  final _repSellerFromCtrl = TextEditingController(), _repSellerToCtrl = TextEditingController(), _repSellerCommRateCtrl = TextEditingController(text: "70");
  final _repBuyerFromCtrl = TextEditingController(), _repBuyerToCtrl = TextEditingController();
  final _repStateFromCtrl = TextEditingController(), _repStateToCtrl = TextEditingController();
  double _repSellerDivisor = 1020, _repSellerCommDivisor = 1000;

  final _b1BagsCtrl = TextEditingController(text: "55"), _b1NutsCtrl = TextEditingController(text: "4400"), _b1WeightCtrl = TextEditingController(text: "25000"), _b1RateCtrl = TextEditingController(text: "40"), _b1LoadingRateCtrl = TextEditingController(text: "650"), _b1AmcCtrl = TextEditingController(text: "500"), _b1HamaliCtrl = TextEditingController(text: "1000"), _b1InsCtrl = TextEditingController(text: "300"), _b1CommCtrl = TextEditingController(text: "500"), _b1FreightCtrl = TextEditingController(text: "35000");
  String _b1LoadingType = "AP";

  final _b2QtyCtrl = TextEditingController(text: "30500"), _b2RateCtrl = TextEditingController(text: "2500"), _b2LoadRateCtrl = TextEditingController(text: "650"), _b2AmcCtrl = TextEditingController(text: "500"), _b2CommCtrl = TextEditingController(text: "1000"), _b2HamaliCtrl = TextEditingController(text: "300"), _b2BagRateCtrl = TextEditingController(text: "30"), _b2BagsCtrl = TextEditingController(text: "30"), _b2DivisorCtrl = TextEditingController(text: "1000"), _b2FreightCtrl = TextEditingController(text: "30000");
  bool _b2LoadingManual = false;
  final _b2LoadManualAmountCtrl = TextEditingController(text: "0");

  String? _editingTruckId;
  String? _editingInvoiceId;

  bool get isMobile => MediaQuery.of(context).size.width < 960;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    _selectedBank = _bankAccounts.first;
    _addGoodsRow(desc: "COCONUT", qty: "", rate: "");

    final now = DateTime.now();
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final today = "$dd-$mm-$yy";

    _confDateCtrl.text = today;
    _tDateCtrl.text = today;
    _iDateCtrl.text = today;
    _payDateCtrl.text = today;
    _tpDateCtrl.text = today;

    _pinCtrl.addListener(() {
      if (_isLocked && _pinCtrl.text.length == 4) {
        if (_pinCtrl.text == _savedPin) {
          setState(() { _isLocked = false; _pinCtrl.clear(); });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text('Incorrect 4-digit PIN! Default: 1234')));
          _pinCtrl.clear();
        }
      }
    });

    _loadCompanyProfile();
    _initAuthAndDrive();
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

 @override
  void onWindowClose() async {
    final bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      // Exit sync removed completely. Data is already safely committed 
      // to local storage and Google Drive the moment you hit "Save".
      await windowManager.destroy();
    }
  }
   static const MethodChannel _nativeSmsChannel = MethodChannel('com.cocotrade.sms/dispatch');

  Future<void> _processPendingSmsQueue() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final pending = _smsQueue.where((item) => item.status == 'PENDING').toList();
    if (pending.isEmpty) return;

    // Check and request runtime permission
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
      if (!status.isGranted) {
        debugPrint("SMS permission denied by user.");
        return;
      }
    }

    bool stateChanged = false;

    for (var item in pending) {
      final cleanPhone = item.phone.replaceAll(RegExp(r'[^0-9]'), '');
      final targetPhone = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

      if (targetPhone.length == 10) {
        try {
          final res = await _nativeSmsChannel.invokeMethod<String>('sendSms', {
            'phone': targetPhone,
            'message': item.message,
          });

          if (res == 'SENT') {
            item.status = 'SENT';
            stateChanged = true;
          } else {
            item.status = 'FAILED';
            stateChanged = true;
          }
        } catch (e) {
          debugPrint("Native SMS channel error: $e");
          item.status = 'FAILED';
          stateChanged = true;
        }
      } else {
        item.status = 'FAILED';
        stateChanged = true;
      }
    }

    if (stateChanged) {
      setState(() {});
      await _commitToLocalDrive();
    }
  }
    Future<void> _launchDeviceMessaging({
    required String phone,
    required String message,
    bool useWhatsApp = false,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length < 10) return;

    final targetNumber = cleanPhone.length > 10 ? cleanPhone : '91$cleanPhone';

    // On Windows / Desktop: Always route to WhatsApp Web or copy text to clipboard
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (useWhatsApp) {
        final waWebUri = Uri.parse("https://web.whatsapp.com/send?phone=$targetNumber&text=${Uri.encodeComponent(message)}");
        await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
      } else {
        // Desktop has no native cellular SMS; copy text so user can paste it anywhere
        await Clipboard.setData(ClipboardData(text: message));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF047857),
              content: Text('Message copied to clipboard for $cleanPhone (Paste in messaging app).'),
            ),
          );
        }
      }
      return;
    }

    // On Mobile (Android / iOS): Use native device intents
    Uri uri;
    if (useWhatsApp) {
      uri = Uri.parse("https://wa.me/$targetNumber?text=${Uri.encodeComponent(message)}");
    } else {
      uri = Uri(
        scheme: 'sms',
        path: cleanPhone.substring(cleanPhone.length - 10),
        queryParameters: {'body': message},
      );
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
    String _formatTradeMessage({
    required String template,
    required String date,
    required String seller,
    required String buyer,
    required String type,
    required double rate,
    }) {
    return template
        .replaceAll('{date}', date)
        .replaceAll('{seller}', seller)
        .replaceAll('{buyer}', buyer)
        .replaceAll('{type}', type)
        .replaceAll('{rate}', rate.toStringAsFixed(0))
        .replaceAll('{company}', _myCompany.name);
   } 
   Future<void> _loadCompanyProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isProfileSetupDone = prefs.getBool('is_profile_setup_done') ?? false;
      _companyName = prefs.getString('company_name') ?? 'CocoTrade ERP';
      _companyPhone = prefs.getString('company_phone') ?? '';
      _companyAddress = prefs.getString('company_address') ?? '';
      final savedInv = prefs.getString('company_invocation');
      if (savedInv != null && savedInv.trim().isNotEmpty) {
        _myCompany.invocation = savedInv.trim();
      }
      _isLoading = false;
      final savedSellerMsg = prefs.getString('sms_seller_template');
    if (savedSellerMsg != null && savedSellerMsg.isNotEmpty) {
      _sellerMsgTemplate = savedSellerMsg;
    }
    final savedBuyerMsg = prefs.getString('sms_buyer_template');
    if (savedBuyerMsg != null && savedBuyerMsg.isNotEmpty) {
      _buyerMsgTemplate = savedBuyerMsg;
    }
    });
   }

    Future<void> _initAuthAndDrive() async {
    final prefs = await SharedPreferences.getInstance();
    await GoogleDriveService.initSilentLogin();

    final localData = await LocalDriveManager.readFromDrive();
    if (localData != null) {
      _applyStateFromMap(localData);
    }

    final savedInv = prefs.getString('company_invocation');
    if (savedInv != null && savedInv.trim().isNotEmpty) {
      _myCompany.invocation = savedInv.trim();
    }

    setState(() {
      _autoSyncOnExit = prefs.getBool('auto_sync_on_exit') ?? true;
      _isProfileSetupDone = prefs.getBool('is_profile_setup_done') ?? false;
      _companyName = prefs.getString('company_name') ?? 'CocoTrade ERP';
      _companyPhone = prefs.getString('company_phone') ?? '';
      _companyAddress = prefs.getString('company_address') ?? '';
      _isFirstLoginDone = prefs.getBool(_prefFirstLoginKey) ?? false;
      _isLicensed = prefs.getBool(_prefIsLicensedKey) ?? false;
      _savedEmail = prefs.getString(_prefEmailKey) ?? "admin@cocotrade.com";
      _savedPassword = prefs.getString(_prefPassKey) ?? "admin123";
      _savedPin = prefs.getString(_prefPinKey) ?? (localData != null && localData['savedPin'] != null ? localData['savedPin'] : "1234");
      _savedLicenseKey = prefs.getString(_prefLicenseKeyString) ?? "YOUR-NEW-LICENSE-KEY";
      _isLocked = true;
      _isLoading = false;
    });

    if (_trucks.isNotEmpty) {
      _calculateOverdueBills(_trucks);
    }
    }

   DateTime _getFYStartDate(String fy) {
    final startYear = int.parse(fy.split('-')[0]);
    return DateTime(startYear, 4, 1);
   }

   DateTime _getFYEndDate(String fy) {
    final startYear = int.parse(fy.split('-')[0]);
    return DateTime(startYear + 1, 3, 31, 23, 59, 59);
    }

   bool _isDateInFY(String dateStr, String fy) {
    final date = parseFlexibleDate(dateStr);
    return date.isAfter(_getFYStartDate(fy).subtract(const Duration(seconds: 1))) &&
           date.isBefore(_getFYEndDate(fy).add(const Duration(seconds: 1)));
    }

    String _toIso(String input) {
    final d = parseFlexibleDate(input);
    return "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";
    }

    Map<String, dynamic> _exportStateMap() {
    final safeTrucks = _trucks.map((t) {
      var json = (t as dynamic).toJson();
      json['date'] = _toIso(json['date']);
      return json;
    }).toList();

    final safePayments = _payments.map((p) {
      var json = (p as dynamic).toJson();
      json['date'] = _toIso(json['date']);
      return json;
    }).toList();

    return {
      'app': 'COCOTRADE_ERP', 'version': '2.0.0', 'lastSaved': DateTime.now().toUtc().toIso8601String(),
      'companyProfile': _myCompany.toJson(),
      'parties': _parties.map((p) => (p as dynamic).toJson()).toList(),
      'trucks': safeTrucks,
      'bankAccounts': _bankAccounts.map((b) => b.toJson()).toList(),
      'payments': safePayments,
      'transportPayments': _transportPayments.map((tp) => (tp as dynamic).toJson()).toList(),
      'confirmations': _confirmations.map((c) => (c as dynamic).toJson()).toList(),
      'coconutTypes': _coconutTypes,
      'smsQueue': _smsQueue.map((s) => s.toJson()).toList(),
      'savedPin': _savedPin,
      'isLicensed': _isLicensed,
      'savedEmail': _savedEmail,
    };
    }

   String _generateFullDatabaseJson() => jsonEncode(_exportStateMap());

    Future<void> _commitToLocalDrive() async {
    Map<String, dynamic> appState = _exportStateMap();
    
    // 1. Instantly write to local device storage (fast & offline safe)
    await LocalDriveManager.writeToDrive(appState);

    // 2. Trigger Google Drive upload in the background without blocking the UI
    if (GoogleDriveService.currentCredentials != null) {
      Future.microtask(() async {
        try {
          await GoogleDriveService.uploadDatabase(jsonEncode(appState));
        } catch (e) {
          debugPrint("Background Cloud Sync Failed: $e");
        }
      });
    }
  }

  void _applyStateFromMap(Map<String, dynamic> data) async {
    setState(() {
      if (data['smsQueue'] != null) {
        _smsQueue = (data['smsQueue'] as List).map((i) => SmsQueueItem.fromJson(i)).toList();
      }
      if (data['companyProfile'] != null) _myCompany = CompanyProfile.fromJson(data['companyProfile']);
      if (data['parties'] != null) _parties = (data['parties'] as List).map((i) => Party.fromJson(i)).toList();
      if (data['trucks'] != null) _trucks = (data['trucks'] as List).map((i) => TruckEntry.fromJson(i)).toList();
      if (data['bankAccounts'] != null) {
        _bankAccounts = (data['bankAccounts'] as List).map((i) => BankAccount.fromJson(i)).toList();
        if (_bankAccounts.isNotEmpty) _selectedBank = _bankAccounts.first;
      }
      if (data['payments'] != null) _payments = (data['payments'] as List).map((i) => PaymentEntry.fromJson(i)).toList();
      if (data['transportPayments'] != null) _transportPayments = (data['transportPayments'] as List).map((i) => TransportPayment.fromJson(i)).toList();
      if (data['confirmations'] != null) _confirmations = (data['confirmations'] as List).map((i) => TradeConfirmation.fromJson(i)).toList();
      if (data['coconutTypes'] != null) _coconutTypes = List<String>.from(data['coconutTypes']);
      if (data.containsKey('savedPin')) _savedPin = data['savedPin'];
      if (data.containsKey('isLicensed')) _isLicensed = data['isLicensed'];
      if (data.containsKey('savedEmail')) _savedEmail = data['savedEmail'];
    });

    final prefs = await SharedPreferences.getInstance();
    if (data.containsKey('savedPin')) await prefs.setString(_prefPinKey, data['savedPin']);
    if (data.containsKey('isLicensed')) await prefs.setBool(_prefIsLicensedKey, data['isLicensed']);
    if (data.containsKey('savedEmail')) await prefs.setString(_prefEmailKey, data['savedEmail']);
    
    // GUARANTEE LOCAL PERSISTENCE ON ANDROID
    await LocalDriveManager.writeToDrive(data);

    if (!kIsWeb && Platform.isAndroid) {
      _processPendingSmsQueue();
    }
  }

  void _performBackup() async {
    final success = await GoogleDriveService.uploadDatabase(_generateFullDatabaseJson());
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF047857), content: Text('Backup saved securely to Google Drive!')),
      );
    }
  }

  void _performRestore() async {
    final cloudData = await GoogleDriveService.downloadDatabase();
    if (cloudData != null && mounted) {
      _applyStateFromMap(cloudData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFF047857), content: Text('Data restored successfully!')),
      );
    }
  }

  void _addGoodsRow({String desc = 'COCONUT', String qty = '', String rate = ''}) {
    final item = GoodsItemController(desc: desc.toUpperCase(), qty: qty, rate: rate);
    item.descCtrl.addListener(() => setState(() {}));
    item.qtyCtrl.addListener(() => setState(() {}));
    item.rateCtrl.addListener(() => setState(() {}));
    _invoiceGoods.add(item);
  }

  List<String> get _sellerNames {
    final Set<String> names = {};
    for (var p in _parties) {
      if (p.type.toString().trim().toUpperCase() == "SELLER" && p.name.toString().trim().isNotEmpty) {
        names.add(p.name.toString().trim().toUpperCase());
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  List<String> get _buyerNames {
    final Set<String> names = {};
    for (var p in _parties) {
      if (p.type.toString().trim().toUpperCase() == "BUYER" && p.name.toString().trim().isNotEmpty) {
        names.add(p.name.toString().trim().toUpperCase());
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  List<String> get _transporterNames {
    final Set<String> names = {};
    for (var p in _parties) {
      if (p.type.toString().trim().toUpperCase() == "TRANSPORTER" && p.name.toString().trim().isNotEmpty) {
        names.add(p.name.toString().trim().toUpperCase());
      }
    }
    final list = names.toList()..sort();
    return list;
  }
  List<String> get _sellerRespectiveBuyers {
    if (_repSeller.trim().isEmpty) return _buyerNames;
    final set = _trucks.where((t) => t.state == _selectedState && t.supplier.toUpperCase() == _repSeller.toUpperCase() && t.buyer.isNotEmpty).map((t) => t.buyer.toUpperCase()).toSet();
    return set.isNotEmpty ? set.toList().cast<String>() : _buyerNames;
  }
  List<String> get _buyerRespectiveSellers {
    if (_repBuyer.trim().isEmpty) return _sellerNames;
    final set = _trucks.where((t) => t.state == _selectedState && t.buyer.toUpperCase() == _repBuyer.toUpperCase() && t.supplier.isNotEmpty).map((t) => t.supplier.toUpperCase()).toSet();
    return set.isNotEmpty ? set.toList().cast<String>() : _sellerNames;
  }

  static DateTime parseFlexibleDate(String input) {
    if (input.trim().isEmpty) return DateTime(1970);
    final clean = input.trim().replaceAll('/', '-');
    try {
      final parts = clean.split('-');
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          return DateTime(int.parse(parts[0]), _parseMonth(parts[1]), int.parse(parts[2]));
        }
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000;
        return DateTime(year, _parseMonth(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}
    return DateTime.now();
  }

  static String formatDisplayDate(String rawDate) {
    if (rawDate.trim().isEmpty) return '—';
    final dt = parseFlexibleDate(rawDate);
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return "$dd-$mm-$yy";
  }

  static int _parseMonth(String m) {
    final num = int.tryParse(m); if (num != null) return num;
    final months = {"JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6, "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12};
    return months[m.toUpperCase()] ?? 1;
  }

  static bool isDateInRange(String entryDateStr, String fromDateStr, String toDateStr) {
    DateTime entryDate = parseFlexibleDate(entryDateStr);
    if (fromDateStr.trim().isNotEmpty && entryDate.isBefore(parseFlexibleDate(fromDateStr))) return false;
    if (toDateStr.trim().isNotEmpty && entryDate.isAfter(parseFlexibleDate(toDateStr))) return false;
    return true;
  }

 static String money(dynamic val) {
    if (val == null) return "₹0";
    final double dVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    if (dVal == 0) return "₹0";
    bool isNeg = dVal < 0; double absVal = dVal.abs();
    String formatted = absVal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'), (m) => '${m[1]},');
    return isNeg ? '-₹$formatted' : '₹$formatted';
  }

  static String pdfMoney(dynamic val) {
    if (val == null) return "0";
    final double dVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    if (dVal == 0) return "0";
    bool isNeg = dVal < 0; double absVal = dVal.abs();
    String formatted = absVal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'), (m) => '${m[1]},');
    return isNeg ? '-$formatted' : formatted;
  }

  static String numFmt(dynamic val) {
    if (val == null) return "0";
    final double dVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return dVal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'), (m) => '${m[1]},');
  }
  static String wordsToIndian(double numVal) {
    int num = numVal.floor(); if (num <= 0) return "ZERO";
    final a = ["", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN"];
    final b = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY", "NINETY"];
    String two(int n) => n < 20 ? a[n] : "${b[n ~/ 10]}${n % 10 != 0 ? " ${a[n % 10]}" : ""}";
    String three(int n) => n < 100 ? two(n) : "${a[n ~/ 100]} HUNDRED${n % 100 != 0 ? " ${two(n % 100)}" : ""}";
    List<String> p = [];
    if (num >= 10000000) { p.add("${three(num ~/ 10000000)} CRORE"); num %= 10000000; }
    if (num >= 100000) { p.add("${three(num ~/ 100000)} LAKH"); num %= 100000; }
    if (num >= 1000) { p.add("${three(num ~/ 1000)} THOUSAND"); num %= 1000; }
    if (num > 0) p.add(three(num));
    return p.join(" ").trim();
  }
// Helper to handle responsive rows safely (must be private _responsiveRow)
  Widget _responsiveRow(List<Widget> children, {CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.end}) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .where((c) => !(c is SizedBox && c.width != null && (c.height == null || c.height == 0)))
            .map((c) {
          Widget inner = c;
          if (c is Expanded) {
            inner = c.child;
          } else if (c is Flexible) {
            inner = c.child;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: inner,
          );
        }).toList(),
      );
    } else {
      return Row(crossAxisAlignment: crossAxisAlignment, children: children);
    }
  }

  // Helper for license key checks (must be private _verifyLicenseKey)
  bool _verifyLicenseKey(String email, String key) {
    if (email.trim().isEmpty || key.trim().isEmpty) return false;
    final cleanMail = email.trim().toLowerCase();
    final bytes = utf8.encode(cleanMail);
    final hmacSha256 = Hmac(sha256, utf8.encode("COCOTRADE_SECRET_2026"));
    final digest = hmacSha256.convert(bytes);
    final hashed = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    final expectedKey = "COCO-${hashed.substring(0, 4)}-${hashed.substring(4, 8)}-${hashed.substring(8, 12)}-${hashed.substring(12, 16)}";
    return key.trim().toUpperCase() == expectedKey;
  }
  Future<void> _selectDateForController(TextEditingController ctrl) async {
    DateTime initial = ctrl.text.isNotEmpty ? parseFlexibleDate(ctrl.text) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF047857),
            onPrimary: Colors.white,
            onSurface: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final dd = picked.day.toString().padLeft(2, '0');
      final mm = picked.month.toString().padLeft(2, '0');
      final yy = (picked.year % 100).toString().padLeft(2, '0');
      setState(() => ctrl.text = "$dd-$mm-$yy");
    }
  }

  void _calculateOverdueBills(List<dynamic> allTrucks) {
    final DateTime today = DateTime.now();
    List<dynamic> overdue = [];
    Map<String, double> buyerPaidMap = {};
    for (var p in _payments) {
      if (p.state != _selectedState || !p.type.contains("BUYER")) continue;
      final buyerKey = p.buyer.toUpperCase();
      buyerPaidMap[buyerKey] = (buyerPaidMap[buyerKey] ?? 0) + p.amount + p.settlement + p.commissionAdjusted;
    }

    List<dynamic> sortedTrucks = List.from(allTrucks.where((t) => t.state == _selectedState && (t.buyerBill > 0 || t.supplierBill > 0)));
    sortedTrucks.sort((a, b) => parseFlexibleDate(a.date).compareTo(parseFlexibleDate(b.date)));

    for (var t in sortedTrucks) {
      final buyerKey = t.buyer.toUpperCase();
      final double billAmount = t.buyerBill > 0 ? t.buyerBill : t.supplierBill;
      double paidSoFar = buyerPaidMap[buyerKey] ?? 0.0;

      if (paidSoFar >= billAmount) {
        buyerPaidMap[buyerKey] = paidSoFar - billAmount;
      } else {
        buyerPaidMap[buyerKey] = 0;
        final balancePending = billAmount - paidSoFar;
        final int daysSinceEntry = today.difference(parseFlexibleDate(t.date)).inDays;

        if (daysSinceEntry > 10 && balancePending > 0) {
          t.remarks = balancePending.toString();
          overdue.add(t);
        }
      }
    }
    setState(() => _overdueBills = overdue);
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF062317),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF047857)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(_companyName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Coconut Canvassing Suite', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          _neoNavItem('dashboard', 'Dashboard', Icons.space_dashboard_outlined),
          _neoNavItem('parties', 'Parties Directory', Icons.contacts_outlined),
          _neoNavItem('trucks', 'Truck Logistics', Icons.local_shipping_outlined),
          _neoNavItem('invoice', 'Tax Invoices', Icons.receipt_long_outlined),
          _neoNavItem('payments', 'Payment Ledger', Icons.account_balance_wallet_outlined),
          _neoNavItem('reports', 'Party Ledgers', Icons.analytics_outlined),
          _neoNavItem('transport', 'Transport Logs', Icons.commute_outlined),
          _neoNavItem('estimate', 'Cost Estimator', Icons.calculate_outlined),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent() {
    Widget content;
    switch (_selectedTab) {
      case 'dashboard':
        content = _buildDashboardView();
        break;
      case 'parties':
        content = _buildPartiesView();
        break;
      case 'trucks':
        content = _buildTruckLogisticsView();
        break;
      case 'invoice':
        content = _buildInvoiceView();
        break;
      case 'payments':
        content = _buildPaymentsView();
        break;
      case 'reports':
        content = _buildReportsView();
        break;
      case 'transport':
        content = _buildTransportView();
        break;
      case 'estimate':
        content = _buildEstimateView();
        break;
      default:
        content = _buildDashboardView();
    }
    return Material(
      color: Colors.transparent,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF081C15),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
      );
    }
    if (!_isLicensed && _isTrialExpired) return _buildFirstTimeEmailLoginScreen();
    if (!_isFirstLoginDone || _forceEmailLogin) return _buildFirstTimeEmailLoginScreen();
    if (!_isProfileSetupDone) return _buildCompanyProfileScreen();
    if (_isLocked) return _buildPinLockScreen();

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: Text(_companyName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          backgroundColor: const Color(0xFF062317),
          foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _showStorageSettingsDialog),
            IconButton(icon: const Icon(Icons.lock_outline_rounded), onPressed: () => setState(() => _isLocked = true)),
          ],
        ),
        drawer: _buildMobileDrawer(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildExecutiveHeader(),
                const SizedBox(height: 12),
                _buildActiveTabContent(),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          _buildNeoSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildExecutiveHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: _buildActiveTabContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- NEO-SAAS SIDEBAR ----------------
  Widget _buildNeoSidebar() {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF062317),
        border: Border(right: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF047857)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Color(0x3310B981), blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: const Icon(Icons.eco_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _companyName.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text('CANVASSING SUITE', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _sidebarSectionLabel('OPERATIONS'),
                _neoNavItem('dashboard', 'Dashboard', Icons.space_dashboard_outlined),
                _neoNavItem('parties', 'Parties Directory', Icons.contacts_outlined),
                _neoNavItem('trucks', 'Truck Logistics', Icons.local_shipping_outlined),
                const SizedBox(height: 14),
                _sidebarSectionLabel('FINANCIALS'),
                _neoNavItem('invoice', 'Tax Invoices', Icons.receipt_long_outlined),
                _neoNavItem('payments', 'Payment Ledger', Icons.account_balance_wallet_outlined),
                _neoNavItem('reports', 'Party Ledgers', Icons.analytics_outlined),
                _neoNavItem('transport', 'Transport Logs', Icons.commute_outlined),
                _neoNavItem('estimate', 'Cost Estimator', Icons.calculate_outlined),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SYSTEM ACTIVE', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    Text('FY $_selectedFinancialYear', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFF87171), size: 18),
                  tooltip: 'Lock ERP',
                  onPressed: () => setState(() => _isLocked = true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 6),
      child: Text(label, style: const TextStyle(color: Color(0xFF4B6E5B), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
    );
  }

  Widget _neoNavItem(String key, String title, IconData icon) {
    final bool active = _selectedTab == key;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _selectedTab = key;
              if (key == 'trucks' && _editingTruckId == null) _clearTruckForm();
              if (key == 'invoice' && _editingInvoiceId == null) _clearInvoiceForm();
              _calculateOverdueBills(_trucks);
            });
            if (isMobile && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF10B981) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? const [BoxShadow(color: Color(0x3310B981), blurRadius: 12, offset: Offset(0, 4))]
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFF86A393)),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.bold : FontWeight.w600, color: active ? Colors.white : const Color(0xFFC7D7CF)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExecutiveHeader() {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [_statePill("Andhra Pradesh"), _statePill("Tamil Nadu")]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA7F3D0))),
              child: Text('FY $_selectedFinancialYear', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedTab.toUpperCase(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 2),
              Text(
                _companyAddress.isNotEmpty ? '$_companyAddress • Tel: $_companyPhone' : 'Live Management Console',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_statePill("Andhra Pradesh"), _statePill("Tamil Nadu")],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_rounded, size: 14, color: Color(0xFF047857)),
                    const SizedBox(width: 6),
                    Text('FY $_selectedFinancialYear', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.settings_outlined, size: 18, color: Color(0xFF0F172A)),
                onPressed: _showStorageSettingsDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statePill(String stateName) {
    final bool active = _selectedState == stateName;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedState = stateName;
          _calculateOverdueBills(_trucks);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF047857) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          stateName,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.white : const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _neoKpiCard({required String label, required String value, required String subtitle, required IconData icon, required Color accentColor}) {
    Widget card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFF64748B))),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(subtitle, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ],
          ),
        ],
      ),
    );
    return isMobile ? SizedBox(width: 170, child: card) : Expanded(child: card);
  }

  // ---------------- DASHBOARD VIEW ----------------
  Widget _buildDashboardView() {
    final curTrucks = _trucks.where((t) => t.state == _selectedState).toList();
    final curPayments = _payments.where((p) => p.state == _selectedState).toList();
    final curConfirmations = _confirmations.where((c) => c.status == 'PENDING').toList();

    final double totalSales = curTrucks.fold(0, (s, t) => s + (t.buyerBill > 0 ? t.buyerBill : t.supplierBill));
    final double totalCollected = curPayments.where((p) => p.type.contains("BUYER") || p.mode == "DIRECT").fold(0, (s, p) => s + p.amount);
    final double outstanding = (totalSales - totalCollected).clamp(0, double.infinity);

    Widget kpiRow = Row(
      children: [
        _neoKpiCard(label: 'Pending Trades', value: '${curConfirmations.length}', subtitle: 'Awaiting Dispatch', icon: Icons.schedule_send_rounded, accentColor: const Color(0xFFF59E0B)),
        SizedBox(width: isMobile ? 10 : 14),
        _neoKpiCard(label: 'Total Trucks', value: '${curTrucks.length}', subtitle: 'Active Logistics', icon: Icons.local_shipping_rounded, accentColor: const Color(0xFF3B82F6)),
        SizedBox(width: isMobile ? 10 : 14),
        _neoKpiCard(label: 'Total Sales', value: money(totalSales), subtitle: 'Gross Revenue', icon: Icons.trending_up_rounded, accentColor: const Color(0xFF10B981)),
        SizedBox(width: isMobile ? 10 : 14),
        _neoKpiCard(label: 'Outstanding', value: money(outstanding), subtitle: 'Pending Dues', icon: Icons.account_balance_wallet_rounded, accentColor: const Color(0xFFEF4444)),
        SizedBox(width: isMobile ? 10 : 14),
        _neoKpiCard(label: 'Active Parties', value: '${_parties.length}', subtitle: 'Registered Directory', icon: Icons.groups_rounded, accentColor: const Color(0xFF6366F1)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isMobile ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: kpiRow) : kpiRow,
        const SizedBox(height: 20),
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quick Trade Confirmation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 16),
              _responsiveRow([
                Expanded(child: _customField('Date *', _confDateCtrl, icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_confDateCtrl))),
                const SizedBox(width: 12),
                Expanded(child: _customAutocomplete('Seller *', _sellerNames, _confSeller, 'SELECT SELLER', (v) => setState(() => _confSeller = v))),
                const SizedBox(width: 12),
                Expanded(child: _customAutocomplete('Buyer *', _buyerNames, _confBuyer, 'SELECT BUYER', (v) => setState(() => _confBuyer = v))),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Coconut Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          InkWell(onTap: _showManageCommoditiesDialog, child: const Text('+ Manage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857)))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _coconutTypes.contains(_confType) ? _confType : (_coconutTypes.isNotEmpty ? _coconutTypes.first : null),
                            isExpanded: true,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: _coconutTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _confType = val!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _customField('Rate (₹) *', _confRateCtrl, isNum: true)),
                const SizedBox(width: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    if (_confSeller.isEmpty || _confBuyer.isEmpty || _confRateCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Seller, Buyer, and Rate.')));
                      return;
                    }

                    final tradeRate = double.tryParse(_confRateCtrl.text) ?? 0;
                    final tradeDate = _confDateCtrl.text.trim();
                    final sellerName = _confSeller.trim().toUpperCase();
                    final buyerName = _confBuyer.trim().toUpperCase();
                    final itemType = _confType;

                    // 1. Resolve contact profiles first
                    final matchedSeller = _parties.firstWhere(
                      (p) => p.name.toUpperCase() == sellerName,
                      orElse: () => Party(name: "", type: "", phone: "", address: ""),
                    );

                    final matchedBuyer = _parties.firstWhere(
                      (p) => p.name.toUpperCase() == buyerName,
                      orElse: () => Party(name: "", type: "", phone: "", address: ""),
                    );

                    // 2. Format tailored messages
                    final sellerMsg = _formatTradeMessage(
                      template: _sellerMsgTemplate,
                      date: tradeDate,
                      seller: sellerName,
                      buyer: buyerName,
                      type: itemType,
                      rate: tradeRate,
                    );

                    final buyerMsg = _formatTradeMessage(
                      template: _buyerMsgTemplate,
                      date: tradeDate,
                      seller: sellerName,
                      buyer: buyerName,
                      type: itemType,
                      rate: tradeRate,
                    );

                    // 3. Add to local confirmations and queue
                    setState(() {
                      _confirmations.add(TradeConfirmation(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        date: tradeDate,
                        seller: sellerName,
                        buyer: buyerName,
                        coconutType: itemType,
                        rate: tradeRate,
                      ));

                      if (matchedSeller.phone.isNotEmpty) {
                        _smsQueue.add(SmsQueueItem(
                          id: 'SMS-${DateTime.now().millisecondsSinceEpoch}-1',
                          phone: matchedSeller.phone,
                          message: sellerMsg,
                          status: 'PENDING',
                          createdAt: DateTime.now().toIso8601String(),
                        ));
                      }

                      if (matchedBuyer.phone.isNotEmpty) {
                        _smsQueue.add(SmsQueueItem(
                          id: 'SMS-${DateTime.now().millisecondsSinceEpoch}-2',
                          phone: matchedBuyer.phone,
                          message: buyerMsg,
                          status: 'PENDING',
                          createdAt: DateTime.now().toIso8601String(),
                        ));
                      }

                      _confSeller = "";
                      _confBuyer = "";
                      _confRateCtrl.clear();
                    });

                    await _commitToLocalDrive();

                    // If currently running on Android device, dispatch immediately
                    if (!kIsWeb && Platform.isAndroid) {
                      _processPendingSmsQueue();
                    }

                    // 4. Show one-tap dispatch modal for WhatsApp / Manual SMS
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (dlgCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Trade Saved — Dispatch Message', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(sellerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(matchedSeller.phone.isNotEmpty ? matchedSeller.phone : 'No phone saved'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.sms_rounded, color: Color(0xFF047857)),
                                      tooltip: 'Send SMS',
                                      onPressed: matchedSeller.phone.isNotEmpty
                                          ? () => _launchDeviceMessaging(phone: matchedSeller.phone, message: sellerMsg, useWhatsApp: false)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366)),
                                      tooltip: 'Send WhatsApp',
                                      onPressed: matchedSeller.phone.isNotEmpty
                                          ? () => _launchDeviceMessaging(phone: matchedSeller.phone, message: sellerMsg, useWhatsApp: true)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(buyerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(matchedBuyer.phone.isNotEmpty ? matchedBuyer.phone : 'No phone saved'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.sms_rounded, color: Color(0xFF047857)),
                                      tooltip: 'Send SMS',
                                      onPressed: matchedBuyer.phone.isNotEmpty
                                          ? () => _launchDeviceMessaging(phone: matchedBuyer.phone, message: buyerMsg, useWhatsApp: false)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366)),
                                      tooltip: 'Send WhatsApp',
                                      onPressed: matchedBuyer.phone.isNotEmpty
                                          ? () => _launchDeviceMessaging(phone: matchedBuyer.phone, message: buyerMsg, useWhatsApp: true)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dlgCtx),
                              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Save Trade'),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildPendingTradesTable(curConfirmations),
        const SizedBox(height: 20),
        _buildOverdueAlertCard(),
      ],
    );
  }

  Widget _buildPendingTradesTable(List<dynamic> curConfirmations) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pending Trade Confirmations (Awaiting Dispatch)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: const [
                    DataColumn(label: Text('DATE', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('SELLER', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('BUYER', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('TYPE', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('RATE', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('ACTIONS', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                  ],
                  rows: curConfirmations.isEmpty
                      ? [
                          const DataRow(cells: [
                            DataCell(SizedBox()), DataCell(SizedBox()),
                            DataCell(Center(child: Text('No pending trades.', style: TextStyle(color: Color(0xFF94A3B8))))),
                            DataCell(SizedBox()), DataCell(SizedBox()), DataCell(SizedBox()),
                          ])
                        ]
                      : curConfirmations.map((c) {
                          return DataRow(cells: [
                            DataCell(Text(c.date, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(c.seller, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
                            DataCell(Text(c.buyer, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
                            DataCell(Text(c.coconutType)),
                            DataCell(Text(money(c.rate), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857)))),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), side: const BorderSide(color: Colors.blue)),
                                  onPressed: () => _routeToTruck(c),
                                  icon: const Icon(Icons.local_shipping_rounded, size: 14, color: Colors.blue),
                                  label: const Text('Truck', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), side: const BorderSide(color: Color(0xFF047857))),
                                  onPressed: () => _routeToInvoice(c),
                                  icon: const Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF047857)),
                                  label: const Text('Invoice', style: TextStyle(fontSize: 11, color: Color(0xFF047857))),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                                  onPressed: () { setState(() => c.status = 'CANCELLED'); _commitToLocalDrive(); },
                                ),
                              ],
                            )),
                          ]);
                        }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverdueAlertCard() {
    if (_overdueBills.isEmpty) return const SizedBox.shrink();

    final ScrollController verticalScroll = ScrollController();
    const double rowHeight = 52.0;
    final double calculatedHeight = (_overdueBills.length > 10 ? 10 : _overdueBills.length) * rowHeight + 48.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 8),
                  Text('Overdue Invoices (10+ Days)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF991B1B))),
                ],
              ),
              Text(
                '${_overdueBills.length} Due',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF991B1B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: calculatedHeight,
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFCA5A5)), borderRadius: BorderRadius.circular(10), color: Colors.white),
              child: Scrollbar(
                controller: verticalScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: verticalScroll,
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFFEE2E8)),
                      columns: const [
                        DataColumn(label: Text('DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)))),
                        DataColumn(label: Text('SELLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)))),
                        DataColumn(label: Text('BUYER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)))),
                        DataColumn(label: Text('BILL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)))),
                        DataColumn(label: Text('BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)))),
                        DataColumn(label: Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)))),
                      ],
                      rows: _overdueBills.map((t) {
                        final double billAmount = t.buyerBill > 0 ? t.buyerBill : t.supplierBill;
                        final double balanceAmt = double.tryParse(t.remarks) ?? 0;
                        return DataRow(cells: [
                          DataCell(Text(formatDisplayDate(t.date))),
                          DataCell(Text(t.supplier.isNotEmpty ? t.supplier : '—')),
                          DataCell(Text(t.buyer.isNotEmpty ? t.buyer : 'Unknown')),
                          DataCell(Text(money(billAmount), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)))),
                          DataCell(Text(money(balanceAmt), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFDC2626)))),
                          DataCell(OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), side: const BorderSide(color: Color(0xFF047857))),
                            onPressed: () => _markBillAsPaid(t),
                            child: const Text('Pay', style: TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.bold)),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
   void _markBillAsPaid(dynamic truckEntry) {
    final double totalBill = truckEntry.buyerBill > 0 ? truckEntry.buyerBill : truckEntry.supplierBill;
    final double alreadyPaid = _payments
        .where((p) =>
            p.buyer.toUpperCase() == truckEntry.buyer.toUpperCase() &&
            formatDisplayDate(p.date) == formatDisplayDate(truckEntry.date) &&
            p.state == _selectedState)
        .fold(0.0, (sum, p) => sum + p.amount + p.settlement);

    final double remainingBalance = totalBill - alreadyPaid;

    if (remainingBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This bill is already fully settled!')));
      return;
    }

    setState(() {
      _payments.add(
        PaymentEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          state: _selectedState,
          type: "RECEIPT FROM BUYER",
          seller: truckEntry.supplier,
          buyer: truckEntry.buyer,
          amount: remainingBalance,
          transportReceived: 0,
          settlement: 0,
          mode: "DIRECT",
          date: formatDisplayDate(truckEntry.date),
        ),
      );
      _calculateOverdueBills(_trucks);
    });

    _commitToLocalDrive();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF047857),
        content: Text('Settled ₹${remainingBalance.toStringAsFixed(0)} for ${truckEntry.buyer}!'),
      ),
    );
    }

   void _carryForwardFinancialYearBalances(String newYear) {
    final startYear = newYear.split('-')[0];
    final String openingDate = "$startYear-04-01";
    int buyerCount = 0;
    int sellerCount = 0;

    for (var buyerName in _buyerNames) {
      final double totalBilled = _trucks
          .where((t) => t.state == _selectedState && t.buyer.toUpperCase() == buyerName.toUpperCase())
          .fold(0.0, (sum, t) => sum + (t.buyerBill > 0 ? t.buyerBill : t.supplierBill));

      final double totalPaid = _payments
          .where((p) => p.state == _selectedState && p.buyer.toUpperCase() == buyerName.toUpperCase())
          .fold(0.0, (sum, p) => sum + p.amount + p.settlement);

      final double pending = totalBilled - totalPaid;

      if (pending > 0) {
        final alreadyLogged = _trucks.any((t) =>
            t.buyer.toUpperCase() == buyerName.toUpperCase() &&
            t.type == "OPENING BALANCE" &&
            t.date == openingDate);

        if (!alreadyLogged) {
          _trucks.add(TruckEntry(
            id: 'OB-BUYER-${DateTime.now().millisecondsSinceEpoch}-$buyerCount',
            state: _selectedState,
            date: openingDate,
            truck: 'OPENING BAL',
            supplier: '—',
            buyer: buyerName.toUpperCase(),
            transporter: '—',
            type: 'OPENING BALANCE',
            qty: 0,
            supplierBill: 0,
            buyerBill: pending,
            commission: 0,
            transportExp: 0,
            freight: 0,
            advance: 0,
          ));
          buyerCount++;
        }
      }
    }

    for (var sellerName in _sellerNames) {
      final double totalBilled = _trucks
          .where((t) => t.state == _selectedState && t.supplier.toUpperCase() == sellerName.toUpperCase())
          .fold(0.0, (sum, t) => sum + t.supplierBill);

      final double totalPaid = _payments
          .where((p) => p.state == _selectedState && p.seller.toUpperCase() == sellerName.toUpperCase())
          .fold(0.0, (sum, p) => sum + p.amount + p.settlement);

      final double pending = totalBilled - totalPaid;

      if (pending > 0) {
        final alreadyLogged = _trucks.any((t) =>
            t.supplier.toUpperCase() == sellerName.toUpperCase() &&
            t.type == "OPENING BALANCE" &&
            t.date == openingDate);

        if (!alreadyLogged) {
          _trucks.add(TruckEntry(
            id: 'OB-SELLER-${DateTime.now().millisecondsSinceEpoch}-$sellerCount',
            state: _selectedState,
            date: openingDate,
            truck: 'OPENING BAL',
            supplier: sellerName.toUpperCase(),
            buyer: '—',
            transporter: '—',
            type: 'OPENING BALANCE',
            qty: 0,
            supplierBill: pending,
            buyerBill: 0,
            commission: 0,
            transportExp: 0,
            freight: 0,
            advance: 0,
          ));
          sellerCount++;
        }
      }
    }

    setState(() => _selectedFinancialYear = newYear);
    _commitToLocalDrive();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF047857),
        content: Text('Balances rolled into FY $newYear! ($buyerCount Buyers, $sellerCount Sellers carried forward).'),
      ),
    );
  }

  void _routeToTruck(dynamic conf) {
    setState(() {
      _selectedTab = 'trucks'; _editingTruckId = null; _editingInvoiceId = null;
      _tDateCtrl.text = conf.date; _tSupplier = conf.seller; _tBuyer = conf.buyer; _tCoconutType = conf.coconutType;
      conf.status = 'DISPATCHED';
    });
    _commitToLocalDrive();
  }

  void _routeToInvoice(dynamic conf) {
    setState(() {
      _selectedTab = 'invoice'; _editingTruckId = null; _editingInvoiceId = null;
      _iDateCtrl.text = conf.date; _iSeller = conf.seller; _iBuyer = conf.buyer;
      if (_invoiceGoods.isNotEmpty) {
        _invoiceGoods[0].descCtrl.text = conf.coconutType; _invoiceGoods[0].rateCtrl.text = conf.rate.toString();
      }
      final matchedBuyer = _parties.firstWhere((p) => p.name == conf.buyer, orElse: () => Party(name: "", type: "", phone: "", address: ""));
      _iAddressCtrl.text = matchedBuyer.address; _iPhoneCtrl.text = matchedBuyer.phone;
      conf.status = 'INVOICED';
    });
    _commitToLocalDrive();
  }

  void _clearTruckForm() {
    _tRemarksCtrl.clear();
    setState(() {
      _editingTruckId = null;
      _hasCustomBuyerBill = false; // Reset to single bill field
      _tTruckCtrl.clear();
      _tQtyCtrl.clear();
      _tSBillCtrl.clear();
      _tBBillCtrl.clear();
      _tCommCtrl.text = "500";
      _tExpCtrl.text = "0";
      _tFreightCtrl.text = "0";
      _tAdvCtrl.text = "0";
      _tSupplier = "";
      _tBuyer = "";
      _tTransporter = "";
      _tCoconutType = "TENDER";
    });
  }

  void _clearInvoiceForm() {
    setState(() {
      _editingInvoiceId = null; _iBuyer = ""; _iSeller = ""; _iTransporter = "";
      _iSellerAmountCtrl.clear(); _iTransportExpCtrl.clear(); _iAddressCtrl.clear(); _iPhoneCtrl.clear(); _iLorryCtrl.clear(); _iDriverCtrl.clear();
      _iBagsCtrl.text = "0"; _iBagRateCtrl.text = "0"; _iLoadingManual = false; _iLoadManualAmountCtrl.text = "0"; _iLoadRateCtrl.text = "0";
      _iAmcCtrl.text = "0"; _iInsCtrl.text = "0"; _iCommCtrl.text = "0"; _iAdvCtrl.text = "0"; _iFreightCtrl.text = "0";
      for (var it in _invoiceGoods) { it.dispose(); }
      _invoiceGoods.clear(); _addGoodsRow();
    });
  }

  void _editFromReport(dynamic t) {
    _tRemarksCtrl.text = t.remarks;
    if (t.isInvoice) {
      // ... existing invoice edit code ...
    } else {
      setState(() {
        _selectedTab = 'trucks';
        _editingTruckId = t.id;
        _editingInvoiceId = null;
        // Auto-expand if buyer bill is different from supplier bill
        _hasCustomBuyerBill = (t.buyerBill > 0 && t.buyerBill != t.supplierBill);
        _tTruckCtrl.text = t.truck == '—' ? '' : t.truck;
        _tDateCtrl.text = t.date;
        _tSupplier = t.supplier == '—' ? '' : t.supplier;
        _tBuyer = t.buyer;
        _tTransporter = t.transporter == '—' ? '' : t.transporter;
        _tCoconutType = t.type;
        _tQtyCtrl.text = t.qty > 0 ? t.qty.toStringAsFixed(0) : '';
        _tSBillCtrl.text = t.supplierBill > 0 ? t.supplierBill.toStringAsFixed(0) : '';
        _tBBillCtrl.text = t.buyerBill > 0 ? t.buyerBill.toStringAsFixed(0) : '';
        _tCommCtrl.text = t.commission > 0 ? t.commission.toStringAsFixed(0) : '500';
        _tExpCtrl.text = t.transportExp > 0 ? t.transportExp.toStringAsFixed(0) : '0';
        _tFreightCtrl.text = t.freight > 0 ? t.freight.toStringAsFixed(0) : '0';
        _tAdvCtrl.text = t.advance > 0 ? t.advance.toStringAsFixed(0) : '0';
      });
    }
  }

  void _editPaymentEntryDialog(dynamic p) {
    final amtCtrl = TextEditingController(text: p.amount.toStringAsFixed(0));
    final discCtrl = TextEditingController(text: p.settlement.toStringAsFixed(0));
    final dateCtrl = TextEditingController(text: p.date);
    String mode = p.mode;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Payment (${p.type})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _customField('Amount', amtCtrl, isNum: true),
                const SizedBox(height: 10),
                _customField('Discount / Settlement', discCtrl, isNum: true),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: mode,
                  items: ["DIRECT", "CASH", "ICICI BANK", "KOTAK BANK", "STATE BANK OF INDIA"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => setDlgState(() => mode = val!),
                  decoration: InputDecoration(
                    labelText: 'Payment Mode',
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
                const SizedBox(height: 10),
                _customField('Date', dateCtrl, readOnly: true, icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(dateCtrl)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                setState(() {
                  p.amount = double.tryParse(amtCtrl.text) ?? p.amount;
                  p.settlement = double.tryParse(discCtrl.text) ?? p.settlement;
                  p.mode = mode; p.date = dateCtrl.text.trim();
                });
                _commitToLocalDrive();
                Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String itemTitle) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text('Are you sure you want to delete "$itemTitle"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    ) ?? false;
  }

 // ---------------- PARTIES DIRECTORY (WITH SEARCH & SORT/FILTER) ----------------
  Widget _buildPartiesView() {
    final query = _partySearchCtrl.text.trim().toLowerCase();
    final filteredParties = _parties.where((p) {
      final matchesType = _partyTypeFilter == 'ALL' || p.type.toUpperCase() == _partyTypeFilter;
      final matchesQuery = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.phone.toLowerCase().contains(query) ||
          p.address.toLowerCase().contains(query);
      return matchesType && matchesQuery;
    }).toList();

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Parties Directory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _showAddPartyDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Party'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Bar & Filter Chips
          _responsiveRow([
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _partySearchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, address...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['ALL', 'BUYER', 'SELLER', 'TRANSPORTER'].map((type) {
                    final bool active = _partyTypeFilter == type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(type),
                        selected: active,
                        selectedColor: const Color(0xFF047857),
                        labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: active ? Colors.white : const Color(0xFF64748B)),
                        onSelected: (_) => setState(() => _partyTypeFilter = type),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: const [
                    DataColumn(label: Text('PARTY NAME', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                    DataColumn(label: Text('TYPE', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                    DataColumn(label: Text('PHONE', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                    DataColumn(label: Text('ADDRESS', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                    DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                  ],
                  rows: filteredParties.isEmpty
                      ? [
                          const DataRow(cells: [
                            DataCell(SizedBox()), DataCell(SizedBox()),
                            DataCell(Center(child: Text('No matching parties found.', style: TextStyle(color: Color(0xFF94A3B8))))),
                            DataCell(SizedBox()), DataCell(SizedBox()),
                          ])
                        ]
                      : filteredParties.map((p) => DataRow(cells: [
                          DataCell(Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: p.type == "BUYER" ? const Color(0xFFECFDF5) : (p.type == "SELLER" ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF)),
                                child: Text(
                                  p.name.isNotEmpty ? p.name.substring(0, 1) : 'P',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.type == "BUYER" ? const Color(0xFF047857) : (p.type == "SELLER" ? const Color(0xFFB45309) : const Color(0xFF1D4ED8))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                            ],
                          )),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: p.type == "BUYER" ? const Color(0xFFECFDF5) : (p.type == "SELLER" ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF)),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: p.type == "BUYER" ? const Color(0xFFA7F3D0) : (p.type == "SELLER" ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE))),
                            ),
                            child: Text(
                              p.type,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: p.type == "BUYER" ? const Color(0xFF047857) : (p.type == "SELLER" ? const Color(0xFFB45309) : const Color(0xFF1D4ED8))),
                            ),
                          )),
                          DataCell(Text(p.phone)),
                          DataCell(Text(p.address)),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, color: Color(0xFF047857), size: 18), onPressed: () => _showAddPartyDialog(party: p)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), onPressed: () async {
                                if (await _confirmDelete(context, p.name)) {
                                  setState(() => _parties.remove(p));
                                  _commitToLocalDrive();
                                }
                              }),
                            ],
                          )),
                        ])).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showManageCommoditiesDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Manage Coconut Types', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextField(
                          controller: ctrl,
                          inputFormatters: [UpperCaseTextFormatter()],
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: 'e.g. GOTTA, BOMBAY CHEEL',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        final val = ctrl.text.trim().toUpperCase();
                        if (val.isNotEmpty && !_coconutTypes.contains(val)) {
                          setDlgState(() => _coconutTypes.add(val));
                          setState(() {});
                          _commitToLocalDrive();
                          ctrl.clear();
                        }
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _coconutTypes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (c, i) => ListTile(
                      dense: true,
                      title: Text(_coconutTypes[i], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                        onPressed: () {
                          setDlgState(() => _coconutTypes.removeAt(i));
                          setState(() {
                            if (!_coconutTypes.contains(_confType) && _coconutTypes.isNotEmpty) _confType = _coconutTypes.first;
                            if (!_coconutTypes.contains(_tCoconutType) && _coconutTypes.isNotEmpty) _tCoconutType = _coconutTypes.first;
                          });
                          _commitToLocalDrive();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))))],
        ),
      ),
    );
  }

  void _showAddPartyDialog({dynamic party, String? initialName, String? initialType, Function(String)? onCreated}) {
    final nameCtrl = TextEditingController(text: party?.name ?? (initialName != null ? initialName.toUpperCase() : ''));
    final phoneCtrl = TextEditingController(text: party?.phone ?? '');
    final addrCtrl = TextEditingController(text: party?.address ?? '');
    String pType = party?.type ?? initialType ?? "BUYER";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          void savePartyAction() {
            final name = nameCtrl.text.toUpperCase().trim();
            if (name.isNotEmpty) {
              setState(() {
                if (party != null) {
                  party.name = name;
                  party.type = pType;
                  party.phone = phoneCtrl.text.trim();
                  party.address = addrCtrl.text.toUpperCase().trim();
                } else {
                  _parties.add(Party(name: name, type: pType, phone: phoneCtrl.text.trim(), address: addrCtrl.text.toUpperCase().trim()));
                }
              });
              _commitToLocalDrive();
              if (onCreated != null) onCreated(name);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF10B981), content: Text('$name saved successfully!')));
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(party != null ? 'Edit Party Details' : 'Add New Party', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _customField('Party Name', nameCtrl, onSubmitted: (_) => savePartyAction()),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Party Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 5),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: pType,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          items: ["BUYER", "SELLER", "TRANSPORTER"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setDlgState(() => pType = v!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _customField('Phone', phoneCtrl, isNum: true, onSubmitted: (_) => savePartyAction()),
                const SizedBox(height: 12),
                _customField('Address', addrCtrl, onSubmitted: (_) => savePartyAction()),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: savePartyAction,
                child: Text(party != null ? 'Update Party' : 'Save & Select'),
              ),
            ],
          );
        },
      ),
    );
  }

 // ---------------- 2. TRUCK LOGISTICS VIEW (With Native Horizontal Scroll) ----------------
  Widget _buildTruckLogisticsView() {
    final query = _tSearchCtrl.text.trim().toLowerCase();
    final filtered = _trucks.where((t) {
      return t.state == _selectedState &&
          (query.isEmpty ||
              t.truck.toLowerCase().contains(query) ||
              t.supplier.toLowerCase().contains(query) ||
              t.buyer.toLowerCase().contains(query) ||
              t.transporter.toLowerCase().contains(query) ||
              t.remarks.toLowerCase().contains(query));
    }).toList();

    // Dedicated controller to ensure a visible horizontal scrollbar
    final ScrollController horizontalScroll = ScrollController();

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_editingTruckId != null ? 'Edit Truck Entry' : 'Create Direct Truck Entry', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  if (_editingTruckId != null)
                    TextButton.icon(
                      onPressed: _clearTruckForm,
                      icon: const Icon(Icons.cancel, size: 16, color: Colors.red),
                      label: const Text('Cancel Edit', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _responsiveRow([
                Expanded(child: _customField('Truck Number', _tTruckCtrl, hint: 'TRUCK NO (OPTIONAL)')),
                const SizedBox(width: 12),
                Expanded(child: _customField('Date *', _tDateCtrl, icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_tDateCtrl))),
                const SizedBox(width: 12),
                Expanded(
                  child: _customAutocomplete(
                    'Supplier', _sellerNames, _tSupplier, 'SELECT SELLER',
                    (v) => setState(() => _tSupplier = v),
                    focusNode: _tSupplierFocus,
                    nextFocusNode: _tBuyerFocus,
                    onAddPressed: () => _showAddPartyDialog(initialType: 'SELLER', onCreated: (name) => setState(() => _tSupplier = name)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _customAutocomplete(
                    'Buyer', _buyerNames, _tBuyer, 'SELECT BUYER',
                    (v) => setState(() => _tBuyer = v),
                    focusNode: _tBuyerFocus,
                    nextFocusNode: _tTransporterFocus,
                    onAddPressed: () => _showAddPartyDialog(initialType: 'BUYER', onCreated: (name) => setState(() => _tBuyer = name)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _customAutocomplete(
                    'Transporter', _transporterNames, _tTransporter, 'SELECT TRANSPORTER',
                    (v) => setState(() => _tTransporter = v),
                    focusNode: _tTransporterFocus,
                    nextFocusNode: _tQtyFocus,
                    onAddPressed: () => _showAddPartyDialog(initialType: 'TRANSPORTER', onCreated: (name) => setState(() => _tTransporter = name)),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                // 1. Coconut Type
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Coconut Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          InkWell(
                            onTap: _showManageCommoditiesDialog,
                            child: const Text('+ Manage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _coconutTypes.contains(_tCoconutType) ? _tCoconutType : (_coconutTypes.isNotEmpty ? _coconutTypes.first : null),
                            isExpanded: true,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: _coconutTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _tCoconutType = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 2. Quantity
                Expanded(child: _customField('Quantity (Nuts)', _tQtyCtrl, isNum: true)),
                const SizedBox(width: 12),

                // 3. Bill Amount Field(s)
                if (!_hasCustomBuyerBill) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Bill Amount *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _hasCustomBuyerBill = true;
                                  if (_tBBillCtrl.text.isEmpty || _tBBillCtrl.text == "0") {
                                    _tBBillCtrl.text = _tSBillCtrl.text;
                                  }
                                });
                              },
                              child: const Text('+ Different Buyer Bill', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _tSBillCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              hintText: 'SELLER & BUYER BILL',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF047857), width: 1.5)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Separate Supplier Bill
                  Expanded(child: _customField('Supplier Bill *', _tSBillCtrl, isNum: true)),
                  const SizedBox(width: 12),
                  // Separate Buyer Bill with collapse trigger
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Buyer Bill *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _hasCustomBuyerBill = false;
                                  _tBBillCtrl.clear();
                                });
                              },
                              child: const Text('× Match Seller', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _tBBillCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              hintText: 'BUYER BILL',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF047857), width: 1.5)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 12),

                // 4. Commission & Transport Exp
                Expanded(child: _customField('Commission', _tCommCtrl, isNum: true)),
                const SizedBox(width: 12),
                Expanded(child: _customField('Transport Exp', _tExpCtrl, isNum: true)),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                Expanded(child: _customField('Freight', _tFreightCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Advance', _tAdvCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Freight Balance (Auto)', TextEditingController(text: money((double.tryParse(_tFreightCtrl.text) ?? 0) - (double.tryParse(_tAdvCtrl.text) ?? 0))), readOnly: true)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _customField('Remarks / Notes', _tRemarksCtrl, hint: 'ENTER REMARKS (OPTIONAL)')),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  final double sBill = double.tryParse(_tSBillCtrl.text) ?? 0;
                  // If separate bill is not enabled, mirror sBill to bBill automatically
                  final double bBill = _hasCustomBuyerBill
                      ? (double.tryParse(_tBBillCtrl.text) ?? sBill)
                      : sBill;

                  if (_tSupplier.trim().isEmpty || _tBuyer.trim().isEmpty || _tTransporter.trim().isEmpty || (sBill <= 0 && bBill <= 0)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text('Error: Supplier, Buyer, Transporter, and Bill Amount are mandatory!')));
                    return;
                  }

                  if (_editingTruckId != null) {
                    final idx = _trucks.indexWhere((x) => x.id == _editingTruckId);
                    if (idx != -1) {
                      setState(() {
                        _trucks[idx] = TruckEntry(
                          id: _editingTruckId!, state: _selectedState, date: _tDateCtrl.text.trim(),
                          truck: _tTruckCtrl.text.trim().toUpperCase(), supplier: _tSupplier.trim().toUpperCase(),
                          buyer: _tBuyer.trim().toUpperCase(), transporter: _tTransporter.trim().toUpperCase(),
                          type: _tCoconutType, qty: double.tryParse(_tQtyCtrl.text) ?? 0, supplierBill: sBill, buyerBill: bBill,
                          commission: double.tryParse(_tCommCtrl.text) ?? 500, transportExp: double.tryParse(_tExpCtrl.text) ?? 0,
                          freight: double.tryParse(_tFreightCtrl.text) ?? 0, advance: double.tryParse(_tAdvCtrl.text) ?? 0,
                          isInvoice: false, remarks: _tRemarksCtrl.text.trim().toUpperCase(),
                        );
                        _clearTruckForm();
                      });
                      _commitToLocalDrive();
                      _calculateOverdueBills(_trucks);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Truck entry updated.')));
                    }
                  } else {
                    setState(() {
                      _trucks.add(TruckEntry(
                        id: DateTime.now().millisecondsSinceEpoch.toString(), state: _selectedState, date: _tDateCtrl.text.trim(),
                        truck: _tTruckCtrl.text.trim().toUpperCase(), supplier: _tSupplier.trim().toUpperCase(),
                        buyer: _tBuyer.trim().toUpperCase(), transporter: _tTransporter.trim().toUpperCase(),
                        type: _tCoconutType, qty: double.tryParse(_tQtyCtrl.text) ?? 0, supplierBill: sBill, buyerBill: bBill,
                        commission: double.tryParse(_tCommCtrl.text) ?? 500, transportExp: double.tryParse(_tExpCtrl.text) ?? 0,
                        freight: double.tryParse(_tFreightCtrl.text) ?? 0, advance: double.tryParse(_tAdvCtrl.text) ?? 0,
                        isInvoice: false, remarks: _tRemarksCtrl.text.trim().toUpperCase(),
                      ));
                      _clearTruckForm();
                    });
                    _commitToLocalDrive();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Truck entry saved.')));
                  }
                },
                child: Text(_editingTruckId != null ? 'Update Truck Entry' : 'Save Truck'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Logistics Records — $_selectedState', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  SizedBox(
                    width: 260,
                    height: 38,
                    child: TextField(
                      controller: _tSearchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search truck, party...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: SizedBox(
                    height: isMobile ? 360 : 480,
                    width: double.infinity,
                    child: Scrollbar(
                      controller: horizontalScroll,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 8.0,
                      child: SingleChildScrollView(
                        controller: horizontalScroll,
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16.0), // Padding to prevent scrollbar overlapping data
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                              columns: const [
                                DataColumn(label: Text('DATE', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('TRUCK/INV', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('SUPPLIER', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('BUYER', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('QTY', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('SUPPLIER BILL', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('BUYER BILL', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('FREIGHT BAL', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                                DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              ],
                              rows: filtered.map((t) => DataRow(cells: [
                                DataCell(Text(t.date)),
                                DataCell(Text(t.isInvoice ? 'INV: ${t.truck}' : t.truck, style: TextStyle(fontWeight: FontWeight.bold, color: t.isInvoice ? const Color(0xFF047857) : Colors.black))),
                                DataCell(Text(t.supplier)),
                                DataCell(Text(t.buyer)),
                                DataCell(Text('${numFmt(t.qty)} NUTS')),
                                DataCell(Text(money(t.supplierBill))),
                                DataCell(Text(money(t.buyerBill))),
                                DataCell(Text(money(t.balance), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.edit, size: 16, color: Color(0xFF047857)), onPressed: () => _editFromReport(t)),
                                    IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () {
                                      setState(() => _trucks.remove(t));
                                      _commitToLocalDrive();
                                    }),
                                  ],
                                )),
                              ])).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- INVOICE VIEW & MODERN CANVAS ----------------
  Widget _buildInvoiceView() {
    Widget formBox = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_editingInvoiceId != null ? 'Edit Tax Invoice' : 'Invoice Details', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              if (_editingInvoiceId != null)
                TextButton.icon(
                  onPressed: _clearInvoiceForm,
                  icon: const Icon(Icons.cancel, size: 16, color: Colors.red),
                  label: const Text('Cancel Edit', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _responsiveRow([
            Expanded(child: _customField('Invoice No.', _iNoCtrl, readOnly: true)),
            const SizedBox(width: 12),
            Expanded(child: _customField('Invoice Date', _iDateCtrl, icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_iDateCtrl))),
            const SizedBox(width: 12),
            Expanded(
              child: _customAutocomplete('Buyer *', _buyerNames, _iBuyer, 'SELECT BUYER', (val) {
                setState(() {
                  _iBuyer = val;
                  final matched = _parties.firstWhere((p) => p.name == val, orElse: () => Party(name: "", type: "", phone: "", address: ""));
                  if (matched.address.isNotEmpty) _iAddressCtrl.text = matched.address;
                  if (matched.phone.isNotEmpty) _iPhoneCtrl.text = matched.phone;
                });
              }, onAddPressed: () => _showAddPartyDialog(initialType: 'BUYER', onCreated: (name) => setState(() {
                  _iBuyer = name;
                  final matched = _parties.firstWhere((p) => p.name == name, orElse: () => Party(name: "", type: "", phone: "", address: ""));
                  if (matched.address.isNotEmpty) _iAddressCtrl.text = matched.address;
                  if (matched.phone.isNotEmpty) _iPhoneCtrl.text = matched.phone;
              }))),
            ),
          ]),
          const SizedBox(height: 12),
          _responsiveRow([
            Expanded(child: _customAutocomplete('Seller', _sellerNames, _iSeller, 'SELECT SELLER', (v) => setState(() => _iSeller = v), onAddPressed: () => _showAddPartyDialog(initialType: 'SELLER', onCreated: (name) => setState(() => _iSeller = name)))),
            const SizedBox(width: 12),
            Expanded(child: _customField('SELLER AMOUNT (MANUAL)', _iSellerAmountCtrl, isNum: true)),
            const SizedBox(width: 12),
            Expanded(child: _customAutocomplete('Transporter', _transporterNames, _iTransporter, 'SELECT TRANSPORTER', (v) => setState(() => _iTransporter = v), onAddPressed: () => _showAddPartyDialog(initialType: 'TRANSPORTER', onCreated: (name) => setState(() => _iTransporter = name)))),
          ]),
          const SizedBox(height: 12),
          _responsiveRow([
            Expanded(child: _customField('Transport Expense', _iTransportExpCtrl, isNum: true)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Divisor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 5),
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<double>(
                        value: _iDivisor,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        items: const [DropdownMenuItem(value: 1000, child: Text('1000')), DropdownMenuItem(value: 1010, child: Text('1010')), DropdownMenuItem(value: 1020, child: Text('1020'))],
                        onChanged: (val) => setState(() => _iDivisor = val!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payment Terms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 5),
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _iTerms,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        items: const [DropdownMenuItem(value: 'CASH', child: Text('CASH')), DropdownMenuItem(value: 'CREDIT (15 DAYS)', child: Text('CREDIT (15 DAYS)')), DropdownMenuItem(value: 'CREDIT (30 DAYS)', child: Text('CREDIT (30 DAYS)'))],
                        onChanged: (val) => setState(() => _iTerms = val!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _customField('Buyer Address', _iAddressCtrl, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _responsiveRow([
            Expanded(child: _customField('Telephone', _iPhoneCtrl, isNum: true, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: _customField('Lorry No.', _iLorryCtrl, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: _customField('Driver No.', _iDriverCtrl, isNum: true, onChanged: (_) => setState(() {}))),
          ]),
          const SizedBox(height: 18),
          const Text('Goods Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 10),
          ..._invoiceGoods.asMap().entries.map((entry) {
            final idx = entry.key; final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(flex: 4, child: _customField(idx == 0 ? 'Description' : '', item.descCtrl, hint: 'COCONUT')),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _customField(idx == 0 ? 'Qty (Nuts)' : '', item.qtyCtrl, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _customField(idx == 0 ? 'Rate (₹)' : '', item.rateCtrl, isNum: true)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _customField(
                      idx == 0 ? 'Amount' : '',
                      TextEditingController(text: item.calculateAmount(_iDivisor) > 0 ? money(item.calculateAmount(_iDivisor)) : ''),
                      readOnly: true,
                    ),
                  ),
                  if (_invoiceGoods.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red, size: 18),
                      onPressed: () {
                        setState(() {
                          final removed = _invoiceGoods.removeAt(idx);
                          removed.dispose();
                        });
                      },
                    ),
                ],
              ),
            );
          }),
          OutlinedButton(
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => setState(() => _addGoodsRow()),
            child: const Text('+ Add Goods'),
          ),
          const SizedBox(height: 18),
          const Text('Charges & Levies', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 10),
          Table(
            columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(4), 2: FlexColumnWidth(2.5)},
            border: TableBorder.all(color: const Color(0xFFE2E8F0)),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                children: const [
                  Padding(padding: EdgeInsets.all(8), child: Text('CHARGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                  Padding(padding: EdgeInsets.all(8), child: Text('INPUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                  Padding(padding: EdgeInsets.all(8), child: Text('AMOUNT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                ],
              ),
              TableRow(children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('Gunnies', style: TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.all(6), child: Row(children: [Expanded(child: _chargeInlineField(_iBagsCtrl, '0', isNum: true)), const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('×')), Expanded(child: _chargeInlineField(_iBagRateCtrl, '0', isNum: true))])),
                Padding(padding: const EdgeInsets.all(8), child: Text(money(_invGunniesAmount), style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              TableRow(children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('Loading', style: TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.all(6), child: _iLoadingManual ? _chargeInlineField(_iLoadManualAmountCtrl, 'Amt', isNum: true) : _chargeInlineField(_iLoadRateCtrl, 'Rate/1000', isNum: true)),
                Padding(padding: const EdgeInsets.all(8), child: Text(money(_invLoadingAmount), style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              TableRow(children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('AMC', style: TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.all(6), child: _chargeInlineField(_iAmcCtrl, '0', isNum: true)),
                Padding(padding: const EdgeInsets.all(8), child: Text(money(_invAmc), style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              TableRow(children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('Insurance', style: TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.all(6), child: _chargeInlineField(_iInsCtrl, '0', isNum: true)),
                Padding(padding: const EdgeInsets.all(8), child: Text(money(_invInsurance), style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              TableRow(children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('Commission', style: TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.all(6), child: _chargeInlineField(_iCommCtrl, '0', isNum: true)),
                Padding(padding: const EdgeInsets.all(8), child: Text(money(_invCommission), style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              TableRow(children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('Advance', style: TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.all(6), child: _chargeInlineField(_iAdvCtrl, '0', isNum: true)),
                Padding(padding: const EdgeInsets.all(8), child: Text(money(_invAdvance), style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
            ],
          ),
          const SizedBox(height: 18),
          _responsiveRow([
            Expanded(child: _customField('Freight (Manual)', _iFreightCtrl, isNum: true, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: _customField('Truck Advance', TextEditingController(text: money(_invAdvance)), readOnly: true)),
            const SizedBox(width: 12),
            Expanded(child: _customField('Balance (Auto)', TextEditingController(text: money(_invTruckBalance)), readOnly: true)),
          ]),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _saveInvoice,
                child: Text(_editingInvoiceId != null ? 'Update Invoice' : 'Save Invoice'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF062317), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _openPrintPreviewModal,
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text('Print Preview (A4)'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _clearInvoiceForm,
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );

    Widget previewBox = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Live Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              TextButton.icon(onPressed: _openPrintPreviewModal, icon: const Icon(Icons.fullscreen, size: 16), label: const Text('Full Screen')),
            ],
          ),
          const SizedBox(height: 12),
          _buildPrintableInvoicePaper(),
        ],
      ),
    );

    return isMobile ? Column(children: [formBox, const SizedBox(height: 16), previewBox]) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: formBox), const SizedBox(width: 16), Expanded(flex: 5, child: previewBox)]);
  }

  void _saveInvoice() {
    if (_iBuyer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buyer is required.')));
      return;
    }
    if (_editingInvoiceId != null) {
      final idx = _trucks.indexWhere((x) => x.id == _editingInvoiceId);
      if (idx != -1) {
        setState(() {
          _trucks[idx] = TruckEntry(
            id: _editingInvoiceId!, state: _selectedState, date: _iDateCtrl.text.trim(),
            truck: _iLorryCtrl.text.trim().toUpperCase().isEmpty ? "—" : _iLorryCtrl.text.trim().toUpperCase(),
            supplier: _iSeller.trim().toUpperCase().isEmpty ? "—" : _iSeller.trim().toUpperCase(),
            buyer: _iBuyer.trim().toUpperCase(),
            transporter: _iTransporter.trim().toUpperCase().isEmpty ? "—" : _iTransporter.trim().toUpperCase(),
            type: "COCONUT", qty: _invTotalGoodsQty,
            supplierBill: double.tryParse(_iSellerAmountCtrl.text) ?? 0, buyerBill: _invGrandTotal,
            commission: _invCommission > 0 ? _invCommission : 500, transportExp: double.tryParse(_iTransportExpCtrl.text) ?? 0,
            freight: _invFreight, advance: _invAdvance, isInvoice: true,
            rate: _invoiceGoods.isNotEmpty ? _invoiceGoods.first.rate : 0, bags: double.tryParse(_iBagsCtrl.text) ?? 0, bagRate: double.tryParse(_iBagRateCtrl.text) ?? 0, loadRate: double.tryParse(_iLoadRateCtrl.text) ?? 0, insurance: double.tryParse(_iInsCtrl.text) ?? 0, amc: double.tryParse(_iAmcCtrl.text) ?? 0, isLoadManual: _iLoadingManual, loadManualAmt: double.tryParse(_iLoadManualAmountCtrl.text) ?? 0,
          );
          _clearInvoiceForm();
        });
        _commitToLocalDrive();
        _calculateOverdueBills(_trucks);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice updated.')));
        return;
      }
    }

    setState(() {
      _trucks.add(TruckEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(), state: _selectedState, date: _iDateCtrl.text.trim(),
        truck: _iLorryCtrl.text.trim().toUpperCase().isEmpty ? "—" : _iLorryCtrl.text.trim().toUpperCase(),
        supplier: _iSeller.trim().toUpperCase().isEmpty ? "—" : _iSeller.trim().toUpperCase(),
        buyer: _iBuyer.trim().toUpperCase(),
        transporter: _iTransporter.trim().toUpperCase().isEmpty ? "—" : _iTransporter.trim().toUpperCase(),
        type: "COCONUT", qty: _invTotalGoodsQty,
        supplierBill: double.tryParse(_iSellerAmountCtrl.text) ?? 0, buyerBill: _invGrandTotal,
        commission: _invCommission > 0 ? _invCommission : 500, transportExp: double.tryParse(_iTransportExpCtrl.text) ?? 0,
        freight: _invFreight, advance: _invAdvance, isInvoice: true,
        rate: _invoiceGoods.isNotEmpty ? _invoiceGoods.first.rate : 0, bags: double.tryParse(_iBagsCtrl.text) ?? 0, bagRate: double.tryParse(_iBagRateCtrl.text) ?? 0, loadRate: double.tryParse(_iLoadRateCtrl.text) ?? 0, insurance: double.tryParse(_iInsCtrl.text) ?? 0, amc: double.tryParse(_iAmcCtrl.text) ?? 0, isLoadManual: _iLoadingManual, loadManualAmt: double.tryParse(_iLoadManualAmountCtrl.text) ?? 0,
      ));
      int currentNum = int.tryParse(_iNoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
      _iNoCtrl.text = "INV-${(currentNum + 1).toString().padLeft(5, '0')}";
      _clearInvoiceForm();
    });
    _commitToLocalDrive();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice saved to database!')));
  }

  void _openPrintPreviewModal() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 920, height: 820, padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Print Preview (A4)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const Divider(),
              Expanded(
                child: PdfPreview(
                  build: (format) => _generatePdfInvoice(format),
                  canChangeOrientation: false, canChangePageFormat: false, canDebug: false, allowSharing: true, allowPrinting: true,
                  initialPageFormat: PdfPageFormat.a4, pdfFileName: '${_iNoCtrl.text}.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePdfInvoice(PdfPageFormat format) async {
    final pdf = pw.Document();
    final prefs = await SharedPreferences.getInstance();
    final customLogoPath = prefs.getString('custom_logo_path');
    pw.MemoryImage? logoImage;
    if (customLogoPath != null && customLogoPath.trim().isNotEmpty && customLogoPath != 'NONE' && await File(customLogoPath).exists()) {
      try {
        final Uint8List customBytes = await File(customLogoPath).readAsBytes();
        logoImage = pw.MemoryImage(customBytes);
      } catch (_) { logoImage = null; }
    }

    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 18), build: (ctx) => _buildPdfPageContent("ORIGINAL", logoImage)));
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 18), build: (ctx) => _buildPdfPageContent("DUPLICATE", logoImage)));
    return pdf.save();
  }

  pw.Widget _buildPdfPageContent(String copyLabel, pw.MemoryImage? logoImage) {
    const greenBorder = PdfColor.fromInt(0xFF4D8B61); 
    const titleGreen = PdfColor.fromInt(0xFF126B35); 
    const redAccent = PdfColor.fromInt(0xFFBD2020);
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1.8))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch, 
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Stack(
                children: [
                  pw.Align(
                    alignment: pw.Alignment.topCenter,
                    child: pw.Text(
                      _myCompany.invocation.isNotEmpty ? _myCompany.invocation : 'Om Sri Ganesaya Namaha', 
                      style: pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic, color: titleGreen),
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.topRight,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: _myCompany.phone.split(',').map((num) => 
                        pw.Text('Cell : ${num.trim()}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))
                      ).toList(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(copyLabel, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: titleGreen))),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  if (logoImage != null) ...[
                    pw.Image(logoImage, width: 34, height: 34),
                    pw.SizedBox(width: 8),
                  ],
                  pw.Text(_myCompany.name, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: titleGreen, letterSpacing: 0.5)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Center(child: pw.Text(_myCompany.tagline, style: pw.TextStyle(fontSize: 11, letterSpacing: 4, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 3),
              pw.Center(child: pw.Text(_myCompany.address, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: redAccent))),
              pw.SizedBox(height: 6),
              pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 4), decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: greenBorder, width: 1), bottom: pw.BorderSide(color: greenBorder, width: 1))), child: pw.Center(child: pw.Text('AS PER G.O.MS.No.575(AP VAT)    Dt. 4-4-2008    COCONUT EXEMPTED FROM TAX\nG.O.MS.No.576(CST)', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)))),
            ],
          ),
          pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 5), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: greenBorder, width: 1))), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Invoice No. ${_iNoCtrl.text.toUpperCase()}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)), pw.Text('Date : ${_iDateCtrl.text.toUpperCase()}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))])),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: greenBorder, width: 1))),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(flex: 6, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("Buyer's Name : ${_iBuyer.isEmpty ? '-' : _iBuyer.toUpperCase()}", style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 3), pw.Text("Address : ${_iAddressCtrl.text.isEmpty ? '-' : _iAddressCtrl.text.toUpperCase()}", style: const pw.TextStyle(fontSize: 10)), pw.SizedBox(height: 3), pw.Text("Telephone No. : ${_iPhoneCtrl.text.isEmpty ? '-' : _iPhoneCtrl.text}", style: const pw.TextStyle(fontSize: 10))])),
                pw.Container(width: 1, height: 46, color: greenBorder), pw.SizedBox(width: 10),
                pw.Expanded(flex: 4, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("Terms : ${_iTerms.toUpperCase()}", style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 3), pw.Text("Lorry No. : ${_iLorryCtrl.text.isEmpty ? '-' : _iLorryCtrl.text.toUpperCase()}", style: const pw.TextStyle(fontSize: 10)), pw.SizedBox(height: 3), pw.Text("Driver No. : ${_iDriverCtrl.text.isEmpty ? '-' : _iDriverCtrl.text}", style: const pw.TextStyle(fontSize: 10))])),
              ],
            ),
          ),
          pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
            child: pw.Table(
              border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: greenBorder, width: 1), verticalInside: pw.BorderSide(color: greenBorder, width: 1)),
              children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F7F3)), children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('#', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Description of Goods', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Quantity (Nos.)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rate (Rs)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Amount (Rs)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)))]),
                ..._invoiceGoods.asMap().entries.map((e) => pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${e.key + 1}', style: const pw.TextStyle(fontSize: 10))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(e.value.description.toUpperCase(), style: const pw.TextStyle(fontSize: 10))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${numFmt(e.value.qty)} NUTS', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(pdfMoney(e.value.rate), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(pdfMoney(e.value.calculateAmount(_iDivisor)), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)))])),
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7FAF8)), children: [pw.SizedBox(), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Total Quantity', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${numFmt(_invTotalGoodsQty)} NUTS', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Total Goods Amount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(pdfMoney(_invTotalGoodsAmount), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)))]),
              ],
            ),
          ),
          pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Amount in Words :', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 3), pw.Text(wordsToIndian(_invGrandTotal), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen))]),
                        pw.SizedBox(height: 24),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(5), 
                          decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))), 
                          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Freight ${pdfMoney(_invFreight)}', style: const pw.TextStyle(fontSize: 8.5)), pw.Text('Adv ${pdfMoney(_invAdvance)}', style: const pw.TextStyle(fontSize: 8.5)), pw.Text('Bal ${pdfMoney(_invTruckBalance)}', style: const pw.TextStyle(fontSize: 8.5))])
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Container(width: 1, height: 105, color: greenBorder),
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    children: [
                      pw.Container(color: const PdfColor.fromInt(0xFFF3F7F4), padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 6), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Particulars', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)), pw.Text('Amount (Rs)', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))])),
                      _pdfParticularRow('Gunnies', pdfMoney(_invGunniesAmount)), _pdfParticularRow('Loading Charges', pdfMoney(_invLoadingAmount)), _pdfParticularRow('AMC', pdfMoney(_invAmc)), _pdfParticularRow('Insurance', pdfMoney(_invInsurance)), _pdfParticularRow('Commission', pdfMoney(_invCommission)), _pdfParticularRow('Truck Advance', pdfMoney(_invAdvance)),
                      pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F7F4), border: pw.Border(top: pw.BorderSide(color: greenBorder, width: 1))), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total Charges', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)), pw.Text(pdfMoney(_invTotalCharges), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12), decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F8F3), border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1.5))), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('TOTAL INVOICE AMOUNT', style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: titleGreen)), pw.Text('Rs. ${pdfMoney(_invGrandTotal)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: titleGreen))])),
          pw.Container(
            padding: const pw.EdgeInsets.all(7), decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 5, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Bank Name : ${_selectedBank.name}', style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)), pw.Text('A/c No. : ${_selectedBank.account}', style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)), pw.Text('IFSC Code : ${_selectedBank.ifsc}', style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)), pw.Text('Branch : ${_selectedBank.branch}', style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))])),
                pw.Container(width: 1, height: 42, color: greenBorder), pw.SizedBox(width: 6),
                pw.Expanded(flex: 5, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Rupees : ${wordsToIndian(_invGrandTotal)}', style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 4), pw.Text(_selectedBank.note, style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic))])),
              ],
            ),
          ),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Customer Signature', style: const pw.TextStyle(fontSize: 9)), pw.Text('For ${_myCompany.name}', style: const pw.TextStyle(fontSize: 9))])),
        ],
      ),
    );
  }

  pw.Widget _pdfParticularRow(String label, String value) {
    return pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2.5), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)), pw.Text(value, style: const pw.TextStyle(fontSize: 8.5))]));
  }

  Widget _particularRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 9)), Text(value, style: const TextStyle(fontSize: 9))]));
  }

  Widget _chargeInlineField(TextEditingController ctrl, String hint, {bool isNum = false}) {
    return SizedBox(
      height: 28,
      child: TextField(
        controller: ctrl, inputFormatters: isNum ? null : [UpperCaseTextFormatter()], keyboardType: isNum ? TextInputType.number : TextInputType.text, onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        decoration: InputDecoration(hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFE2E8F0))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF047857))), filled: true, fillColor: Colors.white),
      ),
    );
  }

  Widget _buildPrintableInvoicePaper() {
    return Container(
      padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF4D8B61), width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: Text('Om Sri Ganesaya Namaha', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Color(0xFF17231B)))), const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 80),
              const Text('TAX INVOICE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF126B35))),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _myCompany.phone.split(',').map((num) => 
                  Text('Cell : ${num.trim()}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF17231B)))
                ).toList(),
              ),
            ],
          ),
          Center(child: Text(_myCompany.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF126B35)))), const SizedBox(height: 3),
          Center(child: Text(_myCompany.tagline, style: const TextStyle(fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.w600, color: Color(0xFF17231B)))), const SizedBox(height: 3),
          Center(child: Text(_myCompany.address, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFBD2020)))), const SizedBox(height: 6),
          Container(padding: const EdgeInsets.symmetric(vertical: 4), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF4D8B61)), bottom: BorderSide(color: Color(0xFF4D8B61)))), child: const Text('AS PER G.O.MS.No.575(AP VAT)    Dt. 4-4-2008    COCONUT EXEMPTED FROM TAX\nG.O.MS.No.576(CST)', textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Color(0xFF17231B)))),
          Container(padding: const EdgeInsets.symmetric(vertical: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF4D8B61)))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Invoice No. ${_iNoCtrl.text.toUpperCase()}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)), Text('Date : ${_iDateCtrl.text.toUpperCase()}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold))])),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF4D8B61)))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Buyer's Name : ${_iBuyer.isEmpty ? '—' : _iBuyer.toUpperCase()}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text("Address : ${_iAddressCtrl.text.isEmpty ? '—' : _iAddressCtrl.text.toUpperCase()}", style: const TextStyle(fontSize: 9.5)), const SizedBox(height: 2), Text("Telephone No. : ${_iPhoneCtrl.text.isEmpty ? '—' : _iPhoneCtrl.text}", style: const TextStyle(fontSize: 9.5))])),
                Container(width: 1, height: 45, color: const Color(0xFF4D8B61)), const SizedBox(width: 8),
                Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Terms : ${_iTerms.toUpperCase()}", style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text("Lorry No. : ${_iLorryCtrl.text.isEmpty ? '—' : _iLorryCtrl.text.toUpperCase()}", style: const TextStyle(fontSize: 9.5)), const SizedBox(height: 2), Text("Driver No. : ${_iDriverCtrl.text.isEmpty ? '—' : _iDriverCtrl.text}", style: const TextStyle(fontSize: 9.5))])),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF4D8B61))),
            child: Column(
              children: [
                Container(color: const Color(0xFFF2F7F3), padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6), child: Row(children: const [SizedBox(width: 20, child: Text('#', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))), Expanded(flex: 4, child: Text('Description of Goods', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))), Expanded(flex: 2, child: Text('Quantity (Nos.)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.right)), Expanded(flex: 2, child: Text('Rate (₹)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.right)), Expanded(flex: 2, child: Text('Amount (₹)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.right))])),
                const Divider(height: 1, color: Color(0xFF4D8B61)),
                ..._invoiceGoods.asMap().entries.map((e) {
                  final i = e.key; final item = e.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                    child: Row(children: [SizedBox(width: 20, child: Text('${i + 1}', style: const TextStyle(fontSize: 9.5))), Expanded(flex: 4, child: Text(item.description.toUpperCase(), style: const TextStyle(fontSize: 9.5))), Expanded(flex: 2, child: Text('${numFmt(item.qty)} NUTS', style: const TextStyle(fontSize: 9.5), textAlign: TextAlign.right)), Expanded(flex: 2, child: Text(money(item.rate), style: const TextStyle(fontSize: 9.5), textAlign: TextAlign.right)), Expanded(flex: 2, child: Text(money(item.calculateAmount(_iDivisor)), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold), textAlign: TextAlign.right))]),
                  );
                }),
                const Divider(height: 1, color: Color(0xFF4D8B61)),
                Container(color: const Color(0xFFF7FAF8), padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6), child: Row(children: [const SizedBox(width: 20), const Expanded(flex: 4, child: Text('Total Quantity', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold))), Expanded(flex: 2, child: Text('${numFmt(_invTotalGoodsQty)} NUTS', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold), textAlign: TextAlign.right)), const Expanded(flex: 2, child: Text('Total Goods Amount', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.right)), Expanded(flex: 2, child: Text(money(_invTotalGoodsAmount), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold), textAlign: TextAlign.right))])),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF4D8B61))),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: Padding(padding: const EdgeInsets.all(6.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Amount in Words :', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(wordsToIndian(_invGrandTotal), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF064E3B)))]), Container(decoration: BoxDecoration(border: Border.all(color: const Color(0xFF4D8B61))), padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Freight ${money(_invFreight)}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)), Text('Adv ${money(_invAdvance)}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)), Text('Bal ${money(_invTruckBalance)}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold))]))]))),
                  Container(width: 1, color: const Color(0xFF4D8B61)),
                  Expanded(flex: 5, child: Column(children: [Container(color: const Color(0xFFF3F7F4), padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Particulars', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)), Text('Amount (₹)', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold))])), _particularRow('Gunnies', money(_invGunniesAmount)), _particularRow('Loading Charges', money(_invLoadingAmount)), _particularRow('AMC', money(_invAmc)), _particularRow('Insurance', money(_invInsurance)), _particularRow('Commission', money(_invCommission)), _particularRow('Truck Advance', money(_invAdvance)), Container(color: const Color(0xFFF3F7F4), padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total Charges', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)), Text(money(_invTotalCharges), style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold))]))])),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8), decoration: BoxDecoration(color: const Color(0xFFF1F8F3), border: Border.all(color: const Color(0xFF4D8B61), width: 1.5)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL INVOICE AMOUNT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF16773A))), Text(money(_invGrandTotal), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF16773A)))])),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(border: Border.all(color: const Color(0xFF4D8B61))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Bank Name : ${_selectedBank.name}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)), Text('A/c No. : ${_selectedBank.account}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)), Text('IFSC Code : ${_selectedBank.ifsc}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)), Text('Branch : ${_selectedBank.branch}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold))])), Container(width: 1, height: 42, color: const Color(0xFF4D8B61)), const SizedBox(width: 6), Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Rupees : ${wordsToIndian(_invGrandTotal)}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(_selectedBank.note, style: const TextStyle(fontSize: 8, fontStyle: FontStyle.italic))]))])),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Customer Signature', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)), Text('For ${_myCompany.name}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold))]),
        ],
      ),
    );
  }

  // ---------------- PAYMENTS VIEW (ALIGNED + SEARCHABLE) ----------------
  Widget _buildPaymentsView() {
    final query = _paySearchCtrl.text.trim().toLowerCase();
    final payList = _payments.where((p) {
      final matchesState = p.state == _selectedState;
      final matchesQuery = query.isEmpty ||
          p.party.toLowerCase().contains(query) ||
          p.type.toLowerCase().contains(query) ||
          p.mode.toLowerCase().contains(query) ||
          p.date.toLowerCase().contains(query) ||
          p.amount.toString().contains(query);
      return matchesState && matchesQuery;
    }).toList();

    final ScrollController payScroll = ScrollController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Transaction Entry Card
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Record Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 16),
              _responsiveRow([
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Transaction Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      const SizedBox(height: 5),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _payType,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: ["PAYMENT TO SELLER", "RECEIPT FROM BUYER"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _payType = val!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _customAutocomplete('Seller / Supplier', _sellerNames, _paySeller, 'SELECT SELLER', (val) => setState(() => _paySeller = val))),
                const SizedBox(width: 12),
                Expanded(child: _customAutocomplete('Buyer', _buyerNames, _payBuyer, 'SELECT BUYER', (val) => setState(() => _payBuyer = val))),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                Expanded(child: _customField(_payType.contains("SELLER") ? 'Amount Paid' : 'Amount Received', _payAmountCtrl, hint: '₹ AMOUNT', isNum: true)),
                const SizedBox(width: 12),
                Expanded(child: _customField('Transport Received', _payTransportReceivedCtrl, isNum: true)),
                const SizedBox(width: 12),
                Expanded(child: _customField('Discount / Settlement', _paySettlementCtrl, isNum: true)),
                const SizedBox(width: 12),
                Expanded(child: _customField('Commission Adjusted', _payCommAdjustedCtrl, hint: '0', isNum: true)),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      const SizedBox(height: 5),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _payMode,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: ["DIRECT", "CASH", "ICICI BANK", "KOTAK BANK", "STATE BANK OF INDIA"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _payMode = val!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _customField('Date', _payDateCtrl, icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_payDateCtrl))),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), minimumSize: const Size(double.infinity, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        final double amt = double.tryParse(_payAmountCtrl.text) ?? 0;
                        final double disc = double.tryParse(_paySettlementCtrl.text) ?? 0;
                        final double commAdj = double.tryParse(_payCommAdjustedCtrl.text) ?? 0;

                        if (amt == 0 && disc == 0 && commAdj == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an amount, discount, or commission adjustment.')));
                          return;
                        }

                        setState(() {
                          _payments.add(PaymentEntry(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            state: _selectedState, type: _payType,
                            seller: _paySeller.toUpperCase().trim(), buyer: _payBuyer.toUpperCase().trim(),
                            amount: amt, transportReceived: double.tryParse(_payTransportReceivedCtrl.text) ?? 0,
                            settlement: disc, commissionAdjusted: commAdj, mode: _payMode, date: _payDateCtrl.text.trim(),
                          ));
                          _payAmountCtrl.clear();
                          _payTransportReceivedCtrl.text = "0";
                          _paySettlementCtrl.text = "0";
                          _payCommAdjustedCtrl.text = "0";
                          _paySeller = ""; _payBuyer = "";
                        });
                        _commitToLocalDrive();
                        _calculateOverdueBills(_trucks);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment entry recorded.')));
                      },
                      child: const Text('Record Transaction'),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Searchable Ledger History Card
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ledger History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  SizedBox(
                    width: isMobile ? 180 : 260,
                    height: 38,
                    child: TextField(
                      controller: _paySearchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search ledger...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: SizedBox(
                    height: isMobile ? 360 : 460,
                    width: double.infinity,
                    child: Scrollbar(
                      controller: payScroll,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        controller: payScroll,
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                            columns: const [
                              DataColumn(label: Text('DATE', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              DataColumn(label: Text('TYPE', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              DataColumn(label: Text('PARTY', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              DataColumn(label: Text('AMOUNT', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              DataColumn(label: Text('MODE', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              DataColumn(label: Text('DISCOUNT', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                              DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
                            ],
                            rows: payList.map((p) {
                              final bool isSeller = p.type.contains("SELLER");
                              return DataRow(cells: [
                                DataCell(Text(p.date)),
                                DataCell(Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isSeller ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isSeller ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0)),
                                  ),
                                  child: Text(p.type, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isSeller ? const Color(0xFFB45309) : const Color(0xFF047857))),
                                )),
                                DataCell(Text(p.party.isEmpty ? '—' : p.party, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(p.mode)),
                                DataCell(Text(money(p.settlement))),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.edit, color: Color(0xFF047857), size: 18), onPressed: () => _editPaymentEntryDialog(p)),
                                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18), onPressed: () {
                                      setState(() => _payments.remove(p));
                                      _commitToLocalDrive();
                                    }),
                                  ],
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  
  // ---------------- 5. REPORTS VIEW ----------------
  Widget _buildReportsView() {
    final fyStart = _getFYStartDate(_selectedFinancialYear);

    Widget _tableHeader(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
    );

    Widget _tableData(String text, {bool isBold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color ?? const Color(0xFF1E293B))),
    );

    double sellerOpeningDue = 0;
    if (_repSeller.isNotEmpty) {
      final priorBilled = _trucks
          .where((t) => t.state == _selectedState && t.supplier.toUpperCase() == _repSeller.toUpperCase() && parseFlexibleDate(t.date).isBefore(fyStart))
          .fold(0.0, (s, t) => s + t.supplierBill);
      final priorPaid = _payments
          .where((p) => p.state == _selectedState && p.seller.toUpperCase() == _repSeller.toUpperCase() && parseFlexibleDate(p.date).isBefore(fyStart))
          .fold(0.0, (s, p) => s + p.amount + p.settlement);
      sellerOpeningDue = priorBilled - priorPaid;
    }

    final sellerTrucks = _trucks.where((t) {
      return t.state == _selectedState &&
          (_repSeller.isEmpty || t.supplier.toUpperCase() == _repSeller.toUpperCase()) &&
          (_repSellerBuyerFilter.isEmpty || t.buyer.toUpperCase() == _repSellerBuyerFilter.toUpperCase()) &&
          _isDateInFY(t.date, _selectedFinancialYear) &&
          isDateInRange(t.date, _repSellerFromCtrl.text, _repSellerToCtrl.text);
    }).toList();
    sellerTrucks.sort((a, b) => parseFlexibleDate(a.date).compareTo(parseFlexibleDate(b.date)));

    final sellerPayments = _payments.where((p) {
      return p.state == _selectedState &&
          (p.type.contains("SELLER") || p.mode == "DIRECT") &&
          (_repSeller.isEmpty || p.seller.toUpperCase() == _repSeller.toUpperCase()) &&
          (_repSellerBuyerFilter.isEmpty || p.buyer.toUpperCase() == _repSellerBuyerFilter.toUpperCase()) &&
          _isDateInFY(p.date, _selectedFinancialYear);
    }).toList();
    sellerPayments.sort((a, b) => parseFlexibleDate(a.date).compareTo(parseFlexibleDate(b.date)));

    final double sTotalQty = sellerTrucks.fold<double>(0.0, (sum, t) => sum + t.qty);
    final double sTotalComm = sellerTrucks.fold<double>(0.0, (sum, t) => sum + t.commission);
    final double sTotalBilled = sellerTrucks.fold<double>(0.0, (sum, t) => sum + t.supplierBill) + (sellerOpeningDue > 0 ? sellerOpeningDue : 0.0);
    final double sTotalPaid = sellerPayments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final double sDiscount = sellerPayments.fold<double>(0.0, (sum, p) => sum + p.settlement);
    final double sCommissionAdjusted = sellerPayments.fold<double>(0.0, (sum, p) => sum + p.commissionAdjusted);
    final double sBalanceDue = sTotalBilled - sTotalPaid - sDiscount - sCommissionAdjusted;

    final double sCommRate = double.tryParse(_repSellerCommRateCtrl.text) ?? 0;
    final double sCalculatedQtyComm = (_repSellerCommDivisor > 0 && sCommRate > 0)
        ? ((sTotalQty * sCommRate) / _repSellerCommDivisor).roundToDouble()
        : 0;
    final double sCombinedTotalCommission = sCalculatedQtyComm + sTotalComm;

    List<Map<String, dynamic>> sellerReportRows = [];
    List<PaymentEntry> unallocatedSellerPayments = List.from(sellerPayments);

    if (sellerOpeningDue > 0) {
      sellerReportRows.add({
        'truck': TruckEntry(id: 'VIRTUAL_OB', state: _selectedState, date: '01-04-${(fyStart.year % 100).toString().padLeft(2, '0')}', truck: 'B/F', supplier: _repSeller, buyer: 'PREVIOUS YEAR DUE', transporter: '—', type: 'OPENING BAL', qty: 0, supplierBill: sellerOpeningDue, buyerBill: 0, commission: 0, transportExp: 0, freight: 0, advance: 0),
        'payments': <dynamic>[],
        'date': '01-04-${(fyStart.year % 100).toString().padLeft(2, '0')}',
        'buyer': 'OPENING BALANCE (B/F)',
        'qty': '0', 'commission': '₹0', 'sellerBill': money(sellerOpeningDue), 'balance': money(sellerOpeningDue),
      });
    }

    for (int i = 0; i < sellerTrucks.length; i++) {
      final t = sellerTrucks[i];
      List<dynamic> matchedPayments = [];
      double currentPaidOnRow = 0.0;
      for (int pIdx = 0; pIdx < unallocatedSellerPayments.length; pIdx++) {
        final p = unallocatedSellerPayments[pIdx];
        final bool sellerMatch = p.seller.toUpperCase() == t.supplier.toUpperCase();
        final bool buyerMatch = p.buyer.isEmpty || t.buyer.isEmpty || p.buyer.toUpperCase() == t.buyer.toUpperCase();
        if (sellerMatch && buyerMatch) {
          matchedPayments.add(p);
          currentPaidOnRow += p.amount + p.settlement + p.commissionAdjusted;
          unallocatedSellerPayments.removeAt(pIdx);
          pIdx--;
          if (currentPaidOnRow >= t.supplierBill && i < sellerTrucks.length - 1) break;
        }
      }
      double paidSum = matchedPayments.fold<double>(0.0, (s, p) => s + p.amount);
      double discSum = matchedPayments.fold<double>(0.0, (s, p) => s + p.settlement);
      double commAdjSum = matchedPayments.fold<double>(0.0, (s, p) => s + p.commissionAdjusted);
      double rowBalance = t.supplierBill - paidSum - discSum - commAdjSum;

      sellerReportRows.add({
        'truck': t, 'payments': matchedPayments, 'date': formatDisplayDate(t.date),
        'buyer': t.buyer, 'qty': numFmt(t.qty), 'commission': money(t.commission),
        'sellerBill': money(t.supplierBill), 'balance': money(rowBalance),
      });
    }

    for (var p in unallocatedSellerPayments) {
      sellerReportRows.add({
        'truck': TruckEntry(id: 'EXTRA_PAY', state: _selectedState, date: p.date, truck: 'PAYMENT', supplier: p.seller, buyer: p.buyer, transporter: '—', type: 'PAYMENT', qty: 0, supplierBill: 0, buyerBill: 0, commission: 0, transportExp: 0, freight: 0, advance: 0),
        'payments': [p],
        'date': formatDisplayDate(p.date),
        'buyer': p.buyer.isNotEmpty ? p.buyer : 'ON ACCOUNT PAYMENT',
        'qty': '—',
        'commission': '₹0',
        'sellerBill': '₹0',
        'balance': money(-(p.amount + p.settlement + p.commissionAdjusted)),
      });
    }

    // 2. Buyer Calculations
    double buyerOpeningDue = 0;
    if (_repBuyer.isNotEmpty) {
      final priorBilled = _trucks
          .where((t) => t.state == _selectedState && t.buyer.toUpperCase() == _repBuyer.toUpperCase() && parseFlexibleDate(t.date).isBefore(fyStart))
          .fold(0.0, (s, t) => s + (t.buyerBill > 0 ? t.buyerBill : t.supplierBill));
      final priorPaid = _payments
          .where((p) => p.state == _selectedState && p.buyer.toUpperCase() == _repBuyer.toUpperCase() && parseFlexibleDate(p.date).isBefore(fyStart))
          .fold(0.0, (sum, p) => sum + p.amount + p.settlement);
      buyerOpeningDue = priorBilled - priorPaid;
    }

    final buyerTrucks = _trucks.where((t) {
      return t.state == _selectedState &&
          (_repBuyer.isEmpty || t.buyer.toUpperCase() == _repBuyer.toUpperCase()) &&
          (_repBuyerSellerFilter.isEmpty || t.supplier.toUpperCase() == _repBuyerSellerFilter.toUpperCase()) &&
          _isDateInFY(t.date, _selectedFinancialYear) &&
          isDateInRange(t.date, _repBuyerFromCtrl.text, _repBuyerToCtrl.text);
    }).toList();
    buyerTrucks.sort((a, b) => parseFlexibleDate(a.date).compareTo(parseFlexibleDate(b.date)));

    final buyerPayments = _payments.where((p) {
      return p.state == _selectedState &&
          (p.type.contains("BUYER") || p.mode == "DIRECT") &&
          (_repBuyer.isEmpty || p.buyer.toUpperCase() == _repBuyer.toUpperCase()) &&
          (_repBuyerSellerFilter.isEmpty || p.seller.isEmpty || p.seller.toUpperCase() == _repBuyerSellerFilter.toUpperCase()) &&
          _isDateInFY(p.date, _selectedFinancialYear);
    }).toList();
    buyerPayments.sort((a, b) => parseFlexibleDate(a.date).compareTo(parseFlexibleDate(b.date)));

    final double bTotalQty = buyerTrucks.fold<double>(0.0, (sum, t) => sum + t.qty);
    final double bTotalBilled = buyerTrucks.fold<double>(0.0, (sum, t) => sum + (t.buyerBill > 0 ? t.buyerBill : t.supplierBill)) + (buyerOpeningDue > 0 ? buyerOpeningDue : 0.0);
    final double bTotalReceived = buyerPayments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final double bDiscount = buyerPayments.fold<double>(0.0, (sum, p) => sum + p.settlement);
    final double bCommissionAdjusted = buyerPayments.fold<double>(0.0, (sum, p) => sum + p.commissionAdjusted);
    final double bPendingBalance = bTotalBilled - bTotalReceived - bDiscount - bCommissionAdjusted;

    List<Map<String, dynamic>> buyerReportRows = [];
    List<PaymentEntry> unallocatedBuyerPayments = List.from(buyerPayments);

    if (buyerOpeningDue > 0) {
      buyerReportRows.add({
        'truck': TruckEntry(id: 'VIRTUAL_OB', state: _selectedState, date: '01-04-${(fyStart.year % 100).toString().padLeft(2, '0')}', truck: 'B/F', supplier: 'PREVIOUS YEAR DUE', buyer: _repBuyer, transporter: '—', type: 'OPENING BAL', qty: 0, supplierBill: 0, buyerBill: buyerOpeningDue, commission: 0, transportExp: 0, freight: 0, advance: 0),
        'payments': <dynamic>[],
        'date': '01-04-${(fyStart.year % 100).toString().padLeft(2, '0')}',
        'seller': 'OPENING BALANCE (B/F)',
        'qty': '0', 'bill': money(buyerOpeningDue), 'balance': money(buyerOpeningDue),
      });
    }

    for (int i = 0; i < buyerTrucks.length; i++) {
      final t = buyerTrucks[i];
      double bill = t.buyerBill > 0 ? t.buyerBill : t.supplierBill;
      List<dynamic> matchedPayments = [];
      double currentPaidOnRow = 0.0;
      for (int pIdx = 0; pIdx < unallocatedBuyerPayments.length; pIdx++) {
        final p = unallocatedBuyerPayments[pIdx];
        final bool buyerMatch = p.buyer.toUpperCase() == t.buyer.toUpperCase();
        final bool sellerMatch = p.seller.isEmpty || t.supplier.isEmpty || p.seller.toUpperCase() == t.supplier.toUpperCase();
        if (buyerMatch && sellerMatch) {
          matchedPayments.add(p);
          currentPaidOnRow += p.amount + p.settlement + p.commissionAdjusted;
          unallocatedBuyerPayments.removeAt(pIdx);
          pIdx--;
          if (currentPaidOnRow >= bill && i < buyerTrucks.length - 1) break;
        }
      }
      double paidSum = matchedPayments.fold<double>(0.0, (s, p) => s + p.amount);
      double discSum = matchedPayments.fold<double>(0.0, (s, p) => s + p.settlement);
      double commAdjSum = matchedPayments.fold<double>(0.0, (s, p) => s + p.commissionAdjusted);
      double rowBalance = bill - paidSum - discSum - commAdjSum;

      buyerReportRows.add({
        'truck': t, 'payments': matchedPayments, 'date': formatDisplayDate(t.date),
        'seller': t.supplier.isEmpty ? '-' : t.supplier, 'qty': numFmt(t.qty),
        'bill': money(bill), 'balance': money(rowBalance),
      });
    }

    for (var p in unallocatedBuyerPayments) {
      buyerReportRows.add({
        'truck': TruckEntry(id: 'EXTRA_PAY', state: _selectedState, date: p.date, truck: 'PAYMENT', supplier: p.seller, buyer: p.buyer, transporter: '—', type: 'PAYMENT', qty: 0, supplierBill: 0, buyerBill: 0, commission: 0, transportExp: 0, freight: 0, advance: 0),
        'payments': [p],
        'date': formatDisplayDate(p.date),
        'seller': p.seller.isNotEmpty ? p.seller : 'ON ACCOUNT PAYMENT',
        'qty': '—',
        'bill': '₹0',
        'balance': money(-(p.amount + p.settlement + p.commissionAdjusted)),
      });
    }

    // 3. Tamil Nadu Operations Summary
    final tnTrucks = _trucks.where((t) {
      return t.state == 'Tamil Nadu' &&
          (_repStateSeller.isEmpty || t.supplier.toUpperCase() == _repStateSeller.toUpperCase()) &&
          _isDateInFY(t.date, _selectedFinancialYear) &&
          isDateInRange(t.date, _repStateFromCtrl.text, _repStateToCtrl.text);
    }).toList();
    tnTrucks.sort((a, b) => parseFlexibleDate(a.date).compareTo(parseFlexibleDate(b.date)));

    List<Map<String, dynamic>> stateRows = [];
    double totalBRecv = 0, totalSPaid = 0, totalAdv = 0, totalCommSum = 0;
    for (var t in tnTrucks) {
      double bR = t.buyerBill;
      double sP = t.supplierBill;
      double adv = t.advance;
      double comm = bR - sP - adv;
      totalBRecv += bR;
      totalSPaid += sP;
      totalAdv += adv;
      totalCommSum += comm;
      stateRows.add({'date': t.date, 'seller': t.supplier.isEmpty ? '-' : t.supplier, 'buyer': t.buyer.isEmpty ? '-' : t.buyer, 'bR': bR, 'sP': sP, 'adv': adv, 'comm': comm});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==================== SELLER STATEMENT ====================
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Seller Statement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _openSellerReportPrintModal(_repSeller.isEmpty ? "ALL SELLERS" : _repSeller, _repSellerBuyerFilter, sellerReportRows, sTotalQty, sTotalComm, sCalculatedQtyComm, sCombinedTotalCommission, sTotalBilled, sTotalPaid, sBalanceDue),
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print Statement'),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: _showAllSellersCommissionDialog,
                        icon: const Icon(Icons.receipt_long_rounded, size: 16),
                        label: const Text('Commission Summary'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _responsiveRow([
                Expanded(flex: 3, child: _customAutocomplete('Filter Seller', _sellerNames, _repSeller, 'CHOOSE SELLER', (v) => setState(() { _repSeller = v; _repSellerBuyerFilter = ""; }))),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: _customAutocomplete('Filter Buyer', _sellerRespectiveBuyers, _repSellerBuyerFilter, 'ALL BUYERS', (v) => setState(() => _repSellerBuyerFilter = v))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _customField('Rate (₹/Div)', _repSellerCommRateCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _customField('From Date', _repSellerFromCtrl, hint: 'DD-MM-YY', icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_repSellerFromCtrl))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _customField('To Date', _repSellerToCtrl, hint: 'DD-MM-YY', icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_repSellerToCtrl))),
              ]),
              const SizedBox(height: 16),
              _repSeller.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: const Center(
                        child: Text(
                          'Please select a Seller above to view statement and ledger.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const double minTableWidth = 900.0;
                            final double tableWidth = constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                child: Table(
                                  columnWidths: const {
                                    0: FlexColumnWidth(1.2),
                                    1: FlexColumnWidth(2.2),
                                    2: FlexColumnWidth(1.4),
                                    3: FlexColumnWidth(1.4),
                                    4: FlexColumnWidth(1.5),
                                    5: FlexColumnWidth(2.6),
                                    6: FlexColumnWidth(1.5),
                                    7: FlexColumnWidth(1.1),
                                  },
                                  border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
                                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                  children: [
                                    TableRow(
                                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                                      children: [
                                        _tableHeader('DATE'),
                                        _tableHeader('BUYER'),
                                        _tableHeader('QTY'),
                                        _tableHeader('COMMISSION'),
                                        _tableHeader('BILL'),
                                        _tableHeader('PAID DETAILS'),
                                        _tableHeader('BALANCE'),
                                        _tableHeader('ACTIONS'),
                                      ],
                                    ),
                                    ...sellerReportRows.map((row) {
                                      final t = row['truck'];
                                      final pList = row['payments'] as List<dynamic>;
                                      return TableRow(
                                        children: [
                                          _tableData(row['date']),
                                          _tableData(row['buyer'], isBold: true, color: const Color(0xFF0F172A)),
                                          _tableData(row['qty'] == '0' ? '—' : '${row['qty']} NUTS'),
                                          _tableData(row['commission']),
                                          _tableData(row['sellerBill'], isBold: true),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                            child: pList.isEmpty
                                                ? const Text('—', style: TextStyle(color: Color(0xFF94A3B8)))
                                                : Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: pList.map((p) => Text('${money(p.amount)} (${p.mode} on ${formatDisplayDate(p.date)})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857)))).toList(),
                                                  ),
                                          ),
                                          _tableData(row['balance'], isBold: true, color: const Color(0xFF047857)),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (t.id != 'VIRTUAL_OB' && t.id != 'EXTRA_PAY') ...[
                                                  IconButton(icon: const Icon(Icons.edit, size: 16, color: Color(0xFF047857)), onPressed: () => _editFromReport(t)),
                                                  IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () {
                                                    setState(() => _trucks.remove(t));
                                                    _commitToLocalDrive();
                                                  }),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                    TableRow(
                                      decoration: const BoxDecoration(color: Color(0xFFECFDF5)),
                                      children: [
                                        _tableData('TOTAL', isBold: true, color: const Color(0xFF047857)),
                                        _tableData('—'),
                                        _tableData('${numFmt(sTotalQty)} NUTS', isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(sTotalComm), isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(sTotalBilled), isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(sTotalPaid), isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(sBalanceDue), isBold: true, color: const Color(0xFF065F46)),
                                        const SizedBox(),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF1F8F3), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA7F3D0))),
                child: Text(
                  'COMMISSION SUMMARY: Qty Comm (${money(sCalculatedQtyComm)}) + Direct Comm (${money(sTotalComm)}) = TOTAL: ${money(sCombinedTotalCommission)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF047857)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==================== BUYER STATEMENT ====================
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Buyer Statement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF062317), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => _openBuyerReportPrintModal(_repBuyer.isEmpty ? "ALL BUYERS" : _repBuyer, _repBuyerSellerFilter, buyerReportRows, bTotalQty, bTotalBilled, bTotalReceived, bPendingBalance),
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Print Statement'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _responsiveRow([
                Expanded(flex: 3, child: _customAutocomplete('Filter Buyer', _buyerNames, _repBuyer, 'CHOOSE BUYER', (v) => setState(() { _repBuyer = v; _repBuyerSellerFilter = ""; }))),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: _customAutocomplete('Filter Seller', _buyerRespectiveSellers, _repBuyerSellerFilter, 'ALL SELLERS', (v) => setState(() => _repBuyerSellerFilter = v))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _customField('From Date', _repBuyerFromCtrl, hint: 'DD-MM-YY', icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_repBuyerFromCtrl))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _customField('To Date', _repBuyerToCtrl, hint: 'DD-MM-YY', icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_repBuyerToCtrl))),
              ]),
              const SizedBox(height: 16),
              _repBuyer.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: const Center(
                        child: Text(
                          'Please select a Buyer above to view statement and ledger.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const double minTableWidth = 840.0;
                            final double tableWidth = constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                child: Table(
                                  columnWidths: const {
                                    0: FlexColumnWidth(1.2),
                                    1: FlexColumnWidth(2.2),
                                    2: FlexColumnWidth(1.4),
                                    3: FlexColumnWidth(1.5),
                                    4: FlexColumnWidth(2.6),
                                    5: FlexColumnWidth(1.5),
                                    6: FlexColumnWidth(1.0),
                                  },
                                  border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
                                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                  children: [
                                    TableRow(
                                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                                      children: [
                                        _tableHeader('DATE'),
                                        _tableHeader('SELLER'),
                                        _tableHeader('QTY'),
                                        _tableHeader('BILL AMOUNT'),
                                        _tableHeader('PAID DETAILS'),
                                        _tableHeader('BALANCE'),
                                        _tableHeader('ACTIONS'),
                                      ],
                                    ),
                                    ...buyerReportRows.map((row) {
                                      final t = row['truck'];
                                      final pList = row['payments'] as List<dynamic>;
                                      return TableRow(
                                        children: [
                                          _tableData(row['date']),
                                          _tableData(row['seller'], isBold: true, color: const Color(0xFF0F172A)),
                                          _tableData(row['qty'] == '0' ? '—' : '${row['qty']} NUTS'),
                                          _tableData(row['bill'], isBold: true),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                            child: pList.isEmpty
                                                ? const Text('—', style: TextStyle(color: Color(0xFF94A3B8)))
                                                : Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: pList.map((p) => Text('${money(p.amount)} (${p.mode} on ${formatDisplayDate(p.date)})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857)))).toList(),
                                                  ),
                                          ),
                                          _tableData(row['balance'], isBold: true, color: const Color(0xFF047857)),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (t.id != 'VIRTUAL_OB' && t.id != 'EXTRA_PAY') ...[
                                                  IconButton(icon: const Icon(Icons.edit, size: 16, color: Color(0xFF047857)), onPressed: () => _editFromReport(t)),
                                                  IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () {
                                                    setState(() => _trucks.remove(t));
                                                    _commitToLocalDrive();
                                                  }),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                    TableRow(
                                      decoration: const BoxDecoration(color: Color(0xFFECFDF5)),
                                      children: [
                                        _tableData('TOTAL', isBold: true, color: const Color(0xFF047857)),
                                        _tableData('—'),
                                        _tableData('${numFmt(bTotalQty)} NUTS', isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(bTotalBilled), isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(bTotalReceived), isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(bPendingBalance), isBold: true, color: const Color(0xFF065F46)),
                                        const SizedBox(),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ],
          ),
        ),

        // ==================== TAMIL NADU SUMMARY ====================
        if (_selectedState == 'Tamil Nadu') ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isMobile ? 14 : 22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tamil Nadu Operations Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 16),
                _responsiveRow([
                  Expanded(child: _customAutocomplete('Filter Seller', _sellerNames, _repStateSeller, 'ALL SELLERS', (v) => setState(() => _repStateSeller = v))),
                  const SizedBox(width: 12),
                  Expanded(child: _customField('From Date', _repStateFromCtrl, hint: 'DD-MM-YY', icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_repStateFromCtrl))),
                  const SizedBox(width: 12),
                  Expanded(child: _customField('To Date', _repStateToCtrl, hint: 'DD-MM-YY', icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(_repStateToCtrl))),
                ]),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const double minTableWidth = 780.0;
                        final double tableWidth = constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(1.2),
                                1: FlexColumnWidth(2.0),
                                2: FlexColumnWidth(2.0),
                                3: FlexColumnWidth(1.5),
                                4: FlexColumnWidth(1.5),
                                5: FlexColumnWidth(1.4),
                                6: FlexColumnWidth(1.5),
                              },
                              border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
                              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                              children: [
                                TableRow(
                                  decoration: const BoxDecoration(color: Color(0xFFFEF3C7)),
                                  children: [
                                    _tableHeader('DATE'),
                                    _tableHeader('SELLER'),
                                    _tableHeader('BUYER'),
                                    _tableHeader('BUYER RECV.'),
                                    _tableHeader('SELLER PAID'),
                                    _tableHeader('ADVANCE'),
                                    _tableHeader('COMMISSION'),
                                  ],
                                ),
                                ...stateRows.map((row) => TableRow(
                                      children: [
                                        _tableData(row['date']),
                                        _tableData(row['seller']),
                                        _tableData(row['buyer']),
                                        _tableData(money(row['bR'])),
                                        _tableData(money(row['sP'])),
                                        _tableData(money(row['adv'])),
                                        _tableData(money(row['comm']), isBold: true, color: const Color(0xFF047857)),
                                      ],
                                    )),
                                TableRow(
                                  decoration: const BoxDecoration(color: Color(0xFFFDE68A)),
                                  children: [
                                    _tableData('TOTAL', isBold: true, color: const Color(0xFF92400E)),
                                    _tableData('—'),
                                    _tableData('—'),
                                    _tableData(money(totalBRecv), isBold: true, color: const Color(0xFF92400E)),
                                    _tableData(money(totalSPaid), isBold: true, color: const Color(0xFF92400E)),
                                    _tableData(money(totalAdv), isBold: true, color: const Color(0xFF92400E)),
                                    _tableData(money(totalCommSum), isBold: true, color: const Color(0xFF047857)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
String _getMonthName(int month) {
    const months = [
      "",
      "JANUARY",
      "FEBRUARY",
      "MARCH",
      "APRIL",
      "MAY",
      "JUNE",
      "JULY",
      "AUGUST",
      "SEPTEMBER",
      "OCTOBER",
      "NOVEMBER",
      "DECEMBER"
    ];
    return (month >= 1 && month <= 12) ? months[month] : "";
  }
  // ---------------- 6. TRANSPORT VIEW (MONTHLY STATEMENT & SORTING) ----------------
  String _getTruckBillMonth(dynamic t) {
    final dt = parseFlexibleDate(t.date);
    return "${_getMonthName(dt.month)} ${dt.year}";
  }

  String _getPaymentBillMonth(TransportPayment p) {
    if (p.billMonth.trim().isNotEmpty) {
      return p.billMonth.trim().toUpperCase();
    }
    final dt = parseFlexibleDate(p.date);
    return "${_getMonthName(dt.month)} ${dt.year}";
  }

  List<String> _getAvailableFinancialMonths() {
    final Set<String> months = {};
    for (var t in _trucks) {
      if (t.state == _selectedState && t.transporter.isNotEmpty && t.transporter != '—') {
        months.add(_getTruckBillMonth(t));
      }
    }
    for (var p in _transportPayments) {
      if (p.state == _selectedState && p.transporter.isNotEmpty) {
        months.add(_getPaymentBillMonth(p));
      }
    }

    final startYear = int.tryParse(_selectedFinancialYear.split('-')[0]) ?? DateTime.now().year;
    final List<String> fyMonths = [
      "APRIL $startYear", "MAY $startYear", "JUNE $startYear",
      "JULY $startYear", "AUGUST $startYear", "SEPTEMBER $startYear",
      "OCTOBER $startYear", "NOVEMBER $startYear", "DECEMBER $startYear",
      "JANUARY ${startYear + 1}", "FEBRUARY ${startYear + 1}", "MARCH ${startYear + 1}",
    ];
    months.addAll(fyMonths);

    final sorted = months.toList()..sort((a, b) {
      final dtA = parseFlexibleDate("01-$a");
      final dtB = parseFlexibleDate("01-$b");
      return dtA.compareTo(dtB);
    });

    return ["ALL MONTHS", ...sorted];
  }

  // ---------------- 6. TRANSPORT VIEW (TYPE-SAFE MONTHLY STATEMENT) ----------------
  Widget _buildTransportView() {
    final filterTrans = _analysisTransporter.trim().toUpperCase();
    final allMonthsList = _getAvailableFinancialMonths();

    // 1. Filter trucks by transporter
    final transporterTrucks = _trucks.where((t) {
      final matchesState = t.state == _selectedState;
      final hasTransporter = t.transporter.isNotEmpty && t.transporter != '—';
      final matchesTrans = filterTrans.isEmpty || filterTrans == 'ALL TRANSPORTERS' || t.transporter.toUpperCase() == filterTrans;
      return matchesState && hasTransporter && matchesTrans;
    }).toList();

    // 2. Filter payments by transporter
    final matchedTransPayments = _transportPayments.where((p) {
      final matchesState = p.state == _selectedState;
      final matchesTrans = filterTrans.isEmpty || filterTrans == 'ALL TRANSPORTERS' || p.transporter.toUpperCase() == filterTrans;
      return matchesState && matchesTrans;
    }).toList();

    // 3. Group and aggregate data by BILLING MONTH with safe num-to-double conversions
    Map<String, Map<String, dynamic>> monthlyMap = {};

    for (var t in transporterTrucks) {
      final mKey = _getTruckBillMonth(t);
      if (!monthlyMap.containsKey(mKey)) {
        monthlyMap[mKey] = {
          'month': mKey,
          'totalExp': 0.0,
          'totalPaid': 0.0,
          'trips': <dynamic>[],
          'payments': <TransportPayment>[],
        };
      }
      final double exp = (t.transportExp is num)
          ? (t.transportExp as num).toDouble()
          : (double.tryParse(t.transportExp?.toString() ?? '') ?? 0.0);
      monthlyMap[mKey]!['totalExp'] = ((monthlyMap[mKey]!['totalExp'] as num?)?.toDouble() ?? 0.0) + exp;
      (monthlyMap[mKey]!['trips'] as List<dynamic>).add(t);
    }

    for (var p in matchedTransPayments) {
      final mKey = _getPaymentBillMonth(p);
      if (!monthlyMap.containsKey(mKey)) {
        monthlyMap[mKey] = {
          'month': mKey,
          'totalExp': 0.0,
          'totalPaid': 0.0,
          'trips': <dynamic>[],
          'payments': <TransportPayment>[],
        };
      }
      final double amt = (p.amount is num)
          ? (p.amount as num).toDouble()
          : (double.tryParse(p.amount?.toString() ?? '') ?? 0.0);
      monthlyMap[mKey]!['totalPaid'] = ((monthlyMap[mKey]!['totalPaid'] as num?)?.toDouble() ?? 0.0) + amt;
      (monthlyMap[mKey]!['payments'] as List<TransportPayment>).add(p);
    }

    // Sort months chronologically
    final sortedMonths = monthlyMap.keys.toList()..sort((a, b) {
      return parseFlexibleDate("01-$a").compareTo(parseFlexibleDate("01-$b"));
    });

    List<Map<String, dynamic>> monthlySummaryRows = [];
    double grandTotalExp = 0.0;
    double grandTotalPaid = 0.0;

    for (var m in sortedMonths) {
      final data = monthlyMap[m]!;
      final double exp = (data['totalExp'] as num?)?.toDouble() ?? 0.0;
      final double paid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final double bal = exp - paid;

      grandTotalExp += exp;
      grandTotalPaid += paid;

      monthlySummaryRows.add({
        'month': m,
        'tripsCount': (data['trips'] as List).length,
        'expense': exp,
        'paid': paid,
        'balance': bal,
        'trips': data['trips'],
        'payments': data['payments'],
      });
    }

    final double grandTotalBalance = grandTotalExp - grandTotalPaid;

    Widget _tableHeader(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
    );

    Widget _tableData(String text, {bool isBold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color ?? const Color(0xFF1E293B))),
    );

    final bool isSingleMonthSelected = _selectedTransportMonth != "ALL MONTHS";
    final singleMonthData = monthlyMap[_selectedTransportMonth];
    final double sExp = (singleMonthData?['totalExp'] as num?)?.toDouble() ?? 0.0;
    final double sPaid = (singleMonthData?['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final double sBal = sExp - sPaid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Transporter Monthly Freight Statement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _showRecordTransportPaymentDialog(),
                        icon: const Icon(Icons.payment_rounded, size: 16),
                        label: const Text('Record Monthly Payment'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF062317), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _openTransportReportPrintModal(
                          _analysisTransporter.isEmpty ? "ALL TRANSPORTERS" : _analysisTransporter,
                          monthlySummaryRows, grandTotalExp, grandTotalPaid, grandTotalBalance,
                        ),
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print Statement'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _responsiveRow([
                Expanded(
                  flex: 3,
                  child: _customAutocomplete('Filter Transporter', _transporterNames, _analysisTransporter, 'ALL TRANSPORTERS', (v) => setState(() => _analysisTransporter = v)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Billing Month', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      const SizedBox(height: 5),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: allMonthsList.contains(_selectedTransportMonth) ? _selectedTransportMonth : "ALL MONTHS",
                            isExpanded: true,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: allMonthsList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedTransportMonth = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              if (isSingleMonthSelected) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statement for: $_selectedTransportMonth', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                    TextButton.icon(
                      onPressed: () => setState(() => _selectedTransportMonth = "ALL MONTHS"),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('View All Months', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFA7F3D0))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Total Trips: ${singleMonthData?['trips']?.length ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('Freight: ${money(sExp)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('Paid for this Month: ${money(sPaid)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF047857))),
                      Text('Pending Balance: ${money(sBal)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: sBal > 0 ? Colors.red : const Color(0xFF047857))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Trips / Loads Dispatched in this Month:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),

                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        columns: const [
                          DataColumn(label: Text('DATE', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TRUCK NO', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TRANSPORTER', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('SUPPLIER', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('BUYER', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('FREIGHT EXPENSE', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: (singleMonthData?['trips'] as List<dynamic>? ?? []).map((t) => DataRow(cells: [
                          DataCell(Text(t.date)),
                          DataCell(Text(t.truck, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(t.transporter)),
                          DataCell(Text(t.supplier)),
                          DataCell(Text(t.buyer)),
                          DataCell(Text(money(t.transportExp), style: const TextStyle(fontWeight: FontWeight.bold))),
                        ])).toList(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Text('Payments Credited Against this Month:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),

                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        columns: const [
                          DataColumn(label: Text('PAYMENT DATE', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TRANSPORTER', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('BANK / MODE', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('ALLOCATED BILL MONTH', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('AMOUNT PAID', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: (singleMonthData?['payments'] as List<TransportPayment>? ?? []).map((p) => DataRow(cells: [
                          DataCell(Text(p.date)),
                          DataCell(Text(p.transporter, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(p.bank)),
                          DataCell(Text(p.billMonth.isNotEmpty ? p.billMonth : _selectedTransportMonth, style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold))),
                          DataCell(Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857)))),
                        ])).toList(),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const double minTableWidth = 840.0;
                        final double tableWidth = constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(2.2),
                                1: FlexColumnWidth(1.4),
                                2: FlexColumnWidth(2.0),
                                3: FlexColumnWidth(2.0),
                                4: FlexColumnWidth(2.0),
                                5: FlexColumnWidth(1.6),
                              },
                              border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
                              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                              children: [
                                TableRow(
                                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                                  children: [
                                    _tableHeader('MONTH'),
                                    _tableHeader('TRIPS COUNT'),
                                    _tableHeader('FREIGHT CHARGES'),
                                    _tableHeader('PAID FOR MONTH'),
                                    _tableHeader('PENDING BALANCE'),
                                    _tableHeader('ACTION'),
                                  ],
                                ),
                                if (monthlySummaryRows.isEmpty)
                                  TableRow(
                                    children: [
                                      _tableData('No freight records found.'),
                                      _tableData('—'),
                                      _tableData('—'),
                                      _tableData('—'),
                                      _tableData('—'),
                                      _tableData('—'),
                                    ],
                                  )
                                else
                                  ...monthlySummaryRows.map((row) {
                                    final double bal = (row['balance'] as num?)?.toDouble() ?? 0.0;
                                    return TableRow(
                                      children: [
                                        _tableData(row['month'], isBold: true, color: const Color(0xFF0F172A)),
                                        _tableData('${row['tripsCount']} Loads'),
                                        _tableData(money(row['expense']), isBold: true),
                                        _tableData(money(row['paid']), isBold: true, color: const Color(0xFF047857)),
                                        _tableData(money(bal), isBold: true, color: bal > 0 ? Colors.red : const Color(0xFF047857)),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), side: const BorderSide(color: Color(0xFF047857))),
                                            onPressed: () => setState(() => _selectedTransportMonth = row['month']),
                                            child: const Text('View Details', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                TableRow(
                                  decoration: const BoxDecoration(color: Color(0xFFECFDF5)),
                                  children: [
                                    _tableData('TOTAL', isBold: true, color: const Color(0xFF047857)),
                                    _tableData('${transporterTrucks.length} Loads', isBold: true, color: const Color(0xFF047857)),
                                    _tableData(money(grandTotalExp), isBold: true, color: const Color(0xFF047857)),
                                    _tableData(money(grandTotalPaid), isBold: true, color: const Color(0xFF047857)),
                                    _tableData(money(grandTotalBalance), isBold: true, color: const Color(0xFF065F46)),
                                    const SizedBox(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showRecordTransportPaymentDialog() {
    String trans = _transporterNames.isNotEmpty ? _transporterNames.first : "";
    final amtCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: _tDateCtrl.text);

    // Default Bill Month to current active month
    final now = DateTime.now();
    String billMonth = "${_getMonthName(now.month)} ${now.year}";
    final months = _getAvailableFinancialMonths().where((m) => m != "ALL MONTHS").toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Record Transport Monthly Payment', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _customAutocomplete('Transporter *', _transporterNames, trans, 'SELECT TRANSPORTER', (v) => setDlgState(() => trans = v)),
                const SizedBox(height: 12),
                _customField('Amount Paid (₹) *', amtCtrl, isNum: true),
                const SizedBox(height: 12),

                // ALLOCATE TO SPECIFIC BILLING MONTH
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('For Billing Month (Statement to Clear) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 5),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: months.contains(billMonth) ? billMonth : (months.isNotEmpty ? months.first : null),
                          isExpanded: true,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (v) {
                            if (v != null) setDlgState(() => billMonth = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _customField('Payment Date *', dateCtrl, readOnly: true, icon: Icons.calendar_today_outlined, onTap: () => _selectDateForController(dateCtrl)),
                const SizedBox(height: 12),
                _customField('Bank / Payment Mode *', _tpBankCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                final double amt = double.tryParse(amtCtrl.text) ?? 0;
                if (trans.isEmpty || amt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a transporter and enter a valid amount.')));
                  return;
                }
                setState(() {
                  _transportPayments.add(TransportPayment(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    state: _selectedState,
                    transporter: trans.toUpperCase().trim(),
                    bank: _tpBankCtrl.text.toUpperCase().trim(),
                    amount: amt,
                    date: dateCtrl.text.trim(),
                    billMonth: billMonth.toUpperCase().trim(),
                  ));
                });
                _commitToLocalDrive();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF047857), content: Text('Payment of ₹${amt.toStringAsFixed(0)} credited to $billMonth for $trans!')));
              },
              child: const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );
  }

  void _openTransportReportPrintModal(String transporterName, List<Map<String, dynamic>> rows, double totalExp, double totalPaid, double balanceDue) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 920, height: 820, padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Transporter Statement — $transporterName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const Divider(),
              Expanded(
                child: PdfPreview(
                  build: (format) => _generateTransportPdfReport(format, transporterName, rows, totalExp, totalPaid, balanceDue),
                  canChangeOrientation: false, canChangePageFormat: false, canDebug: false, allowSharing: true, allowPrinting: true,
                  initialPageFormat: PdfPageFormat.a4, pdfFileName: 'TRANSPORTER_STATEMENT.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generateTransportPdfReport(PdfPageFormat format, String transporter, List<Map<String, dynamic>> rows, double totalExp, double totalPaid, double balanceDue) async {
    final pdf = pw.Document(); 
    const greenBorder = PdfColor.fromInt(0xFF4D8B61); 
    const titleGreen = PdfColor.fromInt(0xFF126B35); 
    const redAccent = PdfColor.fromInt(0xFFBD2020);

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(10), 
        decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1.5))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text(_myCompany.name, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: titleGreen))),
            pw.SizedBox(height: 3),
            pw.Center(child: pw.Text('TRANSPORTER MONTHLY FREIGHT STATEMENT', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: titleGreen))),
            pw.SizedBox(height: 8),
            pw.Container(padding: const pw.EdgeInsets.all(6), color: const PdfColor.fromInt(0xFFEBF5EE), child: pw.Text('TRANSPORTER : ${transporter.toUpperCase()}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen))),
            pw.SizedBox(height: 8),
            pw.Table(
              border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: greenBorder, width: 1), verticalInside: pw.BorderSide(color: greenBorder, width: 1)),
              children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F7F3)), children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('MONTH', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TRIPS', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('FREIGHT EXPENSE (Rs)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('PAID (Rs)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('CUMULATIVE BALANCE (Rs)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)))
                ]),
                ...rows.map((row) {
                  return pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(row['monthDisplay'], style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${row['tripsCount']} Trips', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(pdfMoney(row['expense']), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(pdfMoney(row['paid']), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(pdfMoney(row['balance']), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)))
                  ]);
                }),
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE)), children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TOTAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('-')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${pdfMoney(totalExp)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${pdfMoney(totalPaid)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${pdfMoney(balanceDue)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen)))
                ]),
              ],
            ),
            pw.Spacer(),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Authorized Signature', style: const pw.TextStyle(fontSize: 8.5)), pw.Text('For ${_myCompany.name}', style: const pw.TextStyle(fontSize: 8.5))])),
          ],
        ),
      ),
    ));
    return pdf.save();
  }
  // ---------------- 7. ESTIMATE VIEW ----------------
  Widget _buildEstimateView() {
    final double b1TotalBags = double.tryParse(_b1BagsCtrl.text) ?? 0;
    final double b1TotalNuts = double.tryParse(_b1NutsCtrl.text) ?? 0;
    final double b1Weight = double.tryParse(_b1WeightCtrl.text) ?? 0;
    final double b1WeightRate = double.tryParse(_b1RateCtrl.text) ?? 0;
    final double b1WeightTotal = b1Weight * b1WeightRate;

    final double b1LoadingRate = double.tryParse(_b1LoadingRateCtrl.text) ?? 0;
    final double b1LoadingAmount = _b1LoadingType == "AP" ? ((b1TotalNuts * b1LoadingRate) / 1000) : (b1TotalBags * b1LoadingRate);
    final double b1Amc = double.tryParse(_b1AmcCtrl.text) ?? 0;
    final double b1Comm = double.tryParse(_b1CommCtrl.text) ?? 0;
    final double b1Ins = double.tryParse(_b1InsCtrl.text) ?? 0;
    final double b1Freight = double.tryParse(_b1FreightCtrl.text) ?? 0;

    final double b1TotalCharges = b1LoadingAmount + b1Amc + b1Comm + b1Ins + b1Freight;
    final double b1GrandTotal = b1WeightTotal + b1TotalCharges;
    final double b1PerBagValue = b1TotalBags > 0 ? (b1GrandTotal / b1TotalBags) : 0;

    final double b2Qty = double.tryParse(_b2QtyCtrl.text) ?? 0;
    final double b2Rate = double.tryParse(_b2RateCtrl.text) ?? 0;
    final double b2Divisor = (double.tryParse(_b2DivisorCtrl.text) ?? 1000) <= 0 ? 1 : (double.tryParse(_b2DivisorCtrl.text) ?? 1000);
    final double b2BaseTotal = (b2Qty * b2Rate) / b2Divisor;

    final double b2LoadingRate = double.tryParse(_b2LoadRateCtrl.text) ?? 0;
    final double b2LoadingAmount = _b2LoadingManual
        ? (double.tryParse(_b2LoadManualAmountCtrl.text) ?? 0)
        : (b2Qty * b2LoadingRate) / 1000;

    final double b2Amc = double.tryParse(_b2AmcCtrl.text) ?? 0;
    final double b2Comm = double.tryParse(_b2CommCtrl.text) ?? 0;
    final double b2Bags = double.tryParse(_b2BagsCtrl.text) ?? 0;
    final double b2BagRate = double.tryParse(_b2BagRateCtrl.text) ?? 0;
    final double b2BagsTotal = b2Bags * b2BagRate;
    final double b2Freight = double.tryParse(_b2FreightCtrl.text) ?? 0;

    final double b2TotalCharges = b2LoadingAmount + b2Amc + b2Comm + b2BagsTotal + b2Freight;
    final double b2GrandTotal = b2BaseTotal + b2TotalCharges;
    final double b2PerNutValue = b2Qty > 0 ? (b2GrandTotal / b2Qty) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==================== BOX 1 ESTIMATOR ====================
        Container(
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                const Text('Box 1: Weight & Bags Estimator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                  child: Text('Rate: ${money(b1PerBagValue)} / bag', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Box 1: Weight & Bags Estimator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                      child: Text('Rate: ${money(b1PerBagValue)} / bag', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text('1. Core Count & Parameters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              _responsiveRow([
                Expanded(child: _customField('Total Bags', _b1BagsCtrl, hint: '55', isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Total Nuts', _b1NutsCtrl, hint: '4400', isNum: true, onChanged: (_) => setState(() {}))),
              ]),
              const SizedBox(height: 14),
              const Text('2. Weight Calculation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              _responsiveRow([
                Expanded(child: _customField('Weight (Kgs)', _b1WeightCtrl, hint: '25000', isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Rate (₹/kg)', _b1RateCtrl, hint: '40', isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Weight Amount', TextEditingController(text: money(b1WeightTotal)), readOnly: true)),
              ]),
              const SizedBox(height: 14),
              const Text('3. Loading & Logistics', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              _responsiveRow([
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          const Text('Loading:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          ChoiceChip(
                            label: const Text('AP (Nuts)'),
                            selected: _b1LoadingType == "AP",
                            onSelected: (val) => setState(() { _b1LoadingType = "AP"; _b1LoadingRateCtrl.text = "650"; }),
                          ),
                          ChoiceChip(
                            label: const Text('TN (Bags)'),
                            selected: _b1LoadingType == "TN",
                            onSelected: (val) => setState(() { _b1LoadingType = "TN"; _b1LoadingRateCtrl.text = "70"; }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _customField(_b1LoadingType == "AP" ? 'Loading Rate (₹/1000 nuts)' : 'Loading Rate (₹/bag)', _b1LoadingRateCtrl, isNum: true, onChanged: (_) => setState(() {})),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _customField('AMC (₹)', _b1AmcCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Commission (₹)', _b1CommCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Insurance (₹)', _b1InsCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Freight (₹)', _b1FreightCtrl, isNum: true, onChanged: (_) => setState(() {}))),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF062317), Color(0xFF047857)]), borderRadius: BorderRadius.circular(12)),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BOX 1 ESTIMATED TOTAL', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(money(b1GrandTotal), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text('${money(b1PerBagValue)} / bag', style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('BOX 1 ESTIMATED TOTAL', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                              Text(money(b1GrandTotal), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                            ],
                          ),
                          Text('${money(b1PerBagValue)} / bag', style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==================== BOX 2 ESTIMATOR ====================
        Container(
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 16, offset: Offset(0, 6))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                const Text('Box 2: Quantity & Loading Estimator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                  child: Text('Rate: ₹${b2PerNutValue.toStringAsFixed(2)} / nut', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Box 2: Quantity, Divisor & Loading Estimator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                      child: Text('Rate: ₹${b2PerNutValue.toStringAsFixed(2)} / nut', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text('1. Base Rate & Divisor Calculation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              _responsiveRow([
                Expanded(child: _customField('Quantity (Nuts)', _b2QtyCtrl, hint: '30500', isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: _customField('Rate (₹)', _b2RateCtrl, hint: '2500', isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: _customField('Divisor', _b2DivisorCtrl, hint: '1000', isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: _customField('Base Amount', TextEditingController(text: money(b2BaseTotal)), readOnly: true)),
              ]),
              const SizedBox(height: 14),
              const Text('2. Loading & Levies', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              _responsiveRow([
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          const Text('Loading:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          ChoiceChip(
                            label: const Text('Rate (/1000)'),
                            selected: !_b2LoadingManual,
                            onSelected: (val) => setState(() => _b2LoadingManual = false),
                          ),
                          ChoiceChip(
                            label: const Text('Manual Amt'),
                            selected: _b2LoadingManual,
                            onSelected: (val) => setState(() => _b2LoadingManual = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _b2LoadingManual
                          ? _customField('Manual Amount (₹)', _b2LoadManualAmountCtrl, isNum: true, onChanged: (_) => setState(() {}))
                          : _customField('Loading Rate (₹/1000)', _b2LoadRateCtrl, hint: '650', isNum: true, onChanged: (_) => setState(() {})),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _customField('AMC (₹)', _b2AmcCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(child: _customField('Commission (₹)', _b2CommCtrl, isNum: true, onChanged: (_) => setState(() {}))),
              ]),
              const SizedBox(height: 14),
              const Text('3. Packaging & Freight', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
              const SizedBox(height: 8),
              _responsiveRow([
                Expanded(child: _customField('Bags Count', _b2BagsCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: _customField('Bag Rate (₹)', _b2BagRateCtrl, isNum: true, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: _customField('Bags Amount', TextEditingController(text: money(b2BagsTotal)), readOnly: true)),
                const SizedBox(width: 10),
                Expanded(child: _customField('Freight (₹)', _b2FreightCtrl, isNum: true, onChanged: (_) => setState(() {}))),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F3928), Color(0xFF047857)]), borderRadius: BorderRadius.circular(12)),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BOX 2 ESTIMATED TOTAL', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(money(b2GrandTotal), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text('₹${b2PerNutValue.toStringAsFixed(2)} / nut', style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('BOX 2 ESTIMATED TOTAL', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                              Text(money(b2GrandTotal), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                            ],
                          ),
                          Text('₹${b2PerNutValue.toStringAsFixed(2)} / nut', style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- MODALS & HELPERS ----------------
  void _showAddEditBankDialog({BankAccount? account, VoidCallback? onSaved}) {
    final nameCtrl = TextEditingController(text: account?.name ?? '');
    final accCtrl = TextEditingController(text: account?.account ?? '');
    final ifscCtrl = TextEditingController(text: account?.ifsc ?? '');
    final branchCtrl = TextEditingController(text: account?.branch ?? '');
    final noteCtrl = TextEditingController(text: account?.note ?? 'Please Credit to our Account only');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(account != null ? 'Edit Bank Account' : 'Add New Bank Account', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _customField('Bank Name *', nameCtrl, hint: 'e.g. HDFC BANK'),
                const SizedBox(height: 8),
                _customField('Account Number *', accCtrl, hint: 'e.g. 50100234567890'),
                const SizedBox(height: 8),
                _customField('IFSC Code *', ifscCtrl, hint: 'e.g. HDFC0000123'),
                const SizedBox(height: 8),
                _customField('Branch *', branchCtrl, hint: 'e.g. MAIN BRANCH'),
                const SizedBox(height: 8),
                _customField('Note (Printed on Invoice)', noteCtrl),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
            onPressed: () {
              final name = nameCtrl.text.trim().toUpperCase();
              final acc = accCtrl.text.trim();
              final ifsc = ifscCtrl.text.trim().toUpperCase();
              final branch = branchCtrl.text.trim().toUpperCase();
              final note = noteCtrl.text.trim();

              if (name.isEmpty || acc.isEmpty || ifsc.isEmpty || branch.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text('Please fill all required fields!')));
                return;
              }

              setState(() {
                if (account != null) {
                  account.name = name;
                  account.account = acc;
                  account.ifsc = ifsc;
                  account.branch = branch;
                  account.note = note;
                } else {
                  final newBank = BankAccount(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name, account: acc, ifsc: ifsc, branch: branch, note: note,
                  );
                  _bankAccounts.add(newBank);
                }
              });

              _commitToLocalDrive();
              if (onSaved != null) onSaved();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Color(0xFF047857), content: Text('Bank Account saved and synced!')));
            },
            child: Text(account != null ? 'Update Bank' : 'Save Bank'),
          ),
        ],
      ),
    );
  }

  void _openSellerReportPrintModal(String sellerName, String buyerFilter, List<Map<String, dynamic>> rows, double totalQty, double totalComm, double calculatedQtyComm, double combinedTotalCommission, double totalBilled, double totalPaid, double balanceDue) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 920, height: 820, padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Statement — $sellerName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const Divider(),
              Expanded(
                child: PdfPreview(
                  build: (format) => _generateSellerPdfReport(format, sellerName, buyerFilter, rows, totalQty, totalComm, calculatedQtyComm, combinedTotalCommission, totalBilled, totalPaid, balanceDue),
                  canChangeOrientation: false, canChangePageFormat: false, canDebug: false, allowSharing: true, allowPrinting: true,
                  initialPageFormat: PdfPageFormat.a4, pdfFileName: 'SELLER_STATEMENT.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generateSellerPdfReport(PdfPageFormat format, String seller, String buyerFilter, List<Map<String, dynamic>> rows, double totalQty, double totalComm, double calculatedQtyComm, double combinedTotalCommission, double totalBilled, double totalPaid, double balanceDue) async {
    final pdf = pw.Document(); 
    const greenBorder = PdfColor.fromInt(0xFF4D8B61); 
    const titleGreen = PdfColor.fromInt(0xFF126B35); 
    const redAccent = PdfColor.fromInt(0xFFBD2020);

    final prefs = await SharedPreferences.getInstance();
    final customLogoPath = prefs.getString('custom_logo_path');
    pw.MemoryImage? logoImage;
    if (customLogoPath != null && customLogoPath.trim().isNotEmpty && customLogoPath != 'NONE' && await File(customLogoPath).exists()) {
      try {
        final Uint8List customBytes = await File(customLogoPath).readAsBytes();
        logoImage = pw.MemoryImage(customBytes);
      } catch (_) { logoImage = null; }
    }

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(10), 
        decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1.5))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Stack(
              children: [
                pw.Align(
                  alignment: pw.Alignment.topCenter,
                  child: pw.Text(_myCompany.invocation.isNotEmpty ? _myCompany.invocation : 'Om Sri Ganesaya Namaha', style: pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic, color: titleGreen)),
                ),
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: _myCompany.phone.split(',').map((num) => pw.Text('Cell : ${num.trim()}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))).toList()),
                ),
              ],
            ), 
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (logoImage != null) ...[pw.Image(logoImage, width: 34, height: 34), pw.SizedBox(width: 8)],
                pw.Text(_myCompany.name, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: titleGreen, letterSpacing: 0.5)),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Center(child: pw.Text(_myCompany.tagline, style: pw.TextStyle(fontSize: 10, letterSpacing: 2.5, fontWeight: pw.FontWeight.bold))), 
            pw.SizedBox(height: 3),
            pw.Center(child: pw.Text(_myCompany.address, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: redAccent))), 
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE), border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
                child: pw.Text('STATEMENT OF ACCOUNT', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen)),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6), 
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE)), 
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, 
                children: [
                  pw.Text('SELLER : ${seller.toUpperCase()}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen)), 
                  pw.Text('BUYER : ${buyerFilter.isNotEmpty ? buyerFilter.toUpperCase() : "ALL BUYERS"}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen))
                ],
              ),
            ), 
            pw.SizedBox(height: 5),
            pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
              child: pw.Table(
                columnWidths: const {0: pw.FlexColumnWidth(1.8), 1: pw.FlexColumnWidth(3.2), 2: pw.FlexColumnWidth(1.8), 3: pw.FlexColumnWidth(1.8), 4: pw.FlexColumnWidth(2.0), 5: pw.FlexColumnWidth(4.5), 6: pw.FlexColumnWidth(2.0)},
                border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: greenBorder, width: 1), verticalInside: pw.BorderSide(color: greenBorder, width: 1)),
                children: [
                  pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F7F3)), children: [pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('DATE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('BUYER', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('QTY (NUTS)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('COMMISSION', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('SELLER BILL', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('PAID WITH DATE & BANK', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('BALANCE', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))]),
                  ...rows.map((row) {
                    final List<dynamic> pList = row['payments'] as List<dynamic>;
                    String paidText = pList.isEmpty ? '-' : pList.map((p) => "Rs. ${pdfMoney(p.amount)} (${p.mode} on ${p.date})").join('\n');
                    return pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['date'], style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['buyer'], style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('${row['qty']} NUTS', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['commission'].replaceAll('₹', 'Rs. '), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['sellerBill'].replaceAll('₹', 'Rs. '), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(paidText, style: pw.TextStyle(fontSize: 7.5, color: titleGreen, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['balance'].replaceAll('₹', 'Rs. '), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))]);
                  }),
                  pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE)), children: [pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('TOTAL', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('-', style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('${numFmt(totalQty)} NUTS', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(totalComm)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(totalBilled)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(totalPaid)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(balanceDue)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen)))]),
                ],
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF1F8F3), border: pw.Border.all(color: greenBorder, width: 1)), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('COMMISSION SUMMARY', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: titleGreen)), pw.Text('Qty Commission (Rs. ${pdfMoney(calculatedQtyComm)}) + Commission (Rs. ${pdfMoney(totalComm)}) = TOTAL: Rs. ${pdfMoney(combinedTotalCommission)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: titleGreen))])),
            pw.Spacer(),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Customer Signature', style: const pw.TextStyle(fontSize: 8.5)), pw.Text('For ${_myCompany.name}', style: const pw.TextStyle(fontSize: 8.5))])),
          ],
        ),
      ),
    ));
    return pdf.save();
  }

  void _openBuyerReportPrintModal(String buyerName, String sellerFilter, List<Map<String, dynamic>> rows, double totalQty, double totalBilled, double totalPaid, double balanceDue) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 920, height: 820, padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Buyer Statement — $buyerName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const Divider(),
              Expanded(
                child: PdfPreview(
                  build: (format) => _generateBuyerPdfReport(format, buyerName, sellerFilter, rows, totalQty, totalBilled, totalPaid, balanceDue),
                  canChangeOrientation: false, canChangePageFormat: false, canDebug: false, allowSharing: true, allowPrinting: true,
                  initialPageFormat: PdfPageFormat.a4, pdfFileName: 'BUYER_STATEMENT.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generateBuyerPdfReport(PdfPageFormat format, String buyer, String sellerFilter, List<Map<String, dynamic>> rows, double totalQty, double totalBilled, double totalPaid, double balanceDue) async {
    final pdf = pw.Document(); 
    const greenBorder = PdfColor.fromInt(0xFF4D8B61); 
    const titleGreen = PdfColor.fromInt(0xFF126B35); 
    const redAccent = PdfColor.fromInt(0xFFBD2020);

    final prefs = await SharedPreferences.getInstance();
    final customLogoPath = prefs.getString('custom_logo_path');
    pw.MemoryImage? logoImage;
    if (customLogoPath != null && customLogoPath.trim().isNotEmpty && customLogoPath != 'NONE' && await File(customLogoPath).exists()) {
      try {
        final Uint8List customBytes = await File(customLogoPath).readAsBytes();
        logoImage = pw.MemoryImage(customBytes);
      } catch (_) { logoImage = null; }
    }

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(10), 
        decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1.5))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Stack(
              children: [
                pw.Align(
                  alignment: pw.Alignment.topCenter,
                  child: pw.Text(_myCompany.invocation.isNotEmpty ? _myCompany.invocation : 'Om Sri Ganesaya Namaha', style: pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic, color: titleGreen)),
                ),
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: _myCompany.phone.split(',').map((num) => pw.Text('Cell : ${num.trim()}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))).toList()),
                ),
              ],
            ), 
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (logoImage != null) ...[pw.Image(logoImage, width: 34, height: 34), pw.SizedBox(width: 8)],
                pw.Text(_myCompany.name, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: titleGreen, letterSpacing: 0.5)),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Center(child: pw.Text(_myCompany.tagline, style: pw.TextStyle(fontSize: 10, letterSpacing: 2.5, fontWeight: pw.FontWeight.bold))), 
            pw.SizedBox(height: 3),
            pw.Center(child: pw.Text(_myCompany.address, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: redAccent))), 
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE), border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
                child: pw.Text('STATEMENT OF ACCOUNT', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen)),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6), 
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE)), 
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, 
                children: [
                  pw.Text('BUYER : ${buyer.toUpperCase()}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen)), 
                  pw.Text('SELLER : ${sellerFilter.isNotEmpty ? sellerFilter.toUpperCase() : "ALL SELLERS"}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen))
                ],
              ),
            ), 
            pw.SizedBox(height: 5),
            pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1))),
              child: pw.Table(
                columnWidths: const {0: pw.FlexColumnWidth(1.8), 1: pw.FlexColumnWidth(3.0), 2: pw.FlexColumnWidth(1.8), 3: pw.FlexColumnWidth(2.0), 4: pw.FlexColumnWidth(4.5), 5: pw.FlexColumnWidth(2.0)},
                border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: greenBorder, width: 1), verticalInside: pw.BorderSide(color: greenBorder, width: 1)),
                children: [
                  pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F7F3)), children: [pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('DATE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('SELLER', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('QTY (NUTS)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('BILL', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('PAID WITH DATE & BANK / DIRECT', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('BALANCE', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))]),
                  ...rows.map((row) {
                    final List<dynamic> pList = row['payments'] as List<dynamic>;
                    String paidText = pList.isEmpty ? '-' : pList.map((p) => "Rs. ${pdfMoney(p.amount)} (${p.mode} on ${p.date})").join('\n');
                    return pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['date'], style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['seller'] ?? '-', style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('${row['qty']} NUTS', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['bill'].replaceAll('₹', 'Rs. '), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(paidText, style: pw.TextStyle(fontSize: 7.5, color: titleGreen, fontWeight: pw.FontWeight.bold))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(row['balance'].replaceAll('₹', 'Rs. '), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))]);
                  }),
                  pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE)), children: [pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('TOTAL', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('-', style: const pw.TextStyle(fontSize: 8))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('${numFmt(totalQty)} NUTS', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(totalBilled)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(totalPaid)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('Rs. ${pdfMoney(balanceDue)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: titleGreen)))]),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Customer Signature', style: const pw.TextStyle(fontSize: 8.5)), pw.Text('For ${_myCompany.name}', style: const pw.TextStyle(fontSize: 8.5))])),
          ],
        ),
      ),
    ));
    return pdf.save();
  }

  void _showAllSellersCommissionDialog() async {
    final double sCommRate = double.tryParse(_repSellerCommRateCtrl.text) ?? 0;
    final double divisor = _repSellerCommDivisor > 0 ? _repSellerCommDivisor : 1000;
    List<Map<String, dynamic>> sellerSummaries = [];
    double grandTotalCommission = 0; double grandTotalQty = 0; double grandTotalAdjComm = 0;

    for (var seller in _sellerNames) {
      final sellerTrucks = _trucks.where((t) {
        return t.state == _selectedState && t.supplier.toUpperCase() == seller.toUpperCase() && _isDateInFY(t.date, _selectedFinancialYear) && isDateInRange(t.date, _repSellerFromCtrl.text, _repSellerToCtrl.text);
      }).toList();

      final double totalQty = sellerTrucks.fold<double>(0.0, (s, t) => s + t.qty);
      final double directComm = sellerTrucks.fold<double>(0.0, (s, t) => s + t.commission);
      final double qtyComm = sCommRate > 0 ? ((totalQty * sCommRate) / divisor).roundToDouble() : 0.0;
      final double adjComm = _payments.where((p) => p.state == _selectedState && p.seller.toUpperCase() == seller.toUpperCase() && _isDateInFY(p.date, _selectedFinancialYear) && isDateInRange(p.date, _repSellerFromCtrl.text, _repSellerToCtrl.text)).fold<double>(0.0, (s, p) => s + p.commissionAdjusted);
      final double totalComm = directComm + qtyComm;

      if (totalComm > 0 || totalQty > 0 || adjComm > 0) {
        sellerSummaries.add({'name': seller, 'qty': totalQty, 'adjComm': adjComm, 'totalComm': totalComm});
        grandTotalCommission += totalComm; grandTotalQty += totalQty; grandTotalAdjComm += adjComm;
      }
    }
    sellerSummaries.sort((a, b) => (b['totalComm'] as double).compareTo(a['totalComm'] as double));

    const greenBorder = PdfColor.fromInt(0xFF4D8B61); 
    const titleGreen = PdfColor.fromInt(0xFF126B35); 
    const redAccent = PdfColor.fromInt(0xFFBD2020);

    final prefs = await SharedPreferences.getInstance();
    final customLogoPath = prefs.getString('custom_logo_path');
    pw.MemoryImage? logoImage;
    if (customLogoPath != null && customLogoPath.trim().isNotEmpty && customLogoPath != 'NONE' && await File(customLogoPath).exists()) {
      try {
        final Uint8List customBytes = await File(customLogoPath).readAsBytes();
        logoImage = pw.MemoryImage(customBytes);
      } catch (_) { logoImage = null; }
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          width: 840,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.94),
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Consolidated Commission Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 20), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: PdfPreview(
                    build: (format) async {
                      final pdf = pw.Document();
                      pdf.addPage(pw.Page(
                        pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        build: (ctx) => pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          decoration: const pw.BoxDecoration(border: pw.Border.fromBorderSide(pw.BorderSide(color: greenBorder, width: 1.5))),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              pw.Stack(
                                children: [
                                  pw.Align(alignment: pw.Alignment.topCenter, child: pw.Text(_myCompany.invocation.isNotEmpty ? _myCompany.invocation : 'Om Sri Ganesaya Namaha', style: pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic, color: titleGreen))),
                                  pw.Align(alignment: pw.Alignment.topRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: _myCompany.phone.split(',').map((num) => pw.Text('Cell : ${num.trim()}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))).toList())),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [if (logoImage != null) ...[pw.Image(logoImage, width: 34, height: 34), pw.SizedBox(width: 8)], pw.Text(_myCompany.name, style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold, color: titleGreen, letterSpacing: 0.6))]),
                              pw.SizedBox(height: 2),
                              pw.Center(child: pw.Text(_myCompany.tagline, style: pw.TextStyle(fontSize: 10, letterSpacing: 3, fontWeight: pw.FontWeight.bold))),
                              pw.SizedBox(height: 2),
                              pw.Center(child: pw.Text(_myCompany.address, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: redAccent))),
                              pw.SizedBox(height: 8),
                              pw.Center(child: pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEBF5EE), border: pw.Border.all(color: greenBorder)), child: pw.Text('CONSOLIDATED COMMISSION REPORT', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen)))),
                              pw.SizedBox(height: 12),
                              pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEBF5EE), border: pw.Border.all(color: greenBorder)), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('FINANCIAL YEAR: FY $_selectedFinancialYear', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen)), pw.Text('STATE: ${_selectedState.toUpperCase()}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen)), pw.Text('DATE: ${formatDisplayDate(DateTime.now().toIso8601String())}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: titleGreen))])),
                              pw.SizedBox(height: 12),
                              pw.Table(
                                columnWidths: const {0: pw.FlexColumnWidth(0.8), 1: pw.FlexColumnWidth(4.2), 2: pw.FlexColumnWidth(2.5), 3: pw.FlexColumnWidth(2.2), 4: pw.FlexColumnWidth(2.5)},
                                border: pw.TableBorder.all(color: greenBorder, width: 0.8),
                                children: [
                                  pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F7F3)), children: [pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: pw.Text('#', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Text('SELLER NAME', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen))), pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('TOTAL NUTS', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen)))), pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('COMM ADJ', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen)))), pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('TOTAL COMM', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen))))]),
                                  ...sellerSummaries.asMap().entries.map((entry) {
                                    final idx = entry.key + 1; final item = entry.value;
                                    return pw.TableRow(children: [
                                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: pw.Text('$idx', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9.5))),
                                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Text(item['name'], style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
                                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${numFmt(item['qty'])} NUTS', style: const pw.TextStyle(fontSize: 9.5)))),
                                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(money(item['adjComm']).replaceAll('₹', 'Rs. '), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)))),
                                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(money(item['totalComm']).replaceAll('₹', 'Rs. '), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: titleGreen)))),
                                    ]);
                                  }),
                                  pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEBF5EE)), children: [
                                    pw.SizedBox(),
                                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Text('GRAND TOTAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen))),
                                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${numFmt(grandTotalQty)} NUTS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen)))),
                                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(money(grandTotalAdjComm).replaceAll('₹', 'Rs. '), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: titleGreen)))),
                                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(money(grandTotalCommission).replaceAll('₹', 'Rs. '), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: titleGreen)))),
                                  ]),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ));
                      return pdf.save();
                    },
                    canChangeOrientation: false, canChangePageFormat: false, canDebug: false, allowSharing: true, allowPrinting: true,
                    initialPageFormat: PdfPageFormat.a4, pdfFileName: 'CONSOLIDATED_COMMISSION_REPORT.pdf',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStorageSettingsDialog() {
    _cNameCtrl.text = _companyName;
    _cPhoneCtrl.text = _companyPhone;
    _cAddressCtrl.text = _companyAddress;
    _cTaglineCtrl.text = _myCompany.tagline;
    _sellerMsgCtrl.text = _sellerMsgTemplate;
    _buyerMsgCtrl.text = _buyerMsgTemplate;
    final invocationCtrl = TextEditingController(text: _myCompany.invocation);

    bool isSyncing = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSettingsState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.settings_outlined, color: Color(0xFF047857)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ERP Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.92,
              height: MediaQuery.of(context).size.height * 0.70,
              child: DefaultTabController(
                length: 6, // Exactly 6 tabs
                child: Column(
                  children: [
                    const TabBar(
                      isScrollable: true,
                      labelColor: Color(0xFF047857),
                      unselectedLabelColor: Color(0xFF64748B),
                      indicatorColor: Color(0xFF047857),
                      tabs: [
                        Tab(text: 'Security'),
                        Tab(text: 'Bank Accounts'),
                        Tab(text: 'SMS Templates'),
                        Tab(text: 'Letterhead'),
                        Tab(text: 'Cloud Sync'),
                        Tab(text: 'Fin. Year'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // 1. Security Tab
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _customField('Update Email', _settingsEmailCtrl, hint: _savedEmail),
                                const SizedBox(height: 12),
                                _customField('Update Master Password', _settingsPassCtrl, hint: _savedPassword),
                                const SizedBox(height: 12),
                                _customField('Update 4-Digit PIN', _settingsPinCtrl, hint: _savedPin, isNum: true),
                                const SizedBox(height: 20),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF047857),
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () async {
                                    final newEmail = _settingsEmailCtrl.text.trim();
                                    final newPass = _settingsPassCtrl.text.trim();
                                    final newPin = _settingsPinCtrl.text.trim();
                                    final prefs = await SharedPreferences.getInstance();
                                    if (newPin.isNotEmpty && newPin.length == 4) {
                                      await prefs.setString(_prefPinKey, newPin);
                                      setState(() => _savedPin = newPin);
                                    }
                                    if (newEmail.isNotEmpty) {
                                      await prefs.setString(_prefEmailKey, newEmail);
                                      setState(() => _savedEmail = newEmail);
                                    }
                                    if (newPass.isNotEmpty) {
                                      await prefs.setString(_prefPassKey, newPass);
                                      setState(() => _savedPassword = newPass);
                                    }
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Save Credentials'),
                                ),
                              ],
                            ),
                          ),

                          // 2. Bank Accounts Tab (CLEAN RESPONSIVE CARDS)
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Company Bank Accounts',
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Color(0xFF0F172A)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF047857),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(0, 32),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.add, size: 14),
                                      label: const Text('Add Bank', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      onPressed: () => _showAddEditBankDialog(onSaved: () => setSettingsState(() {})),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ..._bankAccounts.map((bank) {
                                  final bool isSelected = _selectedBank.id == bank.id;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF047857) : const Color(0xFFE2E8F0),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                      boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 2))],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header: Icon + Bank Name + Active Badge
                                        Row(
                                          children: [
                                            Icon(Icons.account_balance_rounded, size: 18, color: isSelected ? const Color(0xFF047857) : const Color(0xFF64748B)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                bank.name,
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isSelected)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: const Color(0xFF047857), borderRadius: BorderRadius.circular(4)),
                                                child: const Text('ACTIVE', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w900)),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                        const SizedBox(height: 8),

                                        // Body: Full-width Account details
                                        Text('A/c: ${bank.account}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                        const SizedBox(height: 2),
                                        Text('IFSC: ${bank.ifsc}  •  Branch: ${bank.branch}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                        const SizedBox(height: 8),

                                        // Footer: Action Buttons Row
                                        Row(
                                          children: [
                                            if (!isSelected)
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  minimumSize: const Size(0, 28),
                                                  side: const BorderSide(color: Color(0xFF047857)),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                ),
                                                icon: const Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF047857)),
                                                label: const Text('Set Active', style: TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.bold)),
                                                onPressed: () {
                                                  setState(() => _selectedBank = bank);
                                                  setSettingsState(() {});
                                                  _commitToLocalDrive();
                                                },
                                              ),
                                            const Spacer(),
                                            IconButton(
                                              padding: const EdgeInsets.all(4),
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF047857)),
                                              tooltip: 'Edit',
                                              onPressed: () => _showAddEditBankDialog(account: bank, onSaved: () => setSettingsState(() {})),
                                            ),
                                            if (_bankAccounts.length > 1) ...[
                                              const SizedBox(width: 8),
                                              IconButton(
                                                padding: const EdgeInsets.all(4),
                                                constraints: const BoxConstraints(),
                                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                                tooltip: 'Delete',
                                                onPressed: () {
                                                  setState(() {
                                                    _bankAccounts.remove(bank);
                                                    if (_selectedBank.id == bank.id) _selectedBank = _bankAccounts.first;
                                                  });
                                                  setSettingsState(() {});
                                                  _commitToLocalDrive();
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),

                          // 3. SMS Templates Tab
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Available Tags: {date}, {seller}, {buyer}, {type}, {rate}, {company}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                                ),
                                const SizedBox(height: 12),
                                _customField('Seller Confirmation Template', _sellerMsgCtrl, maxLines: 4),
                                const SizedBox(height: 12),
                                _customField('Buyer Confirmation Template', _buyerMsgCtrl, maxLines: 4),
                                const SizedBox(height: 16),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF047857),
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('sms_seller_template', _sellerMsgCtrl.text.trim());
                                    await prefs.setString('sms_buyer_template', _buyerMsgCtrl.text.trim());
                                    setState(() {
                                      _sellerMsgTemplate = _sellerMsgCtrl.text.trim();
                                      _buyerMsgTemplate = _buyerMsgCtrl.text.trim();
                                    });
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: Color(0xFF047857),
                                        content: Text('Message templates saved successfully!'),
                                      ),
                                    );
                                  },
                                  child: const Text('Save Templates'),
                                ),
                              ],
                            ),
                          ),

                          // 4. Letterhead Tab
                          SingleChildScrollView(
                            child: Column(
                              children: [
                                _customField('Company Name', _cNameCtrl),
                                const SizedBox(height: 12),
                                _customField('Tagline', _cTaglineCtrl),
                                const SizedBox(height: 12),
                                _customField('Phone', _cPhoneCtrl),
                                const SizedBox(height: 12),
                                _customField('Top Invocation', invocationCtrl),
                                const SizedBox(height: 12),
                                _customField('Address', _cAddressCtrl),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          side: const BorderSide(color: Color(0xFF047857)),
                                        ),
                                        icon: const Icon(Icons.upload_file_rounded, color: Color(0xFF047857)),
                                        label: const Text('Upload Logo', style: TextStyle(color: Color(0xFF047857))),
                                        onPressed: () async {
                                          final XFile? img = await openFile(acceptedTypeGroups: [
                                            const XTypeGroup(label: 'Images', extensions: ['png', 'jpg']),
                                          ]);
                                          if (img != null) {
                                            final prefs = await SharedPreferences.getInstance();
                                            await prefs.setString('custom_logo_path', img.path);
                                            setSettingsState(() {});
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        side: const BorderSide(color: Colors.red),
                                      ),
                                      onPressed: () async {
                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.remove('custom_logo_path');
                                        await prefs.setString('custom_logo_path', 'NONE');
                                        setSettingsState(() {});
                                      },
                                      child: const Text('Remove Logo'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF047857),
                                    minimumSize: const Size(double.infinity, 46),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('company_name', _cNameCtrl.text.trim());
                                    await prefs.setString('company_phone', _cPhoneCtrl.text.trim());
                                    await prefs.setString('company_address', _cAddressCtrl.text.trim());
                                    await prefs.setString('company_invocation', invocationCtrl.text.trim());
                                    setState(() {
                                      _companyName = _cNameCtrl.text.trim();
                                      _myCompany.name = _companyName;
                                      _myCompany.tagline = _cTaglineCtrl.text.trim();
                                      _myCompany.phone = _cPhoneCtrl.text.trim();
                                      _myCompany.address = _cAddressCtrl.text.trim();
                                      _myCompany.invocation = invocationCtrl.text.trim();
                                    });
                                    _commitToLocalDrive();
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Update Profile'),
                                ),
                              ],
                            ),
                          ),

                          // 5. Cloud Sync Tab
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: SwitchListTile(
                                    activeColor: const Color(0xFF047857),
                                    title: const Text('Auto-Sync on Application Exit', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                                    subtitle: const Text('Silently commits and uploads database on window close.', style: TextStyle(color: Color(0xFF64748B))),
                                    value: _autoSyncOnExit,
                                    onChanged: (v) async {
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('auto_sync_on_exit', v);
                                      setState(() => _autoSyncOnExit = v);
                                      setSettingsState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text('MANUAL LOCAL FILE BACKUP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.8)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF047857),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.download_rounded, size: 16),
                                        label: const Text('Export Backup File'),
                                        onPressed: () async {
                                          try {
                                            final nowStr = DateTime.now().toIso8601String().split('T')[0];
                                            final fullJson = _generateFullDatabaseJson();
                                            final encrypted = SecurityHelper.encrypt(fullJson);

                                            final FileSaveLocation? saveLoc = await getSaveLocation(
                                              suggestedName: 'cocotrade_backup_$nowStr.secure',
                                            );

                                            if (saveLoc != null) {
                                              final file = File(saveLoc.path);
                                              await file.writeAsString(encrypted, flush: true);
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(backgroundColor: const Color(0xFF047857), content: Text('Backup exported to ${file.path}')),
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Export failed: $e')));
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          side: const BorderSide(color: Color(0xFF047857)),
                                        ),
                                        icon: const Icon(Icons.file_open_rounded, size: 16, color: Color(0xFF047857)),
                                        label: const Text('Import Backup File', style: TextStyle(color: Color(0xFF047857))),
                                        onPressed: () async {
                                          try {
                                            const XTypeGroup typeGroup = XTypeGroup(
                                              label: 'CocoTrade Backups',
                                              extensions: ['secure', 'json'],
                                            );
                                            final XFile? selectedFile = await openFile(acceptedTypeGroups: [typeGroup]);

                                            if (selectedFile != null) {
                                              final rawContent = await selectedFile.readAsString();
                                              Map<String, dynamic> dataToApply;
                                              try {
                                                final decrypted = SecurityHelper.decrypt(rawContent);
                                                dataToApply = jsonDecode(decrypted);
                                              } catch (_) {
                                                dataToApply = jsonDecode(rawContent);
                                              }

                                              _applyStateFromMap(dataToApply);
                                              await LocalDriveManager.writeToDrive(dataToApply);
                                              Navigator.pop(ctx);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(backgroundColor: Color(0xFF047857), content: Text('Backup file imported and loaded successfully!')),
                                              );
                                            }
                                          } catch (e) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Import failed: $e')));
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Text('GOOGLE DRIVE CLOUD SYNC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.8)),
                                const SizedBox(height: 10),
                                if (GoogleDriveService.currentCredentials != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Color(0xFF047857),
                                          child: Icon(Icons.check, size: 16, color: Colors.white),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Connected Account', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                                              Text(
                                                GoogleDriveService.currentUserEmail ?? 'Active Google Session',
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF064E3B)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFEE2E2),
                                            foregroundColor: const Color(0xFFDC2626),
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.link_off_rounded, size: 16),
                                          label: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                title: const Text('Disconnect Google Drive?'),
                                                content: const Text('Unlinking will stop automatic cloud sync until you connect again.'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                                  FilledButton(
                                                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                    onPressed: () => Navigator.pop(c, true),
                                                    child: const Text('Disconnect'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              await GoogleDriveService.signOut();
                                              setSettingsState(() {});
                                              setState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Google Drive account disconnected.')),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF047857),
                                      minimumSize: const Size(double.infinity, 46),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: isSyncing
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.cloud_upload_rounded),
                                    label: const Text('Backup to Drive'),
                                    onPressed: isSyncing
                                        ? null
                                        : () async {
                                            setSettingsState(() => isSyncing = true);
                                            try {
                                              final jsonStr = _generateFullDatabaseJson();
                                              final success = await GoogleDriveService.uploadDatabase(jsonStr);
                                              if (success && mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(backgroundColor: Color(0xFF047857), content: Text('Database backed up to Google Drive!')),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(backgroundColor: Colors.red, content: Text('Backup failed: $e')),
                                                );
                                              }
                                            } finally {
                                              setSettingsState(() => isSyncing = false);
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 46),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: isSyncing
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF047857)))
                                        : const Icon(Icons.cloud_download_rounded),
                                    label: const Text('Restore from Drive'),
                                    onPressed: isSyncing
                                        ? null
                                        : () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                title: const Text('Restore from Cloud?'),
                                                content: const Text('This replaces your current local database with the cloud backup. Proceed?'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                                  FilledButton(
                                                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                                                    onPressed: () => Navigator.pop(c, true),
                                                    child: const Text('Restore'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              setSettingsState(() => isSyncing = true);
                                              try {
                                                final remoteData = await GoogleDriveService.downloadDatabase();
                                                if (remoteData != null) {
                                                  _applyStateFromMap(remoteData);
                                                  Navigator.pop(ctx);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(backgroundColor: Color(0xFF047857), content: Text('Data restored successfully!')),
                                                  );
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(backgroundColor: Colors.red, content: Text('Restore failed: $e')),
                                                  );
                                                }
                                              } finally {
                                                setSettingsState(() => isSyncing = false);
                                              }
                                            }
                                          },
                                  ),
                                ] else ...[
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF047857),
                                      minimumSize: const Size(double.infinity, 46),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.login_rounded),
                                    label: const Text('Connect Google Drive'),
                                    onPressed: () async {
                                      final success = await GoogleDriveService.signIn();
                                      if (success) {
                                        setSettingsState(() {});
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // 6. Financial Year Tab
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Switch Active Accounting Year', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                                const SizedBox(height: 10),
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedFinancialYear,
                                      isExpanded: true,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      items: _financialYears.map((fy) => DropdownMenuItem(value: fy, child: Text('FY $fy'))).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          _carryForwardFinancialYearBalances(val);
                                          Navigator.pop(ctx);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
 Widget _customField(String label, TextEditingController ctrl, {String hint = '', bool isNum = false, bool readOnly = false, IconData? icon, VoidCallback? onTap, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmitted, int? maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
          const SizedBox(height: 5),
        ],
        SizedBox(
          height: (maxLines ?? 1) > 1 ? null : 40,
          child: TextField(
            controller: ctrl, readOnly: readOnly, onTap: onTap, onChanged: onChanged, onSubmitted: onSubmitted, maxLines: maxLines,
            keyboardType: isNum ? TextInputType.number : TextInputType.text,
            inputFormatters: isNum ? [] : [UpperCaseTextFormatter()],
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: icon != null ? Icon(icon, size: 18, color: const Color(0xFF64748B)) : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF047857), width: 1.5)),
              filled: true, fillColor: readOnly ? const Color(0xFFF8FAFC) : Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _customAutocomplete(
    String label,
    List<String> optionsList,
    String currentVal,
    String hint,
    Function(String) onSelect, {
    Key? key,
    VoidCallback? onAddPressed,
    FocusNode? focusNode,
    FocusNode? nextFocusNode,
  }) {
    final String inferredType = label.toUpperCase().contains('SELLER') || label.toUpperCase().contains('SUPPLIER')
        ? 'SELLER'
        : label.toUpperCase().contains('TRANSPORT')
            ? 'TRANSPORTER'
            : 'BUYER';

    final bool isFilterField = label.toUpperCase().contains('FILTER');

    return _CustomAutocompleteField(
      key: key ?? ValueKey('${label}_${optionsList.length}'),
      label: label,
      optionsList: optionsList,
      currentVal: currentVal,
      hint: hint,
      onSelect: onSelect,
      onAddPressed: onAddPressed ?? () => _showAddPartyDialog(
        initialType: inferredType,
        onCreated: (name) => onSelect(name),
      ),
      onAddNewWithName: isFilterField
          ? null
          : (typedName) {
              _showAddPartyDialog(
                initialName: typedName,
                initialType: inferredType,
                onCreated: (name) {
                  onSelect(name);
                  if (nextFocusNode != null) {
                    nextFocusNode.requestFocus();
                  } else {
                    FocusScope.of(context).nextFocus();
                  }
                },
              );
            },
      focusNode: focusNode,
      nextFocusNode: nextFocusNode,
    );
  }

  Widget _buildPinLockScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF081C15),
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded, size: 48, color: Color(0xFF047857)),
              ),
              const SizedBox(height: 16),
              const Text('ERP Locked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 6),
              const Text('Enter your 4-digit PIN to access the dashboard', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
              const SizedBox(height: 24),
              TextField(
                controller: _pinCtrl,
                obscureText: true,
                maxLength: 4,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "••••",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => setState(() => _forceEmailLogin = true),
                icon: const Icon(Icons.vpn_key_rounded, size: 16),
                label: const Text('Login with Master Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF64748B))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirstTimeEmailLoginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF081C15),
      body: Center(
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, size: 48, color: Color(0xFF047857)),
                    SizedBox(height: 12),
                    Text('CocoTrade Authentication', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    SizedBox(height: 6),
                    Text('Enter your credentials or active license key', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _customField('Customer Email', _loginEmailCtrl),
              const SizedBox(height: 12),
              _customField('License Key', _licenseKeyCtrl),
              const SizedBox(height: 12),
              _customField('Password', _loginPassCtrl),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final email = _loginEmailCtrl.text.trim();
                  final licKey = _licenseKeyCtrl.text.trim().toUpperCase();
                  if (_verifyLicenseKey(email, licKey) || (email.toLowerCase() == _savedEmail.toLowerCase() && _loginPassCtrl.text.trim() == _savedPassword)) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(_prefFirstLoginKey, true);
                    await prefs.setBool(_prefIsLicensedKey, true);
                    setState(() {
                      _isFirstLoginDone = true;
                      _isLicensed = true;
                      _isLocked = false;
                      _forceEmailLogin = false;
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text('Invalid License Key or Login!')));
                  }
                },
                child: const Text('Verify & Secure Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (!_isLicensed && !_isTrialExpired) ...[
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF047857)), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool(_prefFirstLoginKey, true);
                      setState(() {
                        _isFirstLoginDone = true;
                        _forceEmailLogin = false;
                        _isLocked = false;
                      });
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF047857), content: Text('Free Trial Active! $_trialDaysLeft days remaining.')));
                    },
                    child: Text('Start 2-Day Free Trial ($_trialDaysLeft days left)', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                  ),
                ),
              ],
              if (_isFirstLoginDone && _isLicensed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton.icon(
                      onPressed: () => setState(() => _forceEmailLogin = false),
                      icon: const Icon(Icons.pin, size: 16, color: Color(0xFF047857)),
                      label: const Text('Back to PIN Unlock', style: TextStyle(color: Color(0xFF047857), fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyProfileScreen() {
    final nameCtrl = TextEditingController(text: _companyName);
    final phoneCtrl = TextEditingController(text: _companyPhone);
    final addrCtrl = TextEditingController(text: _companyAddress);
    return Scaffold(
      backgroundColor: const Color(0xFF081C15),
      body: Center(
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Setup Business Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              const Text('This will appear on your tax invoices', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
              const SizedBox(height: 24),
              _customField('Business Name', nameCtrl),
              const SizedBox(height: 12),
              _customField('Phone', phoneCtrl),
              const SizedBox(height: 12),
              _customField('Address', addrCtrl, maxLines: 2),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_profile_setup_done', true);
                  await prefs.setString('company_name', nameCtrl.text.trim());
                  await prefs.setString('company_phone', phoneCtrl.text.trim());
                  await prefs.setString('company_address', addrCtrl.text.trim());
                  setState(() {
                    _companyName = nameCtrl.text.trim();
                    _companyPhone = phoneCtrl.text.trim();
                    _companyAddress = addrCtrl.text.trim();
                    _isProfileSetupDone = true;
                  });
                },
                child: const Text('Save Profile & Enter ERP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
} // Closes _MainLayoutScreenState

class _CustomAutocompleteField extends StatefulWidget {
  final String label;
  final List<String> optionsList;
  final String currentVal;
  final String hint;
  final Function(String) onSelect;
  final VoidCallback? onAddPressed;
  final ValueChanged<String>? onAddNewWithName;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;

  const _CustomAutocompleteField({
    super.key,
    required this.label,
    required this.optionsList,
    required this.currentVal,
    required this.hint,
    required this.onSelect,
    this.onAddPressed,
    this.onAddNewWithName,
    this.focusNode,
    this.nextFocusNode,
  });

  @override
  State<_CustomAutocompleteField> createState() => _CustomAutocompleteFieldState();
}

class _CustomAutocompleteFieldState extends State<_CustomAutocompleteField> {
  late TextEditingController _controller;
  FocusNode? _internalFocusNode;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentVal);
  }

  @override
  void didUpdateWidget(_CustomAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentVal != oldWidget.currentVal && widget.currentVal != _controller.text) {
      _controller.text = widget.currentVal;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
            ),
            if (widget.onAddPressed != null)
              InkWell(
                onTap: widget.onAddPressed,
                child: const Text(
                  '+ Add New',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 40,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Autocomplete<String>(
                focusNode: _effectiveFocusNode,
                textEditingController: _controller,
                optionsBuilder: (TextEditingValue textVal) {
                  final query = textVal.text.trim().toLowerCase();
                  if (query.isEmpty) return widget.optionsList;

                  // Only match options that start with or match whole words, 
                  // avoiding loose partial word fragments unless intended.
                  return widget.optionsList.where((opt) {
                    final lowerOpt = opt.toLowerCase();
                    return lowerOpt.startsWith(query) || lowerOpt.contains(' $query');
                  });
                },
                onSelected: (selection) {
                  widget.onSelect(selection);
                  if (widget.nextFocusNode != null) {
                    widget.nextFocusNode!.requestFocus();
                  } else {
                    FocusScope.of(context).nextFocus();
                  }
                },
                optionsViewBuilder: (context, onAutoCompleteSelect, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white,
                      child: Container(
                        width: constraints.maxWidth > 0 ? constraints.maxWidth : 280,
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: options.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('No match. Press Enter to add new', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF94A3B8))),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onAutoCompleteSelect(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Text(
                                        option,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  );
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    inputFormatters: [UpperCaseTextFormatter()],
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF047857), width: 1.5)),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B), size: 24),
                        tooltip: 'Show All ${widget.label}',
                        onSelected: (String selection) {
                          controller.text = selection;
                          widget.onSelect(selection);
                          if (widget.nextFocusNode != null) {
                            widget.nextFocusNode!.requestFocus();
                          } else {
                            FocusScope.of(context).nextFocus();
                          }
                        },
                        itemBuilder: (BuildContext context) {
                          if (widget.optionsList.isEmpty) {
                            return [
                              const PopupMenuItem<String>(
                                enabled: false,
                                value: '',
                                child: Text('No records found (Click + Add New)', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                              ),
                            ];
                          }
                          return widget.optionsList.map((String opt) {
                            return PopupMenuItem<String>(
                              value: opt,
                              child: Text(opt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    onChanged: (v) => widget.onSelect(v.toUpperCase()),
                    onSubmitted: (typedValue) {
                      final cleanVal = typedValue.trim().toUpperCase();
                      if (cleanVal.isEmpty) return;

                      // 1. Exact match
                      final exactMatch = widget.optionsList.firstWhere(
                        (opt) => opt.trim().toUpperCase() == cleanVal,
                        orElse: () => '',
                      );

                      if (exactMatch.isNotEmpty) {
                        controller.text = exactMatch;
                        widget.onSelect(exactMatch);
                        if (widget.nextFocusNode != null) {
                          widget.nextFocusNode!.requestFocus();
                        } else {
                          FocusScope.of(context).nextFocus();
                        }
                        return;
                      }

                      // 2. Single unambiguous prefix match
                      final partialMatches = widget.optionsList.where(
                        (opt) => opt.toUpperCase().contains(cleanVal),
                      ).toList();

                      if (partialMatches.length == 1) {
                        final matched = partialMatches.first;
                        controller.text = matched;
                        widget.onSelect(matched);
                        if (widget.nextFocusNode != null) {
                          widget.nextFocusNode!.requestFocus();
                        } else {
                          FocusScope.of(context).nextFocus();
                        }
                        return;
                      }

                      // 3. New party detected: pop dialog prefilled with typed name
                      if (widget.onAddNewWithName != null) {
                        widget.onAddNewWithName!(cleanVal);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------- CAPITALIZATION TEXT FORMATTER ----------------
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}