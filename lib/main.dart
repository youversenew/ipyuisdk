// =============================================================================
// FILE: lib/main.dart
// SYSTEM: IPYUI UNIVERSAL ENGINE (ULTIMATE EDITION)
// VERSION: 10.0.0-FINAL
// DESCRIPTION: The bridge between Python and Flutter with all bells and whistles.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// --- FLUTTER CORE ---
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

// --- UI SYSTEMS (Fluent aliased to avoid conflicts) ---
import 'package:fluent_ui/fluent_ui.dart' as fluent;

// --- PACKAGES ---
import 'package:window_manager/window_manager.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lottie/lottie.dart'; // For loading screen

// --- LOCAL MODULES ---
import 'utils.dart';
import 'performance.dart';
import 'renderers/material_renderer.dart';
import 'renderers/cupertino_renderer.dart';
import 'renderers/fluent_renderer.dart';

// =============================================================================
// 1. BOOTSTRAP & CRASH GUARD
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
        titleBarStyle: TitleBarStyle.hidden, // Controlled dynamically later
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    runApp(const IpyRoot());
  }, (error, stack) {
    Logger.instance.add("CRASH: $error", LogType.error);
    debugPrint("🔥 FATAL ERROR: $error");
  });
}

// =============================================================================
// 2. ROOT CONFIGURATION & THEME MANAGER
// =============================================================================

class IpyRoot extends StatefulWidget {
  const IpyRoot({super.key});
  @override
  State<IpyRoot> createState() => _IpyRootState();
}

class _IpyRootState extends State<IpyRoot> {
  final Engine _engine = Engine();

  @override
  void initState() {
    super.initState();
    _engine.init(this);

    // Allow DartP to switch themes dynamically
    DartP.instance.changeTheme = (mode) {
      setState(() => _engine.themeMode = mode);
    };
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return EngineInherited(
      engine: _engine,
      child: _buildApp(),
    );
  }

  Widget _buildApp() {
    final String mode = _engine.config['ui_mode'] ?? 'material';
    final Color seedColor =
        Utils.parseColor(_engine.config['seed_color']) ?? Colors.blue;
    final String fontName = _engine.config['font'] ?? 'Roboto';

    // 🪟 1. FLUENT UI (Windows Style)
    if (mode == 'fluent') {
      final accent = fluent.AccentColor.swatch({
        'normal': seedColor,
        'dark': seedColor,
        'light': seedColor,
        'darker': seedColor,
        'lighter': seedColor,
        'darkest': seedColor,
      });

      return fluent.FluentApp(
        title: _engine.config['title'] ?? 'IPYUI Fluent',
        debugShowCheckedModeBanner: false,
        themeMode: _engine.themeMode == ThemeMode.dark
            ? fluent.ThemeMode.dark
            : fluent.ThemeMode.light,
        theme: fluent.FluentThemeData(
          accentColor: accent,
          brightness: Brightness.light,
          visualDensity: fluent.VisualDensity.standard,
          fontFamily: GoogleFonts.getFont(fontName).fontFamily,
        ),
        darkTheme: fluent.FluentThemeData(
          accentColor: accent,
          brightness: Brightness.dark,
          visualDensity: fluent.VisualDensity.standard,
          fontFamily: GoogleFonts.getFont(fontName).fontFamily,
        ),
        home: const IpyShell(),
      );
    }

    // 🍎 2. CUPERTINO (iOS Style)
    if (mode == 'cupertino') {
      return CupertinoApp(
        title: _engine.config['title'] ?? 'IPYUI iOS',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(
          brightness: _engine.themeMode == ThemeMode.dark
              ? Brightness.dark
              : Brightness.light,
          primaryColor: seedColor,
        ),
        home: const IpyShell(),
      );
    }

    // 🤖 3. MATERIAL (Default)
    return MaterialApp(
      title: _engine.config['title'] ?? 'IPYUI App',
      debugShowCheckedModeBanner: false,
      themeMode: _engine.themeMode,
      theme: _buildTheme(Brightness.light, seedColor, fontName),
      darkTheme: _buildTheme(Brightness.dark, seedColor, fontName),
      home: const IpyShell(),
    );
  }

