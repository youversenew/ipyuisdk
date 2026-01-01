// =============================================================================
// FILE: lib/main.dart
// SYSTEM: IPYUI UNIVERSAL RUNTIME v5.0 (GOD MODE)
// FEATURES: Deep Inspector, DartP v2, CSS-like Box, Native Bridge
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

import 'package:window_manager/window_manager.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibration/vibration.dart';

// =============================================================================
// 1. BOOTSTRAP
// =============================================================================

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Desktop Window Setup
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 800),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    runApp(const IpyApp());
  }, (error, stack) {
    debugPrint("🔥 KERNEL PANIC: $error");
  });
}

// =============================================================================
// 2. ROOT & ENGINE PROVIDER
// =============================================================================

class IpyApp extends StatefulWidget {
  const IpyApp({super.key});
  @override
  State<IpyApp> createState() => _IpyAppState();
}

class _IpyAppState extends State<IpyApp> {
  final Engine _engine = Engine();

  @override
  void initState() {
    super.initState();
    _engine.init(this);
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return EngineInherited(
      engine: _engine,
      child: MaterialApp(
        title: _engine.config['title'] ?? 'IPYUI',
        debugShowCheckedModeBanner: false,
        themeMode: _engine.themeMode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const IpyShell(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final seed = _Utils.parseColor(_engine.config['seed_color']) ?? Colors.blue;
    final font = _engine.config['font'] ?? 'Roboto';
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme:
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      fontFamily: GoogleFonts.getFont(font).fontFamily,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF121212)
          : Colors.white,
    );
  }
}

class EngineInherited extends InheritedWidget {
  final Engine engine;
  const EngineInherited(
      {super.key, required this.engine, required super.child});
  static Engine of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EngineInherited>()!.engine;
  @override
  bool updateShouldNotify(EngineInherited old) => false;
}

// =============================================================================
// 3. APP SHELL (WINDOW & TOOLS)
// =============================================================================

class IpyShell extends StatefulWidget {
  const IpyShell({super.key});
  @override
  State<IpyShell> createState() => _IpyShellState();
}

class _IpyShellState extends State<IpyShell> with WindowListener {
  late Engine _engine;
  bool _showDevTools = false;
  bool _inspectMode = false;
  final FocusNode _fn = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = EngineInherited.of(context);
    _engine.setContext(context);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _fn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _fn,
      autofocus: true,
      onKey: (e) {
        if (e is RawKeyDownEvent && e.logicalKey == LogicalKeyboardKey.f12) {
          setState(() => _showDevTools = !_showDevTools);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                if (_engine.config['title_bar'] != 'none') _buildTitleBar(),
                Expanded(
                  child: _engine.isConnected && _engine.rootNode != null
                      ? UniversalRenderer(
                          node: _engine.rootNode!,
                          inspectMode: _inspectMode,
                        )
                      : const SplashScreen(),
                ),
              ],
            ),

