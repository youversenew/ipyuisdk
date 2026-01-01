// =============================================================================
// FILE: lib/main.dart
// PROJECT: IPYUI UNIVERSAL RUNTIME (GOD-MODE / BATTERIES INCLUDED)
// VERSION: 10.0.0-ALPHA-OMEGA
// AUTHOR: IPYUI ARCHITECT
// DESC: Infinite Expandable, Templated, Python-Driven UI with Native Bridge
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

// Flutter Core
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

// Packages
import 'package:window_manager/window_manager.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

// Native Bridge Packages
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';

// =============================================================================
// 1. SYSTEM BOOTSTRAP & CRASH GUARD
// =============================================================================

void main() async {
  // Global Error Trap (No Red Screen of Death on Release)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Configure Desktop Window
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 800),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden, // We render our own TitleBar
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    // Platform Specific Init
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ));
    }

    runApp(const IpyRoot());
  }, (error, stack) {
    debugPrint("🔥 KERNEL PANIC: $error");
    debugPrint(stack.toString());
  });
}

// =============================================================================
// 2. ROOT APPLICATION & THEME ENGINE
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
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Determine Font
    final fontFamily =
        GoogleFonts.getFont(_engine.config['font'] ?? 'Roboto').fontFamily;

    return EngineProvider(
      engine: _engine,
      child: MaterialApp(
        title: _engine.config['title'] ?? 'IPYUI Client',
        debugShowCheckedModeBanner: false,

        // Theme Logic
        themeMode: _engine.themeMode,

        // Light Theme
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor:
                _Utils.parseColor(_engine.config['seed_color']) ?? Colors.blue,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          fontFamily: fontFamily,
        ),

        // Dark Theme
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor:
                _Utils.parseColor(_engine.config['seed_color']) ?? Colors.blue,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          fontFamily: fontFamily,
        ),

        home: const IpyShell(),
      ),
    );
  }
}

class EngineProvider extends InheritedWidget {
  final Engine engine;
  const EngineProvider({super.key, required this.engine, required super.child});
  static Engine of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EngineProvider>()!.engine;
  @override
  bool updateShouldNotify(EngineProvider old) => false;
}

// =============================================================================
// 3. APP SHELL (WINDOW MANAGER & DEVTOOLS HOST)
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
  final FocusNode _keyboardNode = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = EngineProvider.of(context);
    _engine.setContext(context);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _keyboardNode.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    _engine.send("window", "close_request", null);
    // Give Python 100ms to save state or deny close
    await Future.delayed(const Duration(milliseconds: 100));
    super.onWindowClose();
  }

  @override
  Widget build(BuildContext context) {
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
                // 1. Custom Title Bar (Conditional)
                if (_engine.config['title_bar'] != 'none') _buildTitleBar(),

                // 2. Main Viewport
                Expanded(
                  child: _engine.isConnected && _engine.rootNode != null
                      ? UniversalRenderer(
                          node: _engine.rootNode!, inspectMode: _inspectMode)
                      : const ConnectionScreen(),
                ),
              ],
            ),

            // 3. Overlays
            if (_showDevTools)
              Positioned.fill(
                child: DevToolsOverlay(
                  engine: _engine,
                  inspectMode: _inspectMode,
                  onToggleInspect: () =>
                      setState(() => _inspectMode = !_inspectMode),
                  onClose: () => setState(() => _showDevTools = false),
                ),
              ),

            // 4. Toast/Notification Area (could be added here)
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
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
              const Icon(Icons.grid_view_rounded, size: 16),
            const SizedBox(width: 10),
            Text(
              _engine.config['title'] ?? 'IPYUI App',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            const Spacer(),
            if (!Platform.isMacOS) ...[
              _WindowBtn(Icons.remove, windowManager.minimize),
              _WindowBtn(Icons.crop_square, windowManager.maximize),
              _WindowBtn(Icons.close, windowManager.close, isDanger: true),
            ]
          ],
        ),
      ),
    );
  }
}

class _WindowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback cb;
  final bool isDanger;
  const _WindowBtn(this.icon, this.cb, {this.isDanger = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: cb,
      child: Container(
        width: 45,
        height: 35,
        alignment: Alignment.center,
        child: Icon(icon, size: 14, color: isDanger ? Colors.white : null),
      ),
    );
  }
}

