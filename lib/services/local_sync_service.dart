import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LocalSyncService {
  static HttpServer? _server;
  static const int port = 8080;

  // --- DESKTOP: Start Local Sync Server ---
  static Future<String?> startDesktopServer({
    required Function(Map<String, dynamic> incomingData) onDataReceived,
    required Map<String, dynamic> Function() getCurrentData,
  }) async {
    try {
      // Find local IPv4 address
      String? localIp;
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            localIp = addr.address;
            break;
          }
        }
        if (localIp != null) break;
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      debugPrint('Sync Server running at http://$localIp:$port');

      _server!.listen((HttpRequest req) async {
        // Enable CORS
        req.response.headers.add('Access-Control-Allow-Origin', '*');
        req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (req.method == 'OPTIONS') {
          req.response.statusCode = HttpStatus.ok;
          await req.response.close();
          return;
        }

        if (req.uri.path == '/sync') {
          if (req.method == 'GET') {
            // Mobile pulling latest data from Desktop
            final data = getCurrentData();
            req.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(data));
            await req.response.close();
          } else if (req.method == 'POST') {
            // Mobile pushing new data to Desktop
            final body = await utf8.decoder.bind(req).join();
            final Map<String, dynamic> parsed = jsonDecode(body);
            onDataReceived(parsed);

            req.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'success'}));
            await req.response.close();
          }
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });

      return localIp;
    } catch (e) {
      debugPrint('Error starting sync server: $e');
      return null;
    }
  }

  static void stopServer() {
    _server?.close(force: true);
    _server = null;
  }

  // --- MOBILE: Push Data to Desktop ---
  static Future<bool> pushToDesktop(String desktopIp, Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('http://$desktopIp:$port/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Push Sync Error: $e');
      return false;
    }
  }

  // --- MOBILE: Pull Latest Data from Desktop ---
  static Future<Map<String, dynamic>?> pullFromDesktop(String desktopIp) async {
    try {
      final res = await http.get(
        Uri.parse('http://$desktopIp:$port/sync'),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Pull Sync Error: $e');
    }
    return null;
  }
}