            // DevTools Overlay
            if (_showDevTools)
              Positioned.fill(
                child: DevTools(
                  engine: _engine,
                  inspectMode: _inspectMode,
                  onToggleInspect: () =>
                      setState(() => _inspectMode = !_inspectMode),
                  onClose: () => setState(() => _showDevTools = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 32,
      color: isDark ? Colors.black : Colors.grey[200],
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Row(
          children: [
            const SizedBox(width: 10),
            if (_engine.config['icon'] != null)
              Image.network(_engine.config['icon'], width: 16, height: 16),
            const SizedBox(width: 8),
            Text(_engine.config['title'] ?? 'IPYUI',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87)),
            const Spacer(),
            _WinBtn(Icons.remove, windowManager.minimize),
            _WinBtn(Icons.check_box_outline_blank, windowManager.maximize),
            _WinBtn(Icons.close, windowManager.close, isRed: true),
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isRed;
  const _WinBtn(this.icon, this.onTap, {this.isRed = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 14, color: isRed ? Colors.red : Colors.grey),
      ),
    );
  }
}

// =============================================================================
// 4. ENGINE (LOGIC CORE)
// =============================================================================

class Engine {
  static const String _url = 'ws://localhost:8000/ws';

  _IpyAppState? _rootState;
  BuildContext? _ctx;
  WebSocketChannel? _ws;

  bool isConnected = false;
  Map<String, dynamic>? rootNode;
  Map<String, dynamic> config = {'title': 'IPYUI', 'theme': 'light'};
  ThemeMode themeMode = ThemeMode.light;
  List<String> logs = [];
  Map<String, dynamic>? inspectedNode; // For Inspector

  void init(_IpyAppState state) {
    _rootState = state;
    _connect();
  }

  void setContext(BuildContext ctx) => _ctx = ctx;

  void log(String msg, {String type = "INFO"}) {
    final time =
        "${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}";
    logs.add("[$time] [$type] $msg");
    if (logs.length > 1000) logs.removeAt(0);
  }

  void _connect() {
    log("Connecting...", type: "NET");
    try {
      _ws = WebSocketChannel.connect(Uri.parse(_url));
      _ws!.stream.listen(_onMsg,
          onDone: _onDisconnect, onError: (e) => _onDisconnect());
      isConnected = true;
      log("Connected", type: "NET");
      _rootState?.rebuild();
    } catch (e) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    isConnected = false;
    log("Disconnected. Retrying...", type: "NET");
    _rootState?.rebuild();
    Future.delayed(const Duration(seconds: 2), _connect);
  }

  void _onMsg(dynamic msg) {
    try {
      final data = jsonDecode(msg);
      final type = data['type'];

      if (type == 'update') {
        rootNode = data['tree'];
        _rootState?.rebuild();
      } else if (type == 'config') {
        config.addAll(data);
        themeMode =
            config['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
        _rootState?.rebuild();
      } else if (type == 'plugin') {
        _handlePlugin(data['plugin_name'], data['data']);
      } else if (type == 'dartp') {
        DartP.exec(data['code'], _ctx);
      }
    } catch (e) {
      log("Protocol Error: $e", type: "ERR");
    }
  }

  void send(String id, String handler, dynamic value) {
    if (_ws != null && isConnected) {
      _ws!.sink.add(jsonEncode(
          {"type": "event", "id": id, "handler": handler, "value": value}));
      log("Event: $handler -> $id", type: "OUT");
    }
  }

  void _handlePlugin(String name, Map data) async {
    log("Plugin: $name", type: "SYS");
    try {
      if (name == 'toast') {
        ScaffoldMessenger.of(_ctx!)
            .showSnackBar(SnackBar(content: Text(data['message'])));
      } else if (name == 'launcher') {
        launchUrl(Uri.parse(data['url']));
      } else if (name == 'vibrate') {
        if (await Vibration.hasVibrator() ?? false) Vibration.vibrate();
      } else if (name == 'image_picker') {
        final f = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (f != null) send("system", "image_picked", f.path);
      }
    } catch (e) {
      log(e.toString(), type: "ERR");
    }
  }

  void setInspectedNode(Map<String, dynamic> node) {
    inspectedNode = node;
    // Force devtools to update if open (simplification)
  }
}

// =============================================================================
// 5. DARTP V2 (INTERPRETER)
// =============================================================================

class DartP {
  static void exec(String code, BuildContext? context) {
    if (context == null) return;
    final cmd = code.trim();
    print("DartP: $cmd");

    try {
      // Logic Parsing
      if (cmd == "Navigator.pop()") Navigator.pop(context);
      if (cmd == "Window.close()") windowManager.close();
      if (cmd == "Window.maximize()") windowManager.maximize();

      // Advanced: "ScrollTo(0)"
      // Advanced: "Animate(opacity, 0.5)"
    } catch (e) {
      print("DartP Error: $e");
    }
  }
}

// =============================================================================
// 6. UNIVERSAL RENDERER (THE COMPILER)
// =============================================================================

class UniversalRenderer extends StatelessWidget {
  final Map<String, dynamic> node;
  final bool inspectMode;

  const UniversalRenderer(
      {super.key, required this.node, this.inspectMode = false});

  @override
  Widget build(BuildContext context) {
    Widget child = _buildWidget(context);

    // INSPECT OVERLAY
    if (inspectMode) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            EngineInherited.of(context).setInspectedNode(node);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Inspecting: ${node['type']}"),
              duration: const Duration(milliseconds: 500),
            ));
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2),
              color: Colors.blue.withOpacity(0.1),
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }

