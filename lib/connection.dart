// =============================================================================
// FILE: lib/connection.dart
// SYSTEM: IPYUI QUANTUM CONNECTION (STABLE VERSION)
// DESC: Handles WebSocket, Caching, and Binary Streams with Auto-Reconnect
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

// MODULE LINKS
import 'kernel.dart';
import 'utils.dart'; // Logger uchun
import 'devtools.dart'; // Network monitor uchun

// =============================================================================
// 1. STORAGE MANAGER (CACHE & COOKIES)
// =============================================================================

class StorageManager {
  static final StorageManager instance = StorageManager._internal();
  StorageManager._internal();

  SharedPreferences? _prefs;

  /// Tizimni yuklash
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    Logger.instance.add("Storage Initialized", LogType.system);
  }

  // --- UI CACHING (OFFLINE MODE) ---
  
  Future<void> cacheUI(Map<String, dynamic> uiTree) async {
    if (_prefs == null) return;
    try {
      final raw = jsonEncode(uiTree);
      await _prefs!.setString('cached_ui_tree', raw);
      // Logger.instance.add("UI Cached", LogType.system);
    } catch (e) {
      print("Cache Save Error: $e");
    }
  }

  Map<String, dynamic>? loadCachedUI() {
    if (_prefs == null) return null;
    final raw = _prefs!.getString('cached_ui_tree');
    if (raw != null && raw.isNotEmpty) {
      try {
        return jsonDecode(raw);
      } catch (e) {
        print("Cache Corrupted");
      }
    }
    return null;
  }

  // --- COOKIES (SESSION) ---
  
  Future<void> setCookie(String key, String value) async {
    await _prefs?.setString('cookie_$key', value);
  }

  Map<String, String> getAllCookies() {
    if (_prefs == null) return {};
    final keys = _prefs!.getKeys();
    final cookies = <String, String>{};
    for (var k in keys) {
      if (k.startsWith('cookie_')) {
        cookies[k.substring(7)] = _prefs!.getString(k) ?? "";
      }
    }
    return cookies;
  }
}

// =============================================================================
// 2. CONNECTION MANAGER (WEBSOCKET ENGINE)
// =============================================================================

class ConnectionManager {
  static final ConnectionManager instance = ConnectionManager._internal();
  ConnectionManager._internal();

  // Config
  static const String _defaultUrl = "ws://localhost:8000/ws";
  
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  String _activeUrl = _defaultUrl;
  bool _isConnecting = false;

  /// 1. Tizimni ishga tushirish (Main.dart chaqiradi)
  Future<void> initialize() async {
    // A. Xotirani yuklash
    await StorageManager.instance.init();

    // B. Keshdagi UIni yuklash (Internetni kutmasdan)
    final cachedUI = StorageManager.instance.loadCachedUI();
    if (cachedUI != null) {
      Logger.instance.add("UI Loaded from Cache (Offline Mode)", LogType.system);
      // Kernelga beramiz, u UI ni chizadi
      IpyKernel.instance.processManualUI(cachedUI);
    } else {
      Logger.instance.add("No Cache Found", LogType.info);
    }

    // C. Internetni kuzatish
    Connectivity().onConnectivityChanged.listen((results) {
      // Yangi versiyada List<ConnectivityResult> qaytadi
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet && !IpyKernel.instance.isConnected) {
        Logger.instance.add("Network Detected. Reconnecting...", LogType.network);
        connect(_activeUrl);
      }
    });
  }

  /// 2. Serverga Ulanish
  void connect(String url) {
    if (IpyKernel.instance.isConnected || _isConnecting) return;
    
    _activeUrl = url;
    _isConnecting = true;
    _reconnectTimer?.cancel();

    Logger.instance.add("Dialing $url...", LogType.network);

    try {
      // WebSocket yaratish
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // Tinglashni boshlash
      _channel!.stream.listen(
        (message) => _onData(message),
        onDone: () {
          _handleDisconnect("Server Closed Connection");
        },
        onError: (error) {
          _handleDisconnect("Socket Error: $error");
        },
      );

      // Muvaffaqiyatli ulanish
      _handleConnected();

    } catch (e) {
      _handleDisconnect("Fatal Init Error: $e");
    }
  }

  /// Ulanganda bajariladigan ishlar
  void _handleConnected() {
    _isConnecting = false;
    IpyKernel.instance.isConnected = true;
    IpyKernel.instance.forceNotify(); // UI ga "Men ulandim!" deb aytadi
    
    Logger.instance.add("✅ Connection Established", LogType.network);

    // Handshake (Salomlashish)
    final cookies = StorageManager.instance.getAllCookies();
    final handshake = {
      "type": "system",
      "event": "handshake",
      "platform": Platform.operatingSystem,
      "cookies": cookies
    };
    sendJson(handshake);

    // Ping (Har 30 soniyada)
    _startHeartbeat();
  }

  /// Uzilganda bajariladigan ishlar
  void _handleDisconnect(String reason) {
    if (!_isConnecting && !IpyKernel.instance.isConnected) return; // Allaqachon uzilgan

    _isConnecting = false;
    IpyKernel.instance.isConnected = false;
    IpyKernel.instance.forceNotify(); // UI ga "Uzildim" deb aytadi
    
    _stopHeartbeat();
    _channel = null;

    Logger.instance.add("🔴 Disconnected: $reason", LogType.network);
    print("Reconnect scheduled in 3s...");

    // 3 soniyadan keyin qayta urinish
    _reconnectTimer = Timer(const Duration(seconds: 3), () => connect(_activeUrl));
  }

  // ===========================================================================
  // DATA PROCESSOR
  // ===========================================================================

  void _onData(dynamic message) {
    try {
      // 1. BINARY (Tezkor)
      if (message is List<int>) {
        final bytes = Uint8List.fromList(message);
        IpyKernel.instance.processIncoming(bytes);
        DevToolsManager.instance.addPacket('IN', 'BINARY', 'Binary Stream', bytes.length);
        return;
      }

      // 2. TEXT (JSON)
      if (message is String) {
        // DevTools uchun
        DevToolsManager.instance.addPacket('IN', 'JSON', message, message.length);

        // Avtomatik Kesh (Agar Update bo'lsa)
        if (message.contains('"type":"update"')) {
           try {
             final data = jsonDecode(message);
             if (data['tree'] != null) {
               StorageManager.instance.cacheUI(data['tree']);
             }
           } catch (_) {}
        }
        
        // Kernelga uzatish
        IpyKernel.instance.processIncoming(message);
      }
    } catch (e) {
      Logger.instance.add("Parse Error: $e", LogType.error);
    }
  }

  // ===========================================================================
  // SENDERS
  // ===========================================================================

  void sendJson(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      final jsonStr = jsonEncode(data);
      _channel!.sink.add(jsonStr);
      
      // Pingdan boshqasini log qilamiz
      if (data['type'] != 'system') {
        DevToolsManager.instance.addPacket('OUT', 'JSON', data, jsonStr.length);
      }
    } catch (e) {
      Logger.instance.add("Send Error: $e", LogType.error);
    }
  }

  void sendBinary(Uint8List data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(data);
      DevToolsManager.instance.addPacket('OUT', 'BINARY', 'Raw Bytes', data.length);
    } catch (e) {
      Logger.instance.add("Bin Send Error: $e", LogType.error);
    }
  }

  // ===========================================================================
  // HEARTBEAT (PING/PONG)
  // ===========================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (IpyKernel.instance.isConnected) {
        sendJson({"type": "system", "event": "ping"});
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }
}
