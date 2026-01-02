// =============================================================================
// FILE: lib/kernel.dart
// PROJECT: IPYUI QUANTUM RUNTIME
// DESC: Kernel-level OS integration (Camera, Mic, Notifications, Taskbar)
// FEATURES: Background Tasks, Hardware Bridge, Network Watchdog
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// OS & Hardware Plugins
import 'package:window_manager/window_manager.dart';
import 'package:camera/camera.dart';
import 'package:record/record.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

// Internal Modules
import 'utils.dart';
import 'devtools.dart';
import 'connection.dart';

/// IpyKernel - Ilovaning Operatsion Tizim bilan bog'lanish nuqtasi.
class IpyKernel extends ChangeNotifier {
  static final IpyKernel instance = IpyKernel._internal();
  IpyKernel._internal();

  // --- STATE ---
  bool isConnected = false;
  bool isInitialized = false;
  Map<String, dynamic>? uiTree;
  Map<String, dynamic> config = {
    "title": "IPYUI App",
    "theme": "light",
    "ui_mode": "material",
    "debug": true,
  };

  // --- HARDWARE HANDLES ---
  CameraController? cameraController;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // --- STREAMS ---
  final _bgTaskController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get backgroundTasks => _bgTaskController.stream;

  // ===========================================================================
  // 1. INITIALIZATION (KERNEL BOOT)
  // ===========================================================================

  Future<void> boot() async {
    if (isInitialized) return;

    // 1.1 Bildirishnomalarni sozlash
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _notifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit));

    // 1.2 Network Watchdog (Internet nazorati)
    Connectivity().onConnectivityChanged.listen((results) {
      final status = results.first != ConnectivityResult.none;
      Logger.instance
          .add("Network: ${status ? 'Online' : 'Offline'}", LogType.network);
      DevToolsManager.instance
          .addLog("Connectivity changed: $status", LogType.system);
    });

    // 1.3 Windows/Taskbar management
    if (Platform.isWindows) {
      await windowManager
          .setPreventClose(true); // Yopilishni kernel nazorat qiladi
    }

    isInitialized = true;
    Logger.instance.add("Kernel Boot Successful", LogType.system);
  }

  // ===========================================================================
  // 2. CORE COMMUNICATION (JSON & BINARY ROUTER)
  // ===========================================================================

  /// Pythondan kelgan barcha buyruqlarni saralash (Master Router)
  void processIncoming(dynamic message) {
    if (message is String) {
      final data = jsonDecode(message);
      final type = data['type'];

      // DevTools uchun tarmoq logi
      DevToolsManager.instance.addPacket('IN', 'JSON', data, message.length);

      switch (type) {
        case 'update':
          uiTree = data['tree'];
          notifyListeners();
          break;
        case 'config':
          config.addAll(data['payload']);
          _applyKernelConfig();
          notifyListeners();
          break;
        case 'kernel_call':
          _handleHardwareBridge(data['method'], data['args']);
          break;
        case 'dartp':
          DartP.instance.execute(data['code']);
          break;
      }
    } else if (message is Uint8List) {
      // BINARY DATA HANDLING (Images, Models, Audio streams)
      DevToolsManager.instance
          .addPacket('IN', 'BINARY', 'Binary Stream', message.length);
      _handleBinaryStream(message);
    }
  }

  // ===========================================================================
  // 3. HARDWARE BRIDGE (Camera, Mic, Toast, Taskbar)
  // ===========================================================================

  Future<void> _handleHardwareBridge(
      String method, Map<String, dynamic> args) async {
    Logger.instance.add("Kernel Call: $method", LogType.system);

    switch (method) {
      // --- NOTIFICATIONS & UI ---
      case 'showToast':
        _showToast(args['message']);
        break;
      case 'notify':
        _showSystemNotification(args['title'], args['body']);
        break;

      // --- WINDOW & TASKBAR ---
      case 'setTaskbarProgress':
        if (Platform.isWindows) {
          await windowManager.setProgressBar((args['value'] as num).toDouble());
        }
        break;
      case 'setAlwaysOnTop':
        await windowManager.setAlwaysOnTop(args['value'] == true);
        break;

      // --- MULTIMEDIA ---
      case 'initCamera':
        _initializeCamera();
        break;
      case 'startRecording':
        _startAudioCapture();
        break;

      // --- NETWORK ---
      case 'checkInternet':
        final status = await Connectivity().checkConnectivity();
        instance.send(
            "kernel", "internet_status", status != ConnectivityResult.none);
        break;

      default:
        Logger.instance.add("Unknown kernel method: $method", LogType.error);
    }
  }

  // ===========================================================================
  // 4. KERNEL UTILITIES (Private Implementations)
  // ===========================================================================

  void _applyKernelConfig() {
    if (config['title'] != null) windowManager.setTitle(config['title']);
    // Theme switching logic here
  }

  void _showToast(String message) {
    // ScaffoldMessenger or custom overlay
    DevToolsManager.instance.addLog("Toast: $message", LogType.info);
    HapticFeedback.lightImpact();
  }

  Future<void> _showSystemNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
        'kernel_id', 'Kernel Alerts',
        importance: Importance.max);
    const iosDetails = DarwinNotificationDetails();
    await _notifications.show(0, title, body,
        const NotificationDetails(android: androidDetails, iOS: iosDetails));
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw "No camera found";

      cameraController =
          CameraController(cameras.first, ResolutionPreset.medium);
      await cameraController!.initialize();
      notifyListeners();
      Logger.instance.add("Camera Initialized", LogType.system);
    } catch (e) {
      Logger.instance.add("Camera Error: $e", LogType.error);
    }
  }

  Future<void> _startAudioCapture() async {
    if (await _audioRecorder.hasPermission()) {
      // Stream audio bytes back to Python via Connection
      Logger.instance.add("Audio recording started", LogType.system);
    }
  }

  void _handleBinaryStream(Uint8List data) {
    // Process binary data from Python (e.g. dynamic textures or file chunks)
    Logger.instance
        .add("Received binary stream: ${data.length} bytes", LogType.network);
  }

  // ===========================================================================
  // 5. EXTERNAL INTERFACE
  // ===========================================================================

  /// Pythonga xabar yuborish
  void send(String id, String handler, dynamic val) {
    ConnectionManager.instance.sendJson(
        {"type": "event", "id": id, "handler": handler, "value": val});
    DevToolsManager.instance.addPacket('OUT', 'JSON', val, 0);
  }

  /// Manual UI Update (DevTools uchun)
  void processManualUI(Map<String, dynamic> tree) {
    uiTree = tree;
    notifyListeners();
  }

  void forceNotify() => notifyListeners();
}