// =============================================================================
// 4. THE ENGINE (LOGIC CORE & TEMPLATE REGISTRY)
// =============================================================================

class Engine {
  static const String _url = 'ws://localhost:8000/ws';

  _IpyRootState? _rootState;
  BuildContext? _ctx;
  WebSocketChannel? _ws;

  // State
  bool isConnected = false;
  Map<String, dynamic>? rootNode;
  Map<String, dynamic> config = {'title': 'IPYUI', 'theme': 'light'};
  ThemeMode themeMode = ThemeMode.light;

  // LOGS & DEBUG
  List<String> logs = [];
  Map<String, dynamic>? inspectedNode;

  // TEMPLATE REGISTRY (The "Extension" System)
  // Allows loading "compiled" widget trees once and reusing them by type
  final Map<String, Map<String, dynamic>> _templates = {};

  void init(_IpyRootState state) {
    _rootState = state;
    _connect();
  }

  void setContext(BuildContext ctx) => _ctx = ctx;

  void log(String msg, {String type = "INFO"}) {
    final t = "${DateTime.now().minute}:${DateTime.now().second}";
    logs.add("[$t] [$type] $msg");
    if (logs.length > 500) logs.removeAt(0);
  }

  void _connect() {
    log("Connecting to $_url...", type: "NET");
    try {
      _ws = WebSocketChannel.connect(Uri.parse(_url));
      _ws!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (e) => _onDisconnect(),
      );
      isConnected = true;
      _rootState?.rebuild();
      log("Connected to Kernel", type: "NET");
    } catch (e) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    isConnected = false;
    log("Disconnected. Reconnecting...", type: "NET");
    _rootState?.rebuild();
    Future.delayed(const Duration(seconds: 3), _connect);
  }

  void _onMessage(dynamic msg) {
    try {
      final data = jsonDecode(msg);
      final type = data['type'];

      switch (type) {
        case 'update':
          rootNode = data['tree'];
          _rootState?.rebuild();
          break;

        case 'config':
          config.addAll(data);
          themeMode =
              config['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
          _rootState?.rebuild();
          break;

        case 'register_template':
          // Registers a reusable component (The "Library" feature)
          final name = data['name'];
          final template = data['template'];
          _templates[name] = template;
          log("Registered Template: $name", type: "SYS");
          break;

        case 'plugin':
          PluginRegistry.handle(data['plugin_name'], data['data'], this);
          break;

        case 'dartp':
          DartP.exec(data['code'], _ctx);
          break;
      }
    } catch (e) {
      log("Protocol Error: $e", type: "ERR");
    }
  }

  void send(String id, String handler, dynamic value) {
    if (_ws != null && isConnected) {
      _ws!.sink.add(jsonEncode(
          {"type": "event", "id": id, "handler": handler, "value": value}));
      // log("Event: $handler -> $id", type: "OUT"); // Commented to reduce noise
    }
  }

  /// Retrieves a template if the type matches a registered extension
  Map<String, dynamic>? getTemplate(String type) => _templates[type];
}

// =============================================================================
// 5. PLUGIN REGISTRY (BATTERIES INCLUDED)
// =============================================================================

class PluginRegistry {
  static void handle(String name, Map data, Engine engine) async {
    final ctx = engine._ctx;
    if (ctx == null) return;
    engine.log("Plugin Call: $name", type: "PLUG");

    try {
      switch (name) {
        // UI FEEDBACK
        case 'toast':
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(data['message']),
            backgroundColor: _Utils.parseColor(data['color']),
          ));
          break;

        case 'dialog':
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
          break;

        // SYSTEM
        case 'launcher':
          await launchUrl(Uri.parse(data['url']));
          break;

        case 'clipboard':
          await Clipboard.setData(ClipboardData(text: data['text']));
          break;

        case 'vibrate':
          if (await Vibration.hasVibrator() ?? false) {
            Vibration.vibrate(duration: data['duration'] ?? 500);
          }
          break;

        // I/O & SENSORS
        case 'storage_set':
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(data['key'], data['value']);
          break;

        case 'storage_get':
          final prefs = await SharedPreferences.getInstance();
          final val = prefs.getString(data['key']);
          engine.send(data['request_id'], 'result', val);
          break;

        case 'image_picker':
          final picker = ImagePicker();
          final img = await picker.pickImage(
              source: data['source'] == 'camera'
                  ? ImageSource.camera
                  : ImageSource.gallery);
          if (img != null) engine.send('system', 'image_picked', img.path);
          break;

        case 'geolocator':
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied)
            permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            Position pos = await Geolocator.getCurrentPosition();
            engine.send(data['request_id'], 'result',
                {'lat': pos.latitude, 'lng': pos.longitude});
          }
          break;

        case 'device_info':
          final info = DeviceInfoPlugin();
          if (Platform.isWindows) {
            final win = await info.windowsInfo;
            engine.send(data['request_id'], 'result',
                {'os': 'windows', 'computer': win.computerName});
          }
          // Add other platforms...
          break;
      }
    } catch (e) {
      engine.log("Plugin Error: $e", type: "ERR");
    }
  }
}