  Widget _buildWidget(BuildContext context) {
    try {
      final type = node['type'];
      final props = node['props'] ?? {};
      final children = (node['children'] as List?)
              ?.map((c) => UniversalRenderer(node: c, inspectMode: inspectMode))
              .toList() ??
          [];
      final engine = EngineInherited.of(context);

      Widget w;

      switch (type) {
        // --- LAYOUTS ---
        case 'row':
          w = Row(
            mainAxisAlignment: _Utils.mainAlign(props['align']),
            crossAxisAlignment: _Utils.crossAlign(props['cross_align']),
            children: children.cast<Widget>(),
          );
          break;
        case 'column':
          w = Column(
            mainAxisAlignment: _Utils.mainAlign(props['align']),
            crossAxisAlignment: _Utils.crossAlign(props['cross_align']),
            children: children.cast<Widget>(),
          );
          break;
        case 'stack':
          w = Stack(
            alignment: _Utils.align(props['align']) ?? Alignment.topLeft,
            children: children.cast<Widget>(),
          );
          break;
        case 'listview':
          w = ListView(
            padding: _Utils.padding(props['padding']),
            children: children.cast<Widget>(),
          );
          break;

        // --- COMPONENTS ---
        case 'text':
          w = Text(
            props['value']?.toString() ?? '',
            style: _Utils.textStyle(props),
            textAlign: _Utils.textAlign(props['align']),
          );
          break;
        case 'icon':
          w = Icon(
            _Utils.parseIcon(props['icon']),
            size: props['size']?.toDouble() ?? 24,
            color: _Utils.parseColor(props['color']),
          );
          break;
        case 'image':
          final src = props['src'] ?? '';
          final fit = _Utils.boxFit(props['fit']);
          w = src.endsWith('.svg')
              ? SvgPicture.network(src, fit: fit)
              : Image.network(src, fit: fit);
          break;

        // --- CUSTOM UI (Dynamic Button) ---
        case 'button':
        case 'ElevatedButton':
          w = ElevatedButton(
            onPressed: () => _emit(engine, node['id'], 'click'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _Utils.parseColor(props['bg_color']),
              foregroundColor: _Utils.parseColor(props['color']),
              elevation: props['elevation']?.toDouble(),
              padding: _Utils.padding(props['padding']),
              shape: _Utils.shape(props['shape']), // Dynamic Shape!
            ),
            child: children.isNotEmpty
                ? children.first
                : Text(props['text'] ?? 'Button'),
          );
          break;

        // --- INPUTS ---
        case 'input':
          w = TextField(
            decoration: InputDecoration(
              labelText: props['label'],
              hintText: props['placeholder'],
              filled: true,
              fillColor: _Utils.parseColor(props['bg_color']),
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(props['radius']?.toDouble() ?? 8)),
            ),
            obscureText: props['password'] == true,
            onChanged: (v) => _emit(engine, node['id'], 'change', val: v),
          );
          break;

        // --- THE "BOX" (Universal Container) ---
        default:
          w = Container(
            width: props['width']?.toDouble(),
            height: props['height']?.toDouble(),
            margin: _Utils.padding(props['margin']),
            padding: _Utils.padding(props['padding']),
            alignment: _Utils.align(props['alignment']),
            decoration: BoxDecoration(
              color: _Utils.parseColor(props['bg_color']),
              gradient: _Utils.gradient(props['gradient']),
              borderRadius:
                  BorderRadius.circular(props['radius']?.toDouble() ?? 0),
              border: props['border_color'] != null
                  ? Border.all(
                      color: _Utils.parseColor(props['border_color'])!,
                      width: props['border_width']?.toDouble() ?? 1)
                  : null,
              boxShadow: props['shadow'] == true
                  ? [
                      const BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 5))
                    ]
                  : null,
            ),
            child: children.isNotEmpty ? children.first : null,
          );
      }

      // --- WRAPPERS ---
      if (props['expanded'] == true || props['flex'] != null) {
        w = Expanded(flex: props['flex'] ?? 1, child: w);
      }
      if (props.containsKey('click')) {
        w = GestureDetector(
            onTap: () => _emit(engine, node['id'], 'click'), child: w);
      }
      if (props['opacity'] != null) {
        w = Opacity(opacity: props['opacity'].toDouble(), child: w);
      }

      return w;
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(border: Border.all(color: Colors.red)),
        child: Text("ERR: ${node['type']}",
            style: const TextStyle(fontSize: 8, color: Colors.red)),
      );
    }
  }

  void _emit(Engine engine, String? id, String evt, {dynamic val}) {
    if (id != null) engine.send(id, evt, val);
  }
}

// =============================================================================
// 7. DEVTOOLS OVERLAY
// =============================================================================

class DevTools extends StatelessWidget {
  final Engine engine;
  final bool inspectMode;
  final VoidCallback onToggleInspect;
  final VoidCallback onClose;

