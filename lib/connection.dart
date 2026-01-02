// =============================================================================
// FILE: lib/connection.dart
// PROJECT: IPYUI QUANTUM RUNTIME
// MODULE: HIGH-PERFORMANCE TRANSPORT LAYER
// FEATURES: Binary Streams, Cookie/Cache Persistence, Auto-Reconnection, Offline Mode
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// INTERNAL LINKS
import 'kernel.dart';
import 'devtools.dart';
import 'utils.dart';

// =============================================================================
// 1. CACHE & STORAGE MANAGER (Browser-like Cookies)
// =============================================================================

class StorageManager {
  static final StorageManager instance = StorageManager._internal();
  StorageManager._internal();

  late SharedPreferences _prefs;
  bool _ready = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
    Logger.instance.add("Storage Manager Initialized", LogType.system);
  }

  // --- COOKIES (Session / Auth) ---
  Future<void> setCookie(String key, String value) async {
    await _prefs.setString('cookie_$key', value);
  }

  String? getCookie(String key) {
    return _prefs.getString('cookie_$key');
  }

  Map<String, String> getAllCookies() {
    final keys = _prefs.getKeys();
    final cookies = <String, String>{};
    for (var k in keys) {
      if (k.startsWith('cookie_')) {
        cookies[k.substring(7)] = _prefs.getString(k) ?? "";
      }
    }
    return cookies;
  }

  // --- UI CACHING (Instant Load) ---
  Future<void> cacheUI(Map<String, dynamic> uiTree) async {
    // UI ni siqilgan holda saqlaymiz
    final raw = jsonEncode(uiTree);
    await _prefs.setString('cached_ui_tree', raw);
  }

  Map<String, dynamic>? loadCachedUI() {
    final raw = _prefs.getString('cached_ui_tree');
    if (raw != null) {
      try {
        return jsonDecode(raw);
      } catch (e) {
        Logger.instance.add("Cache Corrupted: $e", LogType.error);
      }
    }
    return null;
  }

  Future<void> clearCache() async {
    await _prefs.remove('cached_ui_tree');
  }
}

// =============================================================================
// 2. CONNECTION MANAGER (The Binary Highway)
// =============================================================================

class ConnectionManager {
  static final ConnectionManager instance = ConnectionManager._internal();
  ConnectionManager._internal();

  // Configuration
  static const String _defaultUrl = "ws://localhost:8000/ws";
  static const Duration _pingInterval = Duration(seconds: 30);

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isConnecting = false;
  String _activeUrl = _defaultUrl;

  // Status
  bool get isConnected => IpyKernel.instance.isConnected;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> initialize() async {
    // 1. Storage ni yuklaymiz
    await StorageManager.instance.init();

    // 2. Keshdagi UI ni darhol ko'rsatamiz (Offline First)
    final cachedUI = StorageManager.instance.loadCachedUI();
    if (cachedUI != null) {
      Logger.instance
          .add("Loaded UI from Local Cache (Instant)", LogType.system);
      IpyKernel.instance.processManualUI(cachedUI);
    }

    // 3. Tarmoqni kuzatish
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none && !isConnected) {
        connect(_activeUrl);
      }
    });
  }

  void connect(String url) {
    if (_isConnecting || isConnected) return;
    _isConnecting = true;
    _activeUrl = url;

    Logger.instance.add("Dialing Kernel: $url", LogType.network);

    try {
      // Cookiesni headerga qo'shamiz
      // Eslatma: Dart WebSocket ba'zi platformalarda headerlarni cheklaydi,
      // shuning uchun biz 'Handshake' paketini yuboramiz.

      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) => _onData(message),
        onDone: _onDisconnect,
        onError: (error) {
          Logger.instance.add("Socket Error: $error", LogType.error);
          _onDisconnect();
        },
      );

      // Muvaffaqiyatli ulanish
      _handleConnected();
    } catch (e) {
      Logger.instance.add("Fatal Connection Error: $e", LogType.error);
      _onDisconnect();
    }
  }

  void _handleConnected() {
    _isConnecting = false;
    IpyKernel.instance.isConnected = true;
    IpyKernel.instance.forceNotify(); // UI ga "Online" deb bildirish

    Logger.instance.add("Tunnel Established 🟢", LogType.network);

    // Handshake: Cookies va Device Info yuborish
    final cookies = StorageManager.instance.getAllCookies();
    final handshake = {
      "type": "system",
      "event": "handshake",
      "platform": Platform.operatingSystem,
      "cookies": cookies
    };
    sendJson(handshake);

    // Heartbeatni boshlash
    _startHeartbeat();
  }

  void _onDisconnect() {
    _isConnecting = false;
    IpyKernel.instance.isConnected = false;
    IpyKernel.instance.forceNotify(); // UI ga "Offline" deb bildirish

    _stopHeartbeat();
    _channel = null;

    // Reconnect Logic (Exponential Backoff o'rniga oddiy 3 soniya)
    Logger.instance.add("Link Lost 🔴. Retrying in 3s...", LogType.network);
    _reconnectTimer?.cancel();
    _reconnectTimer =
        Timer(const Duration(seconds: 3), () => connect(_activeUrl));
  }

  // ===========================================================================
  // DATA HANDLING (The Fast Lane)
  // ===========================================================================

  void _onData(dynamic message) {
    try {
      // BINARY (Images, Files, Audio)
      if (message is List<int>) {
        final bytes = Uint8List.fromList(message);
        IpyKernel.instance.processIncoming(bytes);
        return;
      }

      // TEXT (JSON)
      if (message is String) {
        // Avtomatik Keshlashtirish (Faqat to'liq update kelsa)
        // Biz buni Kernelga yuboramiz, u hal qiladi, lekin bu yerda JSON ekanligini bilamiz.
        if (message.contains('"type":"update"')) {
          // Oddiy check, chuqur parse qilmaslik uchun (Performance)
          // Asl parsing Kernelda bo'ladi.
          StorageManager.instance.cacheUI(jsonDecode(message)['tree']);
        }

        IpyKernel.instance.processIncoming(message);
      }
    } catch (e) {
      Logger.instance.add("Packet Corrupted: $e", LogType.error);
    }
  }

  // ===========================================================================
  // SENDING METHODS
  // ===========================================================================

  /// Standard JSON yuborish (UI events)
  void sendJson(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      final jsonStr = jsonEncode(data);
      _channel!.sink.add(jsonStr);
      // DevTools da faqat chiquvchi trafikni ko'rsatish (juda ko'p bo'lmasligi uchun filter)
      if (data['type'] != 'ping') {
        DevToolsManager.instance.addPacket('OUT', 'JSON', data, jsonStr.length);
      }
    } catch (e) {
      Logger.instance.add("Send Failed: $e", LogType.error);
    }
  }

  /// Binary yuborish (Kamera, Fayl, Ovoz)
  void sendBinary(Uint8List data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(data);
      DevToolsManager.instance
          .addPacket('OUT', 'BINARY', 'Raw Bytes', data.length);
    } catch (e) {
      Logger.instance.add("Binary Send Failed: $e", LogType.error);
    }
  }

  // ===========================================================================
  // UTILS
  // ===========================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_pingInterval, (timer) {
      if (isConnected) {
        sendJson({"type": "system", "event": "ping"});
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  void close() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.goingAway);
  }
}