// =============================================================================
// 6. DARTP (DYNAMIC INTERPRETER)
// =============================================================================

class DartP {
  static void exec(String code, BuildContext? context) {
    if (context == null) return;
    final cmd = code.trim();
    print("DartP: $cmd");

    try {
      if (cmd == "Navigator.pop()") Navigator.pop(context);
      if (cmd == "Window.minimize()") windowManager.minimize();
      if (cmd == "Window.maximize()") windowManager.maximize();
      if (cmd == "Window.close()") windowManager.close();
      if (cmd == "System.exit()") exit(0);

      // Advanced: Dynamic Scroll
      // If we had a ScrollController registry, we could do "ScrollTo('list1', 500)"

    } catch (e) {
      print("DartP Error: $e");
    }
  }
}

// =============================================================================
// 7. UNIVERSAL RENDERER (THE MASTER WIDGET)
// =============================================================================

class UniversalRenderer extends StatelessWidget {
  final Map<String, dynamic> node;
  final bool inspectMode;

  const UniversalRenderer(
      {super.key, required this.node, this.inspectMode = false});

  @override
  Widget build(BuildContext context) {
    // 1. Template Resolution (The "Library" Feature)
    // If this node is a reference to a registered template, swap it out.
    final engine = EngineProvider.of(context);
    Map<String, dynamic> effectiveNode = node;

    if (engine.getTemplate(node['type']) != null) {
      // It's a template instance!
      // We take the template structure and merge current props on top.
      final template = engine.getTemplate(node['type'])!;

      // Deep copy to avoid mutating the original template registry
      effectiveNode = jsonDecode(jsonEncode(template));

      // Override ID
      effectiveNode['id'] = node['id'];

      // Override Props (Fixed: Explicit casting to Map to avoid Type Inference error)
      if (node['props'] != null) {
        final Map<String, dynamic> templateProps =
            effectiveNode['props'] != null
                ? Map<String, dynamic>.from(effectiveNode['props'])
                : {};

        final Map<String, dynamic> newProps =
            Map<String, dynamic>.from(node['props']);

        effectiveNode['props'] = {...templateProps, ...newProps};
      }

      // Append Children (Fixed: Explicit casting to List)
      if (node['children'] != null) {
        final List<dynamic> templateChildren = effectiveNode['children'] != null
            ? List.from(effectiveNode['children'])
            : [];

        final List<dynamic> newChildren = List.from(node['children']);

        effectiveNode['children'] = [...templateChildren, ...newChildren];
      }
    }

    final Widget child = _buildCore(context, effectiveNode);

    // Inspector Overlay
    if (inspectMode) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            engine.inspectedNode = effectiveNode;
            engine.log("Inspecting ${effectiveNode['type']}", type: "DEV");
            // Force devtools update is tricky without state, but engine logs update
          },
          child: Container(
            decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 2)),
            child: child,
          ),
        ),
      );
    }
    return child;
  }

  Widget _buildCore(BuildContext context, Map<String, dynamic> node) {
    try {
      final type = node['type'];
      final props = node['props'] ?? {};
      final childrenData = node['children'] as List? ?? [];

      final children = childrenData
          .map((c) => UniversalRenderer(node: c, inspectMode: inspectMode))
          .toList();

      final engine = EngineProvider.of(context);

      Widget w;

      switch (type) {
        // --- LAYOUTS ---
        case 'row':
          w = Row(
            mainAxisAlignment: _Utils.mainAlign(props['align']),
            crossAxisAlignment: _Utils.crossAlign(props['cross_align']),
            children: children,
          );
          break;
        case 'column':
          w = Column(
            mainAxisAlignment: _Utils.mainAlign(props['align']),
            crossAxisAlignment: _Utils.crossAlign(props['cross_align']),
            children: children,
          );
          break;
        case 'stack':
          w = Stack(
            alignment: _Utils.align(props['align']) ?? Alignment.topLeft,
            children: children,
          );
          break;
        case 'listview':
          w = ListView(
            padding: _Utils.padding(props['padding']),
            scrollDirection: props['direction'] == 'horizontal'
                ? Axis.horizontal
                : Axis.vertical,
            children: children,
          );
          break;
        case 'grid':
          w = GridView.count(
            crossAxisCount: props['cols'] ?? 2,
            childAspectRatio: (props['ratio'] ?? 1.0).toDouble(),
            padding: _Utils.padding(props['padding']),
            shrinkWrap: props['shrink'] == true,
            children: children,
          );
          break;

        // --- BASICS ---
        case 'text':
          w = Text(
            props['value']?.toString() ?? '',
            style: _Utils.textStyle(props),
            textAlign: _Utils.textAlign(props['align']),
            maxLines: props['max_lines'],
            overflow: props['max_lines'] != null ? TextOverflow.ellipsis : null,
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
          final src = props['src']?.toString() ?? '';
          final fit = _Utils.boxFit(props['fit']);
          if (src.startsWith('data:image')) {
            // Base64 Image
            final base64String = src.split(',').last;
            w = Image.memory(base64Decode(base64String), fit: fit);
          } else if (src.endsWith('.svg')) {
            w = SvgPicture.network(src,
                fit: fit,
                placeholderBuilder: (_) => const CircularProgressIndicator());
          } else {
            w = CachedNetworkImage(
                imageUrl: src,
                fit: fit,
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image));
          }
          break;

        // --- MEDIA & ANIMATION (BATTERIES INCLUDED) ---
        case 'lottie':
          final src = props['src']?.toString() ?? '';
          if (src.startsWith('http')) {
            w = Lottie.network(src,
                width: props['width']?.toDouble(),
                height: props['height']?.toDouble());
          } else {
            // Assume asset or local, fallback to error
            w = const Icon(Icons.movie_creation_outlined);
          }
          break;

        case 'video':
          // Simplistic Video Player placeholder (Requires stateful wrapper in reality)
          // For the purpose of "Universal Renderer", we usually need a specialized Stateful Widget registry
          // Here we return a placeholder to avoid crashes
          w = Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: const Icon(Icons.play_circle_fill,
                color: Colors.white, size: 50),
          );
          break;

        // --- INTERACTIVE ---
        case 'button':
        case 'ElevatedButton':
          w = ElevatedButton(
            onPressed: () => _emit(engine, node['id'], 'click'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _Utils.parseColor(props['bg_color']),
              foregroundColor: _Utils.parseColor(props['color']),
              elevation: props['elevation']?.toDouble(),
              padding: _Utils.padding(props['padding']),
              shape: _Utils.shape(props['shape']),
            ),
            child: children.isNotEmpty
                ? children.first
                : Text(props['text'] ?? 'Button'),
          );
          break;

        case 'input':
          w = TextField(
            controller: TextEditingController(
                text: props[
                    'value']), // Note: This resets on rebuild. In prod, needs separate state map.
            decoration: InputDecoration(
              labelText: props['label'],
              hintText: props['placeholder'],
              filled: true,
              fillColor: _Utils.parseColor(props['bg_color']),
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(props['radius']?.toDouble() ?? 4)),
              prefixIcon: props['icon'] != null
                  ? Icon(_Utils.parseIcon(props['icon']))
                  : null,
            ),
            obscureText: props['password'] == true,
            onChanged: (v) => _emit(engine, node['id'], 'change', val: v),
            onSubmitted: (v) => _emit(engine, node['id'], 'submit', val: v),
          );
          break;

        case 'switch':
          w = Switch(
            value: props['value'] == true,
            activeColor: _Utils.parseColor(props['active_color']),
            onChanged: (v) => _emit(engine, node['id'], 'change', val: v),
          );
          break;

        // --- THE UNIVERSAL BOX (DIV) ---
        case 'container':
        case 'box':
        default:
          w = Container(
            width: props['width']?.toDouble(),
            height: props['height']?.toDouble(),
            margin: _Utils.padding(props['margin']),
            padding: _Utils.padding(props['padding']),
            alignment: _Utils.align(props['alignment']),
            decoration: BoxDecoration(
              color: _Utils.parseColor(props['bg_color']),
              image: props['bg_image'] != null
                  ? DecorationImage(
                      image: NetworkImage(props['bg_image']), fit: BoxFit.cover)
                  : null,
              borderRadius:
                  BorderRadius.circular(props['radius']?.toDouble() ?? 0),
              border: props['border_color'] != null
                  ? Border.all(
                      color: _Utils.parseColor(props['border_color'])!,
                      width: props['border_width']?.toDouble() ?? 1)
                  : null,
              gradient: _Utils.gradient(props['gradient']),
              boxShadow: props['shadow'] == true
                  ? [
                      BoxShadow(
                          color: (props['shadow_color'] != null
                              ? _Utils.parseColor(props['shadow_color'])
                              : Colors.black26)!,
                          blurRadius: props['blur']?.toDouble() ?? 10,
                          offset: const Offset(0, 4))
                    ]
                  : null,
            ),
            child: children.isNotEmpty ? children.first : null,
          );
      }

      // --- COMMON MODIFIERS ---
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
      if (props['rotate'] != null) {
        w = Transform.rotate(
            angle: props['rotate'].toDouble() * (pi / 180), child: w);
      }
      if (props['visible'] == false) {
        w = const SizedBox();
      }

      return w;
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(border: Border.all(color: Colors.red)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 16),
            Text("${node['type']}",
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
  }

  void _emit(Engine engine, String? id, String evt, {dynamic val}) {
    if (id != null) engine.send(id, evt, val);
  }
}