  const DevTools(
      {super.key,
      required this.engine,
      required this.onClose,
      required this.inspectMode,
      required this.onToggleInspect});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 1. Logs & Console (Bottom)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border: Border(
                    top: BorderSide(color: Colors.greenAccent, width: 2)),
              ),
              child: Column(
                children: [
                  _header(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Logs
                        Expanded(flex: 2, child: _logView()),
                        // Right: Inspector
                        Container(width: 1, color: Colors.white24),
                        Expanded(flex: 1, child: _inspectorView()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: Colors.black,
      child: Row(
        children: [
          const Text("🛠️ IPYUI DEVTOOLS",
              style: TextStyle(
                  color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          const SizedBox(width: 20),
          _toolBtn(inspectMode ? "INSPECTING..." : "INSPECT",
              Icons.find_in_page, onToggleInspect,
              active: inspectMode),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 16),
              onPressed: onClose),
        ],
      ),
    );
  }

  Widget _toolBtn(String lbl, IconData icon, VoidCallback cb,
      {bool active = false}) {
    return InkWell(
      onTap: cb,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.grey[800],
            borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(lbl, style: const TextStyle(color: Colors.white, fontSize: 10))
        ]),
      ),
    );
  }

  Widget _logView() {
    return ListView.builder(
      padding: const EdgeInsets.all(5),
      itemCount: engine.logs.length,
      itemBuilder: (c, i) => Text(
        engine.logs[engine.logs.length - 1 - i],
        style: const TextStyle(
            color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  Widget _inspectorView() {
    if (engine.inspectedNode == null)
      return const Center(
          child:
              Text("Select an element", style: TextStyle(color: Colors.grey)));

    String jsonStr = "";
    try {
      jsonStr =
          const JsonEncoder.withIndent('  ').convert(engine.inspectedNode);
    } catch (_) {}

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Text(jsonStr,
          style: const TextStyle(
              color: Colors.orangeAccent,
              fontFamily: 'monospace',
              fontSize: 11)),
    );
  }
}

// =============================================================================
// 8. UTILS (PARSERS)
// =============================================================================

class _Utils {
  static Color? parseColor(dynamic val) {
    if (val is String) {
      if (val.startsWith('#'))
        return Color(
            int.parse(val.replaceAll('#', ''), radix: 16) + 0xFF000000);
      const m = {
        'white': Colors.white,
        'black': Colors.black,
        'blue': Colors.blue,
        'red': Colors.red,
        'green': Colors.green,
        'transparent': Colors.transparent
      };
      return m[val];
    }
    return null;
  }

  static TextStyle textStyle(Map p) =>
      GoogleFonts.getFont(p['font'] ?? 'Roboto',
          fontSize: p['size']?.toDouble() ?? 14,
          color: parseColor(p['color']),
          fontWeight: p['bold'] == true ? FontWeight.bold : FontWeight.normal);

  static OutlinedBorder? shape(dynamic val) {
    if (val is Map) {
      if (val['type'] == 'RoundedRectangleBorder')
        return RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(val['radius']?.toDouble() ?? 0));
      if (val['type'] == 'CircleBorder') return const CircleBorder();
    }
    return null;
  }

  static Gradient? gradient(dynamic val) {
    if (val is Map && val['colors'] is List)
      return LinearGradient(
          colors: (val['colors'] as List).map((c) => parseColor(c)!).toList());
    return null;
  }

  static EdgeInsets padding(dynamic v) {
    if (v is List && v.length == 4)
      return EdgeInsets.fromLTRB(
          v[0].toDouble(), v[1].toDouble(), v[2].toDouble(), v[3].toDouble());
    if (v is num) return EdgeInsets.all(v.toDouble());
    return EdgeInsets.zero;
  }

  static MainAxisAlignment mainAlign(String? v) => v == 'center'
      ? MainAxisAlignment.center
      : v == 'space_between'
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start;
  static CrossAxisAlignment crossAlign(String? v) => v == 'center'
      ? CrossAxisAlignment.center
      : v == 'stretch'
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start;
  static Alignment? align(String? v) => v == 'center' ? Alignment.center : null;
  static BoxFit boxFit(String? v) =>
      v == 'contain' ? BoxFit.contain : BoxFit.cover;
  static TextAlign textAlign(String? v) =>
      v == 'center' ? TextAlign.center : TextAlign.start;

  static IconData parseIcon(String? n) {
    switch (n) {
      case 'home':
        return Icons.home;
      case 'add':
        return Icons.add;
      case 'settings':
        return Icons.settings;
      case 'check':
        return Icons.check;
      case 'camera':
        return Icons.camera_alt;
      case 'wifi':
        return Icons.wifi;
      case 'battery_full':
        return Icons.battery_full;
      case 'close':
        return Icons.close;
      case 'minimize':
        return Icons.minimize;
      default:
        return Icons.widgets;
    }
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