  ThemeData _buildTheme(Brightness brightness, Color seed, String font) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme:
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      fontFamily: GoogleFonts.getFont(font).fontFamily,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
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
// 3. APP SHELL (WINDOW, KEYBOARD & LAYOUT)
// =============================================================================

class IpyShell extends StatefulWidget {
  const IpyShell({super.key});
  @override
  State<IpyShell> createState() => _IpyShellState();
}

class _IpyShellState extends State<IpyShell> with WindowListener {
  late Engine _engine;
  bool _showDevTools = false;
  final FocusNode _keyboardNode = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = EngineInherited.of(context);
    _engine.setContext(context);

    // Bind DartP DevTools Toggle
    DartP.instance.toggleDevTools = () {
      setState(() => _showDevTools = !_showDevTools);
    };

    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _keyboardNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard Listener for F12
    return RawKeyboardListener(
      focusNode: _keyboardNode,
      autofocus: true,
      onKey: (e) {
        if (e is RawKeyDownEvent && e.logicalKey == LogicalKeyboardKey.f12) {
          setState(() => _showDevTools = !_showDevTools);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            Column(
              children: [
                // 1. Custom Title Bar (Controlled by Config)
                if (_engine.config['title_bar'] != 'native')
                  _buildCustomTitleBar(),

                // 2. Main Renderer (With Performance Boundary)
                Expanded(
                  child: RepaintBoundary(
                    child: _engine.isConnected && _engine.rootNode != null
                        ? UniversalBridge(
                            node: _engine.rootNode!,
                            mode: _engine.config['ui_mode'])
                        : const ConnectionScreen(),
                  ),
                ),
              ],
            ),

            // 3. DevTools Overlay
            if (_showDevTools)
              Positioned.fill(
                child: DevToolsOverlay(
                  engine: _engine,
                  onClose: () => setState(() => _showDevTools = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTitleBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 35,
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Row(
          children: [
            const SizedBox(width: 15),
            if (_engine.config['icon'] != null)
              Image.network(_engine.config['icon'], width: 16, height: 16)
            else
              const Icon(Icons.widgets, size: 16, color: Colors.grey),
            const SizedBox(width: 10),
            Text(
              _engine.config['title'] ?? 'IPYUI',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            const Spacer(),
            // Only show controls on non-macOS platforms usually, or mimic macOS
            if (!Platform.isMacOS) ...[
              _WinBtn(Icons.remove, windowManager.minimize),
              _WinBtn(Icons.check_box_outline_blank, windowManager.maximize),
              _WinBtn(Icons.close, windowManager.close, isDanger: true),
            ]
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback cb;
  final bool isDanger;
  const _WinBtn(this.icon, this.cb, {this.isDanger = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: cb,
      child: Container(
        width: 45,
        height: 35,
        alignment: Alignment.center,
        child:
            Icon(icon, size: 14, color: isDanger ? Colors.white : Colors.grey),
      ),
    );
  }
}

// =============================================================================
// 4. ENGINE CORE (LOGIC, WEBSOCKET, STATE)
// =============================================================================

class Engine {
  static const String _url = 'ws://localhost:8000/ws';

  _IpyRootState? _rootState;
  BuildContext? _ctx;
  WebSocketChannel? _ws;

  bool isConnected = false;
  Map<String, dynamic>? rootNode;
  Map<String, dynamic> config = {
    'title': 'IPYUI',
    'theme': 'light',
    'title_bar': 'custom',
    'ui_mode': 'material',
    'seed_color': '#2196F3'
  };
  ThemeMode themeMode = ThemeMode.light;

  void init(_IpyRootState state) {
    _rootState = state;
    _connect();
  }

  void setContext(BuildContext ctx) {
    _ctx = ctx;
    DartP.instance.setContext(ctx);
  }

  void _connect() {
    Logger.instance.add("Connecting to $_url...", LogType.network);
    try {
      _ws = WebSocketChannel.connect(Uri.parse(_url));
      _ws!.stream.listen(
        _onMsg,
        onDone: _onDisconnect,
        onError: (e) => _onDisconnect(),
      );
      isConnected = true;
      Logger.instance.add("Connected to Kernel", LogType.network);
      _rootState?.rebuild();
    } catch (e) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    isConnected = false;
    Logger.instance.add("Disconnected. Retrying in 3s...", LogType.network);
    _rootState?.rebuild();
    Future.delayed(const Duration(seconds: 3), _connect);
  }

  void _onMsg(dynamic msg) {
    try {
      final data = jsonDecode(msg);
      final type = data['type'];

      // --- FULL UPDATE ---
      if (type == 'update') {
        rootNode = data['tree'];
        // Index for Performance Patching
        PerformanceManager.instance.indexTree(rootNode!);
        _rootState?.rebuild();
      }

      // --- PATCH UPDATE (Optimization) ---
      else if (type == 'patch') {
        final String id = data['id'];
        final Map<String, dynamic> updates = data['updates'];
        final success = PerformanceManager.instance.applyPatch(id, updates);
        if (success) _rootState?.rebuild();
      }

      // --- CONFIGURATION ---
      else if (type == 'config') {
        config.addAll(data);
        themeMode =
            config['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;

        // Handle TitleBar Switching
        if (config['title_bar'] == 'native') {
          windowManager.setTitleBarStyle(TitleBarStyle.normal);
        } else {
          windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        }

        Logger.instance.add("Config Updated", LogType.info);
        _rootState?.rebuild();
      }

      // --- NATIVE PLUGINS ---
      else if (type == 'plugin') {
        PluginRegistry.handle(data['plugin_name'], data['data'], this);
      }

      // --- DARTP ---
      else if (type == 'dartp') {
        DartP.instance.execute(data['code']);
      }
    } catch (e) {
      Logger.instance.add("Protocol Error: $e", LogType.error);
    }
  }

  void send(String id, String handler, dynamic value) {
    if (_ws != null && isConnected) {
      _ws!.sink.add(jsonEncode(
          {"type": "event", "id": id, "handler": handler, "value": value}));
    }
  }
}

// =============================================================================
// 5. UNIVERSAL BRIDGE (RENDERER ROUTER)
// =============================================================================

class UniversalBridge extends StatelessWidget {
  final Map<String, dynamic> node;
  final String? mode;

  const UniversalBridge({super.key, required this.node, this.mode});

  @override
  Widget build(BuildContext context) {
    final engine = EngineInherited.of(context);

    // --- LAZY LOADING CHECK ---
    if (node['type'] == 'listview' && node['props']?['lazy'] == true) {
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (PerformanceManager.instance.shouldLoadMore(notification)) {
            engine.send(node['id'], 'scroll_end', null);
          }
          return false;
        },
        child: _routeRenderer(engine),
      );
    }

    return _routeRenderer(engine);
  }

  Widget _routeRenderer(Engine engine) {
    if (mode == 'fluent') {
      return FluentRenderer.build(node, engine.send);
    } else if (mode == 'cupertino') {
      return CupertinoRenderer.build(node, engine.send);
    } else {
      return MaterialRenderer.build(node, engine.send);
    }
  }
}

// =============================================================================
// 6. PLUGIN REGISTRY (NATIVE FEATURES)
// =============================================================================

class PluginRegistry {
  static void handle(String name, Map data, Engine engine) async {
    Logger.instance.add("Plugin: $name", LogType.system);
    final ctx = engine._ctx;
    if (ctx == null) return;

    try {
      if (name == 'toast') {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(data['message']),
          backgroundColor: Utils.parseColor(data['color']),
        ));
      } else if (name == 'dialog') {
        showDialog(
            context: ctx,
            builder: (c) => AlertDialog(
                  title: Text(data['title']),
                  content: Text(data['content']),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("OK"))
                  ],
                ));
      } else if (name == 'launcher') {
        launchUrl(Uri.parse(data['url']));
      } else if (name == 'vibrate') {
        // Requires vibration package in pubspec
        // if (await Vibration.hasVibrator()) Vibration.vibrate();
      }
    } catch (e) {
      Logger.instance.add("Plugin Error: $e", LogType.error);
    }
  }
}

// =============================================================================
// 7. DEVTOOLS OVERLAY (F12 CONSOLE)
// =============================================================================

class DevToolsOverlay extends StatefulWidget {
  final Engine engine;
  final VoidCallback onClose;
  const DevToolsOverlay(
      {super.key, required this.engine, required this.onClose});

  @override
  State<DevToolsOverlay> createState() => _DevToolsOverlayState();
}

class _DevToolsOverlayState extends State<DevToolsOverlay>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _cmdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
              onTap: widget.onClose, child: Container(color: Colors.black54)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 400,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border:
                    Border(top: BorderSide(color: Colors.blueAccent, width: 2)),
              ),
              child: Column(
                children: [
                  // HEADER
                  Container(
                    color: Colors.black,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        const Text("🛠️ IPYUI DEVTOOLS",
                            style: TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 20),
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.blueAccent,
                            tabs: const [
                              Tab(text: "CONSOLE"),
                              Tab(text: "INSPECTOR"),
                              Tab(text: "NETWORK"),
                            ],
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.save,
                                color: Colors.grey, size: 18),
                            onPressed: _saveLogs,
                            tooltip: "Save Logs"),
                        IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                            onPressed: widget.onClose),
                      ],
                    ),
                  ),