// =============================================================================
// 8. DEVTOOLS OVERLAY (HACKER MODE)
// =============================================================================

class DevToolsOverlay extends StatelessWidget {
  final Engine engine;
  final bool inspectMode;
  final VoidCallback onToggleInspect;
  final VoidCallback onClose;

  const DevToolsOverlay(
      {super.key,
      required this.engine,
      required this.inspectMode,
      required this.onToggleInspect,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dismiss area
          GestureDetector(
              onTap: onClose, child: Container(color: Colors.black12)),

          // Console
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 350,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border:
                    Border(top: BorderSide(color: Colors.blueAccent, width: 2)),
                boxShadow: [BoxShadow(color: Colors.black, blurRadius: 20)],
              ),
              child: Column(
                children: [
                  // Toolbar
                  Container(
                    color: Colors.black26,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      children: [
                        const Text("IPYUI KERNEL",
                            style: TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace')),
                        const SizedBox(width: 20),
                        _ToolIcon(
                            Icons.find_in_page,
                            inspectMode ? "INSPECTING" : "INSPECT",
                            onToggleInspect,
                            active: inspectMode),
                        const Spacer(),
                        _ToolIcon(Icons.close, "CLOSE", onClose),
                      ],
                    ),
                  ),

                  // Content Area
                  Expanded(
                    child: Row(
                      children: [
                        // Logs
                        Expanded(flex: 2, child: _LogList(logs: engine.logs)),
                        Container(width: 1, color: Colors.white10),
                        // Inspector
                        Expanded(
                            flex: 1,
                            child: _Inspector(node: engine.inspectedNode)),
                      ],
                    ),
                  ),

                  // CLI
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.black,
                    child: TextField(
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        prefixText: ">>> ",
                        prefixStyle: TextStyle(color: Colors.blueAccent),
                      ),
                      onSubmitted: (v) {
                        engine.send("devtools", "exec", v);
                        engine.log("EXEC: $v", type: "CLI");
                      },
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _ToolIcon(this.icon, this.label, this.onTap, {this.active = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: active ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))
        ]),
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  final List<String> logs;
  const _LogList({required this.logs});
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (c, i) => Text(logs[logs.length - 1 - i],
          style: const TextStyle(
              color: Colors.white70, fontFamily: 'monospace', fontSize: 11)),
    );
  }
}

class _Inspector extends StatelessWidget {
  final Map<String, dynamic>? node;
  const _Inspector({this.node});
  @override
  Widget build(BuildContext context) {
    if (node == null)
      return const Center(
          child:
              Text("Select an element", style: TextStyle(color: Colors.grey)));

    // Pretty print JSON
    const encoder = JsonEncoder.withIndent('  ');
    String pretty = "";
    try {
      pretty = encoder.convert(node);
    } catch (e) {
      pretty = "Error parsing node";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Text(pretty,
          style: const TextStyle(
              color: Colors.orangeAccent,
              fontFamily: 'monospace',
              fontSize: 11)),
    );
  }
}

// =============================================================================
// 9. UTILS & PARSERS (THE TRANSLATOR)
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
        'transparent': Colors.transparent,
        'grey': Colors.grey
      };
      return m[val];
    }
    return null;
  }

  static EdgeInsets padding(dynamic v) {
    if (v is List && v.length == 4)
      return EdgeInsets.fromLTRB(
          v[0].toDouble(), v[1].toDouble(), v[2].toDouble(), v[3].toDouble());
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is List && v.length == 2)
      return EdgeInsets.symmetric(
          horizontal: v[0].toDouble(), vertical: v[1].toDouble());
    return EdgeInsets.zero;
  }

  static TextStyle textStyle(Map p) {
    return GoogleFonts.getFont(
      p['font'] ?? 'Roboto',
      fontSize: p['size']?.toDouble() ?? 14,
      color: parseColor(p['color']),
      fontWeight: p['bold'] == true ? FontWeight.bold : FontWeight.normal,
      fontStyle: p['italic'] == true ? FontStyle.italic : FontStyle.normal,
      decoration: p['underline'] == true
          ? TextDecoration.underline
          : TextDecoration.none,
    );
  }

  static MainAxisAlignment mainAlign(String? v) {
    if (v == 'center') return MainAxisAlignment.center;
    if (v == 'space_between') return MainAxisAlignment.spaceBetween;
    if (v == 'end') return MainAxisAlignment.end;
    return MainAxisAlignment.start;
  }

  static CrossAxisAlignment crossAlign(String? v) {
    if (v == 'center') return CrossAxisAlignment.center;
    if (v == 'stretch') return CrossAxisAlignment.stretch;
    if (v == 'end') return CrossAxisAlignment.end;
    return CrossAxisAlignment.start;
  }

  static Alignment? align(String? v) {
    if (v == 'center') return Alignment.center;
    if (v == 'top_left') return Alignment.topLeft;
    if (v == 'bottom_right') return Alignment.bottomRight;
    if (v == 'center_left') return Alignment.centerLeft;
    if (v == 'center_right') return Alignment.centerRight;
    return null;
  }

  static BoxFit boxFit(String? v) {
    if (v == 'contain') return BoxFit.contain;
    if (v == 'fill') return BoxFit.fill;
    return BoxFit.cover;
  }

  static TextAlign textAlign(String? v) {
    if (v == 'center') return TextAlign.center;
    if (v == 'right') return TextAlign.right;
    if (v == 'justify') return TextAlign.justify;
    return TextAlign.left;
  }

  static IconData parseIcon(String? n) {
    switch (n) {
      case 'home':
        return Icons.home;
      case 'settings':
        return Icons.settings;
      case 'person':
        return Icons.person;
      case 'add':
        return Icons.add;
      case 'check':
        return Icons.check_circle;
      case 'close':
        return Icons.close;
      case 'camera':
        return Icons.camera_alt;
      case 'map':
        return Icons.map;
      case 'menu':
        return Icons.menu;
      case 'search':
        return Icons.search;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'info':
        return Icons.info;
      case 'warning':
        return Icons.warning;
      case 'error':
        return Icons.error;
      default:
        return Icons.widgets;
    }
  }

  static OutlinedBorder? shape(dynamic val) {
    if (val is Map) {
      if (val['type'] == 'RoundedRectangleBorder') {
        return RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(val['radius']?.toDouble() ?? 0));
      }
      if (val['type'] == 'CircleBorder') return const CircleBorder();
      if (val['type'] == 'StadiumBorder') return const StadiumBorder();
    }
    return null;
  }

  static Gradient? gradient(dynamic val) {
    if (val is Map && val['colors'] is List) {
      return LinearGradient(
        colors: (val['colors'] as List).map((c) => parseColor(c)!).toList(),
        begin: align(val['begin']) ?? Alignment.centerLeft,
        end: align(val['end']) ?? Alignment.centerRight,
      );
    }
    return null;
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
          const Icon(Icons.wifi_tethering, size: 60, color: Colors.blueGrey),
          const SizedBox(height: 20),
          const Text("Connecting to Kernel...",
              style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 20),
          const SizedBox(width: 150, child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