                  // BODY
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildConsole(),
                        _buildInspector(),
                        _buildNetwork(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildConsole() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<LogEntry>>(
            stream: Logger.instance.stream,
            initialData: Logger.instance.logs,
            builder: (context, snapshot) {
              final logs = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: logs.length,
                reverse: true,
                itemBuilder: (c, i) {
                  final log = logs[logs.length - 1 - i];
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                            text: "[${log.timeString}] ",
                            style: const TextStyle(color: Colors.grey)),
                        TextSpan(
                            text: log.message,
                            style: TextStyle(color: log.color)),
                      ],
                    ),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: Colors.black45,
          child: TextField(
            controller: _cmdCtrl,
            style:
                const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(
                border: InputBorder.none,
                prefixText: ">>> ",
                prefixStyle: TextStyle(color: Colors.green),
                hintText: "Enter command...",
                hintStyle: TextStyle(color: Colors.white24)),
            onSubmitted: _runCommand,
          ),
        )
      ],
    );
  }

  Widget _buildInspector() {
    final root = widget.engine.rootNode;
    if (root == null)
      return const Center(
          child: Text("No UI Loaded", style: TextStyle(color: Colors.grey)));

    const encoder = JsonEncoder.withIndent('  ');
    final pretty = encoder.convert(root);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Text(pretty,
          style: const TextStyle(
              color: Colors.orangeAccent,
              fontFamily: 'monospace',
              fontSize: 11)),
    );
  }

  Widget _buildNetwork() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.engine.isConnected ? Icons.check_circle : Icons.error,
              color: widget.engine.isConnected ? Colors.green : Colors.red,
              size: 40),
          const SizedBox(height: 10),
          Text(widget.engine.isConnected ? "CONNECTED" : "DISCONNECTED",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text("ws://localhost:8000/ws",
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _runCommand(String cmd) {
    _cmdCtrl.clear();
    Logger.instance.add("CMD: $cmd", LogType.cli);
    final parts = cmd.split(' ');

    if (parts[0] == 'theme') {
      if (parts.length > 1 && parts[1] == 'dark')
        DartP.instance.execute("Theme.dark()");
      else
        DartP.instance.execute("Theme.light()");
    } else if (parts[0] == 'clear') {
      Logger.instance.clear();
    } else {
      Logger.instance.add("Unknown command", LogType.error);
    }
  }

  void _saveLogs() async {
    final content = Logger.instance.export();
    String? path = await FilePicker.platform
        .saveFile(dialogTitle: "Save Logs", fileName: "logs.txt");
    if (path != null) {
      await File(path).writeAsString(content);
      Logger.instance.add("Saved to $path", LogType.system);
    }
  }
}

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Using Lottie if available, else Circular
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text("Waiting for Python Engine...",
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
